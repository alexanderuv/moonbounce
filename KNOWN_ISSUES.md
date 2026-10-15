# Known issues

Problems outside Moonbounce that it works around or can't yet work around. Each entry says what is affected, what Moonbounce does about it, and how to tell when it can be removed.

## x86-64 Windows: `SIMD4` arguments to async calls are corrupted

- **Affects:** x86-64 Windows, every optimization level. Upstream: [swiftlang/swift#90813](https://github.com/swiftlang/swift/issues/90813).
- **Cause:** a bug in LLVM's x86 backend.
  - The Win64 calling convention passes a 128-bit vector argument by pointer to a temporary copy.
  - Every Swift async call is a guaranteed tail call. For one of those, LLVM puts the copy in the caller's frame and frees that frame before the jump.
  - So a `SIMD4` passed into async code arrives corrupted, or crashes the process. Swift Testing's parameterized arguments take this path.
- **Workaround (#29):** on that target only, public types store their lanes as two `UInt64`s (`Sources/Moonbounce/Math/LaneStorage.swift`).
- **Removal:** the TODO at the top of `LaneStorage.swift` has a standalone check. The test `AsyncArgumentTests.rawSIMD4IsStillCorrupted` starts failing once the bug stops reproducing.

## x86-64 Windows without SSE4.1: no `roundevenf`

- **Affects:** baseline x86-64 Windows, the default target there.
- **Cause:** the target has no rounding instruction, so LLVM lowers the `roundeven` builtin to a call to the C23 function `roundevenf`. The Microsoft C runtime doesn't provide it, so linking fails.
- **Workaround (#29):** on that target, the shim's `mb_round` uses `mb_round_portable`, which rounds with arithmetic and gives the same bits.
- **Removal:** the TODO above `mb_round` in `Sources/_MoonbounceShims/include/_MoonbounceShims.h` says how to check a new toolchain.

## Windows: Swift Testing finds no tests in Release builds

- **Affects:** Windows arm64 and x86-64, Swift 6.4.1. Tracked in [#32](https://github.com/alexanderuv/moonbounce/issues/32).
- **Symptom:** `swift test -c release -Xswiftc -enable-testing` runs, reports `Test run with 0 tests`, and passes. Debug finds every test.
- **What is known:**
  - The Release test DLL contains the same `.sw5test` records as the Debug one, so discovery fails at run time.
  - `/OPT:NOREF` changes nothing.
- **Workaround:** none. CI builds Windows in Release but tests it only in Debug, so the optimized code is untested on Windows.
  - Every CI test step goes through `.github/scripts/swift-test.sh`, which fails a run that finds no tests.
- **Removal:** once a Release run on Windows finds the tests, add the "Test release" step back to the `windows` job in `.github/workflows/ci.yml`, and remove this entry and the matching gap in the Platforms section of `docs/validation.md`.

## Swift: indexing a borrowed `InlineArray` copies the whole value

- **Affects:** every platform, Swift 6.4, at every optimization level that matters (`-O`).
- **Cause:** `InlineArray`'s subscript and `span` depend on the array's address.
  - Swift doesn't let them depend on the address of a borrowed value, such as a parameter or an element read from an array, even one passed by address. It copies the whole value that holds the array to the stack first: 520 bytes for a `Polygon`, its count included.
  - A getter that takes a span copies on every call, even when the value is a local variable.
  - `borrowing` and `~Copyable` parameters copy too. A local variable read through the array's own subscript is read in place.
- **Workaround (#15):** `Polygon`'s clips take their input as a span, and a polygon's own clip methods take one span of it per call. Its element getter uses the storage's subscript. The rule is under Hot paths in `CONTRIBUTING.md`.
- **Removal:** compile this with `swiftc -O -parse-as-library -c` and disassemble `sum`:

  ```swift
  public struct P {
      var storage: InlineArray<32, SIMD4<Float>>
      var count: Int
  }

  @inline(never) public func sum(_ p: P) -> SIMD4<Float> {
      let vertices = p.storage.span
      var total = SIMD4<Float>()
      for i in 0..<p.count { total += vertices[i] }
      return total
  }
  ```

  It calls `memcpy` with 520 bytes, the whole of `P`, today. Once it reads `p` in place, the copy note on `Polygon` and the `CONTRIBUTING.md` rule can go, and this entry with them.

## Swift: the span of an empty array of vectors traps

- **Affects:** Swift 6.4, seen on macOS arm64 at every optimization level; other platforms not checked. Any `Array` or `ContiguousArray` with no storage of its own whose element is aligned to 16 bytes, such as `Vector3`, `Triangle` or `SIMD4<Float>`. The trap is in the caller's `.span`, so it reaches every API that takes a span of these, such as `VertexWelder.weld` and `unweld` and the `Polygon.clip` overloads, when the list is an empty array.
- **Cause:** every empty array without storage shares one empty buffer, whose element address is 8 bytes past a 16-byte boundary. `span` checks the alignment and stops with "baseAddress must be properly aligned to access Element". An array emptied with `removeAll(keepingCapacity: true)` keeps its own storage and is not affected.
- **Workaround (#16):** `VertexWelder.weld` takes the span of its vertex output only once it holds a vertex. A caller with nothing to pass can pass `Span()`, which is empty and works; `VertexWelderTests.emptySoupClearsTheOutputs` does.
- **Removal:** this program stops today, and prints 0 once the bug is fixed:

  ```swift
  let empty: [SIMD4<Float>] = []
  print(empty.span.count)
  ```

  Then the comments that cite this entry in `VertexWelder.swift` and `VertexWelderTests.swift` can go, and this entry with them.

## Swift: incremental Debug builds keep stale `@inline(always)` bodies

- **Affects:** Swift 6.4, seen on macOS arm64 with both SwiftPM build systems; other platforms not checked. Any module that calls a public `@inline(always)` function of another, such as the test target calling Moonbounce's hot paths. The bodies that reach the caller are that function's and those of every `@inline(always)` helper it inlines, internal `@inlinable @inline(always)` ones included.
- **Symptom:** after a change to any of those bodies, an incremental Debug build relinks without recompiling the caller, even when the public function itself is unchanged. Debug inlines `@inline(always)` bodies even at `-Onone`, so the caller keeps running the old code, and tests can pass or fail against code that no longer exists. An `@inlinable` body without `@inline(always)` isn't inlined at `-Onone`, so its change shows up. Release builds were not affected in the same check.
- **Workaround:** after changing any `@inline(always)` body, public or internal, run `swift package clean` before testing. CI builds from scratch and isn't affected.
- **Removal:** in a package with a library target `Lib` and an executable target `App`, build and run this, change the 1 to 2, then build and run again:

  ```swift
  // Lib
  @inline(always) public func value() -> Int { 1 }

  // App
  import Lib
  print(value())
  ```

  The second run prints 1 today. Once it prints 2, this entry can go.
