# 3. rapidhash for deterministic hashing

Status: accepted

## Context

The simulation's state hash and its deterministic containers (#78, #87) need a 64-bit hash that gives the same value on every platform and in every process. Swift's `Hasher` is seeded per process, so it can't serve.

The state hash runs over every body's position and rotation each step, so hashing bytes is on a hot path. [Jolt](https://github.com/jrouwe/JoltPhysics) hashes bytes with 64-bit FNV-1a, which reads one byte per step, and each step waits on the previous multiply. It mixes integers with Thomas Wang's 64-bit mix and combines hashes with mx3.

[rapidhash](https://github.com/Nicoshev/rapidhash) V3 (MIT), a successor of wyhash, reads 16 bytes per multiply below 112 bytes and runs seven independent multiply chains above it. It passes every test in SMHasher and SMHasher3.

## Decision

`DeterministicHash` hashes bytes with rapidhash V3, ported from its C reference with its default secrets. Integers and combining use rapidhash's mixing step: one 64-by-64-bit multiply, with the product's two halves xored together.

Jolt's reasons for FNV-1a don't bind Moonbounce:
- Jolt's `HashString` is `constexpr`, so string hashes can be `case` labels; MSVC can't evaluate a 128-bit multiply in a `constexpr`. Swift has no such use.
- Jolt supports 32-bit and WASM targets, where the 128-bit multiply is emulated. Moonbounce's targets, arm64 and x86-64, each do it in one or two instructions.

Limitations checked against later phases:

| Limitation | Effect on Moonbounce |
|---|---|
| Jolt's binary format stores FNV-1a hashes of class names. | None: Phase 9 (#41) uses Moonbounce's own format, and Jolt's assets come in through an exporter. |
| Two 64-bit keys can share a hash, where Wang's mix is a bijection. | None: hash tables and the contact cache compare keys and use the hash only to place entries. |
| Chaining two runs of bytes differs from hashing them joined. | None: the state hash only chains. `bytes(_:seed:)` documents it. |
| A running hash equal to one of rapidhash's secrets makes the next combine ignore its value. | Reachable only with chosen inputs, about 2⁻⁶⁴ per step. |

## Consequences

- Hash values are fixed: they are pinned in `DeterministicHashTests` from the C reference, and a recorded state hash must match in later releases. Changing the algorithm or its secrets is a breaking change.
- A hash of a value's bytes reads them in memory order, so it relies on every supported platform being little-endian, and on the type having no padding.
- State hashes can't be compared with Jolt's.
