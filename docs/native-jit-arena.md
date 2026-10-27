# Bounded native JIT arena on Apple silicon

The native arm64 macOS runtime repeatedly reported LuaJIT abort 27,
`failed to allocate mcode memory`, followed by complete trace-cache flushes.
Increasing only `maxtrace` and `maxmcode` did not solve it: control run
`1ef11c2b8e` still recorded 1,968 allocation failures/flushes. This is an
allocation-growth failure, rather than proof that the total code budget was
exhausted. No particular OS entitlement policy is claimed as its local cause.

`src/core/JitArena.lua` configures one 16 MiB area with a matching total
machine-code limit and 8,192 traces before native configuration loads game or
mod code. It retires a small bootstrap area once. Repeated configuration does
not flush a running session. Other architectures/OSes and disabled or missing
JIT controls retain their normal policy. Unsupported options leave boot usable. An explicit `POKEPORT_JIT_OPT=0` or custom option list retains its requested policy.
Game rules, fixed-step clocks and rendering quality settings are unchanged.

## Validation

- 30 focused runtime-policy checks: platform/disabled guards, bounded options,
  startup order, idempotence, explicit-policy priority and unsupported-option recovery.
- Public API-2 composition `f3266d366c` passes early-conf boot, the 30
  configuration checks, 10,851 identity / 211 map-view / 486 collision / 180
  warp checks, SDK 3/3 and Dramatic Shape B30.
- 10,851 map-identity, 211 owned-map-view, 486 collision, 121 compositor,
  125 shader and 151 orientation checks pass with the native change.
- Actual unchanged private Origami 1.0.9 (`ae59c77c`) on fork main
  `086cd06c` plus the compatibility changes, byte-checked native source
  `ffc1f74f09`, run `1ae548947f`: all three starting-room voxel views render
  and accept native movement, including after explicit collection.
- The actual run uses the native configuration, with no QA JIT override and
  no CPU sampling profiler. It records no machine-code allocation failure,
  no trace-cache flush in any measured window, and one earlier setup flush.
- M3/16 GB, Metal, logical/internal 1024x768, actual High preset, FXAA and
  original effects, supersampling off. Hardware turn held exclusively through
  source setup and final QA cleanup. Fresh owned profiles; player saves unused.

Each row is 120 ordinary walking frames after 360 settling frames, a 90-frame
idle sample and a separately timed collection/90-frame recovery observation.
The renderer frame serial advances once for every sample. Times include the
whole rendered-frame interval; callback draw timings are submission-side wall
measurements and can include GPU waits.

| View | Mean ms | FPS from mean | Median ms | p95 ms |
| --- | ---: | ---: | ---: | ---: |
| open | 8.62 | 116.0 | 8.46 | 11.71 |
| third | 20.59 | 48.6 | 17.21 | 34.25 |
| first | 21.26 | 47.0 | 17.71 | 33.89 |

Third/first-person averages and frame-time tails still miss a stable 60 FPS.
Their median is near one 60-Hz interval, while p95 includes doubled intervals.
Presentation/pacing/GPU-wait attribution remains to be measured. This bounded
starting-room result is not outdoor, full-gameplay or all-platform acceptance.
Explicit full collection is a separate lifetime stress test (roughly 244–310 ms
here), not included in the ordinary walking FPS above.

Contributions by Roxas2712 — https://github.com/Roxas2712.
See [the contribution terms](../LICENSE-ROXAS2712.md) for Cedric / UNDERdecoded's
specific incorporation permission and required credit. Existing notices remain.
