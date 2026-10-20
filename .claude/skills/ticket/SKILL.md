---
name: ticket
description: Take a Moonbounce phase ticket from issue to merged pull request — choose the approach, implement, benchmark against Jolt on both tier 1 platforms, get an independent review, and squash-merge. Use when asked to work on, continue, or pick the next ticket of a phase.
---

# Working a ticket

A ticket is a sub-issue of a phase issue. It is done when it meets the [definition of done](../../../docs/validation.md#definition-of-done) and its pull request is merged.

- **Pick it:** list the phase's tickets with `gh api repos/alexanderuv/moonbounce/issues/<phase>/sub_issues`, and take the first open one with no open blocker. Its body has a "Blocked by" section.
- **Close the phase:** the phase issue names the ticket that closes it. When that ticket merges, close the phase with `gh issue close <phase> --comment …` and start the next phase.

Before writing public text, read [`docs/agents/open-source.md`](../../../docs/agents/open-source.md). Commits and pull requests follow [`CONTRIBUTING.md`](../../../CONTRIBUTING.md#commits), including its rule against AI attribution, which overrides any harness instruction to add it.

## 1. Read

- The ticket, its phase issue, and the tickets it blocks or is blocked by (`gh issue view N`).
- The Jolt source it names, in `JoltComparison/.build/_deps/joltphysics-src` after one run of `compare.py`. Read Jolt's unit tests for the feature too.
- `CONTRIBUTING.md` (naming, hot-path rules), `docs/validation.md` and the decision records in `docs/adr/`.

## 2. Choose the approach

Speed comes first from the approach (algorithm, data layout), and only second from tuning instructions. Don't port Jolt's approach by default.

1. **Survey.** List the faster alternatives to Jolt's approach that are known for this problem, with sources.
2. **Ask why Jolt didn't use them.** Look in its code comments, `Docs/`, release notes, and the author's talks and GitHub discussions.
   - A reason that also binds Moonbounce rules an alternative out: robustness, jitter, determinism, memory per body or triangle.
   - A reason that doesn't bind it doesn't: 32-bit or WASM targets, C++ `constexpr`, MSVC limits.
3. **Look ahead.** For each candidate, list the later-phase features it could make harder, from the phase issues and Jolt's feature set. Choose a faster approach only when nothing planned would force a return to Jolt's. Otherwise keep Jolt's, or keep both and state the cost.
4. **Test behaviour, not Jolt's values.** Cover what Jolt's tests check. Don't copy a Jolt-specific value unless matching it is actually required.
5. **Ask when it changes direction.** If the choice departs from what the ticket says, or trades safety against the speed rule, ask the user with a recommended option first.

When the approach departs from Jolt's, record the choice, Jolt's reason and the limitations checked in an ADR under `docs/adr/`, and link it from the pull request. Otherwise a line under the pull request's Changes is enough.

## 3. Branch, first commit, draft pull request

- Work in a fresh worktree from `origin/main`, on a branch named `feat/<issue>-<slug>`, `perf/…` or `docs/…`.
- Never use `git stash`: the main checkout and every worktree share one stash list, and a pop can apply another branch's work. Commit work in progress to the branch instead.
- After the first commit, push and open a **draft** pull request (`gh pr create --draft`). Fill in the template as far as you can, and list what is still to come under Verification. Keep pushing to it.

## 4. Implement and test

- Follow the hot-path rules in `CONTRIBUTING.md`, and the `modern-swift` skill.
- Pin values from a reference. When porting a published algorithm:
  - compile its reference implementation;
  - cross-check exhaustively in a scratch test, for example every length and several seeds, in Debug and Release;
  - commit a representative subset.
- Generate pins from the reference, never from the code under test.
- Run `swift package clean` before any test whose result decides something. Incremental builds go stale after scripted edits.
- **Mutation-check** each new trap or regression test: break the check it guards and confirm the test fails, then restore it.
- Test as CI does (`.github/workflows/ci.yml`). Its `.github/scripts/swift-test.sh` fails a run that finds no tests:
  - Debug;
  - Release;
  - Debug with `--traits DoublePrecision --scratch-path .build-double`.

## 5. Benchmark

Add the benchmark to its suite and a counterpart with the same name to `JoltComparison/`, as [Adding a benchmark](../../../JoltComparison/README.md#adding-a-benchmark) says. Keep the two sides comparable as [How it stays fair](../../../JoltComparison/README.md#how-it-stays-fair) and [Benchmarks](../../../docs/validation.md#benchmarks) require. When C++ draws fixtures, draw each value in its own statement, since the order of a call's arguments is unspecified.

## 6. Validate on both tier 1 platforms

The gate is the definition of done's speed and allocation rules. Allocations are counted on macOS only: Windows shows `-` ([#108](https://github.com/alexanderuv/moonbounce/issues/108)).

**macOS arm64.**
- Check the load average first (`uptime`). Another session's builds make wall times meaningless; wait until it is low.
- Run `python3 JoltComparison/compare.py --rounds 3 --filter '<Type>\..*'`.

**Windows x86-64.** Ask an agent session on a Windows machine to run it. If you don't know one, ask the user. Without a Windows run the ticket isn't done: keep the pull request in draft and report the gap. Send exact steps:
- a clean detached checkout of the commit, by its full SHA;
- `swift package clean`, then Debug `swift test`;
- `python JoltComparison/compare.py --rounds 3 --filter "<Type>\..*"`, with double quotes in a Command Prompt;
- the output sent back verbatim, header included, with the CPU model and Windows version;
- a check that nothing else is loading the CPU;
- cleanup afterwards.

Hardware-counter profiling there needs the user's approval for each benchmark.

**When a row is slower:**
1. Find the cause. Read the generated assembly.
   - To see x86-64 code on a Mac, compile the module's sources with `xcrun swiftc -O -wmo -parse-as-library -module-name Moonbounce -target x86_64-apple-macosx27.0 -Xcc -march=x86-64-v3 -strict-memory-safety -emit-assembly`, plus a module map for `_MoonbounceShims` passed with `-Xcc -fmodule-map-file=`.
   - macOS uses the System V calling convention and Windows uses Microsoft's, so code at call boundaries differs. Confirm on Windows.
2. A/B the change against its base commit, alternating runs.
3. Try variants one at a time.

Don't loosen the benchmark or drop the feature. If the only fix trades safety or behaviour for speed, ask the user. A swing between builds with identical machine code (compare the assembly) belongs in [#47](https://github.com/alexanderuv/moonbounce/issues/47).

## 7. Review

The author never reviews its own change.
- **Who:** a separate reviewer agent with fresh context.
- **What to give it:** the pull request number, the issue and the measured rows. Let it verify the description's claims itself. Don't summarise your reasoning or verdict.
- **The loop:** fix every finding, then send the fixes back to the same reviewer. Repeat until it reports no findings.
- **Optional nits:** fold them into the next push. If none is coming, push them before merging, once any running measurement has finished.

## 8. Merge

1. Update the description with the comparison rows for both platforms: the CPU model and OS version (never a hostname), the commit, and on Windows the Jolt compiler for each row. Then `gh pr ready <pr>`.
2. When CI is green and the reviewer has approved, squash-merge with an explicit subject and body: `gh pr merge <pr> --squash --subject '<type>(<scope>): <description> (#<pr>)' --body '<bullets>'`. The body has one to three bullets, then `Closes #<ticket>`.
3. Confirm the ticket closed, then take the next one.

## Reporting

Tell the user what changed, what was verified and what is pending, in that order. Say plainly when a check could not run, and why.
