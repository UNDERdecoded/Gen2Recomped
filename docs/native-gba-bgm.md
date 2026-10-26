# Native GBA music commands and fanfare waits

Imported FireRed/Emerald world scripts retain native background-music and
fanfare commands through the real world adapters and VMs. Named mod music
continues through the shared music service, including its public hooks.
This continues the cry and world-SE work in #289 and its prerequisites.

This changes native imported-script execution. API-3 `queueScript` retains
its separately documented [bounded portable vocabulary](portable-world-scripts.md).

## Commands and ownership

- `playbgm` keeps logical song identity separate from the physical Source.
  Only keep flag `1` or `true` saves an override; song identifiers `0` and
  `0xFFFF` stop BGM.
- `savebgm` records the saved music independently of current and map music;
  a silence identifier clears the saved value.
- `fadeoutbgm` and `fadeinbgm` use the native world adapters' fixed speed four,
  including their final-tick source/queue behavior. `fadenewbgm` dispatches
  immediate replacement in this admitted adapter path.
- `fadedefaultbgm` selects the current map default and preserves native
  saved/map ownership and deferred restoration while a fanfare is active.
- `playfanfare` resolves native variables and starts a nonblocking native
  fanfare; `waitfanfare` waits on its native clock and retains a latched
  completion callback.

The catalogue admits 305 `MUS_*` names, including aliases and reverse names.
A numeric native command can select an existing named shared mod override.
Emerald default selection re-reads live map identity, player position,
weather and story state. FireRed retains its own default map-song policy.

The audio service advances fanfare time independently of accelerated logic.
The reference also has a separate 361-poll script safety limit, which is
preserved: accelerated polling can reach that limit before a long audio
timer ends. Native imported timer metadata determines normal completion;
rendered PCM duration does not. Missing timer metadata retains the native
160-frame fallback. A present table that omits a requested cue retains the
native level-up fallback.

Fanfares occupy their declared SE player, stop the replaced fanfare and
that player's previous sound, and can retain an audible tail after their
script timer finishes. Repeated cues reuse same-session cached Sources.
Fanfare pause stops the native BGM producer and clears queued native PCM;
worker generation and pause-epoch checks reject stale packets after resume.
Shared mod music retains its own transport and ownership rules.

## Public mod hooks and options

Shared named music follows `music.select`, `music.volume`, `music.started`
and `music.stopped` with the reference's admission, order and callback
context. Native M4A carriers use their native route. Shared hook context
retains generic map/bike/surf state, including location/time when the actual
engine world provides them. File selection, silencing, volume overrides,
intro/loop chaining and map changes during fanfares are covered separately.

Native and shared music retain independent master/trim and mode state.
`Game:applyOptions` binds its own dataset and applies native options before
shared callbacks can start another world action. `external_only` mutes
Sources while retaining playback ownership; system-mixing changes are
protected, deduplicated after success and retried when unavailable.

## Recovery and session entry

An unavailable native queue factory preserves logical music state and can
recover on a later cue. A failed native replacement releases the former
shared Source; a bad shared definition retains its existing shared song.
Invalidated queue/static handles cannot crash the covered command/update
paths. Mobile interruption cancels an interrupted fanfare, and foreground
recovery retries against the actual Game's dataset.

An ordinary stop retains its playback semantics. The actual asset
invalidation bus used before the next game/mod dataset also invokes native
music reload, retiring old map/saved music, waits and Sources. This fixes a
production session-entry gap hidden by an earlier fixture's explicit reload.
The initialized-session probe uses actual reference Game3/mounted teardown
and the host's actual main/launcher return path, then loads the same public
API-3 consumer through a fresh Loader. Old Sources/listeners/VMs remain
retired during every observed fresh-session tick.

## Compatibility and qualification

Native GBA command revision **20** refuses prior music semantics before
native link-battle setup. Party codec revision remains **1**. The independent
frozen-parent serializer audit changes only revision 19 to 20: native digest
`43fe7ea27b438e0e`, with legacy `e33d251961f2a41d` retained.

The [source-bound QA receipt](qa/native-gba-bgm.json) identifies qualified
runtime commits/trees, complete matrix and regression results, independent
raw-observation audits, physical audio probes and retained negative controls.
Each runtime passes 268 workers / 178,264 complete paired observations.
The combined runtime passes 292/292 engine suites, SDK 3/3 and B30. The
isolated feature passes 174/183, retaining exactly the same 25 failure lines
across nine inherited suites as its fresh parent; SDK 3/3 and B30 pass too.
The [historical development notes](native-gba-bgm-development.md) preserve
earlier checkpoints and discoveries. Results are local; hosted validation is
reported separately in the PR.

## Reproduction and limits

Use the clean read-only Gen1 reference
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91` and LuaJIT
`a4c064539ea931274d407e1249b4bb575424a0f4`:

```sh
nice -n 19 env LUA=/path/to/pinned/luajit bash scripts/test.sh --quick
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 . \
  --lua /path/to/pinned/luajit --report /path/to/full-contract-report.json
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/native-protocol-audit.lua \
  /path/to/frozen-parent/src/link/Fingerprint.lua
```

The frozen fingerprint parent is
`4994a41ca09fe50e4f186260ed8f5b7b1f233f4d`. Owned stream, fanfare,
audio-service and initialized-game session probes live beside the checker.
Invoke each from the backend checkout with the absolute host checkout,
`gen1`/`gen2`, and `firered`/`emerald`. The initialized-game probe also takes
`native`/`shared`. Existing import playback additionally needs owned ROMs
and an existing import root; no normal import is rewritten.

Actual production renderers execute with CPU hardware doubles, including
cold userdata-shaped SoundData admission. No game boot, GPU, audio device,
normal save or full playthrough is started by these probes. Complete raw
PCM and backend inventories are retained separately. Native synthesizer
PCM/baseline gains, shared GB lookahead and native queue allocation counts
remain distinct; those are not whole-waveform or allocation parity results.

Older imports missing fanfare timer metadata need reimporting to receive
the new extractor output (14 FireRed and 18 Emerald entries). Complete
map/bike/surf transition coverage, other editions, actual device recovery,
full hot-reload screens, arbitrary complete mods and playthroughs remain
open qualification surfaces.
