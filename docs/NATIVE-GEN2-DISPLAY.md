# Native Gen2 display selection

Gen2 display selection belongs to `PaletteFX`, the same owner used by the
native tile, sprite and battle renderers. `GbcPalette` exposes the Gen1Recomp
public vocabulary over that state: `gbc`, `dmg`, `classic`, and `custom`.
The generic native ID for DMG remains `og`, preserving existing option files.

GBC uses the cartridge's indexed palettes. DMG retains the four original
indexed shades as grayscale. Classic uses that same grayscale intermediate
and maps the completed frame through the green ramp once. A custom ramp
replaces indexed palette rows; already-coloured art keeps its existing
true-colour contract. The unrelated Gen1 colourization packs and Gen3
display behaviour retain their existing paths.

`setMode`, `cycle(delta)`, `setCustomRamp`, `applyOptions`, `modeLabel`, and
`presentColors` are available through `GbcPalette`. The mode, custom ramp and
byte BGP all share native state. Raw indexed drawing bypasses display/BGP
selection. A custom ramp takes priority over the selected indexed mode, as
in the reference protocol; Classic's final presentation remains a separate
operation. Missing custom ramps fall back to grayscale.

`PaletteFX.setDisplay(mode, ramp)` applies a selection atomically. It invalidates
tile and animation textures, OBJ images, battle images and cached maps, then
reloads the entered map. The shared `Assets.register` invalidation bus also
notifies external texture producers, including repeated ramps with the same mode
ID. Retained battle image references resolve through their
original palette and crop on the next draw. Reapplying an edited ramp table
also updates its key and invalidates dependent caches. Transient BGP writes do
not enter static atlas cache keys. Mono/custom world bakes retain cave darkness;
battle palette permutations and blackout apply after display selection.

Native Gen2 options and hotkey 2 use the GBC → DMG → Classic ladder, with a
backward step supported. Cycling clears a selected custom ramp and saved
palette ID. Native `options.colors` and legacy `options.color` record the same
selection. Applying legacy mode plus `options.palette` performs one rebuild.

`src.render.Palette` supplies the public palette ID/library operations. Mono IDs
are `m:rrggbb`; named IDs are `p:group/name`. An optional authored
`data.gb_palettes` module supplies named entries; no palette catalogue is
invented or extracted by this library. Categories, labels, lookup, swatches,
ramp caching and invalidation use the reference vocabulary.

## Completed-frame zones and composition

For native Gen2 gameplay, `render.zones` receives the final display zones once,
after native drawing has settled its palettes. Classic starts with one green
whole-frame zone; other modes start with nil. Consumers can replace, remove or
extend those zones. Each dispatch gets its own list. This final pass uses raw
palette destinations so Classic cannot resolve its own green ramp back to gray.

The native Gen2 compositor first combines world and UI into one scene. Its
window-menu callback includes a window-resolution drawer when one is supplied;
this offer does not add the separate native window-menu classes or a palette-picker UI. `render.compose` then receives that completed texture in
`sceneCanvas`, `worldCanvas` and `uiCanvas`, with `generation = 2`, the native
renderer and an explicit `game` owner. The render target is different from the
source texture. A consumer taking composition ownership also owns presentation
of the supplied final zones; `Renderer:blitZones` provides the raw zone blit.
Otherwise the engine applies final zones before present/output effects. HUD and
touch controls retain their screen-space placement outside this game scene.

This is display work toward Gen1 parity. It does not establish complete UI
raster parity, a full unchanged-mod playthrough, save/link acceptance, hardware
performance or full engine parity. Existing upstream/Gen1 licences and the
[Roxas2712 contribution permission](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md) remain applicable.
