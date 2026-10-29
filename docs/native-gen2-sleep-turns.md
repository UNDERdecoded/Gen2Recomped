# Native GSC sleep lifetime and turn admission

The shared controller previously lost the waking turn in Gen2, blocked
Snore/Sleep Talk during sleep, processed flinch before sleep, and applied
Gen1's pre-recharge status checks. Its default sleep roll included a one-turn
counter, and the party Pokemon did not receive the remaining counter.

`Gen2Sleep` now uses the actual native battler, party Pokemon and battle RNG:

- A waking Pokemon acts that turn; Nightmare and the completed counter clear.
- Sleeping Snore/Sleep Talk reaches the existing move-effect owner. Each
  move's own failure when awake still runs after waking.
- Sleep precedes flinch; mandatory recharge precedes both and does not tick
  sleep. CantMove cancels Bide/rampage/charge/Rollout/Fury Cutter state and
  the selected Fly/Dig flags. The existing picture owner follows those flags.
- Default SleepTarget draws a full byte, masks and rejects zero/seven before
  incrementing: counters 2–7. The Tower flag selects the two-bit mask. An
  explicitly configured sleep range and custom status handler remain owned
  by their existing records.
- Each tick updates the existing party sleep counter, so reconstruction
  reads the remaining count. Rest initializes three, allowing two blocked
  attempts before waking. No second turn or presentation clock is added.
- Native held cures and medicine clear both party and active counters at the
  existing cure site, including field medicine and revives.

Source: `pret/pokecrystal` commit
`5c877ef55197039c9676e8e3eec6d254b1c40fe8`,
`engine/battle/effect_commands.asm`: CheckTurn 140–194, enemy twin 370–422,
CantMove 333–356, SleepTarget 3571–3625, Heal/Rest 6032–6080.
The frozen Gen1 GSC `CrystalRules.canAct` and sleep record provide the second
engine reference. No assembly or ROM-derived program is included here.

Tests use actual StatusRegistry, Status, native action/move dispatch and
picture ownership, both sides in Gold/Silver/Crystal. Every possible input
byte and both masks are checked, including rejected draws. They also cover
explicit status/range overrides, Rest, awake failure, charge cleanup,
party reconstruction and shared Gen1/GBA regressions. The fork has a separate semantic checkpoint test; that newer checkpoint
fixture/interface is absent from this upstream baseline and is not copied.
The older upstream enemy-PP policy and Gen1/GBA wake/flinch behavior retain
their native baseline; the adapted assertions explicitly reflect those owners.

This fixes sleep lifetime/admission. Sleep Talk's older generic choice pool,
exact called-move history, Snore's remaining secondary-effect details and
other GSC status/turn-rule differences remain separate work. A conditional
Tower flag test does not establish complete native Battle Tower gameplay.
CPU checks establish neither visible/audible output nor whole unchanged-VASC,
Windows or release qualification. Mods, protected Gen1/player installations,
original ROMs and player saves are unchanged.

Original contributions by Roxas2712; see `LICENSE-ROXAS2712.md`. Existing
source rights and notices remain effective.
