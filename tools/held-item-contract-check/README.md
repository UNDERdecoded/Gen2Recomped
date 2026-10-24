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

Native call scheduling is recorded separately as `native_policy`. Unrestricted
Berry grants even to empty hands heal 35 HP in the reference GBA fixture and
7 in the host; this known gap is printed and excluded from equal observations.
Use `--require-native-schedule-parity` as a strict negative control: it currently
fails on FireRed/Emerald. Do not interpret the default read-contract comparison
as proof of identical residual scheduling or arbitrary-mod compatibility.
