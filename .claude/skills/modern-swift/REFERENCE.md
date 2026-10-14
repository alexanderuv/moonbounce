# Modern Swift syntax reference

Snippets compile with Swift 6.4. Comments mark the Swift version, and the OS where a stdlib type requires one.

## Noncopyable types and ownership (5.9 / 6.0)

```swift
struct FileHandle: ~Copyable {
    let fd: Int32
    deinit { close(fd) }

    borrowing func size() -> Int { /* read-only use */ 0 }

    consuming func release() -> Int32 {   // hand the fd to the caller, skip deinit
        let f = fd
        discard self
        return f
    }
}

func inspect(_ h: borrowing FileHandle) {}       // caller keeps ownership, no retain
func store(_ h: consuming FileHandle) {}         // callee takes ownership

let a = FileHandle(fd: 3)
let b = consume a                                 // move; `a` is no longer usable
store(b)

func log(_ s: borrowing String) { print(copy s) } // `copy` is required to copy a borrowed copyable value
```

Noncopyable generics, protocols and conditional copyability (6.0):

```swift
protocol Resource: ~Copyable { borrowing func id() -> Int }

struct Slot<T: ~Copyable>: ~Copyable { var value: T }
extension Slot: Copyable where T: Copyable {}

extension Resource where Self: ~Copyable {        // without this, the extension requires Copyable
    borrowing func describe() -> String { "\(id())" }
}
```

Borrowing switch and partial consumption (6.0):

```swift
enum Job: ~Copyable { case idle, running(FileHandle) }

func check(_ j: borrowing Job) -> Bool {
    switch j { case .idle: false; case .running: true }   // borrows, no copy
}

func finish(_ j: consuming Job) {
    switch consume j { case .idle: break; case .running(let h): store(h) }
}
```

Noncopyable conformances to `Equatable`/`Hashable` (6.4):

```swift
struct Token: ~Copyable, Hashable { var id: Int }
func same<T: Equatable & ~Copyable>(_ x: borrowing T, _ y: borrowing T) -> Bool { x == y }
```

## Span family (6.2)

```swift
func sum(_ s: Span<Float>) -> Float {
    var t: Float = 0
    for i in s.indices { t += s[i] }              // bounds-checked, no retain, no CoW check
    return t
}

func zero(_ s: inout MutableSpan<Float>) {
    for i in s.indices { s[i] = 0 }
}

var values: [Float] = [1, 2, 3]
let total = sum(values.span)                      // .span / .mutableSpan need macOS 26
var m = values.mutableSpan
zero(&m)

let middle = values.span.extracting(1..<2)        // sub-span, no copy
let header = data.bytes.load(fromByteOffset: 0, as: UInt32.self)   // RawSpan unaligned load (6.4)
```

In-place initialization with `OutputSpan`:

```swift
let squares = [Int](capacity: 8) { (out: inout OutputSpan<Int>) in
    for i in 0..<8 { out.append(i * i) }          // no zero-fill first
}

let r = withTemporaryAllocation(of: Int.self, capacity: 16) { (out: inout OutputSpan<Int>) -> Int in
    out.append(1)                                  // stack scratch buffer (6.4)
    return out.count
}
```

Stable Swift cannot return a `Span` from your own API. Take `Span` as a parameter, or hand one out through a closure:

```swift
struct Image {
    private var pixels: [UInt8]
    func withPixels<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R { try body(pixels.span) }
}
```

## Fixed-size and unique containers

```swift
struct Matrix<let N: Int> { var cells: [N of Float] }   // integer generic parameter (6.2)

var quad: [4 of Float] = [0, 1, 2, 3]                  // InlineArray sugar (6.2, macOS 26)
let zeros = InlineArray<16, Float>(repeating: 0)
let evens = InlineArray<4, Int> { i in i * 2 }
MemoryLayout<[16 of Float]>.size                       // 64: stored inline, no heap

var box = UniqueBox(LargeState())                      // single-owner heap box (6.4, macOS 27)
box.value.counter += 1
let twin = box.clone()                                 // explicit deep copy
let state = box.consume()                              // move the value out, free the box

var handles = UniqueArray<FileHandle>()                // growable, no CoW, noncopyable OK (6.4, macOS 27)
handles.reserveCapacity(16)
handles.append(FileHandle(fd: 4))
for h in handles { inspect(h) }                         // borrowing for-in (Iterable, 6.4, macOS 27)
```

## References (6.4, macOS 27)

```swift
var totals = [10, 20, 30]
var slot = MutableRef(&totals[1])                      // inout reference, nonescapable
slot.value += 4

let r = Ref(config)                                    // borrow reference, BitwiseCopyable
print(r.value.name)
```

## Accessors

```swift
struct Wrapper<Element: ~Copyable>: ~Copyable {
    private var _element: Element
    var element: Element {                             // 6.4: direct access, no coroutine, no copy
        borrow { return _element }
        mutate { return &_element }
    }
}

protocol Container { associatedtype E; var first: E { borrow mutate } }
struct Cell<T>: Container { var first: T }             // a stored property satisfies it, for some types only (see gotchas)
```

## Synchronization (6.0, macOS 15)

```swift
import Synchronization

final class Stats: Sendable {
    let hits = Atomic<Int>(0)
    let log = Mutex<[String]>([])
}

stats.hits.add(1, ordering: .relaxed)
let n = stats.hits.load(ordering: .acquiring)
stats.log.withLock { $0.append("frame") }
let pair = Atomic<WordPair>(WordPair(first: 1, second: 2))
```

## Codegen attributes (6.3)

```swift
@inline(always) func dot(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float { (a * b).sum() }  // class methods must be final

@specialized(where T == Float)
public func scale<T: BinaryFloatingPoint>(_ v: [T], by k: T) -> [T] { v.map { $0 * k } }

@export(implementation) public func fastPath() {}      // replaces @_alwaysEmitIntoClient
@c(moonbounce_step) public func step() {}              // replaces @_cdecl
```

## Concurrency odds and ends

```swift
func parse() throws(ParseError) -> AST                 // typed throws (6.0)
func make() -> sending Buffer                          // region transfer (6.0)
nonisolated(nonsending) func load() async {}           // runs on the caller's executor (6.2)
@concurrent func crunch() async {}                     // always off the caller's actor (6.2)
defer { await flush() }                                // async defer (6.4)
let v = await withContinuation(of: Int.self) { c in c.resume(returning: 42) }  // single resume checked at compile time (6.4, macOS 27)
```
