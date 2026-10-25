# Native GBA Disable and portable move eligibility

GBA Disable now follows the target's last executed learned move, including
known authored moves without cartridge indices. Previously it randomly selected
a positive-PP slot, drew 1–8 phases and aged the counter on attempted actions.
That could disagree with both the public mod snapshot and an already queued move.

The native producer checks accuracy first, then rejects an existing disabled
move, an unknown last move or a learned slot with no PP. It draws `0..3 + 2`
for 2–5 residual phases. `disabledMove` owns the native host ID; the affected
slots are read from the current move list. Reordering follows the identity,
every duplicate is restricted, and removing the identity clears Disable in its
next residual phase. Reaching zero PP does not prematurely end Disable.

A disabled queued action stops before announcement, `battle.move_used`, confusion
and PP consumption. The interruption clears the last executed move and native
multi-turn state, including the existing Bide continuation path. Called moves
retain their native bypass and consume no PP from the called slot. End-of-turn
processing ages Disable before Encore. Switches and Baton Pass do not transfer it.

Move selection, `mod.battle:snapshot()`, public command admission, the move-list
hint and native AI Disable predicates now read the live identity. Snapshot and
admission are read-only; identity/timer changes invalidate previously offered
commands. Legacy authored `disabledSlot` states retain their previous policy.

Builtin adaptation happens per dataset before mods load: a mod can capture and
delegate `mod.content.move_effects:get("DISABLE_EFFECT").run`. An explicit
custom handler remains authoritative, and shared legacy module records are never
mutated. Haze preserves native Disable; a successful legacy Transform clears it,
even when the copied move list still includes the disabled ID. These adapters
only address Disable's lifecycle: they do not certify all Haze/Transform rules.
Older-generation builtins and their slot/countdown behavior stay unchanged.

## Lockstep compatibility

Native GBA command revision is **5**, with native party codec revision **1**.
The active state hash includes the disabled move and timer. Both link roles
refuse older command revisions before party exchange.

The raw native fixture changes from `8be423c61a4477a2` to `da62fe7b50f40107`.
It was independently calculated with the unchanged #219 hasher and only the
explicit revision token changed from 4 to 5. Handler functions serialize as
opaque markers, so per-load builtin delegation adapters do not silently add a
function-byte digest. No older-generation golden was reblessed.

## Validation

The clean feature runtime is `55f4301ab6ef190051b1f6d420f22636a61a1809`.
Gen1 is an unchanged, clean read-only reference at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. No Gen1 development or publication
is required or performed.

- **930 focused checks**: 768 command/lifecycle, 108 public-command/delegation/
  switch and 54 actual link/compatibility checks. The protocol suite also passes.
- **96 workers / 62,976 paired observations** agree. The new Disable mode adds
  810 observations per FireRed/Emerald profile, retaining every bounded RNG
  call/value, each battler's HP/PP/learned moves/last move, actual move events,
  timer and move identity. It covers all four battler slots and duration words,
  failure guards, custom/duplicate moves, removal/reordering, PP depletion,
  confusion/called/queued execution, Bide and multi-turn interruption,
  Haze/Transform, and actual residual expiry.
- Eligibility observations compare Gen1's real native `Commands.selectionError`
  against the host's real read-only `BattleCommands.reason`. Gen1's GBA snapshot
  omits `disabled`; inventing a source value or comparing an omitted field as
  false would not prove native selection agreement.
- Full feature run: **116/125 engine suites**, SDK **3/3**, B30 passed.
  The exact Counter of all **25 inherited FAIL lines across nine suites** equals
  clean #219 (113/122). The full command correctly retains its nonzero exit.
  Independent repairs for those suites belong to the combined test branch.
- The unchanged #219 public-command negative control fails both new assertions:
  it retains random slot 2 and duration 8, rather than the last move and duration
  5. The raw negative output is retained.
- Two actual link roles complete three turns: ordinary Tackle, a faster Disable
  cancelling the already selected Tackle without PP, then an independent Scratch.
  Every completed paired hash and state component agrees.
- Four CPU-only scenarios with actual local FireRed/Emerald imports pass:
  canonical public enemy-action selection, preapplied and same-turn Disable,
  public move submission, full native turn/result queues and residual expiry.
  Disable's real imported accuracy is retained; the controlled hit roll is 1.
  No cartridge caches, ROMs or saves are distributed and no normal SAVE is issued.
- Scoped StyLua, actionlint and whitespace checks pass.

Reproduce from the feature checkout, using the maintained LuaJIT pin documented
in the workflow (`a4c064539ea931274d407e1249b4bb575424a0f4`):

```sh
nice -n 19 "$LUA" tests/engine/gen3_disable.lua
nice -n 19 "$LUA" tests/engine/gen3_disable_continuation.lua
nice -n 19 "$LUA" tests/engine/gen3_disable_link.lua
nice -n 19 "$LUA" tests/engine/gen3_battle_protocol.lua
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 . --lua "$LUA" \
  --report /tmp/disable-contracts.json
nice -n 19 env LUA="$LUA" \
  LUA_INIT='io.stdout:setvbuf("no"); io.stderr:setvbuf("no")' \
  bash scripts/test.sh --quick
```

Private local evidence is retained under `tmp/disable-qa/`, including the full
feature log, complete comparison report, exact baseline FAIL-Counter audit,
negative control and imported smoke. Earlier exploratory/failed logs are retained.

## Remaining boundaries

This is a native command/lifecycle and mod eligibility contract, not complete
battle equivalence. The broader canceller ordering, legacy Rage/other locked-move
controllers, all Haze/Transform rules, whole-game RNG/VBlank orchestration,
animations, live UI pixels and a full cartridge playthrough need separate work.
The existing prepared Quick Claw boundary in the public Encore planning cases
remains documented in [the Encore contract](native-gen3-encore.md); no RNG calls
or differing observations are filtered from this checker.

## Combined fork acceptance

The tested combined runtime `abd621282715d072b421e7b30f3f5c60628d771d`
passes **237/237 engine suites**, SDK **3/3**, B30, the same **96 workers /
62,976 paired observations**, and all four imported CPU smoke scenarios.
Both comparison reports identify a clean host at their respective runtime.
The integration preserves the existing GBA item/residual scheduling and native
AI-order preparation. Later commits only record validation/publication.

Combined evidence is retained in `tmp/disable-full.log`,
`tmp/disable-contracts.json`, `tmp/disable-imported.log` and
`tmp/disable-accepted-evidence.json`. The source checkout remains clean at the
pinned Gen1 revision. Hosted CI status is reported separately in the PR.
