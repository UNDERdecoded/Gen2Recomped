# Frame-profile sections for world, presentation and DS audio

F11 enables the existing `FrameProfile` report. These additional sections use
its shared no-op closer when profiling is disabled; there is no new setting.
All labels begin with spaces, so nested timings do not get counted again as
top-level frame time. Multiple spans with the same label accumulate.

| Label | Work measured |
| --- | --- |
| `world: tiles` | Initial map/neighbour draws, declined-pipeline fallback and the flat upper layer |
| `world: entities` | Flat ghosts, main and above-layer entities, or tilted billboards |
| `world: FX` | Flat/tilted effect groups, pipeline `ctx.drawFx` and final map overlays |
| `tiles: ensureWindow` | Window validation/refill, including cached and missing-art returns |
| `renderer: zone blit` | Actual `blitCanvas` calls, including the unshaded fallback |
| `renderer: present pipeline` | Present processing and final native output |
| `voxel: sun pass` | Shadow preparation, including cache-hit/rate-limit decisions |
| `voxel: terrain` | Main and neighbouring terrain submission, per eye |
| `voxel: water` | Water draw-list construction, planar reflection and water submission, per eye |
| `voxel: cards` | Main character and staged-battle card submission, per eye |
| `audio: Nitro render` | One DS mixer block, including SoundData creation |

These are wall-clock submission timings, not GPU execution times. Reflection
copies of cards contribute to the water section; the cards section measures
the visible scene's card pass. The world labels describe selected drawing
phases rather than an exhaustive partition of `drawWorld`; setup, sorting and
other work remain visible in the enclosing section. Voxel timings run inside
the selected world pipeline. Hook names, arguments and dispatch order are
unchanged. An exception still takes its existing cleanup/error path; an
unfinished span is discarded by the existing profiler contract.

A1 adds observability and makes no performance claim. Desktop before/after
frame timings and ARM/device timings: **not measured**. Capture the same scene,
viewport, camera, mod configuration and profile window when measuring later
optimizations. Profiling itself is disabled by F11 / `FrameProfile.setEnabled(false)`.
