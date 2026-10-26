# Native GBA Mirror Move and battle presentation

This change builds on Gen2Recomped #258. One unchanged API-3 move registration
using `MIRROR_MOVE_EFFECT` now executes native GBA received-move semantics.
FireRed and Emerald are the qualified native profiles. The reference remains
read-only at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

## Gameplay contract

Mirror Move reads the user's received-move history at its native command,
instead of the opponent's last selected action. Move-end records a successful,
mirror-eligible chosen caller after held-item commands. Misses, protection,
immunities, self-targets and KOs do not overwrite earlier valid history. Native
and registered callers share targeting, child events and parent PP ownership.
Mirror Move has no caller animation of its own. Public registrations use the
existing shared fields; neither raw `flags` nor writable `native` envelopes
are added to the API.

The history participates in native linked-state signatures. Command revision
17 also covers the added presentation commands and sound callbacks, rejecting
older native peers before battle setup. Party codec revision remains 1. An
independent frozen-parent serializer audit changes only revision 16 -> 17:
GBA digest `351a5becf7f236a0`; legacy digest `e33d251961f2a41d` is unchanged.

## Native presentation prerequisites

The expanded complete command comparison exposed existing missing Substitute,
Focus Band and Poison animation paths. These are implemented in the actual
battle queue rather than omitted from observation:

- Each called move owns its Substitute lowering/restoration group. Multi-hit
  calls restore only after the native last-hit command. Sparse queue rows and
  holes are preserved. Logical protection is independent of the displayed doll.
- The shared swap controller slides five pixels per update, exchanges offscreen
  on its own update and returns. Broken Substitute runs the native alpha fade,
  white palette ramp, copied-background lifetime, delays and exchange.
- The importer locates and validates both native doll sheets and palette before
  publishing versioned art metadata. Native OAM positions, all double-battle
  slots and live controller offsets reach the existing renderer. Existing
  caches need a reimport for this art; missing metadata retains the prior path.
- Focus Band runs both red fades, native motion, signed fixed-point return and
  edition-specific sound. Poison runs its shake, palette cycles and six sounds.
  Animation options, hidden/protected actors and temporarily lowered dolls
  follow their separate native rules.
- Numbered native sounds resolve without a named role. Explicit panorama/mono
  settings preserve the original cached mix and isolate source variants.
  Existing named roles, file/string overrides, silence and cache invalidation
  retain their contracts.

## Validation

The focused frozen comparison at `74602df7` executes **32 workers / 14,816
paired observations**, all equal, with every worker exiting zero, no timeout
and no native VM diagnostic. It retains all captured events, held reads, RNG,
PP, damage, actor/display state and animation commands. The combined fork at
`01315149` repeats that comparison successfully and passes the same actual
public-submission smoke test.

The matrix includes 11,520 multi-hit observations, 2,208 native/registered/
Metronome-to-registered Mirror observations, 360 swap-controller inputs,
384 Poison/Focus Band inputs, 288 fade inputs and 56 common-PCM inputs.
Controller observation includes every tick: 5,240 swap ticks, 11,112
Poison/Focus Band ticks and 23,488 fade ticks. Host checks include 994 received-
history, 13,778 effect-controller, 104,512 fade/producer, 70 art/draw and 165,455
actual M4A sound checks. Eight structural importer tests and actionlint pass.

Actual host/guest/spectator menus pass 108 checks over two turns per profile,
including events, PP, history and paired completed hashes/state components.
Existing local FireRed/Emerald imports pass 24 scenarios / 48 actual public
fight/move-submitted turns / 120 move-used events, with native or registered
Mirror, Tackle/Scratch/Growl, Choice Band and Shell Bell.

The original 80-sequence negative control differs on #258 in 68 observations.
The same existing-import helper fails on #258 at the received-history
assertion. Earlier invalid registrations, incomplete coordinates, controller
errors and all differing complete animation reports remain retained privately.
The checker rejects caught native VM task errors and wait caps even when its
process exits zero, and fingerprints the shared sound fixture.

The runtime at `f9016f1c` completes 163/172 engine suites, SDK 3/3 and B30.
Its exact anchored FAIL-line Counter equals fresh #258 (157/166): the same
25 lines in nine inherited suites, with no additions or removals. The later
history/CI commits change tests and workflow only; their added host suite
passes 994 checks. The combined fork completes **282/282** engine suites, SDK **3/3** and B30;
fresh stable baseline completes **275/275**, SDK **3/3** and B30. Their exact
anchored FAIL-line Counters are both empty. Each runtime also qualifies all
**220 workers / 175,540 paired observations** across every existing enemy-action
mode. Two original combined Assist workers terminated at 60 seconds. Those
failed reports remain retained; eight fresh workers with a bounded 180-second
budget complete in at most 36.2911 seconds and retain every earlier completed
observation unchanged. The source-bound evidence is in
`qa/native-gen3-mirror-move.json`.

## Scope and reproduction

CPU hardware doubles run unchanged native functions and the actual host queue,
M4A sequencer and drawing methods. Four actual decoded doll sheets match the
read-only reference imports in every RGBA channel: 16,384 pixels, zero changes.
No ROM, cartridge image or private generated pack is committed. Tests write no
normal cache/save and launch no game, audio device or GPU preview.

This evidence does not establish final scene pixels, whole-synthesizer waveform
identity, all public audio-event timing, arbitrary full-mod compatibility or a
complete playthrough. Native player replacement across cached pan/mono/sound
variants is reproduced separately in 16/20 lifecycle cases and remains a
follow-up; these controls do not claim that player lifecycle is fixed.
Ruby/Sapphire are unregistered in this feature stack;
their separate support prerequisites require integration before qualification.

```sh
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --mode substitute_fade --mode battle_effect_presentation \
  --mode native_sound_pan --mode substitute_multi_hit \
  --mode substitute_presentation --mode mirror_move \
  --mode mirror_move_content --mode mirror_move_chained \
  --report /path/to/new-report.json
nice -n 19 /path/to/pinned/luajit \
  tools/enemy-action-contract-check/imported-mirror-smoke.lua \
  /path/to/existing/Gen2Recomp-cache
```

Component contracts and their earlier failure evidence are documented in
`native-gen3-substitute-presentation.md`, `native-gen3-substitute-art.md`,
`native-gen3-battle-effect-presentation.md`, `native-gen3-focus-band-presentation.md`,
`native-gen3-substitute-fade.md`, `native-gen3-mirror-move-contracts.md` and
`native-gen3-mirror-history-gates.md`.
