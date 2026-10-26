# Native Gen2 lifecycle callbacks

Gen2 callbacks now observe production state transitions through the ordinary
mod buses. Existing clock, phone, radio, apricorn and fixed-destination log
implementations remain the source of those notifications.

| Boundary | Public contract |
| --- | --- |
| Day Care compatibility | `(next, {data, mon1, mon2, dayCare})`, byte 0..255 |
| Pending egg creation | `{egg, mother, father, compatibility, stepsToEgg}` |
| Hatch UI completion | `{mon, egg, slot, species, nickname}` |
| Friendship write | `{mon, event, reason, delta, from, to}` |
| Pokérus infection write | `{party, slot, mon, strain, days, source}` |
| Successful roaming encounter | `{index, slot, species, level, mapId}` |
| Actual roaming route change | `{index, slot, species, from, to, reason}` |
| First Unown form capture | `{letter, name, word, count}` |
| Completed contest judging | `{mon, score, place, results}` |
| Catch nickname decision | `(next, mon, {battle, name, game})` |
| Full-party catch disposition | `(next, {battle, mon, name, game})` |
| Trainer replacement style | `(next, battle)`, `shift` or `set` |
| Enemy switch/item decision | `(next, battle)`, canonical decision or claim |
| Return to launcher | `(next)` |
| Gen2 boot stages | `{screen, game}`, with `{skipped, frames}` at movie end |

The native Day Care text-tier result remains unchanged. A private weak side
table carries an observed probability to the real egg roll; public method
patches and the existing `EGG_ODDS` table keep their unobserved behavior. Hatch
notifications retain an original egg snapshot before native in-place changes.
The existing `pokemon.egg_hatched` emission keeps its position and payload.
Friendship emits on actual changes after clamping. Duplicate Unown captures,
failed encounters and repeated movie completion do not announce new work.

Pokérus previously existed only as a saved byte. Native GSC battle wins now
perform the party infection/spread transition, including the Goldenrod gate,
the rare de novo roll, cured immunity and the four-day spread stop. Daily
polling seeds its own stamp and advances counters by the saved RTC calendar.
The event runs after the byte is written. This contribution concerns these
party-byte transitions; it does not claim an audit of all Pokérus consumers.

`force_enable_env` retains a manifest variable name. Only a value of `1`
overrides a saved disable. Native generation targeting and no-mod discovery remain in
effect. Existing `log_url` and `mod:postLog` keep their network permission,
ownership and bounded transport behavior.

Published sprite packs can be consumed through `src.import.pmd.Sprite` using
native fixed-frame rendering, row-major quads, timing and mutable anchors.
Follower, species and Unown query adapters cover the unchanged follower
consumer. A concrete live player provider takes precedence; other hosts use
a small live-field fallback. No ROM reader
is introduced. Authenticated follower entrypoints, spawn and animation hooks
run unchanged for Red, Gold, Crystal and FireRed over owned synthetic pack data.

`tools/check_gen2_lifecycle_profile.py` runs native LÖVE and FrameProfile over
192 owned friendship/roamer/contest transitions per frame, comparing the prior
producer files, guarded native code and an ordinary registered observer.
It measures transition CPU work; it does not measure cartridge gameplay, art
correctness or handheld FPS. No performance rollback flag is added for this
compatibility task. ARM handheld performance has not been measured.
