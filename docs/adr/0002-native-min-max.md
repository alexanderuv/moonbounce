# 2. Native min and max on each target

Status: accepted

## Context

Moonbounce's lane-wise minimum and maximum (`mb_min`, `mb_max`, their reductions and double forms, and the `min`, `max` and `clamped` built on them) are in the hot path of bounding boxes, ray tests, reductions and clamps. They were IEEE 754 minNum and maxNum on every target: a NaN operand yields the other operand, so even NaN inputs gave the same bits everywhere.

arm64 has those instructions (`fminnm`, `fmaxnm`). x86-64 doesn't: its `minps` and `maxps` return the second operand whenever either is NaN. Keeping minNum there costs a NaN test and a blend on every min and max, on the dependency chain. Measured on Windows x86-64 for #26, that made `AABB.encapsulate`, `AABB.rayDistance`, `AABB4.rayDistance` and `Vector4.reduceMin` 1.3 to 2.5 times slower than [Jolt](https://github.com/jrouwe/JoltPhysics), which uses `minps` and `maxps` directly.

## Decision

Min and max are each target's native instruction: minNum and maxNum on arm64, `minps` and `maxps` on x86-64. The results are the same on every target unless a lane is NaN. With a NaN lane, arm64 returns the other operand's lane and x86-64 returns the second operand's lane.

Code that must skip NaN lanes says so and masks them first:
- `Vector4.lowestLane` and `highestLane` replace NaN lanes with infinities before reducing.
- The large-argument check in trigonometry compares lanes rather than reducing them.

## Consequences

- Each min and max is one instruction on both tier 1 platforms. On Windows x86-64, `Vector4.reduceMin` went from 2.5 times slower than Jolt to 59% faster, and `AABB4.rayDistance` from 2.3 times slower to 24% faster.
- A computation that reaches min or max with a NaN can give different results on arm64 and x86-64. A simulation with NaN state is already invalid, so cross-platform determinism holds for valid inputs; it doesn't cover NaN.
- New code that needs NaN lanes ignored can't rely on min or max for it, and must mask the lanes as `lowestLane` does.
