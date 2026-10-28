# Native Gen2 Pokemon palette drawing

`src.world.gen2.Palettes.monColors(data, species, shiny)` reads the existing
native Pokemon/palette records. It accepts a full native dataset, its current
published `gen2Palettes` view, or reference palette-only normal/shiny pairs.
Native species keys resolve to the same native records. Existing dataset
aliases are honoured; this patch does not install another species catalogue. Four detached 0–255 RGB triples are returned; missing or
invalid colours return `nil`. Retired dataset views cannot revive old data.
The built-in `PaletteFX.monPal` uses the same native selection without copying
its source palette. Transformed Pokemon retain their existing precedence.

`src.render.GbcPalette` now resolves to `src.render.Gen2PaletteDraw`, rather
than the unrelated LCD post-process `src.render.GBCFX`. Its indexed-image
shader recovers the four source grayscale shades and substitutes the supplied
palette while preserving texture alpha and drawing tint. `use`, `with`,
`useKeyed`, `keyedWith`, `useRaw`, `withRaw`, `shader`, `keyedShader`,
`available`, `resolve`, `color` and `clear` are provided. Keyed drawing makes
source shade zero transparent. Normal drawing resolves native `PaletteFX`
display/register state; raw drawing bypasses that resolution.
The public `mode` read follows that native resolution, so external evolution
presenters can preserve already coloured art instead of passing it through a
grayscale-index shader. It does not create another display option.

Scoped drawing restores both the previous shader object and managed palette
uniforms, including nested calls, callback failures and partial upload errors.
Public calls upload all four rows because callers can modify exposed shader
objects directly. No private renderer or ROM-derived colour catalogue is
embedded in the implementation.

## Validation and remaining work

ROM-free suites cover public Loader consumers, Gold/Silver/Crystal species
queries, native source identity, shiny/normal/transformed precedence, authored
changes, detached results, retired views, invalid values and graphics failure
paths. The GPU probe `tests/gpu/gen2_palette_draw.lua` compares actual canvas
pixels for every shade, alpha, tint, keying, native register remap, nested
success/error and foreign shader restoration on each tested backend.

Real-ROM validation must additionally compare the native palette producer and
public queries with an independent decoder, using actual imported Pokemon
metadata. Those private inputs and outputs are excluded from the repository.
A successful pixel probe is not proof of every unchanged mod presentation or
full gameplay acceptance.

The complete reference `GbcPalette` API is not yet implemented: its separate
mode/custom-ramp controls and backwards remapping of already coloured frames
still need integration with native display state. The LCD effects API remains
separate. Full colour art, UI layout, original story admission, broader hardware
and complete Gen1/VASC parity remain independent acceptance work. No VASC code
or assets are changed by this feature.
