# Native M4A sound-player ownership

Starting a native GBA sound must replace the preceding sound on its imported
M4A player. Previously Gen2Recomped cached by role and pan/mono variant, so
different IDs or controls could leave several effects playing on the same
player. Gen1Recomp's unchanged native `Audio.playSe` stops that player's
previous source before preparing its replacement.

`Sound.playId`, `Sound.playSe`, named native roles and native effect names now
share player ownership. Other players retain their sources. If a cached PCM
variant is still owned by another player, the new player receives a separate
cached voice. Volume changes, invalidation and device suspension reach those
voices through the existing cache lifecycle. A failed replacement releases the
preceding native source before source construction, matching the reference's
ordering. Suspended sessions cannot create or restart sources.

Native stop-by-ID reaches every player with that ID; stop-all releases every
native voice. Explicit-ID queries include the special player three. Emerald's
regular aggregate query excludes player three, following its native policy;
FireRed's aggregate query includes it. File/string and disabled overrides keep
their separate override behavior and do not cut or impersonate a native player.
Legacy and NitroAudio dispatch retain their existing paths.

## Compatibility

Native battle revision **18** prevents admission of peers using revision 17
semantics. Actual host/guest compatibility checks stop before battle setup.
Party codec revision remains **1**. An independently loaded frozen-parent
serializer, changing only the revision token, produces native digest
`c82a14f754706103`; the legacy digest remains `e33d251961f2a41d` for Red, Gold,
Diamond and Black.

This extends [the Mirror Move and controller foundation](native-gen3-mirror-move.md)
in Gen2Recomped #270. That foundation's historical revision-17 QA receipt is
preserved. The current source-bound receipt is
[`qa/native-sound-player-lifecycle.json`](qa/native-sound-player-lifecycle.json).

## Validation

The original 20 paired source/host cases reproduced **16 differences** with
four zero-exit workers. The current owned controller contract has **40 paired
cases**, covering native/shared/named entrypoints, pan/mono variants, independent
players, same-ID voices, replacement after cloning, native stop/query rules,
special-player policy, and file/string/disabled overrides. Every recorded
command trace, active voice and query participates in direct comparison.

Actual-host regression passes **110 checks**, including every current
controller case, all cached voice volumes, name invalidation/query/stop,
suspend/resume, source-build failure, legacy overlap and bilateral revision-17
rejection. The protocol suite passes **154 checks**.

The combined fork passes **283/283 engine suites**, SDK **3/3** and B30, with
an empty anchored `^FAIL ` Counter, matching the accepted 282/282 baseline.
The feature passes **165/174 engine suites**, SDK **3/3** and B30. Against a
fresh #270 parent (**164/173**), its anchored FAIL-line Counter is identical:
the same **25 lines in nine inherited failing suites**. Neither the baseline
nor candidate failures are hidden.

Both frozen runtimes pass **224 workers / 175,580 complete paired observations**,
including all 40 new lifecycle cases. An independent audit checks every expected
backend/profile/API/mode key and re-compares complete decoded observations.
JSON booleans remain distinct from numeric zero and one.
All workers exit zero without timeout or native-VM diagnostics. Full state,
events, item reads, RNG, PP and animation metadata remain in the comparisons.

Existing FireRed/Emerald imports also exercise the unchanged public Mirror Move
menu/queue path: **24 scenarios / 48 turns / 120 events** per runtime. A separate
read-only actual-audio smoke test synthesizes **10 cartridge sources**, checking
replacement on player one, independence of players two and three, a mono
variant and native stops. Its parent negative control fails at the first
same-player replacement. Sixteen imported player/header records independently
match their actual ROM entries.

The controller speaker is owned hardware; no reference engine function is
replaced. Cached source objects remain in its inventory after stopping, so
later reuse stays observable. The actual-audio smoke mounts existing imported
bytes only in the test's in-memory filesystem. No ROM, audio asset, normal save
or normal cache is written or included. No game, GPU or audio device is launched.

The raw negative controls, first incomplete-inventory fixture, missing-file
invocation and superseded floating-point assertion remain retained locally.
The corrected volume assertion measures both voices within `1e-12`; no
controller observations are discarded or normalized. Report paths and hashes
are recorded in the receipt.

These contracts qualify FireRed and Emerald native player ownership. They do
not establish full synthesizer waveform parity, every public sound-event's
timing, GPU scene parity, unregistered Ruby/Sapphire/LeafGreen profiles, arbitrary
whole-mod compatibility or a full playthrough.

## Reproduction

Use LuaJIT at `a4c064539ea931274d407e1249b4bb575424a0f4` and a clean read-only
Gen1Recomp checkout at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`:

```sh
nice -n 19 env LUA=/path/to/pinned/luajit bash scripts/test.sh --quick
nice -n 19 /path/to/pinned/luajit tests/engine/gen3_sound_player_lifecycle.lua
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --report /path/to/new-all-contracts-report.json
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/imported-native-sound-smoke.lua \
  /path/to/existing/import-cache-root
```

The import cache must contain `firered/` and `emerald/` directories with their
already generated `data/generated/audio.lua` and M4A blobs. No ROM is required
for this smoke, and CI's owned fixtures do not depend on private imports.
