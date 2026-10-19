---
name: ticket
description: Take a Moonbounce phase ticket from issue to merged pull request — choose the approach, implement, benchmark against Jolt on both tier 1 platforms, get an independent review, and squash-merge. Use when asked to work on, continue, or pick the next ticket of a phase.
---

# Working a ticket

A ticket is a sub-issue of a phase issue (for example #34, Phase 2). It is done when it meets the [definition of done](../../../docs/validation.md#definition-of-done) and its pull request is merged. Work tickets one at a time, in order. When the phase's closing ticket merges, close the phase issue and start the next phase.

Before writing public text, read [`docs/agents/open-source.md`](../../../docs/agents/open-source.md). Commits and pull requests follow [`CONTRIBUTING.md`](../../../CONTRIBUTING.md). Never add AI attribution anywhere.

## 1. Read

- The ticket, its phase issue, and the tickets it blocks or is blocked by (`gh issue view N`).
- The Jolt source it names, in `JoltComparison/.build/_deps/joltphysics-src` after one run of `compare.py`. Read Jolt's unit tests for the feature too.
- `CONTRIBUTING.md` (naming, hot-path rules) and `docs/validation.md`.

## 2. Choose the approach

Moonbounce beats Jolt by picking the fastest approach (algorithm, data layout), not by porting Jolt's and tuning instructions. Tuning comes second.

1. **Survey.** List the faster alternatives to Jolt's approach that are known for this problem, with sources.
2. **Ask why Jolt didn't use them.** Look in its code comments, `Docs/`, release notes, and the author's talks and GitHub discussions.
   - A reason that also binds Moonbounce rules an alternative out: robustness, jitter, determinism, memory per body or triangle.
   - A reason that doesn't bind it doesn't: 32-bit or WASM targets, C++ `constexpr`, MSVC limits.
3. **Look ahead.** For each candidate, list the later-phase features it could make harder, from the phase issues and Jolt's feature set. Choose a faster approach only when nothing planned would force a return to Jolt's. Otherwise keep Jolt's, or keep both and state the cost.
4. **Test behaviour, not Jolt's values.** Cover what Jolt's tests check. Don't copy a Jolt-specific value unless matching it is actually required.
5. **Ask when it changes direction.** If the choice departs from what the ticket says, or trades safety against the speed rule, ask the user with a recommended option first.

Record the choice, Jolt's reason, and the limitations you checked in the pull request description.

## 3. Branch, first commit, draft pull request

- Work in a fresh worktree from `origin/main`, on a branch named `feat/<issue>-<slug>`, `perf/…` or `docs/…`.
- Never `git stash` in a worktree: the stash list is shared by all worktrees, and a pop can apply another branch's work.
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
- Run `swift test` in Debug and in Release, and with `--traits DoublePrecision`.

## 5. Benchmark

- Add the benchmark to its suite under `Benchmarks/Sources/`, and a counterpart with the same name to `JoltComparison/` ([Adding a benchmark](../../../JoltComparison/README.md#adding-a-benchmark)).
- Both sides draw the same fixtures from SplitMix64, in the same order. Write separate C++ statements where argument order would otherwise be unspecified.
- Both sides use the same loop shape, the same sweeps per iteration, and an output array the black hole sees.
- Keep storage the operation reuses outside the measured region on both sides.

## 6. Validate on both tier 1 platforms

The gate, from `docs/validation.md`:
- even (within 5%) or faster than Jolt in wall time;
- retired instructions on macOS, cycles on Windows;
- 0 mallocs.

**macOS arm64.**
- Check the load average first (`uptime`). Another session's builds make wall times meaningless; wait until it is low.
- Run `python3 JoltComparison/compare.py --rounds 3 --filter '<Type>\..*'`.

**Windows x86-64.** Ask a Windows session to run it, if one is available: a peer session, reached with `SendMessage`. Send it exact steps:
- a clean detached checkout of the commit;
- `swift package clean`, then Debug `swift test`;
- `compare.py --rounds 3 --filter …`, with the output sent back verbatim, header included;
- a check that nothing else is loading the CPU;
- cleanup afterwards.

Hardware-counter profiling there needs the user's approval for each benchmark.

**When a row is slower:**
1. Find the cause. Read the generated assembly; cross-compile with `swiftc -target x86_64-apple-macos… -Xcc -march=x86-64-v3 -emit-assembly` to see x86-64 code on a Mac.
2. A/B the change against its base commit, alternating runs.
3. Try variants one at a time.

Don't loosen the benchmark or drop the feature. If the only fix trades safety or behaviour for speed, ask the user. A swing from code placement alone, with identical instructions, belongs in #47.

## 7. Review

The author never reviews its own change.
- **Who:** a separate reviewer agent with fresh context. It starts from the diff and the issue.
- **What to give it:** the facts you are claiming, as claims to verify, not as conclusions.
- **The loop:** fix every finding, then send the fixes back to the same reviewer. Repeat until it reports no findings.
- **Optional nits:** fold them into the next push that changes code. Don't push for a nit alone if a measurement is running on the current head.

## 8. Merge

1. Update the description with the comparison rows for both platforms: host, commit, and Jolt's compiler on Windows. Then mark the pull request ready.
2. When CI is green and the reviewer has approved, squash-merge with an explicit subject and body: `<type>(<scope>): <description> (#<pr>)`, one to three bullets, then `Closes #<ticket>`.
3. Confirm the ticket closed, then take the next one.

## Reporting

Tell the user what changed, what was verified and what is pending, in that order. Say plainly when a check could not run, and why.
