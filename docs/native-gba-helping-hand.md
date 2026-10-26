# Native GBA Helping Hand

Imported GBA effect 176 (`HELPING_HAND_EFFECT`, move 270) now registers an
ordinary primary effect. A successful use supports the user's current living
partner for the round. It fails in singles, without a partner, or if either
the user or the partner is already supported. Repeating it does not stack.
Ordinary status interruption and imported Protect flags remain authoritative.

The shared damage calculator applies the native 1.5 multiplier after the
critical multiplier and before STAB/type rounding. Fixed damage is unchanged;
confusion self-damage uses its unmodified base. The support persists across
actions and residual collection until the next native turn-planning boundary.
A replacement battler does not inherit it. Other generations ignore the new
state. No mod-specific damage hook or separate port is needed for these paths.

For example, level-30 Tackle with equal Attack/Defense, normal STAB and roll
100 deals 16 without support and 24 with support. The actual turn queue runs
the slow helper's imported priority-five move before faster ordinary attacks.

## Dependencies and scope

The feature builds on #196's common enemy-action fixture and native turn
integration, plus the existing #178 base-damage and #175 critical-order
corrections. Those two published patches are reused as prerequisite commits;
review the new implementation relative to `45f5b4e3386f704ab011ca3b6690aaa79f0bc425`.
Its prerequisite fixture is taken from #175, without importing unrelated
production changes from that historical stack.

Canonical public `effect = "HELPING_HAND"` writes additionally use #121's
existing effect adapter. Registration enables its binding automatically; no
generated effect table is rewritten. The explicit composed proof requires
both features, patches content during one real API-3 load, and executes a
publicly selected right-flank enemy move with the supported numeric damage.

This verifies the native producer and the shared ordinary damage path,
including fixed-damage and confusion exclusions. Dedicated set-damage/delayed
move paths (Spit Up, Beat Up, Future Sight/Doom Desire), their other existing
semantic differences, full held-item/ability ordering, called/link moves,
AI scoring and full gameplay/RNG parity remain separately auditable surfaces.
The ordinary calculator's boost is not a proof of those special executors.

## Validation

```sh
luajit tests/engine/gen3_helping_hand.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua luajit \
  --report /tmp/enemy-action-report.json
# With the canonical effect adapter integrated:
luajit tests/helping_hand/public_effect.lua
```

The focused host suite passes **5,322 checks**. Cases exercise both GBA
profiles, every helper flank, actual selected attacks and public move/damage
events, critical/noncritical hits, STAB, physical/special/spread moves,
resistance/immunity, variation 85/100, unchanged fixed damage and confusion,
status/refusal/repetition gates, both round boundaries, replacement, reused
support, actual priority queues, PP and non-GBA guards.

The same public consumer and shared fixture match unchanged read-only Gen1
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91` in **28 isolated engine workers /
1,916 paired observations**. These include the prior choice, selector, record,
target and Follow Me cases. Shared sessions use equal stats and synthetic
extractor-shaped move rows; they do not claim a fresh cartridge import.
The unchanged prerequisite fails 391 assertions in the initial new FireRed
matrix. The existing GBA base-damage and critical-order paired checks pass.

The full feature quick run passes **86/95** engine suites versus **85/94** on
the clean prerequisite. Its exact Counter of all **25 FAIL lines across nine
inherited suites** matches, with no additions. SDK 3/3 and B30 pass. Their
baseline repairs are already present in the combined fork.

Adding only `HELPING_HAND_EFFECT` changes the native fixture digest from
`128fc071ae7249cd` to `032184f68094e9ca`; removing that entry and invalidating
the fingerprint cache restores the former. The new golden records this
intentional registry change. The combined checkout must likewise audit its
section pin and replace the former missing-handler assertion.

Gen1 is a read-only reference. No Gen1 code change or publication is required.
