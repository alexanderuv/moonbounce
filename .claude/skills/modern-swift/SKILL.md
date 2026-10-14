---
name: modern-swift
description: Modern Swift ownership and performance features through Swift 6.4 — noncopyable and nonescapable types, borrowing/consuming, Span, InlineArray, UniqueBox, UniqueArray, Ref, borrow/mutate accessors, Mutex/Atomic — with the Swift version and OS each needs. Use when writing, reviewing or optimizing Swift code.
---

# Modern Swift (through 6.4)

Swift has an ownership model: values can be unique, borrowed, moved and viewed in place with no retain/release, no copy-on-write check and no heap allocation. Training data underuses it. On hot paths, reach for these tools before a class, an `Array` copy or an `Unsafe*Pointer`.

## Pick the tool

| Need | Reach for | Instead of |
|---|---|---|
| A resource with exactly one owner and deterministic cleanup (handle, buffer, token) | `struct T: ~Copyable { deinit {} }` | a `final class` with `deinit` |
| Pass without retain/release, or hand over ownership | `borrowing` / `consuming` parameters; `consume x` at the last use | relying on the optimizer |
| Read or write contiguous memory | `Span<T>` / `MutableSpan<T>` parameters, `.span` / `.mutableSpan` | `withUnsafeBufferPointer`, raw pointers |
| Initialize storage in place, no zero-fill | `OutputSpan` via `Array(capacity:initializingWith:)`, `withTemporaryAllocation` | `Array(repeating:)` then overwrite |
| A fixed-size collection | `InlineArray<N, T>` / `[N of T]` | `Array` (heap + CoW) or tuples |
| A growable buffer with no CoW, or noncopyable elements | `UniqueArray<T>` | `Array` |
| Put a large or noncopyable value on the heap with one owner | `UniqueBox<T>` | a wrapper class |
| Refer to a value or element without copying | `Ref<T>` / `MutableRef<T>` | copying out and writing back |
| Expose stored state without a copy | `borrow` / `mutate` accessors | `get`/`set` |
| Share mutable state across threads | `Mutex<State>`, `Atomic<T>` (`import Synchronization`) | class + `NSLock`, or an actor on a hot path |
| Generic code that must be fast across modules | `@specialized(where T == X)`, `@inline(always)`, `@export(implementation)` | hoping for specialization |

## Availability

The Swift version decides the syntax; for Apple platforms, the **OS** decides most stdlib types. Gate APIs newer than the deployment target with `if #available(macOS 27, *)`.

| Feature | Swift | SE | Runtime requirement |
|---|---|---|---|
| `~Copyable`, `deinit` on structs, `borrowing`/`consuming`, `consume`, `copy`, `discard self` | 5.9 | 0366, 0377, 0390 | none |
| Noncopyable generics and protocols, partial consumption, borrowing `switch`, `BitwiseCopyable` | 6.0 | 0426, 0427, 0429, 0432 | none |
| `Mutex`, `Atomic`, `WordPair`, `AtomicLazyReference` | 6.0 | 0410, 0433 | macOS 15 |
| Typed throws `throws(E)`, `sending` | 6.0 | 0413, 0430 | none |
| `Span`, `RawSpan`, `MutableSpan`, `MutableRawSpan`, `OutputSpan`, `extracting(_:)` | 6.2 | 0447, 0467, 0485, 0488 | none (back-deployed) |
| `.span` / `.mutableSpan` on Array, ContiguousArray, InlineArray, `String.utf8`, Data; `UTF8Span` | 6.2 | 0456, 0464 | macOS 26 |
| Integer generic parameters `<let N: Int>` | 6.2 | 0452 | none |
| `InlineArray`, `[N of T]` sugar | 6.2 | 0453, 0483 | macOS 26 |
| Using stdlib `~Escapable` types | 6.2 | 0446 | none |
| `nonisolated(nonsending)`, `@concurrent`, default `MainActor` isolation, `-strict-memory-safety` | 6.2 | 0461, 0466, 0458 | none |
| `@inline(always)`, `@specialized`, `@export(implementation/interface)`, `@c`, `@section`/`@used`, `weak let` | 6.3 | 0496, 0460, 0497, 0495, 0492, 0481 | none |
| `borrow` / `mutate` accessors | 6.4 | 0507 | none |
| Noncopyable `Equatable`/`Comparable`/`Hashable`; `~Copyable`/`~Escapable` associated types; `~Sendable` | 6.4 | 0499, 0503, 0518 | none |
| Span-based `withTemporaryAllocation`; `RawSpan.load(fromByteOffset:as:)` | 6.4 | 0524, 0525 | none (byte-order overload: macOS 27) |
| `UniqueBox`, `UniqueArray`, `Ref`/`MutableRef` | 6.4 | 0517, 0527, 0519 | macOS 27 |
| `Iterable` and borrowing `for-in` over Span, InlineArray, noncopyable elements | 6.4 | 0516 | macOS 27 |
| Noncopyable `Continuation` (`withContinuation`), `isTriviallyIdentical(to:)`, `withTaskCancellationShield` | 6.4 | 0528, 0494, 0504 | macOS 27 |
| `defer { await … }`, `@diagnose(Group, as:)`, `some P?`/`any P?` | 6.4 | 0493, 0522, 0521 | none |

Use only features that are stable in the toolchain: no `.enableExperimentalFeature(...)` and no underscored attributes (`@_lifetime`, `@_noAllocation`, `_read`/`_modify`, …).

**Not available in stable 6.4:** your own `~Escapable` types; returning a `Span` from a function or accessor (hand one out through a closure parameter instead); `yielding` accessors; `deinit` on a `~Copyable` enum; `RigidArray`; `import Containers`; `Span(ofOne:)`; `InlineArray` `==`/`Hashable`; `Optional.ref`; noncopyable `reduce`.

## Gotchas

- Ownership, exclusivity and lifetime errors are reported only during SIL. `swiftc -typecheck` accepts code that `swift build` rejects, so verify with a full build.
- `~Copyable` values cannot go in `Array`/`Set`/`Dictionary`, tuples or `Any`, and cannot conform to `CustomStringConvertible`. Store them in `InlineArray`, `UniqueArray` or `Optional`. Classes cannot be `~Copyable`.
- Generics and extensions assume `Copyable`: write `<T: ~Copyable>` and `extension P where Self: ~Copyable` to include noncopyable types.
- A live `Span` is an access to its owner: mutating the owner while a span exists is an exclusivity violation. Keep spans short-lived inside a `do { }` block, and bind `let s = a.span` before iterating.
- Without OS 27, `for x in span` and `for x in inlineArray` do not compile; loop over `indices`.
- `borrow`/`mutate` accessors are for structs and enums only, not classes or actors. A `{ borrow }` protocol requirement cannot be witnessed when the result type is `Int` or `Array` (6.4 reports "cannot witness borrow requirement"); generic `T` and `String` work.
- `discard self` requires the type to declare a `deinit`. A closure cannot consume a captured noncopyable value.
- `UniqueArray.edit { (out: inout OutputSpan<T>) in … }` does not grow storage; call `reserveCapacity` first or it traps.
- `Mutex` and `Atomic` are noncopyable: store them as `let` in a `final class` or a `~Copyable` struct.

Exact syntax for every row: [REFERENCE.md](REFERENCE.md).
