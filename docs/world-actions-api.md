# Public world actions

`mod.world` adds six methods without a manifest opt-in or Mod API bump:
`canReorderParty`, `reorderParty`, `availableFieldActions`, `useFieldAction`,
`canFly`, and `flyTo`. The new actions validate free-roam state before using
existing native gameplay entry points. Existing world methods, party menus
and script commands keep their contracts.

```lua
local ok, reason = mod.world:reorderParty(1, 2)
if not ok then mod.log:info("%s", reason) end

local actions = mod.world:availableFieldActions()
for _, action in ipairs(actions) do
  -- { id = "surf", label = "SURF" }, for example.
  -- Show a companion UI; revalidate when the player actually chooses it.
end

-- Later, from an explicit player choice:
local started, why = mod.world:useFieldAction("surf")
local flying, flyWhy = mod.world:flyTo("A_NATIVE_DESTINATION_MAP_ID")
```

## Free-roam boundary

The save, overworld map, player, native script runner and authoritative stack
top must be present and ready. Methods refuse while another screen owns the
stack (including battles/dialogue), a script is running/queued, scripted
movement is pending, a transition or field animation is active, the player
is moving/locked, a mod script lock is held, a decoration mode owns input,
or a link session is live. Native engine errors propagate; an action that
throws is never retried by this facade.

`canReorderParty()` and `canFly()` return booleans. Mutations return `true`
when accepted, or `nil, reason` when refused. `availableFieldActions()` gives
an array of detached `{ id, label }` records, or an empty array and a reason
when the world is unavailable/busy. Queries use native eligibility checks,
including existing mod hooks; the facade does not itself perform an action
while probing. A mod's own hook can still have ordinary native side effects.
Recursive mutations from those eligibility hooks are refused, and a changed
source context invalidates the pending request.

A previous successful probe/list is not a reservation. Every action checks
state again when invoked. Typical reasons are `no save`, `no overworld`,
`world is busy`, invalid arguments, unavailable destination or unavailable
field action. Availability of the interface does not promise every action
exists in every generation.

## Party ordering

`reorderParty(fromSlot, toSlot)` swaps two existing party references, matching
the native party menus. It does not insert/remove Pokémon, recalculate them
or copy their data. Slots are integer, one-based indices from 1 to 6; both
must exist. Fainted Pokémon and eggs can be reordered. A same-slot request is
a successful no-op. Invalid slots refuse before changing the party.

`canReorderParty()` is true only when the world is ready and there are at
least two party members. A retained facade reads the current save when used.
No menu selection or battle party order is changed behind a screen's back.

## Flight

`canFly()` additionally requires a real non-egg party carrier, the native
badge/location checks and at least one currently unlocked, valid destination.
`flyTo(mapId)` accepts a native map ID from that game's destination set. It
is not a general warp: unknown, locked, unvisited or invalid landing points
are refused before departure state changes. A caller-provided coordinate,
spawn-table index or arbitrary destination object is not accepted.

| Host | Eligibility and destinations | Native departure |
| --- | --- | --- |
| Gen 1/2 | `partyKnows("FLY")`, outside-map rules, visited `field.flyOrder` towns with `flyWarps` | `OverworldState:flyTo` |
| Gen 3 | Native carrier/badge check, `Gen3FieldRules`, visited town set | Native field-move cut-in, then `flyTo` |
| Platinum / HGSS | `Gen4FieldMoves`, `Gen4Fly.check/destinations`, partner/Safari/badge checks and HGSS costume refusal | `gen4FlyTo` |
| Black / White | Native numeric move lookup, `Gen5Fly.allowed/destinations/destination`; no invented badge gate | `gen4FlyTo` |

The native handlers retain departure timing, player input lock, bike/surf
state changes and exact landing coordinates. The direct map-ID call does
not open a destination picker. Gen 3 keeps its native Pokémon cut-in, falling
back directly when there is no picture to display.

## Verified contextual field actions

This initial adapter deliberately exposes only these native paths:

| Action ID | Gen 1 | Gen 2 | Gen 3 | Gen 4/5 |
| --- | --- | --- | --- | --- |
| `cut` | Native cut eligibility + `tryCut` | Same, reaching native Gen 2 Cut | Refused: object-script adapter required | Refused: native script adapter required |
| `surf` | Native eligibility + `trySurf` | Same | Same, with native field-move presentation | Refused: native script adapter required |
| `dig` | Eligible dungeon → native last-heal departure | Eligible cave/dungeon → recorded entrance | `Gen3FieldRules` → recorded entrance | Refused: native script adapter required |
| `teleport` | Outside map → last heal | Outside map → last heal | Native travel rules → last heal | Refused: native script adapter required |

Native carrier lookup selects a current non-egg party member. Badge checks
and target/location gates are retained; fainted carriers remain eligible
where the native engine permits them. Surf starts mounting; there is no
invented generic dismount action. Dig and Teleport keep distinct native
escape/last-heal semantics. Cut uses live target eligibility rather than
matching a global block number.

`useFieldAction(id, opts)` accepts no options or an empty plain options table.
Unsupported options, action IDs and generation adapters return a reason.
This version does not expose bicycle/fishing, Strength/Flash, healing moves,
custom source selection, Gen 3 object-script actions or DS field-script
activation. These require separate adapters with their native checks; callers
must use the returned action list rather than assuming a fixed menu. Fly is
separate because it needs a destination.

## Deferred completion and cancellation

A `true` result means the native request was accepted, not that the animation,
dialogue or warp has finished. Native gameplay owns those asynchronous flows.
A Gen 3 cut-in blocks competing public mutations until it finishes. Its
effect is guarded by the source save/data/map/player, position/facing, version,
party membership and fresh eligibility. Changing that context cancels the
effect. A repeated completion callback cannot replay it. Abandoning the
presentation does not leave a permanent facade lock; a stale callback cannot
start a later effect. Already executed native gameplay is not rolled back.

## Capabilities and tests

With the optional capability-query feature, each of these six method names
returns true from `mod:supports("world", name)` without constructing Game or
the world. Other capability answers are delegated unchanged. Use
`canFly`/`availableFieldActions` and the mutation's return value for current
state and action-level availability.

`tests/engine/world_actions_api.lua` uses the real loader across all 15 host
version IDs. It exercises refusal parity for world/player/script/link locks,
party identities, slots, destination gates, eggs, partner/costume checks,
contextual dispatch and reentrant/deferred/error paths. It also runs actual
native carrier/badge lookup, Fly/DS Fly departure methods and Gen 1–3
Dig/Teleport departure state changes without ROM assets or graphics. A cut-in
test double drives completion/cancellation deterministically; it is not a
rendered playthrough. ROM-dependent map scripts and graphics still need an
imported legal ROM.
