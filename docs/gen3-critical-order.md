# Gen-3 critical/type rounding

A critical hit against a resistant target could deal one HP less than the
same move in Gen1Recomp's native GBA engine. With base damage 11, critical x2,
Steel resistance and random roll 85, the result must be **9 HP**, not 8:
`floor(floor(11 * 2 / 2) * 85 / 100)`.

The Gen-3 ruleset now opts into `critBeforeType`, applying its damage multiplier
after weather and before STAB and per-type rounding. Profiles without that
flag retain their existing order. This is an engine ruleset correction, with
no new public mod API or change to critical-hit probability.

It matters to portable mods that override `battle.crit`: the same public
critical decision should reach the same tested native damage result on both
engines. The unchanged `examples/portable_critical_order` consumer forces or
suppresses critical hits through that hook, using no engine imports.

The shared checker runs actual move-resolution pipelines on FireRed and
Emerald. Ninety-six cases per profile cover player/enemy attacks, critical and
ordinary hits, STAB, neutral/resisted/doubly resisted/immune targets and random
rolls 85/92/100. HP, PP and public hook-call counts are compared. Fixture stats
and type rows are explicitly equivalent; neither engine's damage calculation
is replaced. Both API modes compare with the clean Gen1 API-3 reference.
See [the checker](../tools/critical-order-contract-check/README.md).

The focused arithmetic suite also checks authored super-effectiveness rows,
immunity and profiles without the new flag. These tests establish critical/type
ordering for the covered conditions, not universal damage-formula or native
battle-rule parity. Other modifiers and battle-policy gaps remain separate.

Install the example in an isolated imported-data test identity to run the
native LÖVE driver:

```sh
POKEPORT_VERSION=firered POKEPORT_DRIVER=tests/drivers/critical_order.lua \
  bash scripts/run-portability-test.sh
```

FireRed and Emerald each run six constructed battles with actual FIGHT/move
input and full native turn queues. The same public mod controls both critical
decisions; HP and PP are checked. The driver starts New Game in memory and
stops before battle finish, afterBattle or normal SAVE. It does not perform a
complete playthrough or fresh full-ROM import.

## Validation

The feature passes **15/15** arithmetic regressions and **780/780** real-loader
checks. Each host API mode passes **4 workers / 192 paired observations**.
Unchanged #174 differs in **18 cases** and fails **2 Steel regression assertions
per GBA profile** with the same current fixtures. Both native imported-data
drivers pass all six battles; the temporary example was removed with hash
guards after both processes exited.

The complete feature passes **141/151** engine suites, **3/3** SDK suites and
B30. All **26 FAIL lines** exactly match #174's ten baseline failure suites;
their separate repairs in #128–134 are outside this feature branch. Hosted CI
approval/execution is separate from these local results.
