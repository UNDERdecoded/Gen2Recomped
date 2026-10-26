# Optional shader presets

OPTIONS -> SHADER PRESET opens a shared picker on GB, GBA and DS games.
The default is OFF. WARM DISPLAY and SOFT LCD are bundled, adjustable examples;
local presets appear after them in filename order. Select with A, then SELECT
on the active preset to edit its parameters. Left/Right or A changes a value;
SELECT resets that value. B/START returns. Changes use the ordinary options
save path, including existing generation-specific option overrides.

The options and shader-control screens bypass this effect so they remain
readable. F8 turns the preset OFF and saves that choice even when another
screen captures keyboard input. A failed selection shows a separate error
page and keeps the last working preset. If a saved preset is unavailable,
startup falls back to OFF without deleting the saved choice. Missing shader
support, allocation errors and render/uniform errors also fall back to the
unfiltered input; a failing active effect is retired until explicitly selected
again. This handles reported API errors, not GPU-driver hangs or the visual
quality of arbitrary user shaders.

## Local format

Place a JSON descriptor and a LÖVE-compatible fragment shader in
`shader-presets/` in the active game-data folder (the normal LÖVE save folder,
portable folder, or the folder selected in the launcher). Discovery uses the
same `CacheFs.dataFs()` read union as other installation data. Reopen the
picker and select the preset again after editing its files.

Example `shader-presets/dim.json`:

```json
{
  "format": 1,
  "name": "DIM DISPLAY",
  "shader": "dim.glsl",
  "parameters": [
    { "id": "brightness", "name": "BRIGHTNESS",
      "min": 0.2, "max": 1.0, "step": 0.05, "default": 0.8 }
  ]
}
```

Matching `shader-presets/dim.glsl`:

```glsl
extern number brightness;

vec4 effect(vec4 color, Image image, vec2 uv, vec2 pixel) {
  vec4 c = Texel(image, uv) * color;
  return vec4(c.rgb * brightness, c.a);
}
```

Descriptors are data only; no Lua is loaded. Filenames contain only letters,
digits, `_` or `-` followed by `.json`/`.glsl`; paths and subdirectories are
not accepted. Names are 1–48 printable ASCII characters and are shortened in
the fixed-width menu. Descriptors are limited to 16 KiB and shader source to
64 KiB. Invalid descriptors remain visible as INVALID; one bad file does not
hide the other presets.

Up to eight scalar parameters are supported. Each requires a unique GLSL
identifier `id`, display `name`, finite `min < max`, positive `step` no larger
than the range, and an in-range `default`. A range may contain at most one
million steps. The compiled shader must expose each declared parameter as a
uniform. Saved values are clamped and snapped to steps; non-finite values use
the default. Defaults themselves are snapped to the same step grid, so reset
and first use agree. Parameter changes send uniforms without recompiling the shader.
`sourceSize`, `pixelScale` and names beginning with `love_` are reserved.

Two optional uniforms are supplied when the shader uses them:

| Uniform | Meaning |
| --- | --- |
| `extern vec2 sourceSize` | Input texture size in physical framebuffer pixels |
| `extern number pixelScale` | Renderer's physical pixels per native game pixel, at least 1 |

Presets must use LÖVE's `effect()` convention and support the target's GLSL
or GLSL ES dialect. The offline `.slangp` importer described below can generate
compatible local presets. There is one selected preset; the game loads no
native compiler or shader-pack downloader.

## Rendering and persistence

The pass processes the completed **primary game view**: world, ordinary game
menus/dialogues, transitions and screen veils. It runs after mod
`render_pipelines.present` and before the existing GBC FX LCD effect. When
GBC colour correction from PR #89 is installed, that remains before the mod
pipelines and this preset pass. Touch controls, `render.hud` overlays and
separately composed DS lower displays retain their existing later draw paths.
A mod that fully handles `render.compose` also retains control of its output.

OFF preserves the existing render path without enumeration, shader compilation
or another render target. Active output preserves the input's unit dimensions
and DPI scale. Targets are reused, recreated/released on resize or DPI changes,
and released with the shader on OFF or replacement. GPU state is enclosed by
`push("all")`/`pop()`; the input is never the active output target.

The additive keys are `options.shaderPreset` (`"off"`, `"builtin:warm"`,
`"builtin:soft-lcd"`, or `"local:<descriptor-basename>"`) and
`options.shaderPresetParams[presetId][parameterId]`. Values belonging to other
presets are preserved. Old option files need no migration and remain OFF.
Custom shaders can be expensive; this first version does not assign device
performance tiers or claim validation on mobile hardware.

## Verification

```sh
luajit tests/engine/shader_presets.lua
love tools/shader-preset-check
```

The ROM-free unit suite covers discovery, validation, persistence, parameter
editing, recovery, menu navigation and resource/state lifetime. The GPU tool
validates bundled sources for desktop GL and GLES, compares real pixels at DPI
1/2/2.75, checks alpha and physical-size uniforms, renders the real
`Renderer:endFrame` path, verifies OFF/identity equivalence and stage ordering,
and injects a draw error to check fallback/state restoration. Set
`SHADER_PRESET_CHECK_SHOT=/absolute/path.png` to export its comparison sheet.
It uses synthetic pixels and the engine's fallback font, with no ROM or saves.

## Importing RetroArch `.slangp` presets

The optional offline importer builds on this preset picker. It uses
librashader 0.12 (preprocessing, SPIR-V compilation/reflection and GLSL
emission), adapts both vertex and fragment stages to LÖVE, and writes a
local preset. The game does not load Rust, invoke a compiler or download
shader packs. Conversion is a command-line step; there is no `.slangp`
file picker in the game in this PR.

Install Rust and LÖVE 11.5 on a desktop with a working graphics display,
then run from the checkout:

```sh
cargo build --manifest-path tools/slang-import/Cargo.toml --release --locked
# Supply your own shader pack and the active game-data folder.
tools/slang-import/target/release/gen2-slang-import \
  /path/to/slang-shaders/handheld/lcd3x.slangp \
  /path/to/game-data/shader-presets --name "LCD3X"
```

Windows uses `gen2-slang-import.exe`. If `love` is not on PATH, add
`--love /absolute/path/to/love` (on macOS, the executable inside
`love.app/Contents/MacOS/love`). Building the importer needs a C++ compiler
for its compiler dependencies; it is independent of normal game builds.
Cargo.lock pins the dependency graph. CI builds/tests the tool on Linux,
macOS and Windows and exercises LÖVE under a virtual display on Linux.

The tool follows local preset references and shader includes through
librashader. Before writing any preset files it validates both GL 1.20 and
GLES 1.00 shader pairs with LÖVE, compiles the current GPU's pair, checks
parameter/size/sampler uniforms and NPOT wrapping, and renders/reads back a
small test target. A failed conversion or preflight leaves the destination
untouched. Success writes four GLSL files per pass, optional PNG LUTs and one JSON descriptor, with
content-derived names and exclusive file creation. Existing files are never
overwritten; a duplicate import reports an error. Sources are synced before
the descriptor is written; a handled write failure removes only that import's
new files. A process interruption can leave orphaned files, which can be
removed manually. Reopen OPTIONS -> SHADER PRESET to discover the result.
Keep the original shader pack and its licence notices; converted shaders
remain subject to their original licences. No third-party shader pack is
bundled here.

The importer supports a bounded subset:

- One to eight ordered passes and up to eight PNG LUTs. Intermediate passes default to source 1x; the final pass defaults to viewport 1x. Explicit source, original, viewport (1/64x to 8x) and absolute (1 to 8192) scaling are supported per axis.
- Separate `Source`/`Original`, strictly earlier `PassOutputN` and named LUT samplers and their size uniforms, `OutputSize`,
  `FinalViewportSize`, the vertex MVP and up to eight scalar parameters,
  including preset overrides. Optimized-out parameters remain editable but
  have no GPU uniform to send.
- Nearest/linear sampling and clamp-to-border, clamp-to-edge, repeat or
  mirrored-repeat addressing when supported by the target GPU.
- Normal RGBA8 output. History/feedback textures,
  mipmaps, float/sRGB targets, temporal/sensor/HDR uniforms,
  unsigned arithmetic and other unsupported GLSL interfaces are rejected.

LCD3x and zfast LCD are examples of this subset. Import success is not a
claim that every RetroArch shader works, or that a shader tested on desktop
will compile or perform well on mobile/console GPUs. GLES is validated as
shader source on desktop; mobile hardware execution needs separate testing.

Generated descriptors use `format: 2`, add `vertex`, `esShader`, `esVertex`,
`filter` and `wrap`, and retain the same parameter and persistence schema.
The renderer selects the matching GL/GLES pair. Generated uniform names are
reserved: `g2_p_<parameterId>`, `g2_Source`, and `g2_<sizeSemantic>`.
Native format-1 presets keep their existing behavior.

For format 2, a private canvas reconstructs the completed primary view on its
native pixel grid: physical input dimensions divided by the renderer's pixel
scale, rounded to the nearest positive integer. `SourceSize` and
`OriginalSize` describe that actual texture as `(w,h,1/w,1/h)`;
`OutputSize` and `FinalViewportSize` describe the physical output. The primary
view includes its current widescreen area and any letterboxing, rather than
an independent original cartridge framebuffer. A mod's preceding presentation
pass is sampled as supplied. Filter/wrap changes apply only to the private
texture. Output dimensions/DPI and the stage ordering above are preserved;
resize, scale changes, replacement, OFF and failures release owned targets.
An imported selection is compiled and checked before replacing a working
preset; later render failures use the existing OFF fallback.

```sh
cargo test --manifest-path tools/slang-import/Cargo.toml --release --locked
luajit tests/engine/slang_presets.lua
# Import the original PROBE and WRAP fixtures using the command above, then:
SLANG_IMPORT_CHECK_DIR=/absolute/path/to/test-presets love tools/slang-import-check
```

The GPU tool checks both shader dialects, custom vertex varyings, parameters,
source/output sizes, wrapping/filtering, alpha, resize/DPI 1/2/2.75 and failed
selection rollback. If the directory also contains imports named `LCD3X` and
`ZFAST LCD`, it compares their real output with independent CPU equations.
`SLANG_IMPORT_CHECK_SHOT=/absolute/path.png` exports a comparison sheet.

### Format-3 pass graphs

Multipass, LUT or nonlegacy scaling imports use `format: 3` with `passes`
and `textures` arrays. Each pass holds the four stage filenames, filter,
wrap and `scaleX`/`scaleY` objects (`type`, `value`). LUT records hold `id`,
`image`, `filter` and `wrap`. Filenames are closed basenames; no executable
metadata is loaded. Shared parameters keep their existing IDs and save keys;
conflicting definitions across passes are rejected.

The runtime compiles both GL/GLES dialects and draws/reads back the complete
graph before replacing a working effect. All canvases and LUT images are
private. Pass sampling settings affect only private rendered inputs; LUTs
retain their own filter/wrap. Original always means the reconstructed native
primary view; Source is the previous pass. The final result is copied to the
primary view's logical size/DPI. Borrowed inputs and the caller's graphics
state are preserved. Resize, OFF, replacement and render failure release
owned resources; render failure returns the unfiltered input.

Before allocation, each frame checks GPU dimension limits and a 32-million
aggregate pixel budget (RGBA8 targets plus LUT pixels). LUTs must be 8-bit
PNG, at most 8 MiB compressed each, 2048 per axis and eight million pixels
combined; header limits precede native decoding. These bounds refuse expensive
presets rather than silently downscaling them. This is a spatial RGBA8 subset,
not full RetroArch compatibility.

```sh
# Import graph.slangp as GRAPH, then:
luajit tests/engine/shader_graph.lua
SHADER_GRAPH_CHECK_DIR=/absolute/path/to/test-presets love tools/shader-graph-check
```

The graph GPU probe checks separate Original/Source/earlier-pass/LUT values,
per-pass sizes, live parameters, alpha, resize/DPI 1/2/2.75, state restoration
and rejected-candidate rollback against an independent pixel equation.
Pixels exactly on a nearest-sampling boundary are excluded from that equation
because GPU floating-point rounding can legitimately choose either neighbor.
