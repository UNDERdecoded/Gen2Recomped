# Legacy world orientation on LÖVE 12

The native preview bundles LÖVE 12. Its clip-space normalization changes the
result of legacy custom 3D shaders that already invert clip-space Y for LÖVE 11.
Unmodified Voxel Ascendant rendered a vertically inverted world in this preview,
including Red's house, while the separately composited UI remained upright.

The renderer keeps the producer's orientation with its returned world image.
Legacy Gen1–Gen3 world pipelines receive one vertical presentation mirror on
LÖVE 12, on both OpenGL and Metal. LÖVE 11 and native Gen4+ world images keep
their existing presentation. Engine-drawn field effects are counter-mirrored
inside the legacy image, preserving both their projected anchors and artwork.
The UI is composited separately and is never mirrored by this correction.

A pipeline that draws an already upright image using ordinary 2D drawing or
current clip coordinates can declare `worldOrientation = "native"` in its
`render_pipelines` definition. `worldOrientation = "legacy"` explicitly requests
the legacy convention. Detached `worldFormat = "renderData.v1"` pipelines retain
their native image convention. The optional metadata is additive; existing
legacy 3D mods need no source or manifest edits. A custom `render.compose` hook
receives `ctx.worldOverrideMirrored` with the image it is taking over.

`tests/engine/world_override_orientation.lua` exercises the real compositor,
separate UI, canvas lifetime and native field-effect transform using recording
graphics calls. GPU acceptance must additionally use asymmetric pixels and
inspect real mod scenes; merely finding a non-black or changing image cannot
establish the correct orientation.
