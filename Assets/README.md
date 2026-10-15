# Assets

Data from other projects that the tests and benchmarks read, each under a license compatible with Moonbounce's. [LICENSE](LICENSE) holds the notices.

| File | Contents | Source | SHA-256 |
|---|---|---|---|
| `convex_hulls.bin` | 6,755 point clouds of 4 to 100 points, from the game models of Horizon Zero Dawn, as sources of convex hulls | [Jolt Physics](https://github.com/jrouwe/JoltPhysics) v5.6.0, `Assets/convex_hulls.bin`, unchanged | `0d7d48ceccf29e141f5c96cba79325fe50db70753dff1f3abce2faef19b159c0` |

`convex_hulls.bin` holds its clouds back to back: each is a little-endian `UInt32` count of points, then each point as three little-endian `Float`s.
