# Unified definition records (opt-in)

A mod can use the same core content records when modifying different game
versions. Enable the format explicitly in an API-2 manifest:

```json
{
  "id": "portable_balance",
  "name": "Portable Balance",
  "version": "1.0.0",
  "api": 2,
  "content_format": "unified",
  "generations": [1, 2, 3, 4, 5],
  "entry": "main.lua"
}
```

```lua
return function(mod)
  -- Required when distributing to older engine builds: those builds do not
  -- understand content_format and would otherwise supply native records.
  assert(mod.contentFormat == "unified", "This mod needs unified content support")
  if mod.content.moves:has("TACKLE") then
    local ok, reason = mod.content.moves:patch("TACKLE", { power = 45 })
    assert(ok, reason)
  end
end
```

Omitting the field (or using `"native"`) preserves existing mod behavior.
API 1 cannot opt in. Mod API stays at **2**: this is the content-record part of
portability, not Gen1Recomp's complete API 3. Callback payloads, saved Pokémon,
world/battle services, scripts and other registries retain their native forms.
A mod still needs testing on every game it claims.

## Available records

The five handles retain `register`, `override`, `patch`, `remove`, `get` and
`each`, and add `has`, `supports()` and `available`. Other content handles pass
through unchanged. `mod.assets` retains its existing content-handle aliases.
On engines that provide `mod:supports`, content queries follow the selected
format's availability; other capability surfaces retain their existing answers.

| Handle | Unified fields | Supported versions |
| --- | --- | --- |
| `pokemon` | `id`, `name`, `dex`, `types`, `baseStats`, `catchRate`, `baseExp`, `growthRate`, `level1Moves`, `learnset`, `evolutions`, `tmhm`; optional breeding/art fields | Existing definitions, Gen 1–5 |
| `moves` | `id`, `name`, `type`, `power`, `accuracy`, `pp`, `effect`, `secondaryChance`, `category`, `priority`, `description` | Existing definitions, Gen 1–5 |
| `items` | `id`, `name`, `price`, `machine`, `effect`, `ball`, `tossable`, `needsTarget`, `description` | Existing definitions, Gen 1–5 |
| `trainers` | `id`, `name`, `pic`, `baseMoney`, `battleTheme`, `partyNames`, `parties` | Existing definitions, Gen 1–5 |
| `encounters` | `id`, `grass`, `water` | Gen 1–3 grass/water tables |

Reads and iteration return detached records. Editing a returned table does
nothing until a write method is called. Each record also contains a detached,
**read-only** `native` snapshot for diagnostics. Unexposed native fields are
preserved by edits; changing that snapshot is refused. `override` requires a
complete unified record and preserves omitted optional/native extension fields;
use `mod.DELETE` to clear a represented optional field. For normal
edits use `patch`; this keeps earlier and later mods' independent fields in the
registry's normal operation order. Writes return `true` on success.

`register` supports string-key definitions on Gen 1–3, except new Gen 3 species:
their EV/ability/storage metadata has no canonical constructor here. Numeric
DS allocations are refused. This layer does not invent storage slots or
metadata. Use native content for those additions. Existing records can be
patched, overridden and removed across all five generations.

### IDs and references

Species, move and item IDs are uppercase symbolic strings, such as `PIKACHU`,
`TACKLE` and `POTION`. Resolution uses the selected dataset's native keys and
names, not fixed cartridge numbers. `FARFETCHD`, `MR_MIME`, `NIDORAN_F` and
`NIDORAN_M` retain distinct names. `TM01`/`HM01` names normalize to
`TM_01`/`HM_01`. Types use Gen 1 spellings, including `PSYCHIC_TYPE`; the native GBA abbreviations `PSYCHC`,
`FIGHT` and `ELECTR` map to their common names.

A numeric table or a generated key such as `SPECIES_025` is mapped through its
name in that ROM. Renaming a definition through a mod does not change its ID
within that load. Numeric/string aliases of one record are read once and
written or removed together. Multiple distinct records with one canonical
name are ambiguous: the adapter refuses to choose one. Missing or ambiguous
`get` returns `nil, reason`; `has` returns false; ambiguous iteration raises.

Trainer and encounter IDs remain game-specific; no cross-game equivalence
between a trainer class, a numbered individual or two maps is implied.
Numeric trainer IDs are exposed as decimal strings. References must resolve
when a write is made: define a referenced record first or declare a mod
dependency that provides it. Missing references return `nil, reason` before
an operation is appended. Removing a referenced definition retains the
loader's post-merge, owner-attributed reference diagnostics, including DS
numeric targets and Gen 2 time tables.

### Pokémon and trainers

`baseStats` uses `hp`, `attack`, `defense`, `speed`, `special`, with optional
`specialAttack` and `specialDefense` for the later split. A patch to `special`
sets both halves on Gen 2–5; explicit split fields can change them separately.
Conflicting values are rejected. Gen 1 refuses unequal Special stats.

`level1Moves` is a list of move IDs. `learnset` is
`{ { level = 9, move = "TACKLE" } }`. Evolutions use
`{ method = "LEVEL", level = 20, species = "RAICHU" }`, or `ITEM`, `TRADE`
and `FRIENDSHIP` with `item`, `time` (`ANYTIME`, `MORNDAY`, `NITE`) or
`comparison` (`ATK_GT_DEF`, `ATK_LT_DEF`, `ATK_EQ_DEF`) where representable.
Held trade items and friendship/stat conditions are translated for Gen 2–3.
DS level evolutions are translated to their numeric target and parameter.
Other DS evolution writes and unknown method changes are refused; unchanged
native methods survive a detached read/modify/write. Gen 1 refuses eggs,
breeding fields, held items and later evolution conditions.

Trainer `parties` always has the form
`{ { { species = "PIKACHU", level = 18, item = "POTION", moves = { "TACKLE" } } } }`.
Items and moves are optional, and held items require Gen 2 or later. Native
per-slot IVs, flags and AI metadata are retained. A DS trainer's single `party`
and `parties[1]` aliases stay synchronized.

Move accuracy is percent, as in the engine's existing normalized definitions.
Gen1–3 move effects use canonical IDs, resolved to the host's actual native
battle handlers before an operation is journaled. For example
`SPECIAL_UP1_EFFECT` selects `SP_ATK_UP1_EFFECT` on Gen2/3; the Gen1 Special
stage does not leak into split Special Attack/Defense. `HIT` and `SLEEP` are
accepted aliases. Registered custom native effects retain their own IDs.

`secondaryChance` is an optional whole percentage (0–100) on Gen2/3. Explicit
odds convert to the nearest native fraction out of 256; detached unmodified
records retain their exact original byte. Explicit zero is distinguished from
a legacy native zero byte whose controller uses a fallback. Changing a
canonical effect applies its reference default chance unless the caller
supplies odds. Authored aliases survive later odds edits.

Unknown native selectors are opaque `native:generation:selector` tokens on
Gen2/3. They roundtrip only with their original record; they cannot assign an
unknown handler to another move. Gen4/5 retain the previous diagnostic-only
numeric selector behavior and refuse effect/chance changes. Item behavior
and changing a DS move type remain unavailable without their native adapters.

The data-only binding catalog is reproduced from pinned Gen1Recomp contract
maps plus the host importer's native names by
`tools/move-effect-contract/generate.py --gen1 CLEAN_REFERENCE --lua LUAJIT
--check`. It does not execute imported content. A binding still requires a
real registered host handler: FOLLOW_ME, HELPING_HAND, MAGIC_COAT, SNATCH,
IMPRISON, ASSIST, NATURE_POWER and SECRET_POWER are refused on the current
host. Identity-dependent native Rest/SonicBoom variants are not assigned to
an incompatible move. This adapter selects native behavior; it does not add
missing battle mechanics or promise cross-engine RNG/pixel equivalence.

### Encounters

An area is `{ rate, slots = { { species = "PIKACHU", level = 5 } } }`.
A range uses `minLevel` and `maxLevel` instead of `level`. Rates are fractions
out of **256**, including fractional values needed to represent GBA rates
exactly. Conversion refuses a rate that cannot be represented in native units;
it never silently rounds. Slot edits retain the native count and probability
buckets. Changing slot counts or weights requires native content.

Gen 2 also exposes `grass.times.MORN`, `DAY` and `NITE` in the same area shape.
A shared rate/slot patch applies to every native time. An explicitly changed
time can override that patch. Unchanged inherited times in a detached record
do not undo a shared edit.

DS encounter tables carry daily, seasonal, swarm and other replacements.
This adapter reports `available = false` and `supports()` returns `false,
reason` for them; reads/writes return `nil, reason` and iteration is empty.
The native encounter API remains available to mods using the native format.

### Lists, failures and lifecycle

Lists replace; `__append` and `__prepend` extend them. `{}` and `mod.DELETE`
clear represented lists, including inherited learnsets and TM lists. Required
scalar fields, base stats and species types cannot be deleted. Other optional
fields support `mod.DELETE` where their native representation permits it.

Malformed records raise schema errors. Non-representable operations return
`nil, reason` before recording anything. Payloads, returned records and native
snapshots never share writable tables with the operation log. Frozen content
still rejects writes. An entry failure rolls back every operation owned by
that mod, including all aliases. No Game, save, graphics or imported ROM is
needed to query or construct the content facade.

## Validation

Run `luajit tests/engine/unified_content.lua`. The tests load synthetic datasets
through the real loader, exercise all registered host versions and compare
native and unified round trips. Behavioral checks use native Pokémon/trainer
construction, encounter selection, DS move parsing and evolution dispatch.
This proves the exercised formats and consumers, not real-ROM playthroughs or
visual correctness. The complete local suite and its base comparison are
reported in the pull request.
