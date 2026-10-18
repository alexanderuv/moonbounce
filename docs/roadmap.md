# Roadmap

Moonbounce is heading toward a complete physics engine in Swift: rigid bodies first, then joints, characters, vehicles and soft bodies. Speed is a requirement from the start, not a later pass. Each piece lands with benchmarks, allocates nothing while stepping, and runs on macOS, Windows and Linux.

The engine is built from the bottom up:

1. **Foundations:** math, geometry, and the runtime underneath them: memory, containers and threads. The math and geometry are done, apart from two Windows benchmarks that still trail Jolt ([#105](https://github.com/alexanderuv/moonbounce/issues/105)); the runtime is next.
2. **Collision:** shapes and queries against them, then bodies, collision layers and the broad phase.
3. **Simulation:** a full rigid-body step, first on one thread, then across many, with the same results at any thread count.
4. **Engine features:** joints and ragdolls, character controllers, vehicles, and saved state with results that match across platforms.
5. **Beyond rigid bodies:** soft bodies, then hair and GPU compute as optional modules.

From the simulation stage on, the whole engine is measured on a set of standard scenes as well as per feature. [Validation](validation.md) defines when a feature is done.
