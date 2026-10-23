# Portable battle-party navigation

`ui.party.grid_navigation` lets a mod select the battle party controller's
native grid policy without replacing a screen's update method. The hook
receives the original opaque party-menu handle in every SDK format. Only
literal `true` opts in; `next(menu)` returns the normal `false` decision.
Removing the wrapper restores the host's existing navigation.

```lua
local mod = ...
if mod:supports("hooks", "ui.party.grid_navigation") then
  mod.hooks:wrap("ui.party.grid_navigation", function(next, menu)
    if myOptions.usePartyGrid then return true end
    return next(menu)
  end)
end
```

The predicate is battle-only. Field menus, submenus, healing animations,
scripted no-input screens and swap/HP-transfer selection retain their existing
input ownership. Confirm and cancel use the native handlers. GBA also retains
its separate confirm/cancel processing when direction and A/B arrive together.
This hook changes navigation, not the menu art or battle legality checks.

## Native policies

GB/Gold-family opt-in navigation treats occupied party entries as a two-column,
row-major grid (`1 2 / 3 4 / 5 6`). Horizontal input chooses the peer in its
row; a missing peer retains the current slot. Vertical input wraps in the same
column, skipping missing cells. Native host menus still differ when the hook
returns false, including whether a Cancel row is present.

GBA uses spatial navigation from the imported slot icon centers. Horizontal
input chooses the closest vertical peer in the requested column; vertical
input chooses the nearest entry in the same column. No vertical neighbor
selects Cancel. From Cancel, up selects the last occupied entry and down the
first. No horizontal neighbor retains the cursor. On old caches without
imported icon positions, the rendered panel positions provide the fallback.
The active battle's party scope determines occupied entries and Cancel;
internal cursor numbering remains engine-specific and opaque.

The common single-layout fixture matches Gen1's actual GB, Gold and GBA
controllers. This does not add missing GBA double-layout artwork or require
identical internal screen objects. Other imported GBA geometries are navigated
according to their own positions. DS party screens retain their existing
controller and report this hook unsupported until a native seam is supplied.

## Validation

The unchanged `portable_party_grid` example is loaded through both real SDKs.
The checker drives native menu input for Red, Yellow, Gold, FireRed and Emerald,
covering one to six party members, every occupied slot, every direction and
GBA Cancel. Gen1 is pinned clean at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. API 1/2 native, Gen2 unified API 2
and API 3 are compared; Gen1 API 2 has no optional unified format.

The Gen2 suite additionally checks every GB/GBA host version in all four SDK
modes, native defaults, wrapper errors and removal, repeated API-3 `next`,
field/submenu/heal/no-input exclusions, imported and old-cache geometry,
empty parties, battle-local party scope and native input-handler routing.
These are ROM-free SDK/controller checks, not GPU pixel or full-playthrough
validation.

```sh
luajit tests/engine/party_grid_navigation.lua
python3 tools/party-grid-contract-check/check.py --gen1 /path/to/gen1 \
  --api 3 --format unified --report /tmp/party-grid.json
```
