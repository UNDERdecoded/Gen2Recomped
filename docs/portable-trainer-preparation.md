# Portable trainer battle preparation

`trainer.before_battle(next, game, context, continueBattle)` runs before the
native trainer battle is constructed. Return literal `true` to defer it;
returning `false`, `nil`, zero or another value lets native admission continue.
`next(game, context, continueBattle)` delegates to other wrappers/default false.
The retained `continueBattle` is a separate one-shot admission function, not
an asynchronous use of the hook bus's synchronous `next`.

```lua
local mod = ...
mod.hooks:wrap("trainer.before_battle", function(next, game, context, continueBattle)
  -- A preparation UI can retain this function until its decision is ready.
  openPreparationUI(function(indices)
    continueBattle(indices and {playerPartyIndices = indices} or {cancel = true})
  end)
  return true
end)
```

`continueBattle()` starts normally; `{cancel=true}` releases the encounter
without constructing a battle or granting victory. A valid first invocation
returns true, including cancellation; duplicates and invalidated requests
return false. A callback can also continue immediately and return true.
Wrappers failing before/after forwarding fall through without duplicating
native admission. Omitting a deferred decision keeps the encounter pending;
mods must offer a decision or cancellation in their UI.

## Scope and native behavior

The context has native `trainerClass`, `partyIndex`, and optional `mapId` and
`npcId`. Identifiers are not a newly canonicalized cross-generation trainer
registry. Gen2 keeps Game opaque and exposes the context through its ordinary
unified context adapter. Pinned Gen1 API 3 also creates a shallow context view
for Game; table identity/arbitrary Game edits are not portable guarantees.
API 1/2 keep their callback defaults; Gen1 ignores API-2 `callback_format`.

The Gen2 producer covers the existing OverworldController trainer challenge
completion and `Commands.start_battle` trainer scripts, including their GBA/DS
wrappers. Trainer sight uses these native routes after its approach. It does
not wrap constructors globally. Direct facility constructors or mod calls to
private constructors do not become new preparation producers. Wild, link,
first-battle and tutorial-marked script entries retain their original routes.
`mod:supports("hooks", "trainer.before_battle")` reports these native producers
on all 15 supported hosts, not interception of every private constructor.

The ordinary challenge TextBox remains before preparation. Victory text,
flags, rewards, post-battle flows and transition ownership remain native.
Cancellation does not defeat the trainer and suppresses immediate same-tile
sight retriggering. Script preparation parks the real ScriptRunner before
construction; its continuation resumes that coroutine, then the normal battle
completion resumes it again. Cancelled scripts receive `lastCheck=false` and
`lastBattleResult="cancel"`, then retire their owning coroutine and release
native script locks/caller completion. Post-battle rows and deferred rewards
never run, including for immediate cancellation and strict mod scripts. Native per-engine event
placement/cancellation details are not promised identical.

A deferred Gen2 request is tied to the original Game/save/data/stack/session,
party table/member order, hook provider/subscriptions and native actor/map or
script coroutine/context. Retained callbacks cannot start against a replaced
session, removed NPC or changed trainer. Native core.update retires invalid
requests; removal of a subscriber cancels a still-current encounter and frees
its pending guard. Stale contexts are retired without running an old completion
against a replacement session. Core-update watcher cleanup preserves other
subscribers. Registration rollback, unsubscribe and owner cleanup still apply.

## Battle-local player party

`{playerPartyIndices={3,2}}` selects save-party members three and two, in that
order, for this battle only. It copies the index list and keeps references to
the selected Pokémon. It never replaces/reorders `save.party` or clones the
Game. HP/PP/status/EXP changes to selected members remain real save changes.
The scope governs the lead, doubles partner, switch/replacement eligibility,
native party menus, EXP participation/EXP.ALL, party-based move/AI queries,
party-row rendering and scope exhaustion. Public battle snapshots already read
the battle-local party. Catch storage and tutorial party restoration continue
to use the actual save.

An empty, sparse, duplicate, fractional, out-of-range or non-table selection
falls back to the full party, matching the pinned reference's bounded behavior.
Selected fainted/egg members are not silently replaced by unselected healthy
ones: native eligibility applies within the selected party. All selected mons
fainting can end the battle even if an excluded bench mon is healthy.

## Verification

```sh
luajit tests/engine/trainer_preparation.lua
luajit tests/engine/trainer_preparation_native.lua
luajit tests/engine/trainer_party_scope.lua
python3 tools/trainer-preparation-contract-check/check.py --gen1 /path/to/gen1 --api 1
python3 tools/trainer-preparation-contract-check/check.py --gen1 /path/to/gen1
python3 tools/trainer-preparation-contract-check/check.py --gen1 /path/to/gen1 --format unified
python3 tools/trainer-preparation-contract-check/check.py --gen1 /path/to/gen1 --api 3 --format unified
```

The clean pinned Gen1 reference is
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. One unchanged example consumer runs
on Red, Yellow, Gold, FireRed and Emerald through both real Loaders. Classic
Gen1 and Gen2 workers use their native prepareTrainerBattle and real battle
constructors; native Gen1 Gold uses startScriptedBattle and its own battle
engine; Gen1 GBA uses the real BattleBridge and native state. The worker compares
native construction, party order, deferral, cancellation, immediate continuation,
true-only claiming, wrapper failures, cleanup, rollback and invalid-scope fallback.
No reference sources are modified.

Gen2-only tests exercise actual challenge TextBoxes, script coroutines, victory
flags/rewards, cancellation, stale references and one-shot admission on all 15
hosts/four callback modes. Party-scope tests exercise actual doubles, native
party screens, EXP and defeat logic. Fixtures supply ROM-free data/asset seams;
the native producer, constructors and gameplay methods are not replaced.
The workflow additionally runs Gen1's unmodified trainer_before_battle,
unified_gen2_hooks and unified_gen3_hooks suites. These checks do not claim
an imported-ROM playthrough or GPU pixel equivalence.
