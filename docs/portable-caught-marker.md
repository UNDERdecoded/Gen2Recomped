# Portable caught-marker visibility

`battle.caught_marker_visible(next, battle)` controls the already-caught marker
inside eligible enemy healthboxes on GB and GBA. Use the same mod on both engines:

```lua
local mod = ...
if mod:supports("hooks", "battle.caught_marker_visible") then
  mod.hooks:wrap("battle.caught_marker_visible", function(next, battle)
    if hideCaughtMarkers then return false end
    return next(battle)
  end)
end
```

Only literal `true` shows the marker. `false`, nil, zero and every other value
hide it. Gen 1's default is false (the original HUD has no caught indicator);
Gen 2 and GBA default to true. A mod can opt Gen 1 in by returning true.

The native ownership/wild-battle gate precedes the hook. A mod cannot use this
predicate to identify an uncaught species or mark a trainer's Pokémon. Gold
also keeps the already-caught bit captured at encounter entry and checks the
active species again when drawing. GBA excludes player healthboxes, tutorials
and unrevealed ghosts. Status badges take precedence over its marker, and GBA
doubles keep their existing marker exclusion. GB/Gold can show status and marker
together. Intro/hidden HUD branches do not query or draw this element.

The argument is the native battle screen/state, whose internal shape differs
between engines and generations. Native API 1/2 retain identity; API 3 and the
host's API-2 unified mode use a context view, matching the reference boundary.
Forward the argument to `next`; use public battle snapshots for portable reads.
This hook does not normalize private controller fields into a new battle model.

GBA retains the visibility verdict for the presented healthbox, keyed by its
Pokémon object/species, displayed name and ailment. It does not reevaluate a
wrapper on every frame; option changes or unsubscribe take effect on the next
presentation refresh. GB/Gold query on each eligible HUD draw. API-3 repeated
`next` invokes the downstream chain once; wrapper failures follow normal bus
recovery, and failed-entry rollback removes the owner.

## Native rendering and cached artwork

Classic and wide GB layouts draw the optional ball beside the enemy name.
Gold-family layouts use native HUD tile 0x5d at the enemy healthbox's (1,1).
GBA singles draw at the native healthbox offset (8,16). These paths remain
inside `battle.status_hud_visible` and the usual intro/sendout visibility gates.
DS reports this hook unavailable and keeps its own renderer.

New GBA imports extract healthbox element tile 70 into
`battle/hud/caught.png` and publish `constants.gen3BattleHud.images.caught`.
Existing caches use their already imported Pokédex marker as a fallback, with
the older tall Emerald cell cropped to its central native 8x8 footprint. Reimport for
the dedicated native 8x8 healthbox tile. Missing optional art draws no placeholder.
Legacy fallback artwork/layout is not claimed pixel-identical to the new tile.
No cartridge art is bundled by this change.

## Verification

```sh
luajit tests/engine/caught_marker_contract.lua
luajit tests/engine/caught_marker_renderers.lua
luajit tests/engine/caught_marker_import.lua
python3 tools/caught-marker-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified --report /tmp/caught-marker.json
```

The checker requires a clean reference at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The unchanged public consumer runs
through the real GB `BattleState:caughtMarkerVisible`, Gold battle-screen
predicate and GBA `Healthbox.shouldShowCaughtMarker`, compared with the host's
native producer for Red/Blue/Yellow, Gold/Silver/Crystal and FireRed/Emerald in
four SDK modes. These use native-shaped data/session fixtures. They prove the
native predicate and SDK boundary, not full shared compositor or cartridge
playthrough parity. Host renderer tests separately drive classic/wide/GBA HUD
compositors with spies only at font/tile/image leaves, including GBA caching,
status precedence, hidden HUDs and ownership gates. A separate 4bpp test verifies
the real flat ROM reader, tile selection, palette and transparency for the
importer, including the separate read beyond the unchanged 66-tile status scan.
