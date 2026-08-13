# Crystal intro + title screen: what the ROM actually does

Everything here was read off the cartridge with `tools/lr35902.py` (a small
LR35902 disassembler added for exactly this) and verified by rendering the
result to PNG. Nothing in this file is from memory or from a guess — where a
number appears, it came out of the ROM.

Bank `$39` unless stated otherwise. Addresses are Crystal 1.1 (`f2f52230…`);
1.0 shares the manifest.

## Title screen — DONE

Implemented in `RomExtractorGen2:extractCrystalTitleArt`. See the comment
there; the short version is that BG tile ids are **signed** (LCDC bit 4
clear), so one 156-tile `TitleLogoGFX` blob serves both `$80…$FF` and
`$00…$1B`, and Suicune is BG tiles out of **VRAM bank 1** selected by
attribute `$08` on rows 12–17.

## Intro — NOT DONE

`CrystalIntro` (`39:$48AC`) loops `IntroSceneJumper`, which indexes
`IntroScenes` (`39:$491E`), a table of 28 `dw`. The scenes alternate:

* **odd** scenes load assets and call `NextIntroScene` immediately
* **even** scenes hold for a frame budget, animating, then advance

The frame budget is the `cp $NN` guarding `NextIntroScene`, against the
counter at `$CF64`:

| pair | setup scene | hold scene | frames |
|------|-------------|------------|--------|
| 1  | IntroScene1  (Unown A)          | IntroScene2  | 128 |
| 2  | IntroScene3  (Background)       | IntroScene4  | 128 |
| 3  | IntroScene5  (Unown HI)         | IntroScene6  | 128 |
| 4  | IntroScene7  (Bg + Pichu/Wooper + Suicune run) | IntroScene8 | 64 |
| 5  | IntroScene9                     | IntroScene10 | 192 |
| 6  | IntroScene11 (Unowns)           | IntroScene12 | 192 |
| 7  | IntroScene13 (Bg + Suicune run) | IntroScene14 | 128 |
| 8  | IntroScene15 (Suicune jump)     | IntroScene16 | 128 |
| 9  | IntroScene17 (Suicune close)    | IntroScene18 | 96  |
| 10 | IntroScene19 (Suicune back)     | IntroScene20 | 152 |
| 11 | IntroScene21                    | IntroScene22 | 8   |
| 12 | IntroScene23                    | IntroScene24 | 32  |
| 13 | IntroScene25 / IntroScene26 (Crystal Unowns) | IntroScene27 | 128 |
| 14 | —                               | IntroScene28 | 24  |

### Asset loads, per setup scene

Every blob is LZ3. `Intro_DecompressRequest2bpp_*` takes the destination in
`de`; `CopyBytes` moves the palette to `wBGPals1` (`$D000`) and again to
`$D080`.

| scene | tilemap | attrmap | palette | GFX → VRAM |
|-------|---------|---------|---------|------------|
| 1  | IntroUnownATilemap        | IntroUnownAAttrmap        | IntroUnownsPalette        | IntroUnownsGFX→`$9000`, IntroPulseGFX→`$8000` |
| 3  | IntroBackgroundTilemap    | IntroBackgroundAttrmap    | IntroBackgroundPalette    | IntroBackgroundGFX→`$9000` |
| 5  | IntroUnownHITilemap       | IntroUnownHIAttrmap       | IntroUnownsPalette        | IntroUnownsGFX→`$9000`, IntroPulseGFX→`$8000` |
| 7  | IntroBackgroundTilemap    | IntroBackgroundAttrmap    | IntroBackgroundPalette    | IntroBackgroundGFX→`$9000`, IntroPichuWooperGFX→`$8000`, IntroSuicuneRunGFX→`$8000` |
| 11 | IntroUnownsTilemap        | IntroUnownsAttrmap        | IntroUnownsPalette        | IntroUnownsGFX→`$9000` |
| 13 | IntroBackgroundTilemap    | IntroBackgroundAttrmap    | IntroBackgroundPalette    | IntroBackgroundGFX→`$9000`, IntroSuicuneRunGFX→`$8000` |
| 15 | IntroSuicuneJumpTilemap   | IntroSuicuneJumpAttrmap   | IntroSuicunePalette       | IntroSuicuneJumpGFX→`$9000`, IntroUnownBackGFX→`$8000` |
| 17 | IntroSuicuneCloseTilemap  | IntroSuicuneCloseAttrmap  | IntroSuicuneClosePalette  | IntroSuicuneCloseGFX→**`$8800`** |
| 19 | IntroSuicuneBackTilemap   | IntroSuicuneBackAttrmap   | IntroSuicunePalette       | IntroSuicuneBackGFX→`$9000`, IntroUnownsGFX→`$8800` |
| 26 | IntroCrystalUnownsTilemap | IntroCrystalUnownsAttrmap | IntroCrystalUnownsPalette | IntroCrystalUnownsGFX→`$9000` |

### Render rule (verified)

Tilemaps and attrmaps decompress to 1024 bytes = a 32×32 BG map; the visible
screen is the top-left 20×18. Tile ids are signed, so the VRAM destination
decides which id range a blob answers for:

* `de = $9000` → ids `$00…$7F`, blob index = id
* `de = $8800` → ids `$80…$FF`, blob index = id − `$80`
* `de = $8000` → OBJ only, not reachable from the BG map

Palette = `attrmap[i] & 7` into the scene's 8 four-colour palettes.

Rendered this way, scenes 3, 15 and 19 come out pixel-correct first try.
Scenes 1, 5, 11 and 26 render **black or white, and that is correct** — the
Unown scenes start faded out and are brought up by `CrystalIntro_UnownFade`
(`39:$5223`) and `Intro_FadeUnownWordPals`.

### What is left

1. **Palette fades** — `IntroFadePalettes`, `CrystalIntro_UnownFade`,
   `Intro_FadeUnownWordPals` (`.FastFadePalettes` / `.SlowFadePalettes`).
   Without these the Unown scenes stay blank.
2. **Per-scene scroll.** Scene 17 renders offset, so the close-up pans;
   `hSCX`/`hSCY` writes per scene still need reading.
3. **OBJ animation** — `CrystalIntro_InitUnownAnim` (`39:$51DC`),
   `IntroSuicuneRunGFX`, `IntroPichuWooperGFX`, `IntroPulseGFX`, and
   `Intro_ColoredSuicuneFrameSwap` / `LoadSuicuneFrame`.

Until all four are in, playback would be a slideshow with several blank
frames — worse than the current behaviour, which is to show the branding
cards and go to the title.

## Gender select — NOT STARTED

The data is all present and decodes; nothing selects between it yet.

| asset | Chris | Kris | notes |
|-------|-------|------|-------|
| Oak-intro full body | `ChrisPic` | `KrisPic` | 7×7, **raw, column-major** |
| Trainer card portrait | `ChrisCardPic` | `KrisCardPic` | 5×7, **raw, column-major** |
| Battle back pic | `ChrisBackpic` | `KrisBackpic` | 6×6; Chris is **LZ3**, Kris is **raw** |
| Overworld | `ChrisSpriteGFX` | `KrisSpriteGFX` | |
| Palette | — | `KrisPalette` | `02:$70D2` |

Note the storage is not uniform: Gold's `ChrisPicAndTrainerCardGFX` is
row-major, Crystal's card and full-body pics are column-major, and
`KrisBackpic` is raw where `ChrisBackpic` is compressed. Check each one
rather than assuming.
