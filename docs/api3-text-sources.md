# Portable API-3 script text

API 3, and API 2 with `content_format: "unified"`, expose `mod.content.text`
source strings for GB, Gen 2 and the registered GBA games. API 1/2 native mode
retains its existing text keys and bytes. DS text handles retain their existing
native behavior; this change does not claim a shared DS printer.

```lua
local mod = ...
mod.content.text:register("MOD_GREETING", "Hello, {PLAYER}!\\nWelcome.\\pGood luck!")
```

Source controls are newline (`\n`), paragraph (`\f`) and scroll (`\v`). The
literal escape pairs `\\n`, `\\p`/`\\f` and `\\l` are accepted too. Reads return
source strings with actual control characters. Percent signs remain literal;
this registry is not a printf formatter. Carriage returns and raw byte 252
printer controls cannot round-trip through the shared source language and
return `nil, "unsupported: ..."` on writes. Invalid value types throw.

GBA source uses `{PLAYER}`, `{RIVAL}` and `{STR_VAR_1}` through `{STR_VAR_3}`.
The adapter writes the latter to the host's native `{VAR1}` through `{VAR3}`,
so the existing script buffer commands and textbox token handlers consume them.
Reads reverse those aliases. Escaped literal braces retain their source spelling;
placeholder conversion applies only to actual source tokens. Other public GBA cartridge placeholder and symbol
names round-trip with the version's grammar. Unknown placeholders and printer
style commands are refused, rather than accidentally installing a missing token.
The source contract does not promise matching glyph artwork or pixel layout.
GB/Gen-2 tokens retain their own native grammar and registered handlers.

## Native script IDs

Gen-2 text IDs use the reference's lowercase hexadecimal `bank:address` form,
for example `55:4067`. The host VM stores that same script text as
`TEXT_S55_4067`. Unified reads, writes, removes and enumeration map to that
physical record. They do not create an unused `data.text["55:4067"]` shadow.
Existing host native IDs are still accepted. Differently-cased authored labels
remain distinct IDs; they are not silently normalized into cartridge addresses. Two distinct records occupying
both spellings are an ambiguity, even if their current contents match; the
adapter refuses to guess which one a mod meant.

New authored labels remain usable from authored scripts. **This is not yet
`mod.content.rom_text`**: named GBA cartridge label aliases and engine/battle/menu
prose bindings require the next, separate registry adapter. Existing Gen-2 host
text still shares a native table with prose. This PR does not advertise that
all Gen1 cartridge text labels already resolve on every host game.

The ordinary registry journal retains load-order, failure rollback, tombstones,
and frozen-after-load writes. Unified operations on a canonical and native
Gen-2 alias fold into the same ordered registry record. On reloading the same
mounted host dataset, successful adapter writes retire only while their exact
installed bytes and table identity remain present. External edits and unrelated
keys survive. The retirement journal is scoped to the dataset and does not
change untouched native API-1/2 text loads.

## Verification

```sh
luajit tests/engine/text_sources.lua
luajit tests/engine/text_source_authority.lua
python3 tools/text-source-contract-check/check.py --gen1 /path/to/clean/gen1
python3 tools/text-source-contract-check/check.py --gen1 /path/to/clean/gen1 --host-api 2
```

The checker pins Gen1Recomp to `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.
Both SDKs load the same public example and corpus without engine imports in the
consumer. API-2 host opt-in is compared with the reference's API-3 source
contract; reference API 2 remains native, so these are not mislabeled as the
same API-2 format. Real readers include Gen-2 VM text, host lowered
`writetext`/ScriptRunner/TextBox, and GBA VM text/TextIR and host GBA commands.
The grammar corpus checks storage/source equality independently of presentation;
it does not run every symbol through every game's full UI.

`tests/drivers/text_sources.lua` is the additional imported-data LÖVE driver.
Use the isolated combined-fork launcher and temporarily install the example;
for Gold, supply `id.txt` containing an existing cartridge `bank:address` ID.
The driver opens, renders and closes real native dialogue, using an in-memory
New Game. It performs no normal SAVE and makes no full-playthrough claim.

## Validated snapshot

Feature runtime `13598190777c0de6fac79cbe0f2663b8f8c56725`; combined runtime
`a7a4091be9f4b631d54cd6f57ce1d33c5d8bed46`:

- Source/native contracts **3,700/3,700**; ownership/legacy/retirement contracts
  **234/234**. Both host opt-in modes are covered, native API-1/2 bytes retain
  their old behavior, and DS keeps its native text handles.
- **32 isolated SDK workers / 3,148 paired observations** per feature/combined
  snapshot. Eight versions, reference API 3 versus host API 3 and API 2/unified.
  The unchanged consumer covers 196 observations per GB/GBA game and 198 per
  Gen-2 game. The corpus includes all public GBA placeholder/symbol names,
  dialect-specific battle names, near misses, escaped literals and raw controls.
- Feature **131/141 engine suites**, SDK **3/3**, B30 pass. The same ten baseline
  suites produce exactly the same **26 FAIL lines** as #169; independent
  baseline repairs are in #128–134. Combined **186/186**, SDK **3/3**, B30 pass.
- Native LÖVE 11.5, existing imported **Gold, FireRed, Emerald**: unchanged
  installed consumer, real title/New Game, actual imported Gold text at
  `TEXT_S55_4067`, native lowered writetext/GBA script commands, player/string
  buffer expansion, real textbox rendering, paragraph pages, A-close and script
  resume, frozen late writes. The owned example was removed with hash guards.
  This is an in-memory dialogue smoke, with no normal SAVE, full playthrough,
  fresh full-ROM reimport or pixel-equivalence claim.
- The unchanged #169 negative control writes a shadow `55:4067` while the native
  VM still prints its old physical text; a common GBA string variable remains
  literal. Both discrepancies are observed through real readers.
- Imported Red regressions: battle **468/468**, save conversion **95/95**, parity
  J **73/73**, K **22/22**. No external binary save fixture supplied.
- New Lua formatting, workflow actionlint, Python compile and diff checks pass.
  No ROM, imported cache, save or private mod is included.

Later documentation-only commits do not change the runtime tested above.
Hosted CI status is reported separately in the PR; local passing runs do not
imply GitHub Actions executed or passed.
