# Native palette register and frame remapping

The public `src.render.GbcPalette` module resolves to the engine's
`Gen2PaletteDraw`. Its byte-register API shares `PaletteFX`'s native shade map;
there is no second register owned by a compatibility facade.

## Forward drawing

`BGP_IDENTITY` is `0xe4`. `bgpShades(byte)` returns the four two-bit fields,
with colour zero first, in a one-based array. `remap(colors, byte)` applies
those indices to a four-row RGB palette. Nil and identity preserve the original
palette table.

`setBgp(byte)` returns the previous byte. Identity is represented by nil.
Reading or assigning `GbcPalette.bgp` accesses this same native state; native
`PaletteFX.setShadeMap` writes are immediately visible through it. The existing
native frame reset clears it as well.

`resolve(colors)` selects the display palette without applying the register.
`color`, `use`, `with` and keyed draws apply the current register once.
`useRaw` and `withRaw` bypass display selection and the register. Native
`PaletteFX.sendColors` consumes the same state. The separate palette-upload
optimization uses this owner when present.

## Already-coloured frames

`remapTable(bgPalettes, byte, objPalettes, ramp, objRamped)` returns source
colours, destination colours, a live count and an ambiguity count. Tables hold
0–255 RGB triples, padded to `REMAP_MAX` (64) with detached rows. BG palettes
take the explicit byte permutation. OBJ palettes normally retain their colours.
An optional forced ramp supplies BG destinations; selected `objRamped` entries
take its unpermuted colours.

Shared RGB values can no longer identify the original palette after composition.
The first BG interpretation wins; conflicting destinations increase the ambiguity
count. This is a limitation of remapping RGB frames, not proof of indexed
per-pixel equivalence. Extra entries beyond 64 are omitted with BG slots first.

`remapUniforms(...)` builds normalized shader inputs, or returns nil for an empty
table. `useRemapUniforms(inputs)` and `useRemap(...)` bind the actual remap shader
and return `true, ambiguityCount` on success. Matching uses squared RGB distance
below `(3/255)^2`; unmatched pixels retain their RGB. Alpha and draw tint are
preserved. Compilation/upload failure returns false, retaining the previous
shader. A failed remap shader can recover when the graphics compiler changes.

Public uniform uploads are unconditional. Nested `with`, `withRaw` and
`keyedWith` restore both shader identity and prior palette/remap uniforms,
including after a callback or partial upload fails.

## Verification and remaining display work

`tests/engine/gen2_palette_register.lua` checks all 256 bytes against independent
field decoding in Red, Gold, Silver and Crystal, native/public register ownership,
BG/OBJ remapping, collisions, forced ramps, bounds, uniform ownership and failures.
`tests/gpu/gen2_palette_register.lua` verifies actual pixels for all 256 bytes
through public and native shaders, including the optimized native upload path,
OBJ preservation, unrelated RGB, alpha and tint. Run `run()` from an isolated
LÖVE host separately on each backend. It requires no cartridge or private mod.

This register change alone does not establish full Gen1 display parity. See
`NATIVE-GEN2-DISPLAY.md` for the native display-selection and cache/presentation
owners. Full unchanged-mod story/save/link acceptance and wider engine parity
remain separate requirements.

The public method protocol follows the Gen1Recomp reference interface. Existing
Gen1Recomp and upstream credits and licences remain applicable; see `NOTICE.md`.
