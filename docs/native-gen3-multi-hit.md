# Ordinary native GBA multi-hit execution

Native multi-hit moves need independent damage commands for each reached strike.
The host previously drew an eight-value hit count before accuracy, computed the
ordinary damage only once, and stopped when a Substitute broke. This changed RNG
consumption, individual damage events and live continuation seen by mods.

The GBA paths for raw effects **29** (two to five), **44** (two hits) and **77**
(Twineedle) now calculate ordinary damage for each reached strike. Explicit
`chooseDamage` and `perHitDamage` handlers remain authoritative. Scripted Beat Up
retains its independent party eligibility and Endure rules.

- Accuracy precedes hit count. The native count opcode draws `0..3`; values 0/1
  give 2/3 hits, while 2/3 require a second `0..3 + 2` draw.
- Every reached ordinary strike gets its own critical/damage calculation and
  event. GBA crits draw `0..denominator-1` and compare with zero. The previous
  `1..denominator` draw had the same probability but a different observable RNG
  ABI. The raw comparison now covers every critical stage without normalizing
  away bounds or returned values.
- Later strikes continue against real HP after Substitute breaks. Actual Endure
  stops an ordinary multi-hit sequence; Focus Band can save later strikes too.
  PP is spent once, with called moves preserving their native PP bypass.
- Later strikes inspect live user/target state. Sleep, user/target fainting and
  a new type immunity can stop continuation. A later immunity suppresses the
  native Twineedle chance command, retaining the first landed damage event.
- The existing nested dispatcher carries the calling move, so a Sleep Talk
  caller can exempt sleeping continuation. This is tested after the caller's
  move selection; complete Sleep Talk selection and status-controller parity
  are not certified here.
- Native hit-count adapters are installed per dataset before mods capture
  `mod.content.move_effects:get(...).hitCount`. Overrides and delegation work
  without changing shared legacy statics. A no-loader path uses the same native
  adapters. Other generations retain their existing count/damage policy.

Public events are detached views. Continuation probes mutate the owned fixture's
real battlers when a public hit event arrives; they assert the mutation and its
consequences. They do not claim that writing into a detached event view changes
engine state.

## Compatibility and scope

GBA command revision is **6**, native party codec remains **1**. The raw fixture
hash changes from `da62fe7b50f40107` to `a7db0874db78aec0`, independently computed
with the unchanged #220 hasher and only the revision token changed from 5 to 6.
Older-generation goldens were not reblessed. Link peers reject revision 5 before
party selection.

The ordinary native rules are deliberately separate from scripted Beat Up.
The first integration incorrectly applied ordinary Endure/user-faint termination
to Beat Up; the original full logs and eight differing comparison runs are
retained. The accepted implementation preserves all existing Beat Up contracts.

Triple Kick's dedicated per-hit accuracy/power script, Ruby/Sapphire move-end
scheduling, complete ability interactions, broader canceller/controller rules,
Rage production, whole-game RNG/VBlank timing, animations and full playthroughs
remain separate work. This PR is a prerequisite for testing native Rage against
multi-hit attacks; it does not claim Rage itself has been ported.

## Accepted evidence

Feature runtime: `00e67c40abcb224ff693e4f543a4d018014edf73`.
Combined runtime: `1a20cb1f104972c46c756ba6a55e814fc27619c8`.
Gen1 reference: clean, unchanged and read-only at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

- **17,974 focused checks** pass: 17,856 native command/live-continuation, 68
  composition/caller/legacy and 50 actual link/compatibility checks. The native
  protocol suite also passes.
- Both clean runtimes match the source in **100 workers / 74,496 paired
  observations**. The new mode contributes **5,760 observations per profile**,
  covering all four battler slots, all count words, all critical stages,
  Substitute/Endure/Focus Band/KO, Protect/hidden/accuracy/type immunity,
  Twineedle chance, called PP, and live sleep/type/faint changes between hits.
  Every RNG bound/value, individual public damage/move event, all battler HP/PP,
  status, substitute HP, last move and attack stage is retained.
- Feature regression: **119/128 engine suites**, SDK **3/3**, B30 passed.
  The exact Counter of all **25 inherited FAIL lines in nine suites** matches
  clean #220 (116/125), without additions. The full command keeps its nonzero exit.
- Combined regression: **240/240 engine suites**, SDK **3/3**, B30 passed,
  including the independent baseline repairs and all earlier Beat Up contracts.
- Unchanged #220 fails **1,524 focused assertions** from the exact accepted
  fixture. Of its 5,760 FireRed observations, **5,088 differ** from the unchanged
  source. The fixture SHA-256 matches the source report; raw negative output and
  earlier exploratory/failed logs remain retained.
- Two real link roles complete three turns using the variable-count, double-hit
  and Twineedle paths. All paired completed hashes/components and learned PP agree.
- **18 CPU-only scenarios** with actual local FireRed/Emerald imports pass public
  canonical enemy-action selection and execution for DoubleSlap, Double Kick and
  Twineedle, each ordinary/with a breaking Substitute/with Endure. Imported
  accuracy, type, power and PP are retained; a controlled valid accuracy roll is
  used. No caches, ROMs or saves are distributed and no normal SAVE is issued.
- Scoped StyLua, actionlint and whitespace checks pass.

Use the maintained LuaJIT pin in the workflow
(`a4c064539ea931274d407e1249b4bb575424a0f4`):

```sh
nice -n 19 "$LUA" tests/engine/gen3_multi_hit.lua
nice -n 19 "$LUA" tests/engine/gen3_multi_hit_composition.lua
nice -n 19 "$LUA" tests/engine/gen3_multi_hit_link.lua
nice -n 19 "$LUA" tests/engine/gen3_battle_protocol.lua
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 . --lua "$LUA" \
  --report /tmp/multi-hit-contracts.json
nice -n 19 env LUA="$LUA" \
  LUA_INIT='io.stdout:setvbuf("no"); io.stderr:setvbuf("no")' \
  bash scripts/test.sh --quick
```

Feature evidence is in `tmp/multi-hit-qa/`: the accepted full/comparison/import
logs, `accepted-evidence.json`, exact FAIL-Counter audit and unchanged-parent
negative control. Combined evidence is in `tmp/multi-hit-full-accepted.log`,
`tmp/multi-hit-contracts-accepted.json`, `tmp/multi-hit-imported.log` and
`tmp/multi-hit-accepted-evidence.json`. Later commits only record validation and
publication. Hosted CI is tracked separately in the published PR.
