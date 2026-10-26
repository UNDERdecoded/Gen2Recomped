# World render and water budget (P8)

`V.renderBudget` defaults to `true` in `mods/DRAMATIC_SHAPE/main.lua`. Set it to
`false` to disable P8 independently: native window resolution, the previous water
algorithm with 24 ray steps / 5 refinements and analytic waves, original sends, uncached neighbor/atlas paths and string shape keys. The LÖVE 12 effect-signature correction is a
shader compatibility repair shared by both modes.

## RenderScale card

The RENDER SCALE row stores AUTO or an integer 1–4. AUTO uses two framebuffer
pixels per rendered pixel on Android/iOS, Switch/Horizon and Linux ARM; macOS and
other desktop hosts use one. Explicit choices remain available. The world renders
at ceil(width/factor) × ceil(height/factor), AA resolves at that size, then an owned
full-size canvas receives a nearest-filtered upscale. Projected field FX and the
world HUD use the corresponding scale. Engine UI and headset eye/mirror policy
retain their own existing resolution. Readable depth allocation tries depth16
first when the renderer reports OpenGL ES; desktop format preference stays intact.

## WaterBudget card

The WATER row adds AUTO. Existing FULL/SKY/OFF values retain their meaning and are
not rewritten. AUTO resolves to FULL on desktop HIGH and SKY on mobile/Linux ARM
or capped tiers. Existing tier ceilings still apply. Ray steps/refinements are
additive tier values, 12/3, with the old 24/5 fields retained for rollback. This is
a smaller reflection search budget, with corresponding visual differences.

A 256-square, repeat-wrapped R8 field stores a periodic approximation of the
existing wave trains at the existing quantized wave time. Spatial frequencies
round to complete cycles across the tile; temporal rates, weights, bend/swell and
height/normal controls stay derived from the authored tables. Wave lookup replaces
repeated sine evaluation in relief and normal sampling. Unsupported R8 rendering
retains analytic waves. Invalidation releases the field and its shader.

Reflective water shades into a separate half-width/half-height canvas. A flat
prepass preserves thin sheets and establishes surface depth. The expensive shader
reads full-resolution scene depth. A cheap second geometry draw composites the
nearest sampled result against the reattached full-resolution depth buffer; it is
not a rectangle laid over foreground objects. Failed allocation/binding restores
the complete full-resolution reflective path, with sticky target refusal until
invalidation. Planar reflection disables the simultaneous screen-space march and
its otherwise-unused cast copy. Off-plane planar fragments retain sky.

The GLES fragment default becomes mediump for color/lighting. World positions,
matrices, depth reconstruction and ray/relief calculations retain explicit high
precision. The installed LÖVE 12 parser requires effect parameter precision to
match its declaration; both switch modes use that signature. Plain/grid variants
compile natively; LÖVE 11 also validates both modes as GLES shader source. This is
not a measurement on an actual GLES device.

## Existing caches

ShaderState keeps persistent per-shader/per-name records and snapshots small
numeric vectors/matrices. It probes the first send, remembers absent uniforms,
then calls known sends directly when values change. Flag changes clear snapshots;
unknown names are not retried, while a first rejected value for a known name can
recover. Existing instanced-state copies remain supported. Water uses this path
only with P8 enabled.

Neighbor translations are private weak-key records with live offset validation.
The render-local atlas memo resolves each map/palette once for all passes in that
frame, avoiding repeated TerrainAtlas preparation and palette-key work without
changing its cross-frame invalidation. Gen-3 shape memoization uses class buckets,
separate pinned/unpinned buckets and numeric height keys. Persisted editor-key
formats are unchanged. No engine record or public mod interface receives these
caches. The manifest, permissions, engine-internals use and source notices remain.

## Reproduction and evidence

Run `python3 tools/check_render_budget.py --love /absolute/path/to/love --report
.local/qa/render-budget/profile.json` on one shell line. The guarded runner pins
inputs and uses an isolated identity. Its owned water and raised foreground quads
exercise actual scene/water shaders, canvas/depth handling, wave field and producer.
No ROM, imported artwork or player save is used. Readback checks preserve foreground
pixels and distinguish reflection from the flat fallback, including failed half
and R8 targets. Policy, nearest upscale, mutation-aware uniforms, unknown names,
live rollback, neighbor offsets, half-target size and planar/march exclusion are
also checked. Counts include individual foreground pixels and scene opens.

Each mode warms up 120 frames and measures 120. FrameProfile reports
`voxel.water submit (owned geometry)`; the separate completion value includes an
equal one-pixel GPU readback. Presentation and full-game FPS are excluded.

| Desktop macOS ARM64 host | Previous path | Budget |
| --- | ---: | ---: |
| LÖVE 11.5 OpenGL, CPU submission | 0.144 ms | 0.172 ms |
| LÖVE 11.5 OpenGL, GPU completion fence included | 1.375 ms | 0.882 ms |
| LÖVE 12 Metal, CPU submission | 0.125 ms | 0.104 ms |
| LÖVE 12 Metal, GPU completion fence included | 1.568 ms | 1.017 ms |

The added prepass/composite can cost submission time; OpenGL's final run does.
Other Metal runs also showed a small submission increase. The scoped reduction in
completion time is not a universal CPU/FPS claim. Mobile/handheld, populated maps,
VR and long-session behavior remain unmeasured. OpenGL passes 4094 scoped checks
(including two GLES validations), Metal 4092. Source hashes and acceptance are in
[render-budget-p8.json](qa/render-budget-p8.json).

Integrated fork: 478/478 engine suites, 3/3 SDK suites, 253 gallery checks,
200 API-3 comparisons / 400 workers and all 17 unchanged external fixture
entrypoints in complete mode pass. The public stack retains exactly its previous
29 FAIL lines across 11 inherited suites (156/167), with no new failing suite;
SDK 3/3, gallery 253, API-3 48/96 and all 17 external entrypoints pass.
