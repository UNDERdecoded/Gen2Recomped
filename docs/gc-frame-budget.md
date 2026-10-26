# P2: incremental GC in unused deadline time

`Performance.gcBudget` defaults to `true`. At boot the collector uses pause 120
and step multiplier 300. Each concrete `Performance.CAPS` row additionally has
`gcPause`, `gcStepMul` and `gcBudgetSeconds`; tiers may reduce the default
0.0005-second idle allowance. No options are rewritten.

The ordinary engine's fixed `step(1)` moves out of `Game:update`. The run loop
uses no-argument incremental steps before its remaining software wait. It starts
no further step after the earlier of the actual deadline and the half-millisecond
allowance, and stops on completion of a cycle. An expired deadline or a stopped
collector receives no work. VSync never gets an invented future budget; only
the actual remainder of its carried deadline is eligible, and no extra sleep
is added after VSync.

The budget is cooperative: a single indivisible collector step can finish past
the boundary. It is not a preemption guarantee for an arbitrary heap/finalizer.
The F11 child section `frame pacing: gc budget` is nested in the existing
`frame pacing: sleep` section, so the parent includes collection plus waiting.

The fork's pre-existing Gen3 `Game3.stepGC` delegation stays at its original
update boundary with the original arguments/behavior. A frame owned by that
public seam gets no second idle GC service. Its delegated/custom work remains
outside the engine idle allowance. This preserves consumers that replace it.

The independent rollback switch is:

```lua
require("src.core.Performance").gcBudget = false
```

The next frame restores the previous pause/multiplier and uses the old native
update step. The separate P1 switch and callback interfaces are unchanged.

`tools/check_frame_pacing.py --gc --love /path/to/love --report /owned/qa/gc.json`
runs the guarded native comparison. P1 stays enabled for both phases; only P2
changes. The workload allocates 512 short tables per frame, with 120 warm-up
and 120 measured frames per phase. Raw FrameProfile logs, original tuning,
heap samples and measured-source SHA-256 hashes are retained.

Observed composed fork, macOS/arm64, 60 Hz, VSync 1, cap 60:

| Backend | Original fixed step, ms/frame | New idle mean / max, ms | Heap peak before / after, KiB |
| --- | ---: | ---: | ---: |
| LÖVE 11.5 OpenGL | 0.00 (rounded) | 0.098 / 0.499 | 918 / 775 |
| LÖVE 12 Metal | 0.00 (rounded) | 0.120 / 0.278 | 1,179 / 692 |

Short-workload CPU means were 1.012 → 0.920 ms/frame and 0.717 → 0.651 ms/frame,
respectively. Both retained approximately 60 FPS and restored the original
200/200 tuning when disabled. These are bounded synthetic allocation checks,
not full-game heap, long-session, arbitrary-finalizer or handheld measurements.
