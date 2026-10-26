# Portable battle move navigation

`battle.move_grid_navigation` selects native move-menu navigation without
replacing a battle update method. The callback receives the actual opaque
battle/screen handle. Only a first result of literal `true` enables the grid;
`false`, `nil`, zero and other values select the list. `next(battle)` asks for
the host layout's normal mode. Unsubscribing restores that mode.

```lua
local mod = ...
mod.hooks:wrap("battle.move_grid_navigation", function(next, battle)
  if myOptions.useMoveGrid then return true end
  return next(battle)
end)
```

The native default is a list for classic GB and a grid for GBA/DS and Gen2's
wide layout. As in Gen1Recomp's original GB battle, the Gen1 wide layout is a
fixed grid and bypasses the predicate. Gen2's Gold-family wide screen allows
an explicit list override; its unwrapped native default remains a grid, while
Gen1's distinct Gold screen defaults to a list. Portable custom UIs should
choose their desired mode explicitly rather than infer host-private fields.

Grid slots are ordered `1 2 / 3 4`. Missing cells retain the current slot.
Single-battle grids wrap between row/column peers. GBA doubles use the native
clamped player controller: left at the left edge and up at the top edge stay
put. This corrects Gen2's previous generic wrapping at GBA doubles edges and
matches Gen1's native GBA controller. DS retains its existing grid behavior.
The list uses native up/down wrapping. A/B/SELECT stay with their normal
handlers; the same decision also applies to Gen2's Mimic copy menu.

Both native and unified callback formats keep the battle handle opaque.
Subscribing does not normalize engine-private controller fields. Use public
snapshots/actions for gameplay data and input actions. Availability is reported
for the actual shared native producer in Gen1–5.

## Validation

The unchanged `portable_battle_grid` example is loaded through both real SDKs.
Shared cases drive native move-menu updates for Red, Yellow, Gold, FireRed and
Emerald: all four directions, every occupied slot and every move count from
one to four, in explicit list/grid modes. They also drive the native GBA
doubles input controller and compare its edge and missing-cell behavior.
The Gen1 reference is pinned to clean
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.

Native API 1/2 and API 3 are compared directly. Gen2's optional unified API 2
is compared with Gen1's native API 2, since Gen1 has no `callback_format`
extension. Gen2 additionally tests all fifteen games, native defaults, wide
layout rules, Mimic, wrapper failure recovery, API-3 next caching, unsubscribe
and empty move grids.

```sh
luajit tests/engine/battle_grid_navigation.lua
python3 tools/battle-grid-contract-check/check.py --gen1 /path/to/gen1 \
  --api 3 --format unified --report /tmp/battle-grid.json
```

These are ROM-free native-controller and SDK tests, not cartridge playthroughs
or GPU pixel goldens. This predicate changes navigation; custom grid/list art
remains the mod's responsibility.
