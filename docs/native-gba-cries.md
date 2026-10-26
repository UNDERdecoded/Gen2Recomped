# Native GBA cry playback and world-script waits

The admitted FireRed/Emerald profiles use the native species recording,
cry mode, integer release envelope, pitch, chorus and reverse controls.
`playmoncry` resolves both species and mode through the script variable
store and starts playback immediately. `waitmoncry` yields the actual
runner until the tracked cry finishes. Generic GB `play_cry` retains its
existing text-dialog behavior.

The cry clock runs with the real 60 Hz audio service. A waiting script
advances it only if no audio tick occurred since its previous poll.
Recording-derived duration wins over a stuck audio source; early source
completion also releases the wait. Missing native audio data retains the
native 64-frame fallback. SE-player ownership and waits stay independent.

Native WaveData supports ordinary signed PCM and Game Freak DPCM. The
renderer applies the native modes at the GBA frame rate, including Emerald's
mode-six volume. Native Hoenn cry IDs follow their species control table,
not the species position after the old Unown slots. New imports advertise
`gen3Cries.mapping = "native-species-v1"`; existing stock sequential Hoenn
entries are corrected during native playback. Explicit mod-owned, file,
string and disabled definitions retain their override path.

Rendered PCM is cached in a bounded per-data cache. Each playback owns a
fresh source, preserving overlapping cries. `stopCry` stops the latest
tracked native source. Species invalidation and session suspension release
associated sources. Isolated dex playback uses native PCM without replacing
the world's wait state, controls or music attenuation.

Native command revision **19** prevents lockstep with revision 18's cry
semantics. Party codec revision remains **1**. Independent frozen-parent
serialization changes only command revision 18 to 19: native fixture digest
`22e453523676534e`; legacy digest `e33d251961f2a41d` remains unchanged.

## Validation and scope

The [source-bound QA receipt](qa/native-gba-cries.json) records qualified
runtime commits, source/test trees, fixture and raw-report hashes, complete
comparison counts, the retained timeout and its successful bounded replay.

- Combined runtime `0286d291`: **285/285** engine suites, SDK **3/3**, B30
  and every quick tier pass.
- Feature runtime `1322ee81`: **167/176** engine suites versus fresh parent
  `c7cda532` **166/175**. The exact anchored FAIL-line Counters match: the
  same **25 lines / nine inherited suites**, with no additions or removals.
  SDK **3/3** and B30 pass on both.
- Each runtime: **240 qualified workers / 176,170 complete paired
  observations** against clean unchanged Gen1 code at
  `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. All admitted
  mode/backend/profile combinations execute exactly once; complete nested
  fields, events, RNG, PP, animation data, PCM and JSON boolean types remain
  compared. The three new cry contracts contribute **554 paired rows**.
- Native cry suite: **10,983 checks**, including actual
  Game/FixedStep/StateStack clocks at 1x/2x/10x, field locks, public command
  hooks, script-ended events, isolated playback, cache/source ownership,
  missing devices, recovery and the real structural importer over owned
  bytes. Protocol **175**, SE-player lifecycle **110** and world-SE-wait
  **6,306** checks also pass.
- Each runtime on existing local FireRed/Emerald imports and owned ROMs:
  **18 actual cry-script cases**, all **221 frames per case** and every PCM
  sample equal; separately **48 complete actual PCM outputs** match.
  Imported M4A bytes equal the original ROM slices. All **135** runtime
  Hoenn cry IDs equal both native ROM control tables.
- Actual nonfading BGM sources receive the native attenuation/restoration
  across modes, release, stop, overlap and option changes. These checks
  retain raw volume readings and verify attenuation relative to each
  backend's baseline gain; they do not assert whole-music waveform parity.
- Existing import regressions retain **10 native sound cases** and
  **24 Mirror Move scenarios / 48 public-submitted turns / 120 move-used
  events** per runtime, with complete observations equal between candidates.
- Removing only the Game cry-clock call produces **six exact expected
  failures**, 10,977/10,983 checks. The unchanged parent separately reproduces
  deferred cries, dropped mode/variable handling and no-op cry waits.

One original feature FireRed `nature_power` worker was terminated at its
recorded 60-second deadline without observations. Its original report
remains retained. Four fresh workers pass with a bounded 180-second budget,
9.6–19.2 seconds; every previously completed observation is unchanged. The
checker gives this exhaustive mode the same bounded budget. No failed or
superseded raw evidence is discarded.

Tests use CPU hardware doubles with the real engines, native controllers,
VMs and renderers. They start no game, GPU or actual audio device and write
no normal saves/imports. No ROM, generated audio image or private pack is
committed. Results cover admitted FireRed/Emerald contracts, not every
public audio-event timing, unsupported native profile, arbitrary full mod
or playthrough. Native BGM commands remain separate follow-up work: actual
`fadeoutbgm 4` still stops immediately on the host instead of following the
native 64-frame fade.

## Reproduction

Use LuaJIT `a4c064539ea931274d407e1249b4bb575424a0f4` and a clean read-only
Gen1 checkout at the reference above. From this checkout:

```sh
nice -n 19 env LUA=/path/to/pinned/luajit bash scripts/test.sh --quick
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 . \
  --lua /path/to/pinned/luajit --report /path/to/all-contracts.json
```

A targeted run accepts `--mode native_cry_commands`,
`--mode native_cry_lifecycle` and `--mode native_cry_pcm` together. The
canonical checker records raw workers and timings. The receipt also records
an independent full JSON comparison which distinguishes booleans from
numbers, including `false` versus `0`.

The existing-import tools take explicit read-only inputs. No import is
created and no normal cache is rewritten. For example, from this checkout:

```sh
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/imported-native-cry-smoke.lua \
  . gen2 firered /path/to/existing/imports /path/to/owned-firered.gba
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/imported-native-cry-render.lua \
  gen2 firered /path/to/existing/imports /path/to/owned-firered.gba
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/native-cry-bgm-smoke.lua . gen2 firered
```

Repeat with `emerald` and its ROM. For the native counterparts, run from the
clean reference checkout, invoke these tools by absolute path, change
`gen2` to `gen1`, and replace the smoke tools' `.` argument with this
checkout's absolute path. Keep every raw tagged observation when comparing
outputs. The BGM-source probe checks attenuation properties against its
retained raw per-backend gains rather than equating different baseline
music streams.
