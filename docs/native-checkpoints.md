# Native checkpoint facade

Every mod API level exposes `mod.checkpoints:inspect(game)`, `capture(game)`,
`restore(game, checkpoint)`, `resume(game, checkpoint)` and
`ensureNormalSave(game, checkpoint)`. Inspect before offering a capture. A refusal
includes a named reason; it never substitutes a different game state.

This service is independently implemented using the host's native save,
controller, actor, script and battle services. It supports the host’s selectable
editions through generation 5. A settled player can capture native actors that
are wandering, partway through a step, repositioned by a script, following the
player or present in connected maps. Native map patches, actor pools and shared
follower trails retain their semantic state and relationships.

Ordinary single-player wild and trainer battles admit a player decision in
`menu`, `moveSelect` or `targetSelect` after queued actions, messages, animation
and introductions have finished. Battlers, party/stat aliases, field and side
tokens, volatile state, cursors and the native RNG resume together. Native wild,
trainer and static-encounter completion operations resolve fresh actor owners.
A built-in data-only `start_battle` row can resume through a fresh ScriptRunner
at its following row, including its native completion. The old coroutine and
closures are never restored or serialized.

Link/multiplayer, Safari, ghost, demonstration and special battle modes, forced
actions, concurrent scripts, opaque callbacks/custom RNG, native VM call stacks,
active transitions and unqualified effects are deliberate refusal boundaries.
An arbitrary function or mod-owned controller cannot be inferred from its data.
This contract does not promise capture at every instant of a story or battle.

## Data and ownership

Format 1 is detached plain data: identity contains `engineVersion`, `gameVersion`
and `playthroughId`; `save` contains canonical progress; `runtime.overworld`
contains `{map, x, y, facing, surfing}`; `rng.love` contains the host RNG encoding.
Current snapshots add `runtime.actors` and optionally `runtime.battle` with a
validated semantic data graph and a native continuation descriptor. No engine
object, sprite, GPU resource, function or private transaction token is public
checkpoint data. Legacy static/spinner format-1 records remain readable under
their original admission rules. Legacy records without RNG retain the current RNG.

Restore validates identity, installed content, coordinates, actor and battle
relationships, continuation owners and RNG before reconstruction. It creates
fresh native resources in a private transaction, suppresses ordinary entry/load
events and verifies a full recapture. Normal map entry cannot erase canonical
checkpoint progress. Failed reconstruction restores the original save, actors,
controller fields, map cache, palettes, stack ownership and both RNG services.
Old resources remain owned by rollback until commit.

Saved `modData` rewinds and the mod-save service is rebound to it. Current global
and per-mod options retain their live identity; separately persisted mod storage
does not rewind. Unknown mod-owned world fields remain owned by their mods.
Other runtime references/caches are not saved; mods must refresh them on the
single committed `checkpoint.restored` event with `{game, kind}`.

`resume` requires the native title and selected playthrough. Failure preserves
the title; resume never writes normal progress. `ensureNormalSave` separately
verifies the current checkpoint, returns `true, "already_exists"` for an existing
save, or uses the real normal save lifecycle for the first save. A conflicting
destination is refused. Injected read-only test filesystems cannot redirect a
real normal save write.

## Qualification

Five CPU suites exercise the actual loader, Game, state stack, controllers,
map cache, party and save services over owned synthetic data. All selectable
edition selections are covered (18 in the fork, 15 in the public host), including native static/trainer producers,
script suffix execution, malformed payload refusal, partial-apply rollback,
title resume and ordinary battle-turn continuation. These are runtime/contract
checks, not full ROM playthroughs.

`tools/check_native_checkpoint_rng.py` runs actual LÖVE math/RNG on 11.5 and 12.
It checks all four native stationary-spinner modes for 384 updates in Red/Gold
at API 1/2/3, plus 192 complete native world updates and two actual battle turns
in eight representative editions at every API level. Every future checkpoint
and RNG value must match after restore. Each host performs 14,520 assertions.
Graphics are substituted; GPU and full-story acceptance are outside this test.
An older public checkout can supply the shared storage guard with `--qa-tools`.

See `docs/qa/checkpoint-runtime-m4.json` for exact qualified revisions and gate
results. `docs/qa/checkpoint-spinners-m4.json` retains the earlier, narrower
qualification as history. This compatibility service has no performance switch;
FrameProfile before/after for checkpoint operations: not measured.

The current upstream Gen4 field/side effects, including boolean side keys,
and the native battler-keyed chosen-action relationships are reconstructed
as semantic data. Ordinary singles do not require a double-battle position.
Maps with native dynamic Gen4/Gen5 gym controllers are refused explicitly
until their mutable controller resources have a qualified reconstruction.

On hosts with native PP-bound move actions, checkpoint reconstruction uses
the existing action owner's slot query and move factory. It retains learned
slot identity and PP read/write behavior without saving a metatable.
Delegated action metadata/references outside that qualified factory boundary
remain refused. Future-decision tests now restore a post-turn checkpoint
and check the learned-slot alias as well as complete recapture equality.
