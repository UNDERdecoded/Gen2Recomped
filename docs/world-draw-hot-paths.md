# P4: native world draw dispatch and private worklists

`Performance.worldDrawHoist` defaults to `true`. Set it to `false` to disable
private list reuse and whole-loop protection and restore per-frame bound FX,
height/entity/focus adapters and individual protected entity draws. The switch
is independent of P1–P3.

Native FX bodies, entity drawing, ground rise and canopy focus are methods with
explicit frame arguments. Ordinary flat draws use these methods directly.
Fresh no-argument bindings remain at public pipeline and billboard callback
seams: a retained FX callback must keep its own frame/camera. No record, method
signature, hook order or render pipeline field changes.

Reflectors use a private counted instance list; removed entities are released.
Reflection cover cells use two private numeric columns and a reusable seen set.
Nested draws borrow separate work storage while the outer lease is busy.
An overridden public `rippleCells` still receives fresh pair tables in the old
shape. None of the new pools is included in a public callback record.

The ordinary entity loop has one protected call. Its original sprite-depth
cleanup still runs before the original error is rethrown. The deferred above-
terrain pass retains its original ordering after the top layer.

The guarded native host runs 64 synthetic rectangle actors through actual
`drawWorld`, reflection coverage, FX and native canvas composition. There is no
ROM, save/profile, extracted asset or mod scene. Each phase has 120 warm-up and
120 measured frames; VSync 1, 60 Hz, P1/P3 enabled. GC is stopped in each measured
window to expose allocation growth, then restarted. Heap growth includes all
host/profiler allocations and is not retained memory or a leak measurement.

Observed macOS arm64, switch off → on:

| Tree / backend | F11 world entities, ms/frame | F11 FX, ms/frame | Raw draw mean, ms | CPU, ms/frame | Heap growth / 120 frames, KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fork / LÖVE 11.5 OpenGL | 0.04 → 0.05 | 0.01 → 0.01 | 0.395 → 0.468 | 1.101 → 1.243 | 2758 → 1059 |
| Fork / LÖVE 12 Metal | 0.02 → 0.02 | 0.01 → 0.01 | 16.405 → 16.408 | 0.728 → 0.703 | 2748 → 1043 |
| Public adaptation / LÖVE 11.5 OpenGL | 0.03 → 0.02 | 0.01 → 0.01 | 0.270 → 0.241 | 0.911 → 0.801 | 2758 → 1059 |
| Public adaptation / LÖVE 12 Metal | 0.02 → 0.02 | 0.01 → 0.01 | 16.417 → 16.407 | 0.612 → 0.597 | 2749 → 1043 |

Untimed protected calls fall from 55 to 1 in this scene (nine actors are deferred
to the above-terrain pass). Heap growth is about 61% lower. Short timing results
are mixed, and Metal can place GPU/VSync waiting in submission. No general FPS
or CPU improvement is established. Full game, Android, dedicated ARM handheld
and long session: not measured.

Reproduce with `tools/check_frame_pacing.py --world-draw --love /path/to/love
--report /owned/qa/world.json`. The guarded runner retains raw F11 logs and
measured-source fingerprints. `tests/engine/world_draw_hot.lua` exercises four
editions, operation order/coordinates, batch-call count, private list reuse,
shrinking lists, public ripple records, reentrant covers, retained FX callbacks
and sprite-depth cleanup. A separate local comparison with the unchanged
pre-P4 controller also matched all draw traces in those four editions.
