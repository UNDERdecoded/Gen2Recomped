# Native GBA background music: development checkpoint

This work continues the native-audio series after #289. It is an incomplete
development checkpoint, not a release qualification or a claim of complete
music parity. The playable integration branch has not been advanced.

The world VM preserves `playbgm`, `savebgm`, `fadedefaultbgm`, `fadenewbgm`,
`fadeoutbgm` and `fadeinbgm` as native commands. Logical current, map and
saved music remain independent of physical song labels. Only `playbgm`'s
keep flag `1` or `true` saves an override; zero and `0xFFFF` stop playback.
The actual native world adapters use fixed speed four for outgoing and
incoming fades, regardless of the encoded speed. `fadenewbgm` dispatches
immediate playback in those adapters.

The admitted FireRed/Emerald identifier catalogue includes 305 `MUS_*`
names, including aliases and native reverse names. Named mod file music
can be selected by numeric native commands without renaming its definitions.
Shared mod music retains its own transport and user-volume behavior.

Emerald's default selection reads live map identity, player position,
saved weather and story variables/flags through the host's existing formats:
`MAP_Gxx_Nxx`, `save.gen3Vars`, `save.flags` and `save.gen3Weather`.
It handles Route 111's sandstorm, Sootopolis silence, legendary weather,
the occupied Space Center and Weather Institute, and Route 118's split at
x=24. Repeated commands re-read the current state. FireRed retains its
separate map-song default. This does not yet replace every map/bike/surf
transition entry point.

## Checked at this checkpoint

All comparisons run unchanged native Gen1 code at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, using the real production world
adapters, VMs, music services and owned audio hardware doubles. No native
audio method is replaced with a host result. LuaJIT is pinned to
`a4c064539ea931274d407e1249b4bb575424a0f4`.

- **40 workers / 2,648 complete paired observations**, independently
  compared with JSON booleans distinguished from numeric zero/one.
- The new BGM contracts contribute **1,970 rows**: 1,844 symbol rows,
  32 command/lifecycle cases with all 81 frames and play traces per case,
  and 94 default-policy cases with all five frames and play traces.
  File cases retain every created source, including stopped sources and
  their actual gains. Another 40 rows cover native fanfare commands and
  waits; twelve rows cover initial missing-output state, fades and replacement
  of shared file music, 46 rows cover public music hooks and events, 26 rows
  cover audio options/reentrant world actions, and the remaining 554 rows
  recheck native cry contracts.
- **80/80** BGM command, **62/62** stream and **7,364/7,364** fanfare engine
  checks pass, as do **124/124** missing-device/session recovery and
  **4,616/4,616** public music hook checks, **102/102** audio option and
  **51/51** cold cache/invalid-handle checks at that historical checkpoint.
  The full feature quick run passes **174/183** engine suites,
  SDK **3/3** and B30. A fresh preceding development checkpoint `3f3f473d`
  passes **173/182**;
  the exact anchored `FAIL ` line Counters are identical:
  **25 lines / nine inherited failing suites**, with no additions/removals.
- The changed workflow passes actionlint. New modules and BGM test files
  pass StyLua verification. These are local results, not executed hosted CI.

The earlier development default-policy probe reproduced differences in
44/88 Emerald cases and none of the six FireRed controls. Failed and
superseded reports remain retained. The corrected implementation passes
all 94 cases, including live state changes after an earlier default command.

## Native stream follow-up

Native M4A cue construction now leaves an empty, stopped queue. Each
synchronous native audio service produces one buffer, after applying that
tick's fade, and then starts playback. A stop on the final fade tick cannot
produce another buffer. Finite native sequences retain their silent carrier
until a stop or replacement command. Shared named mod music keeps its
separate transport; a chip source is started only by its streaming owner.

Worker recovery preserves the native source owned by `Music`, including
queued PCM and the current fade, both before and after the first worker
buffer. Stale worker generations cannot enter the queue. The stream engine
suite passes **62/62 checks**, covering synchronous playback and controlled
worker-channel failures. The corrected recovery removes six reproduced
assertion failures; failed and superseded logs remain retained.

A separate real-sequencer comparison runs **four workers / 18 cases /
1,534 complete observed frames**. All portable BGM control fields, runner
state, active source counts and gains relative to each backend's retained
baseline agree. Sixteen native/file cases also have equal queue, produced
buffer and play counters. Both chip-override cases retain the reference's
different existing GB lookahead cadence; their complete counter differences
are recorded, not treated as native-queue parity.

Every produced PCM buffer is retained: **7,929,856 scalar samples** from the
reference and **8,323,072** from the host. The native synthesizers still
produce different PCM; this comparison does not establish waveform parity.
Named mod M4A definitions remain a host extension: the reference's shared
mod player does not accept that format. Host tests verify that the extension
does not incorrectly allocate a native background carrier.

## Native fanfare follow-up

`playfanfare` resolves script variables and begins a native, nonblocking
fanfare. Its timer reads imported `constants.gen3Fanfares` metadata and native
song information, including the level-up fallback when a present table does
not admit the requested song. Missing timer metadata retains the native
160-frame default. Rendered sound duration does not decide script completion.

The real audio service advances the timer. `waitfanfare` also retains the
reference's separate **361-poll** script safety limit and latched completion
callback. Accelerated logic can reach that safety limit before a long
fanfare's audio timer finishes; both behaviors are compared explicitly.
New/repeated fanfares, explicit same/different/silent BGM cues, deferred
defaults and BGM dispatch to a native fanfare preserve their distinct native
rules. Shared mod music is not paused as though it were a native carrier.

Native fanfare sources use the music option and occupy the declared SE
player. Repeated cues reuse the cached source; replacement stops the former
fanfare and the target player's previous sound. The audible tail can outlive
the native script timer. Fanfare pause clears queued native BGM PCM and
stops its producer. Worker packets retain a pause epoch so an old packet
cannot re-enter the resumed source; stale resume commands are ignored.

The fanfare engine suite passes **7,364 checks**, including actual
`Game`/`FixedStep`/`StateStack` execution at 1x/4x/10x, field ownership,
public script hooks, completion events, physical map-music restoration,
the real worker body and controlled worker transport. The audio service
uses its game instance's dataset, so a correct logical song cannot mask a
failed physical replay against another dataset. The previous behavior
reproduced six physical-restoration assertion failures.

The 40 complete fanfare command rows compare unchanged native production
adapters and VMs. A separate **four-worker / 12-case / 156-frame** comparison
uses the real native/host renderers and keeps all distinct PCM, source
inventories, SE queries and queue counters. The earlier checkpoint warmed
the reference cache to accommodate table-backed headless SoundData. The cold
admission follow-up below removes that workaround. This does not claim
whole-waveform parity or real-device qualification.

## Missing output and session follow-up

An initial native map cue retains its logical song when a queueable Source
cannot be created. A transient device failure does not permanently mark the
native song as a bad mod definition: after output becomes available, another
cue can play, followed by the originally failed song. The command comparison
covers missing factories and factories returning nil on both engines. Host
recovery tests also cover a throwing factory; the reference's native queue
factory call itself is unguarded, so this is a host robustness check rather
than a claim of matched exception behavior.

External music stop and reload cancel the native fanfare, finish its old wait
and discard its owned static Sources. Native script BGM stops retain their
separate behavior, including a still-active fanfare timer and audible tail.
Suspension cancels the interrupted fanfare before foreground recovery, so a
failed re-cue cannot revive an old wait. `Game:audioSession` resumes against
its own dataset, including the delayed retry when the device is still absent.

The **124-check** engine suite exercises cold static factory nil/errors,
successful later replay, SE player ownership, stop/reload cache disposal,
latched cancellation and the actual mobile Game interruption/retry path.
When a native cue replaces shared mod music, the previous shared source is
released before constructing the native carrier. A failed native carrier
cannot leave the previous mod playing. A bad shared mod definition retains
the existing shared song instead. The unchanged parent reproduces **12
failures in 124 checks** for the native replacement path. The twelve
complete paired no-output rows include every observed control state and all
source inventories. Existing real-sequencer BGM/fanfare comparisons still
pass with their previously documented waveform and shared-GB limitations.

A separate actual-import stage probe reads private ROMs and existing audio
images without modifying normal imports. The current importer regenerates
**14 FireRed and 18 Emerald fanfare rows**. All 32 native timer resolutions
agree with their ROM table values and imported SE player identities. The
existing Emerald cache has no fanfare metadata; fresh extraction produces
it correctly. Cached absence and fresh output are reported separately.
This metadata check does not establish actual-import playback or native
waveform parity.

## Actual-import playback follow-up

Four workers run the actual native/host importers, renderers, world adapters
and VMs over owned FireRed/Emerald ROMs and their existing imported audio
images. The native audio pack is produced by the unchanged reference's
production extractor in memory; the host uses its existing image and freshly
extracted native fanfare metadata. No normal cache is rewritten.

The **eight cases / 688 observed frames** cover native BGM fades, the real
80-frame level-up fanfare wait, a deferred default map cue and a BGM stop
during the fanfare. Complete portable BGM/fanfare state, script completion,
static-source inventories, active BGM gains relative to each backend's
baseline, and queue/produced/play counters agree. Each case renders audible
actual-import PCM. All **2,681,636 reference / 2,169,890 host scalar samples**
are retained separately. Distinct waveforms and rendered tail lengths are
not treated as equality. The cold admission follow-up below also removes
the earlier actual-import probe's reference-cache prewarming.

## Public music hook follow-up

The generic music service now receives the same admission as the reference's
native mod bridge: named shared mod music enters `music.select`,
`music.volume`, `music.started` and `music.stopped`; native M4A carriers
retain their separate native route. A shared selector cannot replace or
silence a native carrier. Shared overrides still support selection, nil
silencing and volume changes on their actual Sources.

Shared hook contexts carry the generic player's map/bike/surf state rather
than a native `SONG_*` identity. The engine world's location and time of day
are included when that actual engine context is present. Map cues use the
native selection/ownership path and defer while a native fanfare owns the
clock. They produce the shared bridge's `gen3` reason instead of a second
map-specific callback shape.

The shared audio service runs before the native timer/fade service, matching
the reference's order. Options reapply the previous shared level before the
new value, including the previous fractional level during a fade. A completed
fanfare observes the old shared volume before its stop/select/start events.
Native cry start, completion and explicit stop do not introduce additional
shared volume callbacks.

The **46 complete cases / 736 observed frames** cover both profiles, unchanged
and modifying wrappers, file failures, options during fades, source replacement,
intro/loop chaining, exact map cues, map changes during fanfares and native
world cry commands rendering real owned PCM. The engine suite passes **4,616
checks**. The complete unchanged parent `a29c4158` differs in all **46/46**
cases using the same current fixtures; every parent/reference worker exits
zero, and the reference observations agree with the corrected run.

An early location fixture accidentally obtained a read-only mod facade on
FireRed. Its failure is retained as superseded evidence. The final fixture
loads the actual engine class, supplies world data and restores the module
entry afterwards; no reference engine method is replaced. Separate rendered
BGM/fanfare and actual-import regressions retain their waveform limitations.

## Audio options and reentrant music hooks

Native and shared music now retain independent volume and mode state. The
native master becomes live before shared `music.volume` callbacks run, so a
world cue, fade or fanfare started inside a callback receives the new option.
`external_only` mutes actual native and shared music Sources without discarding
playback ownership; `game_only` disables system mixing and `both` enables it.
Platform calls are protected, deduplicated after success and retried after
an unavailable backend. No audio device is started by the tests.

Missing native options retain the reference's native defaults, while missing
shared options retain the generic player's existing trim and mode. These
defaults can issue two distinct system-mixing policy changes in one options
application; the contract preserves their order. Applying native-only options
does not overwrite the independent legacy player's trim. `Game:applyOptions`
binds its actual dataset, including newly registered mod audio before its
first cue, rather than relying on a previous music command's dataset.
Shared fade-ins set their independent trim to zero immediately; the existing
world-command regression catches an audible full-volume first frame.

The `native_bgm_options` contract compares **26 complete scenarios / 364
observed frames** across FireRed and Emerald, including mode transitions,
omitted options, early mod registration and reentrant native/shared/fanfare
actions. `tests/engine/gen3_audio_options.lua` adds **102 checks**, including
the real Game options path, cross-generation trim preservation and platform
API failure/recovery. The complete unchanged parent `fb48ae31` differs in
all **26/26** scenarios using the current fixtures; all four workers exit
zero. Complete callback contexts, results, controller state, Sources and
boolean platform policies are retained. This does not claim every audio
option or arbitrary mod callback combination is qualified.

## Cold cache admission and invalidated handles

The stream hardware fixture now returns LuaJIT userdata-shaped SoundData
with the headless sample store behind it. Both engines still execute their
unchanged production renderers. Only the hardware constructors are wrapped;
the CPU Source retains the complete backing PCM for observation. The fixture
restores both constructors when closed and requires the same LuaJIT runtime
as the engine and CI.

Owned and actual-import fanfare probes no longer call `bakeSong` to populate
the reference cache. Public native script dispatch must render cold PCM and
create an actual static Source from userdata. Assertions reject prewarmed
SoundData or a missing static constructor call. The **12 owned cases / 156
frames** and **eight imported cases / 688 frames** retain all source records
and distinct rendered PCM. BGM stream regressions still cover **18 cases /
1,534 frames**, including the documented two GB lookahead differences.

`tests/engine/gen3_audio_cold.lua` passes **51 checks**. It verifies sample
preservation, cold public fanfare/wait dispatch, same-session Source reuse,
new Sources after reload, cached static playback failure/recovery and SE
queries against a refusing handle. The real host Game interruption path
survives native streaming handles whose audio methods all raise, an unavailable
foreground replacement and a later retry using that Game's dataset. Old
handles cannot restart behind the replacement stream. These tests qualify
the existing production implementation; this follow-up changes QA, not
runtime behavior.

Cold SoundData/Source admission is not a claim of a cold ROM/sample-decoder
cache, real-device recovery or cross-engine full-session teardown parity.
The host interruption test and the paired native audio contracts have distinct
scopes. The existing native gain/PCM differences also remain recorded.

A separate owned audio-service teardown/re-entry probe compares native and
shared music, each with and without a fanfare, on both profiles. Portable
song/map/save state, static Sources, SE queries and VM completion agree.
It also observes every new audio tick and asserts that every old static and
queue Source stays stopped. Its complete hardware inventories retain a
backend difference: native cue replacement reuses one reference queue but
creates a second host queue. Both are stopped after teardown. This probe does
not establish equal allocation counts or full game/mod-session lifecycle parity.

## Production session entry invalidation

The broader initialized-session probe uncovered a real gap hidden by the old
fixture's explicit `Music.reload`: the host's actual launcher return stopped
Sources and detached mod listeners, but the asset invalidation used before
the next Game did not clear native map/saved music. The unchanged reference's
game and mounted-session teardown released both. All four host cases failed
the stricter entry assertion; all four reference cases passed. These failed
results are retained. The incomplete full feature matrix and feature/combined
regressions were deliberately cancelled as superseded, not accepted as passes.

Music now subscribes its existing native reload path to the actual asset
invalidation bus. This retires the native controller when launcher entry or
mod-loader invalidation changes the dataset; an ordinary playback stop still
retains its separate semantics. The expanded cold engine suite passes
**69/69 checks**, including the actual bus, saved/map state, a live VM wait
and every old static/streaming Source. Broad qualification of this correction
is pending.

`tools/enemy-action-contract-check/native-game-audio-session-smoke.lua` uses
the real reference `Game3:reset` and game/mounted-session orchestrator. On the
host it loads the production main chunk without calling `love.load`, assigns
its initialized Game upvalue and enters the real `Game:returnToLauncher`,
launcher teardown and launcher constructor. It then invokes the actual asset
entry stage before any fixture cleanup can conceal stale state. The same
public API-3 consumer loads through a fresh Loader. Each subsequent tick must
leave old Sources stopped, the old VM complete and old listeners detached,
while the fresh listener and fanfare wait work. Full raw inventories retain
backend queue-count/gain differences. This is initialized-session teardown and
loader re-entry coverage, not a complete ROM boot, GPU, device, hot-reload
screen or arbitrary full-mod/playthrough qualification. The workflow runs
both music variants on both profiles and retains their raw output.

## Native command compatibility revision

GBA command revision **20** separates these music and script-wait semantics
from revision 19. The party codec stays at revision **1**. The frozen parent
`4994a41c` serializer independently predicts the new native digest
`43fe7ea27b438e0e` by changing only `[native_gba_commands]19` to
`[native_gba_commands]20`; the current complete surface must equal that
derived string. Red, Gold, Diamond and Black keep `e33d251961f2a41d`.

The protocol suite passes **175 checks**, including both link-controller roles
refusing old native semantics and full mirrored synthetic battles. The native
party codec's **194,540 checks** also pass. This targeted compatibility check
does not replace the pending complete contract matrix and combined runtime.

## Work still required before a pull request

- Finish the corrected paired initialized-session teardown/re-entry matrix
  and its independent raw-observation audit.
- Broader actual-import coverage, the complete existing contract matrix and
  a qualified combined runtime.
- Complete broad regression and integration qualification before advancing
  the playable branch.

Tests start no game, GPU or audio device and write no normal saves/imports.
No ROM, generated recording or private import is committed. This checkpoint
does not establish arbitrary full-mod compatibility or a completed playthrough.

## Reproduction

From this checkout, with the pinned LuaJIT and a clean read-only reference:

```sh
nice -n 19 env LUA=/path/to/pinned/luajit bash scripts/test.sh --quick
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 . \
  --lua /path/to/pinned/luajit \
  --mode native_bgm_symbols --mode native_bgm_commands --mode native_bgm_policy \
  --mode native_fanfare_commands --mode native_bgm_devices \
  --mode native_bgm_hooks --mode native_bgm_options \
  --mode native_cry_commands --mode native_cry_lifecycle --mode native_cry_pcm \
  --report /path/to/bgm-development-report.json
```

Keep every raw worker and failed report. The canonical checker records the
complete observations; checkpoint qualification additionally performs an
independent recursive comparison that distinguishes JSON boolean types.

The owned native-stream probe emits the full raw source/PCM inventory:

```sh
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/native-bgm-stream-smoke.lua \
  . gen2 firered > /path/to/host-native-bgm-streams.log
```

Repeat with `emerald`. For the reference, run from its clean checkout,
invoke the tool by absolute path, pass this checkout's absolute path as
the first argument and change `gen2` to `gen1`. Compare the admitted
control/queue properties while preserving all backend-specific raw source
records and PCM; do not report whole raw waveform equality.

The same invocation pattern applies to
`tools/enemy-action-contract-check/native-fanfare-stream-smoke.lua`, which
retains the real fanfare renderers' complete outputs and source ownership.

The private actual-import metadata probe runs the production import stage
with the headless filesystem, then checks every generated timer against its
owned ROM table and the native fanfare resolver:

```sh
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/imported-native-fanfare-metadata.lua \
  /path/to/existing/import-root /path/to/owned-firered.gba /path/to/owned-emerald.gba
```

No normal imports are updated by this probe. Keep the missing-table discovery
and the fresh extraction results; they describe different input states.

The actual-import playback probe emits all state and PCM, using the same
backend invocation convention as the owned-stream tools:

```sh
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/imported-native-bgm-smoke.lua \
  . gen2 firered /path/to/existing/import-root /path/to/owned-firered.gba \
  > /path/to/imported-firered-host.log
```

Repeat for Emerald and the clean reference. Admission compares the documented
control/ownership/queue properties; retain the complete backend PCM outputs.

The owned audio-service teardown probe needs no ROM and retains the complete
old Source inventories, including the documented allocation-count difference:

```sh
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/native-audio-session-smoke.lua \
  . gen2 firered > /path/to/session-firered-host.log
```

Use the same reference/host invocation convention and repeat for Emerald.
Compare portable song/map/save state, VM completion and static Sources while
retaining the different native queue inventories. Every old Source must stay
stopped throughout re-entry. These are owned audio-service transitions, not
full game/mod-session lifecycle qualification.

For the independent protocol audit, use a clean frozen parent at `4994a41c`:

```sh
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/native-protocol-audit.lua \
  /path/to/frozen-parent/src/link/Fingerprint.lua
```
