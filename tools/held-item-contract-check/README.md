# Native held-item contract comparison

```sh
python3 tools/held-item-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified \
  --report /tmp/held-item-contract.json
```

Requires Python 3, LuaJIT, a complete host checkout and clean Gen1Recomp at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The source checkout is read only.
No ROM, generated cartridge cache, private mod or network access is needed.

Runs isolated workers for both real SDKs on Gold/Silver/Crystal and
FireRed/Emerald. Compare API 1/native, API 2/native, API 2/unified and
API 3/unified. The source API 2 lacks a unified opt-in and uses native callbacks.
The same example is loaded unchanged. Workers execute native effect reads,
moves, order/escape/entry handlers and real registered residual phases.
The native producers/effects are not stubbed and Runtime is not called by tests.

Reports include refs, dirty status, consumer hash, paired observations and
assertion totals. Actual move damage is checked for effect direction rather
than asserting identical formulas. The source GBA residual collector is not
its complete presentation/award controller. See the public documentation for
other native boundaries.

Native call scheduling is also recorded as `native_policy`. Unrestricted
7-HP Berry grants now heal 35 HP on both GBA engines, with six residual reads.
`--require-native-schedule-parity` checks the entire policy record (HP and read
count) and is required in all four CI modes. Shared cases additionally cover
real called/spread actions, canceled actions, PP/cures, residual ordering and
four active slots. These assertions are not a proof of arbitrary-mod or
complete battle-rule equivalence.
