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
