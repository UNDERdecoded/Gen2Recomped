# Native GBA Poison presentation and native sound controls

This path extends native Substitute art and the existing battle queue.
Gen1 remains read-only at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

## Implemented native Poison path

Successful native poison status changes queue their status-animation command.
The actual battle queue executes the native shake, two palette cycles and six
edition-specific sounds. Presentation does not change HP, status, PP or battle
RNG. Hidden/protected actors and disabled animations follow native skip rules.
Mono/stereo uses the existing game sound option. Live sprite offsets and tint
reach the battle renderer through its normal presentation methods.

Native numbered sounds also resolve through cartridge songs when no named
role exists. Explicit panorama and mono controls preserve the original mix;
each control combination owns a separate cached source. Existing named-role,
native-name file/string overrides and disabled sounds retain their behavior.
Cache invalidation refreshes the native number lookup after a mod audio edit.

## Evidence

- Unchanged native sequencer/VM versus actual host queue: **144 paired Poison
  inputs / 1,848 ticks / 144 actual sound controls**, all equal. Inputs cover
  all six single/double positions, animation options, stereo/mono and native
  hidden/Substitute skips. Every actor's captured display state, HP, status,
  protection, and RNG count participates in comparison.
- A common owned PCM carrier runs through the native mixer and host pan
  processor: **56 paired cases**, all samples and format metadata equal.
  The initially mismatched 32768-Hz carrier fixture is retained; the qualified
  fixture uses the native default 44100-Hz input, without rewriting results.
- Actual host M4A sequencing, source creation and dispatch: **165,455 checks**,
  including source separation/reuse, all PCM samples, mono, retained defaults,
  file/string overrides, silence and legacy forwarding. Existing mod audio:
  **116/116**. Native status presentation unit checks: **3,074/3,074**.
- The broader complete command regression retains **11,520 multi-hit rows**,
  **1,920 Mirror Move rows** and **360 Substitute-controller cases**. The 192
  poison-command differences are resolved. The complete comparison remains
  **failed at that checkpoint** on **1,152 animation observations**, all
  Substitute fade or Focus Band. No observation, event, RNG field or animation was removed.

Audio controls are measured at the output source. The Source carrier uses
owned cached PCM; the host carrier runs through its actual M4A sequencer.
The separate mixer comparison covers the same input samples on both engines.
This does not establish whole-synthesizer waveform equality, all public audio
event parity, or final scene pixel equality. CPU hardware doubles launch no
game, audio device or GPU preview and modify no normal cache/save.

## Combined qualification

Actual Substitute-fade and Focus Band playback are now implemented. The final
32-worker / 14,816-observation matrix passes with all captured fields retained.
The original Poison runtime completes 161/170 engine suites, SDK 3/3 and B30,
with exactly the same 25 inherited FAIL lines as fresh #258. Native revision
17, real linked roles, received-history and public imported-submission evidence
are recorded in `native-gen3-mirror-move.md`. Earlier failures remain retained.

Raw successes, failed/superseded inputs and complete observations remain in
`tmp/battle-effect-qa/`. Reproduce the focused contracts with:

```sh
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --mode battle_effect_presentation --mode native_sound_pan \
  --report /path/to/new-report.json
```
