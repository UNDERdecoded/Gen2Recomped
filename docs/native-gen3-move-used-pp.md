# Native GBA move-used and PP command ordering

Stacked on #241 and the existing #161 charge-decision producer. This aligns
the tested native GBA command boundaries without adding a new mod API.

Ordinary GBA attack strings emit `battle.move_used` before the selected PP
command. The command reads the current selected slot and Pressure abilities
after callbacks, rather than spending a retired learned record. Removing a
slot does not cancel an already admitted attack or spend a different slot.

Zero-PP admission is decided before the event. Such a failure still emits its
attack-string event, then refuses the move without animation, damage or a
move-end command. A callback refill cannot retroactively admit it. A failed
spread action must not continue attacking its remaining targets.

Charge commands are different: the charge-decision hook precedes PP reduction.
A retained first charge consumes PP without an attack-string event. Hook
bypass and native sunlight consume PP before the subsequent event. Release
does not consume a second PP. Non-GBA ordering is preserved.

The new shared fixture executes unchanged native scripts for FireRed and
Emerald. Its 408 rows retain event-visible PP, the public API-3 move records,
the next subscriber's view after native callback changes, charge-hook PP, all RNG,
current/retired PP and all active HP. They cover ordinary, Pressure, one/zero
PP, callback refill/edit/replacement/removal, changed Pressure, forced slots,
actual Sleep Talk, awake/asleep failures, authored `ctx.callMove`, Struggle,
charge/release/bypass/sunlight and spread targets. Callback mutations are
controlled native fixture inputs; this does not introduce a new public PP
writer or promise writeback of event snapshots.

All 408 rows currently agree. The exact composed prerequisite fails 360 rows
with that same fixture. Raw initial failures and corrected results remain in
`tmp/move-used-pp-qa/`. The actual host/guest/spectator test passes 84 checks
over two menu-driven turns per profile, with a stateful public held-damage
consumer depending on event-visible PP. The first linked probe attempted to
write an event snapshot and lacked a two-turn input barrier; its failed raw
result is retained separately from the corrected read-only public consumer.

The fixture also repeats actual planning before charge release, including
release after the last PP was spent. A wrapped action must release the stored
move by identity, rather than charge again or refuse for zero PP. The exact
previous module fails 24 rows for this case; the fixed path clears charge and
invulnerability, deals native damage and spends no second PP.

Native command revision is 12; party codec remains 1. An independent audit
applies only token 11 -> 12 to the unchanged prerequisite hasher and reproduces
`6ce58ced7ffad4d9`; older-generation digest `e33d251961f2a41d` stays unchanged.

## Local acceptance

Production and final fixtures were tested on clean feature
`05927b85d01d9b230abadb9d309541da2d6d0df3` and combined candidate
`b70f28ef071b019c88829b30488dcd7f6eba086e`.

| Check | Feature | Combined |
| --- | --- | --- |
| Engine suites | 146/155 | 264/264 |
| SDK suites | 3/3 | 3/3 |
| Quick tiers / B30 | inherited engine-tier failure / B30 passes | all pass |
| Enemy/action contracts | 152 workers / 80,540 equal paired rows | same, all equal |
| Held-damage command | 2,040 equal paired rows | same, all equal |
| Ordinary GBA damage | 6,912 equal paired rows | same, all equal |
| Strict held-item scheduling, four API formats | 40 workers / 1,914 equal paired rows | same, all equal |
| Charge decision, four API formats | 64 workers / 1,020 equal paired rows | same, strict native-policy parity |
| Actual FireRed/Emerald imports | both existing modes pass | both existing modes pass |

The feature retains the exact Counter of 25 inherited anchored FAIL lines
across nine suites from the fresh unchanged composed prerequisite `167f6c91`
(144/153 engine suites, SDK 3/3 and B30). The combined candidate has no FAIL
lines. Feature charge-decision checks retain the prerequisite's documented
legacy enemy-PP policy; the combined branch already includes #162's native
AUTO defaults and passes the stricter raw-policy comparison.

The default contract matrix includes the new fixture; no selected modes or
observation fields are omitted from final acceptance. Source checkouts remain
clean and unchanged at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91` (native
execution) and `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36` (older shared
contracts). The maintained LuaJIT runtime is pinned at
`a4c064539ea931274d407e1249b4bb575424a0f4`. CPU checks use `nice -n 19`.
AST-verified formatting, whitespace checks and actionlint pass.

The imported checks use actual local FireRed/Emerald data with explicit GBA
rules, constructed parties and public menus. They distribute no ROM/cache or
normal SAVE and do not establish graphical playthrough acceptance.

## Remaining scope

A repeated complete held-phase probe still has 10 native versus 11 host reads
for successful Sleep Talk; awake/empty/blocked calls retain matching 2/2/4
counts. King's Rock/Shell Bell orchestration remains a separate native gap.
Other special command boundaries and callers such as Nature Power, complete
catalogs/controllers and graphical playthroughs are not certified here.

Raw initial failures, negative controls, earlier completed runs and final
acceptance reports remain under `tmp/move-used-pp-qa/`. Earlier runs did not
cover the copied planned-release path; the final full suites and complete
matrices were repeated after that correction.
