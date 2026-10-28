# Font text selection and Gen1 parity

Repeated `Font.width` and `Font.draw` calls previously rebuilt glyph arrays
and UTF-8 spans even when the font and label were unchanged. Gen1's reference
renderer already reuses this work. The native renderer now keeps at most
4096 encoded labels and exposes the same `Font.glyphCount` and `Font.revision`
interfaces.

`Font.encode` still returns a fresh, caller-owned array. Widths are deliberately
measured through the current `advanceOf` function, preserving GBA proportional
faces and live face switches. A replaced public encoder is honored by width
and drawing; a replaced splitter bypasses the cache. `Font.load`/`invalidate`
retire cached selection, as does activation, replacement or removal of the
translation font. The missing-atlas draw path counts UTF-8 glyphs rather than
bytes when returning its width.

## Validation

- `luajit tests/engine/font_text_contract.lua`: 44 checks for UTF-8/ligatures,
  caller ownership, actual glyph dispatch and metrics, face switching, public
  hooks, reloads, translation activation/removal and missing-atlas fallback.
  On the previous `0af0b3cf` main, the same fixture fails on the missing
  `glyphCount` API. Its atlas/font I/O is synthetic; Font is the real module.
- A private comparison loaded the same owned Crystal font record and atlas
  dimensions into this renderer and frozen Gen1 reference `535a5ec0`.
  `split`, `encode`, width and glyph draw dispatch matched for all six sampled
  labels, including the single ROM tile for `é`. The earlier suspected
  encoding defect in `POKéMON` was not reproduced by this comparison.
- In a CPU-only sample, 2000 iterations of measuring and drawing six labels
  allocated 36142 KiB before the change and about 2.6 KiB afterwards, with
  identical checksums. Graphics calls were no-ops; this measures text
  processing and dispatch, **not GPU performance, frame rate or visual parity**.

No mod files change. These CPU checks do not qualify all fonts, menus or
final release packages.

## Source text commands

Gen1 expands `#MON` to `POKéMON` when the active font does not declare a
`#`-prefixed charmap entry. The native Font now follows that same command
contract: expanded glyphs retain the original command's byte range and use
the current font's character mappings, including relocated accents and
ligatures. Explicit mod charmap entries retain authority; the missing-atlas
raster fallback retains its existing literal-string policy.

`Font.fit` emits a complete command once, or materializes its visible prefix
when an ellipsis cuts through the expansion. Native TextBox wrapping keeps a
shared source-byte group intact, moving it to the next line when needed. An
individual group wider than the entire box still advances, matching the
existing oversized-glyph policy.

`luajit tests/engine/font_text_macros.lua` adds 62 checks, including actual
native typewriter ticks and line wrapping. The private real-Crystal-font
comparison reproduces the `#MON` mismatch on main `6b164d96` and matches Gen1
after the change for eight sampled labels. This remains CPU glyph-dispatch
evidence, not final-window acceptance.

## Optional Gen1 TTF records

The engine accepts `mod.content.font:register("ttf", {})` and routes its
merged `data.font.ttf` record through the native Font and TextBox pipeline.
Supported fields match Gen1: `file`, `size`, `spacing`, `yOffset`, `bold`
and `tiles` (UTF-8 characters or a list of charmap sequences). The all-optional
schema branch is closed so malformed pages cannot pass as TTF records.

The default is the same unmodified Plain Pixel 0.009 font pinned by the Gen1
reference. It rasterizes at DPI 1 with monochrome hinting and nearest
filtering; native atlas text stays the default. Unicode characters use
`Font.TTF_BASE + codepoint`, multi-character charmap ligatures retain tiles,
and explicit `tiles` entries preserve single-character tile mappings.
Direct border-code drawing remains on the atlas. Measurements, wrapping and
typewriter glyphs use the selected font's advances. Reload/removal retires
its glyph and metric caches; a failed font load logs and retains atlas text.

The native style and translation paths remain available. A selected TTF owns
its text glyphs; without it, the existing translation-service fallback still
handles characters missing from the atlas. `Font.ttfActive()` reports the
actual successful load, rather than the presence of a configuration table.

`tests/engine/font_ttf_contract.lua` exercises the actual Font/TextBox and SDK
merge with synthetic font I/O. Real raster and final-window checks are
separate acceptance requirements; passing this contract alone is not a
claim of complete visual parity.

## Gen2 extra sheets and frame selection

`Font.useBattleExtra(on)` returns the prior sheet selection;
`Font.battleExtraActive()` reports it. The battle page replaces only the
25 tiles at `$60-$78`. The selected textbox frame still owns `$79-$7e`
and the blank at `$7f` remains on the ordinary page. An inactive authored
`battleExtra` page also survives the public content-registry merge.

`Font.setFrame(index)` and `Font.frameIndex()` retain the selected row
across font reloads and work before loading the font. Optional missing or
out-of-range rows fall back to the baked frame. GBA named faces and their
separate nine-tile frame sheets keep their own lookup path.

The GSC importer emits the actual battle-extra font and eight six-tile
1bpp frame rows from each mounted ROM. No ROM art is shipped.
The ordinary extra sheet also follows LoadFontsExtra's three initial
loads: solid black, up-arrow and Pokegear telephone, replacing unused
FontExtra bold-letter tiles. Gold/Silver's paired 1bpp source and Crystal's
separate black/2bpp-arrow sources retain their own ROM symbol addresses.

Custom segmented/compressed font manifests retain their previous extraction;
other non-retail layouts need an explicit `fontFrameCount` to admit a
frame sheet. The generated Gen2 cache revision requires an ordinary
reimport of older font records while retaining saves. The native options
menu offers FRAME when the extracted sheet exists, applies changes
immediately, and restores the saved selection through `Game:applyOptions`.

The selection, import and options contract fixtures test glyph boundaries,
all eight rows, missing sheets, named-face isolation, native input, save
codec and the real cache-readiness gate. These ROM-free checks do not
replace a mounted-ROM GPU test or establish complete mod/release parity.
