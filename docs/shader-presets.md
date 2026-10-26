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
or GLSL ES dialect. This feature does not translate RetroArch `.slangp`
presets. There is one shader pass and one selected preset, with no download,
Rust/native bridge, LUT graph, frame history or pass feedback.

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
