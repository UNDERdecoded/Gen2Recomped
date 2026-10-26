# P5: palette uploads and cropped zone quads

`Performance.paletteZoneCache` defaults to `true`; set it to `false` to restore
four fresh uniform vectors per zone and the original full-canvas/scissor blit.
This switch is independent of P1–P4.

Native uploads compute effective palette row indices without allocating the
intermediate inverted/shade-mapped palette tables. The public `effectiveColors`
and `permute` methods retain their existing return shape/identity behavior.
The names `c0`, `c1`, `c2`, `c3` remain unchanged; no uniform packing is introduced.

Each shader has a weakly held private last-value record and four reusable
vectors. All twelve normalized floats are compared; only changed rows are sent
inside one contiguous native blit. Every later blit starts with a full upload,
so direct raw shader writes between blits cannot leave stale colors. Public
`sendColors` calls always upload. Custom table send providers still receive fresh
vectors. Replacing public palette methods, graphics draw or shader dispatch
disables batch assumptions and preserves the original call seam.

The native nearest-filtered texture path uses one private cached Quad with
`setViewport`, clipped to the source canvas and the old pixel coverage. It is
limited to identity transforms, positive whole-framebuffer-pixel magnification
and origins, matching X/Y target DPI and nonnegative clipping boxes. Fractional
zoom/origins, flipped/scaled/rotated views, anisotropic DPI, linear filtering,
high-DPI source textures and compound render targets use the original path.
LÖVE 12 additionally requires target DPI 1/2/4 for exact half-pixel rounding.
Zones and their palettes are never changed or pooled.

LÖVE 11 truncates logical scissor arguments before DPI conversion; LÖVE 12 uses
float arguments and rounds physical scissor values. The crop deliberately
matches the existing behavior in each supported path. Primary API/backend
sources: [11.5 Lua API](https://github.com/love2d/love/blob/11.5/src/modules/graphics/wrap_Graphics.cpp#L524),
[11.5 backend](https://github.com/love2d/love/blob/11.5/src/modules/graphics/opengl/Graphics.cpp#L968),
[12 Lua API](https://github.com/love2d/love/blob/main/src/modules/graphics/wrap_Graphics.cpp),
[12 Metal backend](https://github.com/love2d/love/blob/main/src/modules/graphics/metal/Graphics.mm).

The guarded `tools/check_frame_pacing.py --palette-zones --love /path/to/love
--report /owned/qa/palette.json` first compares actual GPU readbacks byte for
byte. Each backend passes 432 cases across Red/Gold, four display modes,
shade-register remapping, overlapping/true-color zones, clipping, transforms,
three target densities, fractional origins/zoom and source filtering/density.
OpenGL exercises 48 optimized and 384 fallback cases; Metal 16 optimized and
416 fallback cases. First versions of the crop failed these tests and were
restricted/corrected before qualification. Uniform behavior has 491 focused
checks, including in-place palette mutations, raw shader writes between blits,
public wrappers and fresh consumer-owned vectors.

The timed workload draws 96 equal-palette zones over owned generated source
pixels, with 120 warm-up + 120 measured frames per switch phase, macOS arm64,
60 Hz/VSync 1. GC is stopped during each measured window to expose allocation
growth, then restarted. Heap growth includes host/profiler work and is not
retained memory or a leak measurement. Shader:send calls fall from 384 to four
per contiguous identical-palette blit; later blits still resynchronize.

| Tree / backend | F11 zone blit, ms/frame | Raw draw mean, ms | CPU, ms/frame | Heap growth / 120 frames, KiB |
| --- | ---: | ---: | ---: | ---: |
| Fork / LÖVE 11.5 OpenGL | 0.34 → 0.42 | 0.358 → 0.451 | 0.956 → 1.210 | 4368 → 49 |
| Fork / LÖVE 12 Metal | 16.39 → 16.40 | 16.397 → 16.407 | 0.630 → 0.613 | 4369 → 49 |
| Public adaptation / LÖVE 11.5 OpenGL | 0.41 → 0.22 | 0.445 → 0.243 | 0.968 → 0.705 | 4368 → 49 |
| Public adaptation / LÖVE 12 Metal | 16.37 → 16.35 | 16.376 → 16.364 | 0.759 → 0.735 | 4368 → 49 |

Timing/CPU results are mixed across short runs; no general FPS/CPU gain is
established. Metal queue submission can include GPU/VSync waiting. Full-game,
Android, dedicated ARM handheld and long session: not measured. Reports retain
the exact measured source fingerprints and raw F11 logs.
