// Bytes hash with rapidhash V3 by Nicolas De Carli
// (https://github.com/Nicoshev/rapidhash), ported from its C reference and
// checked against it. rapidhash is based on wyhash by Wang Yi. Its license:
//
// Copyright (C) 2025 Nicolas De Carli
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

/// 64-bit hashes that are the same on every platform and in every process,
/// for the simulation's state hash and its deterministic containers. Swift's
/// `Hasher` is seeded per process, so it can serve neither.
///
/// Bytes hash with rapidhash V3 (docs/adr/0003). Integers and combining use
/// rapidhash's mixing step, one 64-by-64-bit multiply that folds the
/// product's halves together. A hash of a value's bytes reads them in memory
/// order, and every platform Moonbounce supports is little-endian. The values
/// never change between releases: a state hash recorded once must match
/// later.
@frozen
public enum DeterministicHash {
    /// The seed a hash of bytes starts from unless given another.
    public static let seed: UInt64 = 0

    /// The rapidhash of `bytes` with `seed`. Pass the result of an earlier
    /// call as the seed to chain several runs of bytes into one hash; the
    /// chain differs from the hash of the runs joined.
    @inline(always)
    public static func bytes(_ bytes: RawSpan, seed: UInt64 = seed) -> UInt64 {
        bytes.withUnsafeBytes { buffer in unsafe rapidhash(buffer, seed: seed) }
    }

    /// The rapidhash of `value`'s bytes with `seed`. The type must have no
    /// padding, whose bytes are undefined.
    @inline(always)
    public static func bytes<T: BitwiseCopyable>(of value: T, seed: UInt64 = seed) -> UInt64 {
        withUnsafeBytes(of: value) { buffer in unsafe rapidhash(buffer, seed: seed) }
    }

    /// The rapidhash of `string`'s UTF-8 bytes with `seed`. Strings that
    /// compare equal but differ in their bytes, such as "é" composed and
    /// decomposed, hash differently.
    @inlinable
    public static func string(_ string: String, seed: UInt64 = seed) -> UInt64 {
        var string = string
        return string.withUTF8 { utf8 in unsafe rapidhash(UnsafeRawBufferPointer(utf8), seed: seed) }
    }

    /// A hash of `value` for hash tables: one multiply by a fixed constant,
    /// with the product's two halves xored together.
    @inline(always)
    public static func mix(_ value: UInt64) -> UInt64 {
        multiplyFold(value ^ secret0, secret1)
    }

    /// Mixes the hash of `value` into `seed`. The order of values matters.
    @inline(always)
    public static func combine(_ seed: inout UInt64, _ value: some DeterministicHashable) {
        seed = multiplyFold(seed ^ secret0, value.deterministicHash ^ secret1)
    }

    /// The hash of several values in order: the first's hash, with each of
    /// the rest combined into it.
    @inline(always)
    public static func of<First: DeterministicHashable, each Rest: DeterministicHashable>(
        _ first: First, _ rest: repeat each Rest
    ) -> UInt64 {
        var seed = first.deterministicHash
        repeat combine(&seed, each rest)
        return seed
    }

    // MARK: rapidhash

    // rapidhash's default secrets.
    @usableFromInline static let secret0: UInt64 = 0x2D35_8DCC_AA6C_78A5
    @usableFromInline static let secret1: UInt64 = 0x8BB8_4B93_962E_ACC9
    @usableFromInline static let secret2: UInt64 = 0x4B33_A62E_D433_D4A3
    @usableFromInline static let secret3: UInt64 = 0x4D5A_2DA5_1DE1_AA47
    @usableFromInline static let secret4: UInt64 = 0xA076_1D64_78BD_642F
    @usableFromInline static let secret5: UInt64 = 0xE703_7ED1_A0B4_28DB
    @usableFromInline static let secret6: UInt64 = 0x90ED_1765_281C_388C
    @usableFromInline static let secret7: UInt64 = 0xAAAA_AAAA_AAAA_AAAA

    /// The 128-bit product of `a` and `b`, as rapidhash's `rapid_mum`.
    @inlinable @inline(always)
    static func multiply(_ a: UInt64, _ b: UInt64) -> (low: UInt64, high: UInt64) {
        let product = a.multipliedFullWidth(by: b)
        return (product.low, product.high)
    }

    /// The two halves of the 128-bit product of `a` and `b`, xored together,
    /// as rapidhash's `rapid_mix`.
    @inlinable @inline(always)
    static func multiplyFold(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let product = multiply(a, b)
        return product.low ^ product.high
    }

    @unsafe @inlinable @inline(always)
    static func read64(_ key: UnsafeRawBufferPointer, _ offset: Int) -> UInt64 {
        UInt64(littleEndian: unsafe key.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    @unsafe @inlinable @inline(always)
    static func read32(_ key: UnsafeRawBufferPointer, _ offset: Int) -> UInt64 {
        UInt64(UInt32(littleEndian: unsafe key.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
    }

    /// rapidhash V3 of `key` with `seed` and the default secrets, as the
    /// reference's `rapidhash_withSeed`.
    @unsafe @inlinable @inline(always)
    static func rapidhash(_ key: UnsafeRawBufferPointer, seed: UInt64) -> UInt64 {
        let count = key.count
        var seed = seed ^ multiplyFold(seed ^ secret2, secret1)
        var a: UInt64 = 0
        var b: UInt64 = 0
        var remaining = count
        if count <= 16 {
            if count >= 4 {
                seed ^= UInt64(count)
                if count >= 8 {
                    a = unsafe read64(key, 0)
                    b = unsafe read64(key, count - 8)
                } else {
                    a = unsafe read32(key, 0)
                    b = unsafe read32(key, count - 4)
                }
            } else if count > 0 {
                a = unsafe UInt64(key[0]) << 45 | UInt64(key[count - 1])
                b = unsafe UInt64(key[count >> 1])
            }
        } else {
            var p = 0
            if remaining > 112 {
                var see1 = seed, see2 = seed, see3 = seed
                var see4 = seed, see5 = seed, see6 = seed
                repeat {
                    seed = unsafe multiplyFold(read64(key, p) ^ secret0, read64(key, p + 8) ^ seed)
                    see1 = unsafe multiplyFold(read64(key, p + 16) ^ secret1, read64(key, p + 24) ^ see1)
                    see2 = unsafe multiplyFold(read64(key, p + 32) ^ secret2, read64(key, p + 40) ^ see2)
                    see3 = unsafe multiplyFold(read64(key, p + 48) ^ secret3, read64(key, p + 56) ^ see3)
                    see4 = unsafe multiplyFold(read64(key, p + 64) ^ secret4, read64(key, p + 72) ^ see4)
                    see5 = unsafe multiplyFold(read64(key, p + 80) ^ secret5, read64(key, p + 88) ^ see5)
                    see6 = unsafe multiplyFold(read64(key, p + 96) ^ secret6, read64(key, p + 104) ^ see6)
                    p += 112
                    remaining -= 112
                } while remaining > 112
                seed ^= see1
                see2 ^= see3
                see4 ^= see5
                seed ^= see6
                see2 ^= see4
                seed ^= see2
            }
            if remaining > 16 {
                seed = unsafe multiplyFold(read64(key, p) ^ secret2, read64(key, p + 8) ^ seed)
                if remaining > 32 {
                    seed = unsafe multiplyFold(read64(key, p + 16) ^ secret2, read64(key, p + 24) ^ seed)
                    if remaining > 48 {
                        seed = unsafe multiplyFold(read64(key, p + 32) ^ secret1, read64(key, p + 40) ^ seed)
                        if remaining > 64 {
                            seed = unsafe multiplyFold(read64(key, p + 48) ^ secret1, read64(key, p + 56) ^ seed)
                            if remaining > 80 {
                                seed = unsafe multiplyFold(read64(key, p + 64) ^ secret2, read64(key, p + 72) ^ seed)
                                if remaining > 96 {
                                    seed = unsafe multiplyFold(read64(key, p + 80) ^ secret1, read64(key, p + 88) ^ seed)
                                }
                            }
                        }
                    }
                }
            }
            a = unsafe read64(key, p + remaining - 16) ^ UInt64(remaining)
            b = unsafe read64(key, p + remaining - 8)
        }
        a ^= secret1
        b ^= seed
        let product = multiply(a, b)
        return multiplyFold(product.low ^ secret7, product.high ^ secret1 ^ UInt64(remaining))
    }
}

/// A type whose hash is the same on every platform and in every process, so
/// the deterministic containers can key on it.
public protocol DeterministicHashable {
    /// The value's hash, the same everywhere for equal values.
    var deterministicHash: UInt64 { get }
}

extension Int32: DeterministicHashable {
    /// ``DeterministicHash/mix(_:)`` of the value's bits.
    @inline(always)
    public var deterministicHash: UInt64 { DeterministicHash.mix(UInt64(UInt32(bitPattern: self))) }
}

extension UInt32: DeterministicHashable {
    /// ``DeterministicHash/mix(_:)`` of the value.
    @inline(always)
    public var deterministicHash: UInt64 { DeterministicHash.mix(UInt64(self)) }
}

extension Int64: DeterministicHashable {
    /// ``DeterministicHash/mix(_:)`` of the value's bits.
    @inline(always)
    public var deterministicHash: UInt64 { DeterministicHash.mix(UInt64(bitPattern: self)) }
}

extension UInt64: DeterministicHashable {
    /// ``DeterministicHash/mix(_:)`` of the value.
    @inline(always)
    public var deterministicHash: UInt64 { DeterministicHash.mix(self) }
}

extension Int: DeterministicHashable {
    /// As for `Int64`.
    @inline(always)
    public var deterministicHash: UInt64 { Int64(self).deterministicHash }
}

extension UInt: DeterministicHashable {
    /// As for `UInt64`.
    @inline(always)
    public var deterministicHash: UInt64 { UInt64(self).deterministicHash }
}

extension Float: DeterministicHashable {
    /// ``DeterministicHash/mix(_:)`` of the value's bits, with -0 hashed as 0
    /// since the two are equal.
    @inline(always)
    public var deterministicHash: UInt64 { DeterministicHash.mix(UInt64((self == 0 ? 0 : self).bitPattern)) }
}

extension Double: DeterministicHashable {
    /// ``DeterministicHash/mix(_:)`` of the value's bits, with -0 hashed as 0
    /// since the two are equal.
    @inline(always)
    public var deterministicHash: UInt64 { DeterministicHash.mix((self == 0 ? 0 : self).bitPattern) }
}
