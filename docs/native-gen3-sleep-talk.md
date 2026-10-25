# Native GBA Sleep Talk and authored move calls

The shared core previously cancelled Sleep Talk at the ordinary sleep check.
Its legacy effect also selected forbidden calls, reused the caller's target
and remembered the resulting move instead of the selected caller.

Install GBA sleep and Sleep Talk adapters per dataset before mods capture
builtin handlers. Sleeping move numbers 214/173 can proceed, native wake lets
an ordinary move act, Early Bird decrements twice, and Uproar respects
Soundproof across all active slots. Keep the existing fork's party-side
remaining sleep counter synchronized. Other generations retain their current
status behavior and shared builtin statics are unchanged.

Sleep Talk reads the current first four slots, including zero-PP choices.
Exclude the native move-number blacklist, two-turn scripts, Disable and active
Encore restrictions. Fixed-number sleep admission remains native: a custom
move with effect 97 does not automatically become move 214. Named authored
moves need no imported numeric index. Dispatch the resulting move as called,
retarget user/foe/spread calls and use controller slot order for all-other-
battlers attacks. Only the caller spends PP. Native bookkeeping remembers the
caller; failed calls preserve the previous move and skip the move-end script
while retaining the separate after-action item sweep.

Stacks on #226 and reuses the existing [#121 effect adapter](https://github.com/UNDERdecoded/Gen2Recomped/pull/121).
The adapter was absent from this isolated native-command stack and is already
in the combined branch. Reuse its production implementation unchanged; adapt
its harness to this stack's available modes and reuse the current Follow Me/
Helping Hand assertions. A separate clean #226+#121 prerequisite is tested.
The abandoned narrow adapter is superseded by #121 in the final tree.

## Accepted evidence

Feature runtime `cb6ddfadc2d29b878efcb0eb4f76869dc7b8c16a` and combined
runtime `4941d8d6c753925ab47180aaa80bf37b665ff7b6` are clean, tested commits.
Later commits document acceptance/publication.

- **1,068 focused checks** pass: 846 command/public-authored-content, 162
  effect/status/composition/failed-call/legacy and 60 real link/compatibility.
  The 154-check native protocol suite and the reused adapter's 860 host checks
  also pass.
- **116 workers / 77,668 paired observations** agree with unchanged read-only
  Gen1 `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The new modes add **648
  command rows and five public authored-content rows per FireRed/Emerald
  profile**. Command cases cover singles/doubles/all actor slots, choices,
  wake/Early Bird/Uproar/Soundproof, exclusions, edited forbidden metadata,
  current slots, zero PP, Disable/Encore, called execution, multi-hit/Triple
  Kick/Snore/Recover/Rage and spread calls. These are controlled native-shaped
  inputs rather than cartridge copies.
- The identical API-3 authored entry registers a named move without an index
  and its own effect through both public loaders. Ordinary, zero-PP, awake,
  primary/stat-change and patched-Fly cases execute the actual registered
  handlers. The source fixture mounts the loader's merged authored row/name
  and binds its actual merged registries; it does not recreate the handler or
  formula. Mounts are fixture-owned and restored in memory, with no Gen1 file
  changes. Hook/event failures must also leave both loaders' error lists empty.
- Every bounded RNG call/value, selected public move/hit event and all recorded
  battler HP/PP/status/active sleep/last-move/stage/Substitute/Rage observations
  remain in those comparisons. No failed rows or RNG draws are filtered out.
- Full feature: **130/139 engine suites**, SDK **3/3**, B30. The exact Counter
  of **25 inherited FAIL lines across nine suites** equals clean prerequisite
  `63bf2a9b9b856027c27c65ae1031febbb9e5d7e5` (**127/136**). Its full command's
  nonzero exit remains retained. Independent baseline repairs are in the
  combined runtime: **249/249 engine suites**, SDK **3/3**, B30, the same full
  comparison and imported tests pass there.
- Unchanged prerequisite fails **108 assertions** and all **648/648** complete
  FireRed command rows differ. Its authored-content mode fails **eight
  assertions**, with **4/5** rows differing. The same final fixtures are used.
- Two real link roles complete four turns: sleeping Sleep Talk, blocked
  ordinary move, awake Sleep Talk failure and independently selected ordinary
  move. Every paired completed hash/component, sleep state and learned PP
  agrees. Command revision **9** rejects revision 8 before party exchange;
  party codec stays **1**. Raw fixture `b9ec4e8a94f4ba6e` becomes
  `f1bec52ffc687ea3`, independently audited with the unchanged #226 hasher and
  only the explicit revision token changed. Other-generation goldens stay.
- **Twelve CPU-only scenarios with actual local FireRed/Emerald imports** pass
  public move/menu submission and completed turns: three calls followed by an
  ordinary move on waking, zero-PP children, empty/forbidden pools, Early Bird
  wake and awake failure. Extracted attack metadata stays intact. Native
  Sleep Talk's DEPENDS target is observed rather than assuming a self target;
  assertions run outside callbacks and loader errors are checked explicitly.
  No ROM/cache/save assets are distributed and no normal SAVE is issued.
- Scoped StyLua, actionlint and whitespace checks pass.

ROM-free reproduction with maintained LuaJIT
`a4c064539ea931274d407e1249b4bb575424a0f4`:

```sh
nice -n 19 "$LUA" tests/engine/gen3_sleep_talk.lua
nice -n 19 "$LUA" tests/engine/gen3_sleep_talk_composition.lua
nice -n 19 "$LUA" tests/engine/gen3_sleep_talk_link.lua
nice -n 19 env LUA="$LUA" bash scripts/test.sh --quick
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 "$PWD" --lua "$LUA" \
  --report /tmp/sleep-talk-contracts.json
```

Optional imported-data check (root contains `firered/data/generated` and
`emerald/data/generated`):

```sh
nice -n 19 "$LUA" tools/enemy-action-contract-check/imported-sleep-talk-smoke.lua \
  /path/to/local/Gen2Recomp
```

Feature evidence is in `tmp/sleep-talk-qa/accepted-evidence.json`,
`full-final-accepted.log`, `contracts-final-accepted.json` and
`imported-final-accepted.log`. Combined evidence uses
`tmp/sleep-talk-accepted-evidence.json`, `tmp/sleep-talk-full-final-accepted.log`,
`tmp/sleep-talk-contracts-final-accepted.json` and
`tmp/sleep-talk-imported-final-accepted.log`. Prerequisite evidence is retained
in the clean baseline worktree's `tmp/sleep-talk-baseline-qa/`.
Initial fixture errors, unmatched spread order, missing prerequisite probes,
the invalid unmerged integration run and all negative reports remain retained.

## Remaining boundaries

An extra **complete `held_item.trigger` probe still differs**. Raw source
`tmp/sleep-talk-qa/phase-gen1.log` and final host `phase-gen2-fixed.log` retain
all observed fields/reads. Empty source items carry numeric zero while the
host omits that field. A valid called attack has missing/extra check/damage/
flinch reads (10 source reads, 11 host reads). Failed awake/empty calls now have
two reads on each engine, and blocked ordinary actions have four, but the
complete payloads still differ. These are unresolved findings, not passing
held-item-trace evidence; the accepted matrix above covers its stated scope.

Complete held-item/choice-item and attack-canceller orchestration (including
Truant, freeze and recharge), arbitrary child-controller/interactive timing,
Ruby/Sapphire scheduling, full catalogs, global RNG/selection, graphics and
full playthrough parity remain separate work. Host builtin capture/delegation
and party-counter preservation are scoped host checks. The native Gen1 GBA
catalog still does not expose those builtin records for capture. The older
general API-3 checker's historical Gen1 pin is not new evidence against the
unchanged reference used here. No Gen1 development or publication is required
or performed. Hosted CI is recorded separately on the PR.
