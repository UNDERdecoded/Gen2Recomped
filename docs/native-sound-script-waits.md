# Native GBA world-script sound waits

Native `waitse` previously lowered to no operation, so a script could change
variables, release field objects or continue dialogue while its sound was
still playing. It now yields through the actual script runner until the native
SE query is complete, with both clocks and the latched callback used by the
unchanged reference.

The script polls current native players rather than a captured source. A sound
replaced on the same player or a remaining independent player therefore keeps
the wait active. File overrides remain separate. Emerald's aggregate query
excludes player three; FireRed includes it. Silence and override-only cases
continue immediately.

The callback has a **180-tick real-time audio budget**, serviced after logic in
the existing `Game:update` 60 Hz audio loop. The script also retains its native
**181-poll logic fallback**. At accelerated logic speeds those are different
clocks. Once the audio callback observes silence, completion stays latched even
if another sound starts before the next script poll. Consecutive waits each
start their own clocks.

This extends Gen2Recomped #277. Native battle revision **18**, party codec **1**
and their existing fingerprints remain unchanged: this is world-script
scheduling, with no new portable command or advertised public capability.
The native command hook still wraps the yielding command, source/strictness
metadata survives and the script-ended event follows the post-wait write once.

## Validation

- **36 paired actual-controller cases** across FireRed and Emerald, including
  normal/accelerated/logic-only clocks, callback latching, consecutive waits,
  replacement, stops, independent players, special-player policy and overrides.
  The reference's native VM and the host's native lowering/ScriptRunner execute
  the same owned operation sequence; no engine function is replaced.
- **6,306 actual-host checks**, including real Game.update, FixedStep and
  StateStack at 1X/2X/10X. Actual field freeze/release commands retain object and
  input locks while waiting, then release them; the owning state keeps updating.
- Removing only the real-time `Sound.update` call from Game.update reproduces
  two exact failures: each profile completes at tick 181 instead of 180. The
  local negative variant and its report are retained, not integrated.
- With existing actual audio imports, native
  `lockall; playse; waitse; setvar; releaseall; end` waits **25 ticks in FireRed**
  and **34 in Emerald**, derived from the actual 17,641/24,256-sample PCM buffers
  at 44,100 Hz. Every one of the 100 recorded frames per profile keeps objects
  locked before the write and releases them afterward. Complete feature and
  combined outputs agree, including JSON types. The unchanged #277 parent
  fails with tick 0 instead of tick 25.
- Existing actual imported player-ownership tests still synthesize ten native
  sources per runtime. The public Mirror Move smoke still executes 24 scenarios,
  48 turns and 120 move-used events per runtime, retaining complete outputs.

The combined runtime passes **284/284 engine suites**, SDK **3/3** and B30,
with an empty anchored FAIL-line Counter against the accepted 283/283 parent.
The feature passes **166/175 engine suites**, SDK **3/3** and B30; its exact
anchored FAIL-line Counter matches a fresh #277 parent (**165/174**): the same
**25 lines in nine inherited failing suites**, all retained.

Each frozen runtime passes **228 zero-exit workers / 175,616 complete paired
observations**. The independent audit checks every expected backend, profile,
API and mode key, immutable fixture hashes, clean source commits and every
decoded value. JSON booleans remain distinct from numeric zero and one.
No timeout or native-VM diagnostic remains; complete state, events, held reads,
RNG, PP and animation fields remain included.

The original frozen negative contract has **7 differences in 12 paired cases**,
with four zero-exit workers and identical active voices/queries at every frame.
The original observations, source-only clock oracle, first invalid StateStack
constructor invocation and all later reports remain retained. The
[negative receipt](qa/native-sound-script-waits-negative.json),
[native clock oracle](qa/native-sound-script-wait-clocks.json) and current
[source-bound qualification receipt](qa/native-sound-script-waits.json) identify
the exact commits, inputs and report hashes.

## Reproduction and scope

Use LuaJIT `a4c064539ea931274d407e1249b4bb575424a0f4` and a clean read-only
reference at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`:

```sh
nice -n 19 env LUA=/path/to/pinned/luajit bash scripts/test.sh --quick
nice -n 19 /path/to/pinned/luajit tests/engine/gen3_sound_script_waits.lua
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --report /path/to/new-all-contracts-report.json
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/imported-native-world-sound-wait-smoke.lua \
  /path/to/this/checkout /path/to/existing/import-cache-root
```

The optional imported smoke requires existing `firered/` and `emerald/` imports.
It reads their generated audio metadata and M4A blobs, mounts them only in the
test's in-memory filesystem and feeds actual decoded PCM to an owned speaker.
Speaker completion follows the buffer duration. No audio device, GPU, normal
cache/save write or redistributed ROM/audio asset is involved.

Run the source-only clock oracle from the pinned reference checkout with
`tools/enemy-action-contract-check/native-sound-wait-clock-oracle.lua` addressed
in this checkout and this checkout's path as its argument. It preserves every
observed frame, including callback latching with a replacement still playing.

These are native world-controller/game-update and owned-hardware contracts.
They do not establish every public sound-event timing, synthesizer waveform
parity, complete mobile audio-session parity, rendered scene parity, unregistered
profiles, arbitrary whole-mod compatibility or a full playthrough.
