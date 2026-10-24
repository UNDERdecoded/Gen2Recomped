# Portable engine prose

`mod.content.rom_text` exposes label-keyed prose on Gen 2 and the registered
GBA games. GB and DS report this registry unavailable. API 3 and API 2/unified
use the shared source-string grammar from [script text](api3-text-sources.md).
The host's native API-1/2 facade uses strings; the reference's native GBA IR
format is not a portable native-API-2 format.

```lua
local mod = ...
if mod:supports("content", "rom_text") then
  mod.content.rom_text:override("_WokeUpText", "{USER} woke up!")
end
```

The label belongs to its native generation. Gen-2 prose has an imported base;
GBA's registry is a separate overrides map, so an untouched label reads nil
while the native screen still uses its cartridge text. Removing a Gen-2 label
makes native prose readers use their fallback. Removing a GBA override exposes
the cartridge label again. `register`, `override`, `patch`, `remove`, detached
scalar reads, ordered iteration, failure rollback and frozen writes use the
ordinary registry contract.

The native GB/Gen-2 formatter supports positional and named brace slots. With
one table argument, braced or unbraced token keys replace only supplied values.
Player/rival tokens can remain for the textbox. `{DONE}` and `{PROMPT}` are end
metadata, not substitution slots or visible prose. A `%s` in the source is not
a brace slot: an incompatible call retains the native fallback policy.

## Native readers covered here

- Gen-2 native battle prose uses the shared formatter. Overrides of the exact
  imported prose labels also project into the existing native label table,
  reaching existing native readers of those labels. The source-derived
  membership lists are names only, with no cartridge prose.
- GBA Pokemon-storage actions and their descriptions have ten explicit native
  label bindings. The real storage-menu constructor reads detached views of
  these overrides, including its older-cache fallback. Imported constants are
  unchanged. All five actions/descriptions are tested through both engines'
  actual native menu readers; this does not invent a generic word matcher.

**Registry availability does not mean every native GBA UI/battle reader has
been bound.** Party, item-PC, other field menus and GBA battle-message contexts
need further explicit adapters. Likewise, a Gen-2 screen that still prints a
hardcoded fallback rather than reading its ROM label needs a native reader
change. This PR is a shared registry and its first verified native consumers,
not complete translation coverage or universal printer/glyph equivalence.

## Script/prose isolation

An API-3 Gen-2 script and engine prose may both be called `_WokeUpText`. The
script namespace starts without the prose label; an authored script value is
stored separately and the native VM/text commands read that value. A removed
or empty private script prints the native missing-script placeholder instead
of revealing engine prose. Gen-2 `bank:address` IDs still reach their original
physical VM entries. Generated internal keys do not remain in the legacy text
table; authored labels beginning with the private prefix are escaped too.
Native API-1/2 legacy text keys retain their existing host access path.

Successful prose and private-script writes retire on reload only while their
installed values and target identities remain present. External edits and
unrelated native values survive. The private projections do not consume RNG or
construct Game during discovery or capability checks.

## Verification

```sh
luajit tests/engine/rom_text_content.lua
luajit tests/engine/rom_text_authority.lua
luajit tests/engine/rom_text_format.lua
luajit tests/engine/rom_text_labels.lua
python3 tools/rom-text-contract-check/check.py --gen1 /path/to/clean/gen1
python3 tools/rom-text-contract-check/check.py --gen1 /path/to/clean/gen1 --host-api 2
python3 tools/rom-text-contract-check/check-format.py --gen1 /path/to/clean/gen1
python3 tools/rom-text-contract-check/generate-labels.py --gen1 /path/to/clean/gen1 --check
```

The reference is pinned at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.
API-2 host opt-in is compared with the reference's API 3, not mislabeled as
reference API-2/unified. The public consumer has no engine imports. Source
formatting, namespace isolation and native reader observations are separate
from imported-data/UI smoke tests. No ROM, imported cache or save is included.
The LÖVE driver is `tests/drivers/rom_text.lua`; use the isolated testfork
launcher. Native smoke and full-suite results are recorded below.

## Validated runtime

Feature `52541d1b0160de2361a2bffe15fd4fad4eb9a20c`; combined
`62f8902617255195b4a12b176f171925c49209ec`. Later documentation changes do not
change the tested runtime.

- **175/175** public/native registry checks, **510/510** ownership/isolation/
  retirement checks, **57/57** native formatting checks, **52/52** provenance
  checks. Existing script-text contracts **3,700/3,700** and **234/234** pass.
- **24 isolated SDK workers / 94 paired native observations** at both runtime
  snapshots, using the same public consumer. Red gates availability; Gold,
  Silver, Crystal, FireRed and Emerald compare supported behavior. Host API
  2/unified compares with reference API 3; reference API 2 remains native.
- Separate real-formatter comparison: **8 native engine workers / 96 paired
  observations**, Red/Gold/Silver/Crystal, against the clean pinned reference.
- The source-derived prose membership and ten GBA storage bindings regenerate
  exactly from pinned public import metadata. No cartridge prose is copied.
- Feature **135/145 engine suites**, SDK **3/3**, B30 pass: exactly the same
  **26 FAIL lines / ten baseline suites** as #170. Independent baseline
  repairs remain #128–134. Combined **190/190**, SDK **3/3**, B30 pass.
- Imported-data **LÖVE 11.5 / Gold, FireRed, Emerald** at the combined runtime:
  unchanged consumer, real title/New Game; Gold's native battle-prose helper
  and textbox/end-marker handling, separate same-label native script display,
  A-close/script resume; GBA real storage menu with all five action labels and
  descriptions, B-close/reopen; frozen late writes. This does not execute a
  complete battle/wakeup turn. Isolated identity, in-memory New Game, no
  normal SAVE, full playthrough, fresh full-ROM reimport or pixel-equivalence
  claim. Owned temporary example removed with hash guards.
- Unchanged #170 rejects the example because it has no registry; its actual
  native Gold prose and GBA storage reader retain their original values.
- Imported Red regressions: battle **468/468**, save conversion **95/95**,
  parity J **73/73**, K **22/22**. No external binary save fixture supplied.
- New Lua formatting, workflow actionlint, Python compile, deterministic
  generation and diff whitespace checks pass. Hosted CI status is reported
  separately in the PR and does not inherit these local results.
