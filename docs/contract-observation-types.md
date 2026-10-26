# Boolean and numeric contract observations

The enemy/action checker compares complete decoded observations recursively.
JSON booleans remain distinct from numbers: `false` cannot equal `0`, and
`true` cannot equal `1`, including inside nested records and arrays. Object
key order is immaterial, array order remains significant, and equivalent
JSON numbers such as `1` and `1.0` retain numeric equality.

Previously Python's dictionary/list equality silently admitted these Boolean
changes. A black-box synthetic-worker negative control reproduces a false
pass for both profiles on the unchanged checker. This is a checker defect,
not evidence of a native runtime mismatch. The preceding native music
qualification additionally compares its raw observations with an independent
type-aware auditor.

The CLI regression exercises the actual argument parsing, worker admission,
comparison and report path with synthetic worker output. It checks both
directions at scalar, array and nested-record depth, positive numeric/object
controls, structural differences and existing exit/observation-count/native
VM diagnostic/timeout rejection. Timeout raw bytes remain preserved.

```sh
nice -n 19 python3 -m unittest discover -s tests/tools -p test_contract_observations.py
```

`POKEPORT_CONTRACT_CHECKER` can select a frozen old checker for a negative
control. The test owns only temporary report files and mocks worker/git
calls; it does not boot a game, open a device or modify a reference checkout.

The five CLI tests exercise 26 synthetic cases and pass with the correction.
The unchanged checker fails all 12 Boolean/number drift cases while retaining
the positive and worker-failure controls. All 13 tool tests, including the
eight existing Substitute-discovery regressions, pass together. Both independently qualified native capture sets also replay successfully
through the corrected comparator: 268 workers / 178,264 complete paired
observations per set. This reparses recorded output rather than executing
the engines again. The [source-bound receipt](qa/contract-observation-types.json)
records the checker, capture identities and retained negative controls.
