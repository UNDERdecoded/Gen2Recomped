# Unified hook and event records

This is an additive, explicit Mod API 2 option inspired by Gen1Recomp's
unified callback boundary. It adapts Gen2Recomped's existing call sites across
generations 1–5. It does not introduce Gen1Recomp API 3 hooks or events.

```json
{
  "id": "portable_hooks",
  "name": "Portable hooks",
  "version": "1.0.0",
  "api": 2,
  "entry": "main.lua",
  "callback_format": "unified"
}
```

Absent/`"native"` keeps the original API, including object identities and
custom hook names. Unknown format values and unified callbacks on API 1 fail
manifest validation. `mod.callbackFormat` exposes the selected format. The
option is independent of `content_format`; either can be adopted first.
There is no global conversion of saves, registry data or battle state.

```lua
return function(mod)
  mod.events:on("pokemon.level_up", function(event)
    mod.log:info("%s reached %d", event.mon.species, event.level)
  end)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local damage, info = next()
    if ctx.user.mon.species == "PIKACHU" then damage = damage + 1 end
    return damage, info
  end)

  mod.events:on("pokemon.before_give", function(gift)
    if gift.species == "EEVEE" then gift.nickname = "Buddy" end
  end)
end
```

## Records

IDs are resolved through this boot's registries. Pokémon, move and item IDs
are symbolic strings, including on numeric-ID DS hosts. Imported numeric
records use their names (e.g. `PIKACHU`); named/custom keys retain their IDs.
No National Dex lookup or hard-coded item-number conversion is used. Unknown
or ambiguous replacement IDs fail validation. An unchanged unknown native
ID can round-trip without being guessed or rewritten. Native aliases remain
one identity even after registry merging creates separate row tables.

| Record | Common fields |
| --- | --- |
| Live Pokémon | `species`, `item`, `nickname`, `name`, `level`, `hp`, `maxHp`, `status`, `isEgg`, `stats`, `moves`, `native` |
| Stats | `hp`, `attack`, `defense`, `speed`, `special`, `specialAttack`, `specialDefense` |
| Live move slot | `{ id, pp, maxPp, ppUps }` |
| Battler | `{ mon, id, side, native }`; `side` is `"player"`/`"enemy"` when known |
| Trainer party slot | `species`, `level`, optional `item`, `moves` as symbolic ID strings, `native`; other native metadata is read-only |
| Encounter / fishing slot | `species`, `level` or `min`/`max`; native slot metadata retained |
| Move definition | `id`, `name`, `type`, `power`, `accuracy`, `pp`, `priority`, `category`, symbolic `effect` when available, `native` |
| Species definition | `id`, `name`, `baseStats`, `types`, `baseExp`, `catchRate`, `growthRate`, `native` |
| Item definition | `id`, `name`, `price`, `description`, `consumable`, `native` |

Optional fields remain absent if the native data does not provide them.
`maxHp` maps to native `mon.stats.hp`. Special stats map to `spatk`/`spdef`;
Gen 1's single special stat is exposed through all three special fields.
Editing one keeps its aliases consistent; contradictory edits are rejected.
Type aliases match unified content IDs (`ELECTR` → `ELECTRIC`, `FIGHT` →
`FIGHTING`, `PSYCHIC`/`PSYCHC` → `PSYCHIC_TYPE`, `MYSTERY` → `CURSE_TYPE`).
Status values are `sleep`, `poison`, `burn`, `freeze`, `paralyze`, `toxic`, or
`nil`; clearing uses `nil` or `false`. Unknown existing statuses are retained
until explicitly changed. `isEgg` is the native boolean flag.

Definitions and `native` snapshots are detached, read-only diagnostics. Use
content registration during mod initialization to change definitions. The
callback view intentionally exposes a limited common definition shape;
additional generation-specific fields are available under `native`.
Battler metadata is read-only. Change its live Pokémon via `battler.mon`.
Shared native records share one public view within a call, so `user.mon` and
`target.mon` remain the same object when they reference the same Pokémon.

## Adapted hooks

| Hook | Adapted boundary |
| --- | --- |
| `battle.accuracy`, `battle.damage`, `battle.crit`, `exp.gain` | Context records: battlers, Pokémon, move/species definitions, known ID fields |
| `battle.run`, `battle.catch_exp`, `battle.low_health_alarm` | Context shell; native battle handle |
| `battle.turn_order` | Both battler/move pairs; bound battler result preserves native identity |
| `battle.enemy_action` | Second argument battler; move-action `id` in result |
| `battle.exp_award` | `alive` Pokémon list and `applyShare` helper |
| `catch.rate` | Ball ID, Pokémon, species definition, `opts.ballDef` item definition |
| `trainer.party` | Third argument and result use trainer slots, not live saved Pokémon |
| `evolution.check` | Second argument live Pokémon, evolution/trigger context known IDs |
| `fieldmove.eligibility` | Move ID and bound live Pokémon result |
| `encounter.fishing` | Rod ID, candidate list and encounter result |
| `encounter.roll` | Context and encounter result; imported encounter-table argument stays native |
| `encounter.species` | Encounter argument/result and context |
| `pokemon.sprite`, `pokemon.icon` | Context Pokémon and species ID; path result stays native |
| `ui.party.submenu` | Third argument live Pokémon; menu rows and nested callbacks stay native |

The remaining native hooks pass their arguments/results through. In
particular, UI callbacks, renderers, input, script arguments, maps, movement,
saves, intro speech and link fingerprint data retain their engine contracts.
Registering an unknown engine callback in unified mode fails immediately.
The source-catalog test forces an explicit boundary decision for new seams;
registration is not a promise that a given game executes that seam. Where
available, use `mod:supports("hooks"/"events", name)` to query the host.

`battle.exp_award`'s `ctx.applyShare(mon, divisor, announce)` accepts a bound
public Pokémon, commits pending validated edits, calls the native helper,
and refreshes the public views. It retains native argument/result behavior,
including errors. Retained helpers and `next` cannot be used after the hook
callback returns. Live party membership/order cannot be changed through this
view. New encounter, enemy-action and trainer-party records may be returned;
live Pokémon/battler replacements must be records bound during that call.

## Mutation and failure behavior

Edits to represented live Pokémon fields, trainer slots, encounters and
context fields are validated before being written. Levels must be 1–100;
stats/max HP positive integers; HP must fit the maximum. Move lists contain
at most four entries, PP must fit the selected move and PP Ups, and `maxPp`
is read-only. Trainer parties contain at most six slots. Unsupported fields,
read-only changes and invalid IDs reject the transaction before any staged
record is changed. Hidden native metadata (IVs, EVs, personality, slot fields)
is retained. Native Pokémon, stats tables, move lists and existing move slots
keep their identities, including battle aliases into those tables.

Before `next()`, validated edits are committed together. After downstream
returns, public views refresh from native state. A successful callback's
later edits commit together too. Throwing before `next()` skips the wrapper;
throwing/validation failure after `next()` keeps downstream results and
changes. Already committed edits and native helper effects are not undone.
Calling `next()` again returns the cached result (including nil holes), or
rethrows the cached error; it never repeats downstream gameplay. Native
errors preserve their identity and are not converted into mod failures.

Only the represented record edits participate in this transaction. Game,
battle, save, world, map, data and RNG handles stay native, as do unclassified
engine-specific fields; direct changes through such handles have ordinary
native side effects. Changing a species/level does not automatically rebuild
battle definitions, recalculate stats, grant moves or emit evolution events.
Use the engine's gameplay operations when that bookkeeping is required.

## Events

Ordinary engine notifications copy their outer context and adapt known
record fields/IDs: battle Pokémon/battlers/moves, level-up learnable move IDs,
move actions, caught/received/evolved Pokémon and trade records. Edits to
these snapshots do not write back. Engine handles remain native, including
`side`, `battle`, `game`, interaction targets and script contexts. A status
source such as `SYNCHRONIZE` remains an engine label rather than a guessed
move ID.

`pokemon.before_give` is the explicit mutable exception: `species`, `level`
and optional `nickname` are validated and committed atomically. Its script
`ctx` stays native. A failure changes none of those gift fields, and later
listeners continue through the original event bus.

Save lifecycle/repair events, screen and intro-speech events, `game.ready`,
`mods.loaded`, and mod option events pass through natively. This preserves
save repair semantics, forwarding metatables and nested callback identities.
Namespaced `mod.<id>.<nonempty-name>` events also pass through unchanged.
Mods may listen to other mods' events and emit only their own namespace.
Priorities, unsubscribe, once semantics, owner attribution and failed-entry
rollback are provided by the original event/hook buses.

## Verification

`tests/engine/unified_mod_callbacks.lua` runs through a ROM-free in-memory
filesystem and the real loader/event/hook buses across every supported host.
It covers string/numeric IDs and aliases, transactional writeback, native
identity, mixed mod chains, `next`/helper failures, event isolation, mutable
gifts, priorities, ownership rollback and the native default. The catalog
checks compare against actual source call sites, rather than another list.
Run it with the same LuaJIT runtime as the engine, then run `scripts/test.sh`.
ROM-dependent gameplay checks still require an imported legal ROM.
