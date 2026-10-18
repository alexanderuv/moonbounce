# Contributing

## Code

### Naming

Types use full words, per the Swift API Design Guidelines: `Vector3`, `Quaternion`. A vector of something other than `Float` puts the element type first: `UInt32Vector4`. Terms of art keep their usual names: `AABB`, `Ray`.

### Hot paths

A hot path is anything a simulation step can call per body or per constraint. Each rule below closed a gap that a benchmark measured; the comment cited for it explains why.

- **3D vectors are `SIMD4<Float>` with z repeated in w,** never `SIMD3<Float>` (`Vector3`; `StorageInvariantTests` pins the invariant).
- **Vector math goes through `SIMDPrimitives.swift`:** min/max, reductions, shuffles, fused multiply-adds and negation, backed by `_MoonbounceShims` (the file's header comment).
- **Public hot-path API is `@inline(always)` on `@frozen` types** (`Vector3`). On a public declaration that implies `@inlinable`, so write `@inline(always)` alone. An internal helper called from inlined code is `@inlinable @inline(always)`. Setup and serialization API, such as Euler angles or compression, is `@inlinable` and leaves inlining to the optimizer.
- **Square roots are `hardwareSquareRoot()`, never `squareRoot()`** (`SIMDPrimitives.swift`). On every platform but Apple's (Windows and Linux), `squareRoot()` of a negative `Float` or `Double` calls the C library to set `errno`, a function call on every miss of a ray test; `hardwareSquareRoot()` is the bare instruction with the same value.
- **SIMD constants are computed properties** (`signMask` in `Trigonometry.swift`). Scalar constants stay `let`.
- **Option sets combine with `union`, never an array literal** (`SimplexFeature`). Inlined into a large caller, a literal such as `[.a, .b]` can stay an array that is allocated on every call.
- **`InlineArray` storage is read in place only from a variable** (`Polygon`; [known issue](KNOWN_ISSUES.md#swift-indexing-a-borrowed-inlinearray-copies-the-whole-value)). To read a parameter or other borrowed value by index, Swift first copies the whole value to the stack. So an operation over a list of values takes it as a span, a loop over a borrowed one takes a single span up front, and an element getter uses the storage's own subscript, which reads a variable in place, rather than a span, which copies even then.
- **Scratch that starts empty is a temporary allocation** (`Polygon.clip`). A new `InlineArray` fills every slot, which costs more than the work for a few vertices; `withUnsafeTemporaryAllocation` gives uninitialized stack memory instead, but only up to 1,024 bytes ([known issue](KNOWN_ISSUES.md#swift-temporary-allocations-over-1-kib-go-to-the-heap)). Larger scratch is allocated once by a noncopyable value that the caller keeps and reuses (`EPA`).

Benchmarks have their own conventions, in [validation](docs/validation.md#benchmarks).

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

There is no catch-all section. A decision that outlives the PR goes in an ADR, and a follow-up goes in an issue.

Keep it short:

- Add a code snippet only when the public API's shape changes, or when a usage example says it faster than prose.
- Add a diagram (Mermaid) only for a flow or dependency structure that prose makes hard to follow.
- Delete empty sections. No file lists, no restating the diff, no tool banners.
