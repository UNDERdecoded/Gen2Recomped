# Existing Gen1Recomp mods on the native host

The compatibility target is an unchanged mod manifest, entry point and assets.
Compatibility contracts belong in this engine. A mod-specific converter or a
replacement entry point is not evidence that the original mod works here.

API 3 already exposes portable content, world and UI contracts. Mods declaring
`engine_internals` can additionally import Gen1Recomp's native module names.
Those imports require actual compatible implementations: the old Game3 runtime,
map layouts, caches, battles and render passes are not equivalent to unrelated
native classes with similar names.

## Map identity

`src.import.gba.map_catalog` now implements the identity operations used by old
mods: `mapIdFor`, `groupNumFor`, `slotKeyFor`, `resolve`, `isKnown` and
`pretToEngine`. The original five-edition names, including FRLG's older
`SEVII_*` aliases, come from the public Gen1Recomp v0.3.94 catalog at
`37a49b31f458d51ea9e00b90f2a247272ad09cb8`. No ROM data is included.

Native code can bind those names to its actual `data.maps` table with
`src.compat.gen1.MapIdentity.bind(maps, edition)`. `nativeId(oldName)` returns
the real native key and the exact borrowed definition. `legacyId(nativeKey)`
returns the original name. The ROM group and number establish the identity;
the adapter never rewrites definitions, connections, scripts or saves.
Same-object aliases remain valid. Conflicting definitions for one slot are
rejected. A removed/replaced record or changed slot retires the binding; bind
again after replacing the map table or changing its keys. Malformed slots and
unknown names do not acquire a guessed native destination.

This is the identity portion of the old catalog, not its tileset discovery or
cache registry. It does not implement `src.core.game3.map`, construct an old
Game3 session, or establish rendering/gameplay acceptance of Origami 1.0.9.
The original package's entry still stops at the missing old map module.

## Verification

Run the same old-name consumer against a clean pinned public Gen1 checkout and
this host:

```sh
python3 tools/gen1-map-compat/check.py --gen1 /path/to/pinned-gen1 --lua luajit
```

The check regenerates the complete name metadata from the actual reference
catalog and requires byte equality, then runs the identical consumer on both
engines. There are 34,127 checks per engine across FireRed, LeafGreen, Emerald,
Ruby and Sapphire. The independent native binding suite adds 10,824 checks,
including stale records, duplicate slots, same-object aliases and invalid IDs.
The five-edition comparison requires the host's LeafGreen/Ruby/Sapphire
cartridge support (PRs #183/#186/#187). On a host with FireRed and Emerald
only, pass `--edition firered --edition emerald`; that consumer performs
14,766 checks per engine. The detached binding suite covers all five catalogs
on either host and does not activate an unavailable cartridge.

Optional `--native-cache /path/to/own-qa-imports --native-edition firered
--native-edition emerald` checks existing QA-only native imports without any
game launch. The accepted imports match all 425 FireRed and 518 Emerald maps,
with zero unknown slots. This is an imported-record check, not a live warp,
renderer, collision or player-save test. Use fresh QA identities for gameplay.

## Remaining boundaries

The next map boundary must preserve current-map ownership, layout cells and
revisions, connected placements/residency, semantic IDs and atlas lifetimes
together. The public name lookup alone must not be aliased to `src.world.Map`.
Old cache files must not be mounted as the new cache schema. Battles and UI
need their own state, action, timing and presentation contracts. Each completed
boundary needs unchanged-mod tests, native lifecycle checks and graphics proof
where it affects drawing. Full Origami and general internal-API compatibility
remain unaccepted until those paths work with the original package.
