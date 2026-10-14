# Contributing

## Commits

Commit messages follow [Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<scope>): <description>

- <what changed and why>

Closes #<issue>
```

- **Description:** imperative mood, lowercase first word (type names such as `Matrix4x4` keep their case), no trailing period, the whole subject line under 72 characters.
- **Body:** optional. One to three bullets on what changed and why, not a replay of the diff.
- **Footer:** `Closes #<n>` for the ticket the commit completes, `Refs #<n>` for related ones. The phase lives in the ticket, so subjects carry no `[Phase N]` prefix.
- **Breaking changes:** add `!` after the type or scope and a `BREAKING CHANGE:` footer that says what callers must change. This applies before 1.0 too.

| Type | Use for |
|---|---|
| `feat` | New public API or capability |
| `fix` | Wrong behaviour corrected |
| `perf` | Same behaviour, faster or fewer instructions |
| `refactor` | No change to behaviour or speed |
| `test` | Tests or benchmarks only |
| `docs` | Documentation only, including the roadmap and ADRs |
| `build` | Package manifests, toolchain, compiler flags |
| `ci` | CI workflows |
| `chore` | Anything else that touches neither the library nor its tests |
| `revert` | Reverting an earlier commit |

The scope is optional and names the area touched: `math`, `geometry`, `shims`, `benchmarks` or `comparison` (the Jolt comparison script and harness). Add a scope when a new area appears, such as `collision` or `shapes` in Phase 3.

```text
feat(geometry): add ray vs sphere distance

- Solve the quadratic with a cancellation-free root finder
- Benchmark RaySphere.distance against Jolt

Closes #9
```

## Pull requests

Pull requests are squash-merged, and the PR title becomes the commit subject on `main`. Write the title as a Conventional Commits subject.

The description follows the [pull request template](.github/pull_request_template.md):

- **Summary:** one or two sentences on what changes and why, then `Closes #<n>`. A reviewer should know what they are looking at before opening the diff.
- **Changes:** the notable changes, by behaviour rather than by file. Leave this out when the summary already says it all.
- **Verification:** only what CI doesn't show. When a hot path or a benchmark changes, include the comparison script's rows for the affected benchmarks (benchmark, Moonbounce, Jolt, result). Leave this out otherwise.
- **Notes:** decisions, trade-offs, follow-ups, and anything deliberately left out. Leave this out when there are none.

Keep it short:

- Add a code snippet only when the public API's shape changes, or when a usage example says it faster than prose.
- Add a diagram (Mermaid) only for a flow or dependency structure that prose makes hard to follow.
- Delete empty sections. No file lists, no restating the diff, no tool banners.
