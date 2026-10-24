# Portable GBA enemy action targets

On FireRed/Emerald, a mod-selected `battle.enemy_action` move now honors its
positional `target` field through the native Gen2 planner/executor path:

```lua
mod.hooks:wrap("battle.enemy_action", function(nextAction, battle, battlerId)
  local action = nextAction(battle, battlerId)
  if action.kind == "move" then action.target = 2 end
  return action
end)
```

Positions are 0 player-left, 1 enemy-left, 2 player-right, 3 enemy-right.
The numeric choice stays on the action until execution. The engine resolves
the current occupant, so a replacement is hit and an absent selected slot
redirects through native targeting. A move's explicit target takes precedence
over an older UI choice. Existing native actor handles are also accepted;
malformed hints use the ordinary safe fallback.

The move's target policy remains authoritative. Self moves stay on the user,
random-target moves retain their existing selection path, both-foe moves
start with the chosen foe, and all-other-battler moves execute in positional
order. Targeted Electric attacks respect active Lightning Rod holders and
the actual turn order, without later-generation immunity/stat boosts.
Native AI scoring/automatic target selection is not fabricated.

GBA Pressure PP costs count all relevant holders for both-foe, all-other and
opponents-field moves. Self-targeting does not charge the user's own Pressure.
Spread execution spends PP once and emits `battle.move_used` once per action;
actual hit targets remain available through `battle.damage_dealt`. The GBA
zero-power default path no longer publishes a zero-damage hit it did not deal;
explicit custom/fixed damage paths and earlier-generation events are retained.

## Verification

```sh
luajit tests/engine/portable_enemy_targets.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua luajit \
  --report /tmp/enemy-action-report.json
```

The identical public consumer and shared fixture run against unchanged
read-only Gen1Recomp `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The reference uses
its actual native planner and move executor; the host additionally drains
actual single-turn double-battle queues. Cases cover all four selected
positions from both opposing flanks, mutation/replacement, move/damage event
cardinality and order, PP, field/self/spread policies, Pressure, Lightning Rod
priority, cached targets and replaced/absent occupants. The fixture declares
native-shaped synthetic move rows to isolate target policies, not real-game
Spikes or other unimplemented field effects.

Gen2-only regressions cover malformed hints, legacy handles and unchanged
random-target behavior/target RNG against a control with identical combat
stats. Existing move-result, selector and record contracts stay in the runner.

This validates selected action targets, not complete targeting/gameplay parity.
Follow Me and other unported native effect producers, automatic AI target
scoring, full random-target/native RNG parity, called moves, link ordering,
damage amounts and item/switch/watch actions remain separate work. No Gen1
source change or publication is required. The feature is stacked on #194.
