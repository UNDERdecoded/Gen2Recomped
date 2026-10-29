# Native source Game2 frame queries

`src.core.Game2` resolves to native `Game`, but the native class lacks the
source `frameFit(w,h)` and `viewport(w,h)` observations. An unchanged Gen2
scene therefore uses a fallback instead of asking its source owner.

Add passive queries through the existing Gen2 chrome and native viewport
owners: logical scale/origin, window DPI, actual drawable dimensions and
a detached classic 160x144 viewport result. They do not replace native
composition, mutate the cartridge or allocate another scene renderer.
Actual drawable-size queries use framebuffer coordinates. The shared
`PixelFit` helper extracts the existing compositor scale/origin arithmetic;
drawable inputs must not receive a second DPI multiplication.

This offer is based on the native viewport/touch stack in PR383. It includes
the already offered Chrome component from PR224 with all of its required
pieces: `Gen2Chrome`, its module alias, its palette-owner extension and its
tests. Inverted font ramps must be reversed after display-mode selection
and before the hardware shade-register permutation; the optional native
`effectiveColors(c,invert)` argument supplies that operation without a
second palette state. Calls without the optional flag retain their behavior.

Historical selected validation on offered implementation `5e4ee81f`:

- 3161 frame-query checks through the actual API2 SDK and the actual older
  native `Renderer:endFrame` compositor, across five GSC editions, six
  window shapes and DPI 1, 1.25, 1.5, 2 and 3. The newer fork's `frameRects`
  observation helper is not invented on this older host.
- 116 native menu-chrome checks, including inverted palettes with a
  noncommuting shade map, real font/box drawing and input/list behavior.
- The same frame-query probe fails cleanly on the preceding PR383 source
  `a3f0d344` because the two methods are missing.

The newer fork's real Metal test then exposed a case those initial logical
queries did not cover: unchanged VASC passes2048x1536 framebuffer dimensions
in a1024x768 DPI2 window. The initial query returned scale10.5/origin184,12;
the actual native compositor uses pixel scale10/origin224,48. That initial
candidate is rejected for coordinate acceptance. The expanded probe fails
263 of4454 checks on that fork candidate.

Offered correction `d3652034` independently passes4454 frame-query checks
through this older host's actual compositor and116 menu-chrome checks.
The expanded probe includes actual drawable arguments, the recorded Retina
regression, odd pixel dimensions and decorated native fitting. The same
shared-policy correction passes the newer fork's4454 query checks plus
its existing window/playfield/chrome regressions.

The newer fork's corrected source `123b8036` also passes a fresh actual Metal
checkpoint CONTINUE, connected walk and natural encounter with unchanged
VASC. Its observed drawable query returns scale10/origin224,48, matching
the native compositor. Four inspected owned OS images cover both selected
field camera flags; both select the same authored battle-stage view.
All 27336 mod files, their QA copies, the ROM and the earned source checkpoint
are unchanged. This is evidence for the shared coordinate correction on the
newer fork, not an actual GPU qualification of this older offered host.
Bottom command art remains partly clipped; full visual parity is rejected.

Complete combined-host tests, every custom skin/cutout/safe-area and odd
fractional-DPI logical configuration, physical Windows behavior, matched unchanged
mod GPU/actor pinning and release acceptance remain open. The concrete
missing API is established; this does not yet prove the cause or correction
of a particular clipped command card.

Source contract reviewed in Gen1Recomp `535a5ec0`, `src/core/Game2.lua`.
The existing Chrome component retains its original provenance and licence
conditions. Original engine authors' rights remain effective. Integration
and tests by Roxas2712 are offered under
<https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md>,
including its specific Cedric / UNDERdecoded permission with credit; this
does not replace earlier grants or assign ownership of the underlying engine.
