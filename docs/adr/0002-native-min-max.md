# 2. Native min and max on each target

Status: accepted

## Context

Moonbounce's lane-wise minimum and maximum (`mb_min`, `mb_max`, their reductions and double forms, and the `min`, `max` and `clamped` built on them) are in the hot path of bounding boxes, ray tests, reductions and clamps. They were IEEE 754 minNum and maxNum on every target: a NaN operand yields the other operand.

arm64 has those instructions (`fminnm`, `fmaxnm`). x86-64 doesn't: its `minps` and `maxps` return the second operand whenever either is NaN. Keeping minNum there costs a NaN test and a blend on every min and max, on the dependency chain. Measured on Windows x86-64 for #26, that made `AABB.encapsulate`, `AABB.rayDistance`, `AABB4.rayDistance` and `Vector4.reduceMin` 1.3 to 2.5 times slower than [Jolt](https://github.com/jrouwe/JoltPhysics).

## Decision

Min and max are each target's native instruction: minNum and maxNum on arm64, `minps` and `maxps` on x86-64. The results are the same on every target except in two cases:
- With a NaN lane, arm64 returns the other operand's lane and x86-64 returns the second operand's lane.
- With zeros of opposite sign, arm64 orders -0 below +0 and x86-64 returns the second operand's lane.

Code that must skip NaN lanes says so, and either masks them first or puts the possible NaN in the first operand:
- `Vector4.lowestLane` and `highestLane` replace NaN lanes with infinities before reducing.
- On x86-64, the large-argument check in trigonometry compares lanes instead of reducing them.
- `clamped`, `MortonCode.interleave` and the generic float-to-integer conversion take the NaN as the first operand, so a NaN becomes the lower limit on every target.

## Consequences

- Each min and max is one instruction on both tier 1 platforms.
- A computation that reaches min or max with a NaN, or with zeros of opposite sign, can give different bits on arm64 and x86-64. Cross-platform determinism, when it lands, has to keep both out of min and max or mask them.
- New code that needs NaN lanes ignored can't rely on min or max for it, and must mask the lanes as `lowestLane` does or order the operands as `clamped` does.
