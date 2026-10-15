# Roadmap

Moonbounce is built in phases, from the math core up to a complete physics engine: rigid bodies, constraints, characters, vehicles and soft bodies. Each phase ships tested and benchmarked features. A feature is not done until its benchmark is fast enough and it allocates nothing while stepping; [Validation](validation.md) has the full rules.

## Phases

Each phase's issue lists its features, the benchmarks that measure them and the tests that cover them.

| Phase | Delivers | Issue |
|---|---|---|
| 0 | Math core: vectors, quaternions, bounding boxes, rays | Done |
| 1 | Math and geometry: matrices, trigonometry, ray tests, closest points, GJK, EPA, convex hulls | [#33](https://github.com/alexanderuv/moonbounce/issues/33), in progress |
| 2 | Core runtime: allocators, containers, synchronization, the job system | [#34](https://github.com/alexanderuv/moonbounce/issues/34) |
| 3 | Collision shapes and queries | [#35](https://github.com/alexanderuv/moonbounce/issues/35) |
| 4 | Bodies, collision layers and the broad phase | [#36](https://github.com/alexanderuv/moonbounce/issues/36) |
| 5 | Rigid-body simulation on one thread | [#37](https://github.com/alexanderuv/moonbounce/issues/37) |
| 6 | Multithreaded simulation | [#38](https://github.com/alexanderuv/moonbounce/issues/38) |
| 7 | Constraints, ragdolls and skeletal animation | [#39](https://github.com/alexanderuv/moonbounce/issues/39) |
| 8 | Character controllers | [#40](https://github.com/alexanderuv/moonbounce/issues/40) |
| 9 | Saved state, cross-platform determinism, serialization | [#41](https://github.com/alexanderuv/moonbounce/issues/41) |
| 10 | Vehicles | [#42](https://github.com/alexanderuv/moonbounce/issues/42) |
| 11 | Soft bodies | [#43](https://github.com/alexanderuv/moonbounce/issues/43) |
| 12 | Hair and GPU compute, as optional modules | [#44](https://github.com/alexanderuv/moonbounce/issues/44) |
| — | Tooling: debug drawing, build configuration | [#45](https://github.com/alexanderuv/moonbounce/issues/45) |

Phases mostly run in order. Phase 2 can proceed alongside Phases 1 and 3. Phase 8 needs only Phase 5. After Phase 6, Phases 7, 9, 11 and 12 are independent of each other, and Phase 10 follows Phase 7.

## Milestones

Besides per-feature benchmarks, the engine is measured as a whole on a set of [standard scenes](validation.md#end-to-end-scenes). They come online as the phases land:

- **Phase 5:** stacking, convex bodies on meshes, very large meshes and body counts, and fast-moving bodies, on one thread.
- **Phase 6:** the same scenes at any thread count, with identical results.
- **Phase 7:** ragdolls.
- **Phase 8:** characters.
- **Phase 9:** identical results on macOS and Windows.
