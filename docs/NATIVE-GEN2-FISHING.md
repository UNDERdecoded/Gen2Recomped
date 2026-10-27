# Native Gen2 fishing lifecycle

Gold, Silver and Crystal rod use enters the native overworld's public
`useRod(rodId)` method. The native bag performs a non-random admission check, keeps a refused use
in the bag, and closes itself before calling that method. The upstream START
menu has already exited when it opens the bag. Registered-item use reaches the same method through `goFishing`.
The other generations retain their existing fishing paths.

`rollFishing(rodId)` returns `nowhere`, `nofish`, `nibble` or `battle` plus
the native individual. It reads the current map's extracted fish group,
time table and active fishing swarm. The existing `encounter.fishing` hook
observes the resolved group and may replace the encounter once. Missing
Gen2 tables cannot fall back to the Gen1 Magikarp rule. Facing-water admission
at a map edge uses the native, un-clamped connection landing; the player
and current map do not move.

`beginFishing(outcome, wild)` installs one shared `world.fishing` /
`player.fishingState` record with `phase`, `timer`, `outcome`, `wild`, `facing`
and a bobber in current-map cell/pixel coordinates. Native logic ticks own
the 40-frame cast and 40-frame bite, the bite emote/player pose, and the
verdict text. Presentation code can observe these records without owning
the encounter or its clocks.

The bite verdict clears fishing ownership before native battle admission.
The battle receives the identical already-created Pokemon, including its
DVs, stats, moves and held item. The internal handoff is single-use and bound
to the live game/data/save/map/player/edition and cast position. It cannot be
used for an arbitrary replacement table or a retired session. Ordinary
`BattleState.newWild` calls continue to generate their own Pokemon.

Map changes, retired world/save/data/player cohorts, cancellation, removed
verdict boxes and lifecycle errors release the cast. Cleanup leaves unrelated
emote/input owners intact. Public callbacks cannot reenter the active rod
admission or roll.

The ROM-free regression is `tests/engine/gen2_fishing_lifecycle.lua`. It uses
the actual native Pokemon/battle constructors, TextBox input, bag and
registered-item paths with generated fixture data. This is separate from
validation with a caller-owned ROM, naturally earned rod and real GPU/mod
presentation. A source-contract result does not establish that gameplay or
a final packaged release has passed.

The public lifecycle and frame contract were compared with Gen1Recomp
revision `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Existing project rights and
notices remain applicable. Contributions by Roxas2712 are
covered by `LICENSE-ROXAS2712.md`.

This addition extends the field-service ownership foundation in upstream PR
#327, without bundling a separate Gen2 menu implementation, species-name
registry or checkpoint system. The upstream controller retains its own
existing native battle callback; the development fork additionally binds
its checkpoint service at the controller handoff.
