# Native critical/type contracts

Use clean Gen1Recomp `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`:

```sh
python3 tools/critical-order-contract-check/check.py --gen1 /path/to/pinned/gen1 --host-api 3 --report /tmp/critical-api3.json
python3 tools/critical-order-contract-check/check.py --gen1 /path/to/pinned/gen1 --host-api 2 --report /tmp/critical-api2.json
```

Set `--lua /path/to/luajit` if needed. Each invocation runs ten isolated
workers and compares **480 pairs** on Gold/Silver/Crystal/FireRed/Emerald. The
source always uses API 3; the host uses API 3 or API 2/unified. Both load the
same public `battle.crit` consumer through their real SDKs, then run native
move pipelines with equivalent stats, live types and random damage rolls.

Gen-2 observations cover both attackers, levels 1/3/29/30/99/100,
critical/noncritical, STAB/non-STAB and rolls 217/255: 96 cases per version.
The GBA cases cover both attackers, critical/noncritical, STAB,
neutral/half/quarter/immune type effects and rolls 85/92/100: 96 per profile.
Damage, PP and public critical-hook counts are compared. Reports preserve the engine refs and consumer/fixture
hashes; the checker refuses a different or modified reference. These are
synthetic ROM-free fixtures, not native GUI or complete playthrough tests.
The isolated imported-data drivers and native-rule boundaries are documented
in the [Gen-2 correction](../../docs/gen2-critical-base.md) and
[GBA correction](../../docs/gen3-critical-order.md).
