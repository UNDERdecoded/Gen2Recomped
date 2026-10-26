# Native GBA Follow Me

FireRed/Emerald's imported effect 172 (`FOLLOW_ME_EFFECT`, move 266) now has
an ordinary native effect record. A successful move marks its user's side
with a round-local position. Selected opposing attacks resolve the current
living occupant of that position, including public API-3 `battle.enemy_action`
choices. Mod code does not need an engine-specific redirection hook.

The position is shared by a side: the last successful caster wins. A slot
replacement inherits the position for the rest of the round. A fainted
occupant does not draw attacks, but its active timer still suppresses
Lightning Rod, matching the covered native reference behavior. Live Follow
Me takes precedence over Lightning Rod. Self and spread moves retain their
own target policy. The native effect consumes normal owned PP, executes at
its imported priority and remains subject to ordinary status interruption.
Substitute and Protect do not block the imported self effect.

Both sides reset when the next turn is planned, before turn-started observers
and action execution. Residual collection does not prematurely clear the
flag. The producer and targeting state are limited to GBA; existing GB/DS
rules remain separate.

## Validation

```sh
luajit tests/engine/gen3_follow_me.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua luajit \
  --report /tmp/enemy-action-report.json
```

The 180 focused checks cover both GBA profiles, both sides/flanks, successive
casters, default and mod-selected targets, fainting and replacement,
Lightning Rod precedence, self/spread/single policies, sleep refusal,
Substitute/Protect, residual and next-turn lifetime, real priority queues,
PP and non-GBA guards. Actual move/damage events verify execution targets.
The shared fixtures use synthetic extractor-shaped move rows, not a fresh
cartridge import or full gameplay capture.

The same API-3 consumer and fixture match unchanged read-only Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`: 24 engine workers and 354 paired
observations, including prior choice/argument/record/target contracts.
Running the new FireRed cases on unchanged #195 fails 29 assertions.

This feature stacks on #195. The local quick run passes 82/91 engine suites,
3/3 SDK suites and B30, versus 80/90 on that prerequisite. Exact FAIL-line
Counters show no additions: only the two fingerprint failure lines disappear;
all 25 remaining lines across nine inherited suites are identical. Registering
only this new effect changes the prerequisite fingerprint from
`41e69caf4afa35ab` to `128fc071ae7249cd`; removing just that entry and invalidating
the fingerprint cache restores the former. The committed golden pins the new
native registry. Baseline repair PRs remain separate.

## Canonical effect composition

The canonical public effect adapter is a separate dependency (#121). When
both changes are integrated, public `effect = "FOLLOW_ME"` writes select the
real native handler automatically; no generated contract-table edit is needed.
An explicit composed proof loads a real API-3 mod, patches a move through
`mod.content.moves`, reads the canonical effect back, then casts it and checks
that a real mod-selected attack is redirected with owned PP:

```sh
luajit tests/follow_me/public_effect.lua
```

That proof requires both features and deliberately fails if either is absent.
The standalone feature's normal suite does not pretend to include #121.
In the combined checkout the old missing-handler assertion in
`tests/engine/unified_move_effects.lua` must be updated to assert availability.

Remaining native effect producers (Helping Hand, Magic Coat, Snatch,
Imprison and called/terrain effects), random-target/RNG parity, AI scoring,
link/called-move execution and full damage/gameplay parity are separate work.
No Gen1 source change or publication is required.
