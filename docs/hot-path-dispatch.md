# P3: native update/draw dependency dispatch

`Performance.hotPathHoist` defaults to `true`. Set it to `false` to restore
per-call require/pcall dispatch, the per-frame blit closure and fresh native
presentation records independently of P1/P2.

`HotModules` lazily retains successful module values. Live fields and explicit
replacement or clearing of `package.loaded` remain observable; failed optional
loads are not cached. The Discord update uses its existing protected call with
the original `dt`, without allocating a wrapper closure after initialization.
No module path, hook argument or hook ordering changes.

The renderer's blit adapter carries DPI as explicit arguments and still calls
the public `blitCanvas` method. Its existing `uiPresentation` field becomes an
engine-owned live view. A table installed there by a consumer is never mutated
by the reuse path.

Only the unwrapped native renderer may borrow the private viewport scratch.
Public `endFrame` calls always return detached records, and replacing that
method bypasses the private shortcut. HUD hook arguments are detached at the
moment of dispatch, including a hook registered during compose/output. The
fork's window UI also retains its public record path. Scratch is never included
in a hook record.

Run `tools/check_frame_pacing.py --hot-path --love /path/to/love --report
/owned/qa/hot.json` through the QA storage guard. The owned synthetic state draws
a rectangle through real `Game:draw`, canvases and composition. Each switch
phase has 120 warm-up and 120 measured frames at 60 Hz, VSync 1, P1 enabled.
The log contains the actual F11 `draw: whole frame` section; raw JSON also records
total draw wall time, process CPU, source fingerprints and an untimed require
counter. This is not a complete overworld, battle or mod scene. Profiling is on
in both measured phases.

Measured on macOS arm64 (milliseconds/frame, switch off → on):

| Tree / backend | F11 draw (rounded) | Raw draw mean | Process CPU | require calls |
| --- | ---: | ---: | ---: | ---: |
| Fork / LÖVE 11.5 OpenGL | 0.16 → 0.21 | 0.166 → 0.218 | 0.787 → 0.919 | 15 → 6 |
| Fork / LÖVE 12 Metal | 16.36 → 16.38 | 16.373 → 16.383 | 1.134 → 1.026 | 15 → 6 |
| Public adaptation on ed5189c2 / LÖVE 11.5 OpenGL | 0.21 → 0.21 | 0.223 → 0.215 | 0.952 → 0.936 | 14 → 5 |
| Public adaptation on ed5189c2 / LÖVE 12 Metal | 16.44 → 16.44 | 16.455 → 16.449 | 0.844 → 0.831 | 14 → 5 |

Queue submission can absorb GPU/VSync waiting in Metal; these are wall-time
sections, not isolated GPU durations. The short runs show reduced dependency
dispatch and known allocations, with mixed CPU/timing results. They do not
establish a general frame-rate or CPU improvement. Dedicated ARM handheld,
Android, long-session and full-game measurements: not measured.

Regression checks cover cached dependency identity/replacement/retry, detached
public and late HUD records, method wrappers, DPI forwarding and private native
reuse. Existing output/hook tests and the compatibility acceptance are retained.
