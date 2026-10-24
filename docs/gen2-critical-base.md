# Native Gen-2 critical base

Gen-2 critical hits double the truncated base damage before the damage cap
and final +2. Using Gen-1's doubled-level calculation instead changes the
rounding at levels such as 1, 3 and 29. At level 29, power 35 and equal
50-point Attack/Defense, a non-STAB critical at random 217 deals **17 HP**;
the doubled-level path dealt 16. With STAB the result is **25 HP**, not 23.

Imported `constants.generation = 2` now selects that native critical-base
step when the ruleset has no explicit critical multiplier. Gen-1's existing
level calculation and explicit-multiplier profiles retain their own paths.
This does not change critical probability or add another public mod API.

The same `examples/portable_critical_order` consumer now supports Gen 2 as
well as Gen 3. It forces or suppresses `battle.crit` using only the public hook.
The Gen-2 contract cases run actual native move pipelines through both real
SDKs on Gold/Silver/Crystal: both attackers, levels 1/3/29/30/99/100,
critical/noncritical, STAB/non-STAB, and random rolls 217/255. Damage, PP and
public callback counts are compared. Stats, active types and generation
metadata are explicitly equivalent; neither native damage function is mocked.

The existing FireRed/Emerald matrix also remains in the shared checker.
See [the combined critical checker](../tools/critical-order-contract-check/README.md)
and [the earlier GBA correction](gen3-critical-order.md).

These tests establish the covered critical-base rounding. Further Gen-2
modifiers, stage/badge interactions and full battle-rule parity require their
own validation. Callback context equivalence beyond what the shared public
consumer reads is not asserted by this damage matrix.

For native LÖVE, install the example in an isolated imported Gold identity:

```sh
POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_critical_base.lua \
  bash scripts/run-portability-test.sh
```

The driver starts New Game in memory and constructs six battles with controlled
session stats. Actual FIGHT/move input and complete turn queues check ordinary
hits, critical level boundaries and STAB through the public consumer. It stops
before battle finish, afterBattle or normal SAVE. This is not a complete
playthrough or fresh full-ROM import; native Silver/Crystal GUI runs are not
implied by the headless matrix.

## Validation

**7/7** focused arithmetic regressions and **1,950/1,950** loader checks pass.
Each host API mode passes **10 workers / 480 paired observations** against
clean Gen1 `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The unchanged #175 parent
differs in **32 damage observations** and fails **two level-29 regression
assertions per Gen-2 version** with the same current fixtures.

Native LÖVE 11.5 passes six constructed battles each on imported Gold,
FireRed and Emerald: **18 battles and 36 public critical decisions**, at clean
feature runtime `397d7d6fb48bcf8f539c152397bb3e5ad220d23d`. Gold checks the new
level boundaries; the GBA runs retain the earlier type-rounding regressions.
The temporary installed example was removed with hash guards. Native
Silver/Crystal GUI runs are not claimed. Later changes record validation only.

The complete feature passes **142/152** engine suites, **3/3** SDK suites and
B30. All **26 FAIL lines** exactly match the parent's ten known baseline
failure suites; their separate #128–134 repairs are outside this feature.
The combined testing runtime `6ba0ca1569a27faba67f0481e602df777fa5dc39`, with
those repairs, passes **197/197** engine suites, **3/3** SDK suites, B30 and both
shared contract modes. Critical implementation/consumer/driver files are byte
identical between feature and combined trees; the native results above retain
their feature runtime and are not relabeled as a new composed native run.
