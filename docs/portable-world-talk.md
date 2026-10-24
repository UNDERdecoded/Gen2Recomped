# Portable NPC conversation hook

`world.talk(next, owner, target)` runs when native A-button interaction resolves
a talkable NPC, before the native talk dispatcher acquires its freeze, faces
the actor or starts its dialogue/script. Call `next()` or `next(owner, target)`
to continue. Omit `next` to answer instead. A return value, including `false`
or `nil`, does not request fallthrough; this is a dispatch hook, not a boolean
visibility predicate.

```lua
local mod = ...
mod.hooks:wrap("world.talk", function(next, owner, target)
  if target and target.id == myRuntimeNpcId then
    -- Start this mod's public dialogue/script flow here.
    return
  end
  return next(owner, target)
end)
```

`examples/portable_world_talk` is an unchanged consumer loaded by both engines.
It can claim a selected actor ID, observe the original handles and unsubscribe.
It does not patch engine classes or require internal modules.

## Native boundaries

Both arguments are original opaque engine handles in API 1, native/unified
API 2 and API 3. They are not canonical NPC or Game records. Gen2Recomped's
owner is its OverworldController; Gen1's classic owner is its overworld, while
its separate native GBA field supplies Game. Use public mod APIs for game
operations and do not depend on a common owner layout.

Gen2's shared producer covers all 15 supported hosts, including native GBA
and DS worlds. It retains the existing counter lookup, hidden/moving/blocker
and GBA elevation rules before dispatch. Special Pikachu/HGSS follower talk
keeps its separate native route. Signs, field tiles, ordinary script calls
to `talkTo` and trainer sight approaches are not new hook producers.
`world.interacted` still reports the original resolved actor once for the NPC
interaction, including when a mod claims it. This hook does not replace the
notification or the separate trainer-start contract.

The default continuation matches Gen1's classic void `talkTo` dispatch.
Explicit `next` arguments reach downstream hooks unchanged. Redirecting the
native conversation to a different actor is not a portable promise: Gen1's
GBA script continuation closes over the originally resolved actor. Hook
priorities, unsubscribe, entry rollback, owner cleanup and failure recovery
retain their bus contracts. A failing wrapper before forwarding falls through;
a failure after forwarding does not repeat the completed native conversation.
Native talk errors propagate without replay.

API 3 caches repeated continuation calls on both engines. Gen2 rejects a
continuation after its callback returns; pinned Gen1 can return the cached
result later. A portable mod calls `next` synchronously and does not retain it.
API 1/2 keep their existing native/unified continuation rules.

The pinned Gen1 Gold engine **does not call `world.talk` from its native
`src.world.gen2.World:interactBody`**, despite the name being accepted by its
catalog. The shared checker exercises this real native boundary and expects
no callback there. Gen2 Gold does execute the common contract. The checker
does not substitute the classic Gen1 controller for Gold or modify reference
sources to force a match.

## Verification

```sh
luajit tests/engine/world_talk.lua
luajit tests/engine/world_talk_routing.lua
luajit tests/engine/world_talk_dialogue.lua
python3 tools/world-talk-contract-check/check.py --gen1 /path/to/gen1 --api 1
python3 tools/world-talk-contract-check/check.py --gen1 /path/to/gen1
python3 tools/world-talk-contract-check/check.py --gen1 /path/to/gen1 --format unified
python3 tools/world-talk-contract-check/check.py --gen1 /path/to/gen1 --api 3 --format unified
```

The checker requires a clean Gen1 checkout at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Each worker runs from its own
engine's working directory, using the real Loader, hook bus and native
interaction method. Red, Yellow, FireRed and Emerald have matching shared
observations; Gold has the explicit producer boundary above. Gen1 ignores
API-2 `callback_format`, so that row compares native Gen1 API 2 against unified
Gen2 API 2 with the same consumer.

The common fixture spies on the native conversation/script destination after
real object lookup. Gen1 GBA uses its actual event-object pool, counter lookup,
Field.interact and freeze/face calls. Gold uses its own native interactBody.
Gen2 routing covers all 15 hosts and four callback modes; a separate native
runtime-NPC test exercises real spawn, NPC construction, talkTo, TextBox
confirmation, freeze release, unsubscribe and removal. It binds the same
module-local Game/script dependencies normally installed by enter(), avoiding
an imported map/GPU. Its spawn uses the native public WorldAPI, independently
of the separately stacked API-3 NPC adapters.

The workflow also runs Gen1's unmodified `world_talk` and `unified_npcs` suites,
including real GBA runtime dialogue/registered scripts and cancellation. These
are ROM-free behavioral tests, not imported-ROM playthroughs or pixel goldens.
