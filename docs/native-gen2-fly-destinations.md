# Native GSC flight destinations

`src.world.gen2.FieldMoves` now exposes `FLYPOINTS`, `KANTO_FLYPOINT`,
`hasVisitedSpawn(save, spawn)` and `flyPoints(save, landmarks, region)` over
Gold/Silver/Crystal's actual native save flags and imported landing spots.
The destination and Gold flag constants follow the separate read-only
Gen1Recomp reference `535a5ec0`; existing upstream rights remain effective.

The map region boundary comes from the native Pallet header. Crystal inserts
the Battle Tower before Silver Cave; the former fixed Gold boundary put
Crystal’s Silver Cave cursor on the wrong regional painting.

Native `setflag` and `clearflag` keys take priority over older visited-map,
spawn-name or numeric-engine-flag fallback saves. Crystal's inserted flag row
is resolved through the same `Gen2Flags.scriptFlag` function as the native
script VM. No second save bit or write is introduced. A clear therefore
cannot be undone by a stale visited fallback. Registered map aliases retain
the native destination identity and landing coordinates.

The default query returns the visited Johto destinations. A Kanto request
switches regions only after Indigo is visited, matching the reference query.
The actual `TownMap` flight picker consumes this public query, so a mod's
wrapper can combine both regional lists. Selection still uses real imported
fly warps and the existing native flight/arrival owner. Unrecognized spawns
and absent landing spots cannot become selectable.

The GSC flag layout is deliberately not applied to Prism, Polished Crystal
or another generation. Their existing native picker paths remain in place.

## Verification and remaining work

`tests/engine/gen2_fly_destinations.lua` passes 149 checks: actual native VM
set/clear execution, Crystal/Gold/Silver flag numbering, explicit-clear
precedence, previous save fallbacks, exact registered aliases, regional gates,
actual `TownMap` A/B selection/cancellation and a real SDK-loaded query wrapper
with actual loader teardown. Existing field-state checks also pass (30).
The tests use generated-data and device fixtures, not a cartridge or player
profile. A CI contract runs both suites.

The retail G/S/C town-map graphics are LZ-compressed. The importer previously
treated them as raw 2bpp tiles, producing repeated horizontal dashes and broken
coastlines on both regional paintings. It now decompresses them before pixel
decoding, rejects undersized sheets, and invalidates only G/S/C import markers
so existing bad images rebuild. Explicit hack layout overrides remain intact.
The ROM-free pixel regression checks every pixel of both 160×144 regional
fixtures across G/S/C (36 checks), including distinct palette nibbles and
asymmetric tile patterns. The saturated original GBC palette is retained.

This change does not add legacy action-result protocols, change field-move
badges or party admission, or accept the unchanged package's complete flight
cinematic. Live Crystal flight, full field-action integration and the mod's
Hall-of-Fame flag/presentation expectations still need separate acceptance.
No new release acceptance follows solely from these CPU checks.

## Upstream composition

This topic is based on the camera/state-query series in PR243 (`b9c0545a`).
It includes the standalone Gen2 `MapIdentity` reader unchanged from PR211
(`3aa7017f`), so the flight query can run without copying unrelated fork or
Gen3 naming code. Complete imported shared-map alias production remains in
PR211. The new flight delta does not include private mod data, ROM data,
launcher/release policy or the fork contribution-notice packaging changes.
