# Legacy world and embedded HUD orientation on LÖVE 12

LÖVE 12 normalizes canvas clip coordinates differently from LÖVE 11. Legacy
custom 3D shaders already invert clip-space Y themselves. Reflecting the
completed world image corrected those 3D pixels but inverted ordinary 2D
menus, battle HUDs and effects drawn into that same image.

`src/render/LegacyShaderCompat.lua` now restores the LÖVE 11 high-level shader
coordinate contract at shader creation, before those draws are combined. It
adapts the `position` entry point, its projection argument and the global
projection matrix consistently. The canvas uniform follows shader/canvas
changes and graphics-state restores. Ordinary matrix-based 2D shaders cancel
the paired reflections and retain their normal orientation. LÖVE 11, raw
`vertexmain` entry points and shaders declaring
`#define POKEPORT_NATIVE_CLIP_SPACE 1` are unchanged.

The compositor no longer mirrors ordinary world overrides. An explicitly
unconverted image may still request `worldOrientation = "legacy"`; `native`
and detached `renderData.v1` retain their native convention. The existing
field-effect counter-transform follows only that explicit mirror policy.
The shader compatibility layer handles the usual mixed 3D/2D image before
presentation, so its HUD can remain upright without transforming the HUD.

## Scoped evidence

- The real shader creation/state adapter passes 57 ROM-free checks and the
  compositor/field-effect policy passes 151, both independently and on the
  composed fork.
- The standalone GPU fixture passes 304 checks in seven cases on LÖVE 12
  OpenGL and Metal, and 220 on stock LÖVE 11.5. It covers actual custom and
  matrix-based vertex paths, canvas/window targets, state restoration and
  mixed artwork. The negative control disables the shader correction and
  fails the asymmetric pixel assertion.
- Actual Red/VASC battle/menu work and native Emerald/FireRed OpenGL
  regressions were tested at their recorded earlier source checkpoints.
  These are distinct from a new complete Windows or all-games acceptance.
- The current Crystal checkpoint uses the unmodified supplied Johto package
  on both backends: actual First/Third V/F6 input, native grid movement and
  upright StartMenu, plus the Mart/Center geometry and menu probes. See the
  [Johto report](https://github.com/Roxas2712/Gen2Recomped/blob/f56a81f6e0eb97ab5024706fca3f07cfe4d1eca0/docs/johto-native-compatibility.md) for exact sources, normal
  no-mod staircase/house exits and the remaining renderer/interior gaps.

The earlier whole-image-mirror evidence in
`docs/validation/love12-world-orientation.json` is historical; it does not
establish that an embedded battle HUD was correct. The repeatable current
fixtures are `tests/engine/legacy_shader_compat.lua`,
`tests/engine/world_override_orientation.lua`,
`tools/legacy-shader-check/main.lua` and
`tools/world_orientation_gpu_driver.lua`. Windows hardware, every mod feature,
all maps/doors and complete engine parity remain open.
