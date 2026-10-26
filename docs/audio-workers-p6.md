# PCM and audio workers (P6)

`src.core.Performance.audioWorkerOptimization` defaults to `true`. Set it to
`false` to disable this task independently of the other performance changes.
The live chip-music worker receives flag changes; existing unused prewarm
entries are discarded. New DS players use the legacy four-buffer transport
when disabled, and active worker players materialize their queued state.

## PCM writes

`AudioPcm` returns ordinary 16-bit `SoundData`. It acquires a signed PCM pointer
once per buffer, with `setSample` as the fallback. FFI writes require an active
JIT: interpreted FFI was slower on the tested LÖVE 11 build.

The installed `SoundData.setSample` implementation determines conversion:
the C method takes and multiplies floats, while LÖVE's LuaJIT wrapper multiplies
numbers directly. The independently written converter follows that distinction.
See the official [C implementation](https://github.com/love2d/love/blob/11.5/src/modules/sound/SoundData.cpp)
and [LuaJIT wrapper](https://github.com/love2d/love/blob/11.5/src/modules/sound/wrap_SoundData.lua).
Boundary, mono/stereo and array tests compare complete output bytes.

## Effects and cries

`Sound.update`, serviced by `Music.update`, submits at most one speculative job
per frame, with two jobs in flight. The existing synthesis thread returns PCM
on `chipaudio_fx`; only the main thread creates Sources. Music buffers and effect
jobs share the worker fairly. Jobs retain their own stereo/channel mix and
restore the live music mix after rendering.

Completed Sources enter the existing private `Sound.lua` cache without playing,
ducking music or emitting `sound.played`. Unused speculative audio is limited to
16 MiB. First use rechecks the exact definition, derived cry resolution, audio
input and mix. Changed entries are discarded. Used entries retain the existing
cache behavior. Invalidation, cancellation and audio-session suspension reject
late results. Failed speculative jobs do not mark a sound as permanently bad.
Custom/metatable/cyclic definitions use the existing source constructors.

A cold cue, unavailable worker or disabled prewarm uses the original synchronous
constructor and logs the fallback once per synthesis kind. This keeps the
existing immediate Source return, playback and callback timing.

## DS transport and its compatibility boundary

Eligible SSEQ players share `chip_worker` with the other synthesizers. The source
has 16 buffers, each with up to 8192 stereo frames at 32768 Hz. Worker output is
bounded to two blocks per player; at most 16 worker players and four archive
registrations are retained. Inactive jobs expire after five seconds. One-shots
retain the legacy 512-frame end padding instead of adding an 8192-frame tail.

Worker samples use signed 16-bit ByteData and private pointers. PCM8, PCM16 and
ADPCM retain their decoded values; PSG square/noise amplitudes have an explicit
scale. Mixing proceeds by voice between sequencer tick boundaries, preserving
phase addition, event-before-sample ordering and voice accumulation order.
Normal main-thread updates transfer completed buffers and state snapshots.

Sequencer state belongs to the worker while this path is active. Ordinary reads
or writes of `tracks`, `voices`, `samples`, `variables`, `tempo`, `tickPhase`,
`master`, `ended`, `arc`, `seq`, `bytes` or `start` retire the worker, restore the
legacy metatable and materialize the last **queued** snapshot. PCM arrays are
then ordinary Lua tables again. Direct sequencer-method overrides also select
the legacy path. Already queued audio remains queued; no hidden replay occurs.
The normal volume, pitch, looping, pause, play, stop and variable methods remain.

This is an explicit compatibility boundary: raw table enumeration (`pairs`,
`rawget`) and inspection of the temporary transport metatable bypass ordinary
field access. Consumers that depend on those operations should disable P6 before
constructing a DS player. Snapshots describe queued synthesis, potentially ahead
of audible output. A full 16-block queue represents four seconds of lookahead;
control changes affect future synthesis. A paused player whose worker lease
expires resumes through the logged legacy fallback.

The conservative instruction walker keeps sequences using the main RNG or shared
variables on the legacy transport. Argument bytes are parsed by opcode shape,
not searched as raw opcode values. Worker errors, expired jobs and disabling the
flag also select the logged legacy renderer.

## Reproduction and scope

Run `python3 tools/check_audio_profile.py --love /absolute/path/to/love
--report .local/qa/audio-workers/profile.json` (one shell line). The checker uses
`qa_storage`, an isolated identity, complete source hashes and owned compact
GB/M4A/SDAT programs. It tests actual native SoundData and threads. Source hardware
is a double, with no output device or player save/profile involved.

The DS comparison checks every PCM byte across all three encodings, PSG voices,
looping and one-shot tails, exact phase and live voice fields, independent players,
variable methods and compatibility fallbacks. FrameProfile uses 120 warmup and
120 measured frames per case: PCM writes, cold/prewarmed first cue and legacy/worker
DS updates under 512-frame-per-frame simulated consumption. These are scoped CPU
measurements, not a game FPS, audio-device recovery or complete playthrough claim.
Mobile/handheld measurements are not available.

Measured on desktop macOS ARM64, LÖVE 12 / Metal with JIT enabled, using the
owned fixture and Source double described above:

| Main-thread section | Legacy/cold | P6 |
| --- | ---: | ---: |
| 8192 stereo PCM frames | 0.148 ms | 0.065 ms |
| First effect cue | 0.235 ms | 0.019 ms after prewarm |
| DS update, simulated 512 frames consumed per frame | 0.089 ms | 0.010 ms |

The [source-bound validation record](qa/audio-workers-p6.json) retains the native
report and acceptance summary. The native checker passes 358 scoped checks. These values are source-bound to
its local report; rerun the checker for another host/build. They exclude actual
Source-device cost. Interpreted LÖVE 11 keeps `setSample`; a native comparison
must not be presented as a JIT FFI speedup on that build.
