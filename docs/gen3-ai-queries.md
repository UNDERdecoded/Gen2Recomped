# GBA AI move and battler queries

The native bytecode importer already decodes several query commands that
`Gen3AI` could not execute. Its whole-script gate consequently skipped a
reachable script containing any of these commands.

`Gen3AIQueries` supplies seven query families through the existing VM:

- The last-used move, preserving the importer's `get_last_used_bank_move`
  name and the `get_last_used_move` alias.
- Move type, power and native effect from the current result register.
- The live Protect/Detect/Endure counter.
- Active types and Flash Fire state, including partner selectors.

Metadata reads resolve physical indices against current move records; known
GBA types retain their native numbers across legacy name aliases. Declared
custom type indices can also be read from the type registry. MOVE_NONE keeps
its zero metadata when a host cache omits that row. A different missing move
is an error, matching the reference interpreter; it is not a successful zero
result. These queries consume no RNG and do not change battle state.

The last-move and Protect commands preserve the reference's USER/TARGET
selection. The explicitly partner-aware type/Flash Fire commands use actual
battle slot lookup and return false for an absent partner. Existing native
producers supply `lastMove`, `protectRun` and `flashFire` on the host.

## Shared interpreter contract

The same case file runs equivalent programs through Gen1Recomp's real GBA
`AiVm` and Gen2Recomped's real `Gen3AI`. Each VM reads typed native session
records and scores both move slots. No copied query implementation provides
an expected result.

The matrix contains **4 workers / 472 paired observations** on FireRed and
Emerald. It covers all 18 native type numbers, legacy aliases, declared custom
types, numeric and named move references, both last-move names, missing
history, omitted MOVE_NONE rows, invalid definitions, Protect counts,
user/target/partner selection, absent partners and exact RNG non-consumption.
The host suite also checks that a different unsupported reachable query
still rejects the entire script, without partial scores or RNG draws.

```sh
luajit tests/engine/gen3_ai_queries.lua
python3 tools/gen3-ai-query-contract-check/check.py --gen1 /path/to/gen1
```

The reference must be clean at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Workers load their respective
engine modules. The dedicated workflow retains the comparison report.
No ROM, generated cartridge assets or graphics runtime is required.

This is a read-query/interpreter contract. It does not publish the unfinished
enemy switch/item hook, establish every native AI opcode or stock trainer
script, or claim new graphical gameplay validation. Other unsupported
queries remain gated. Reference-side held-effect/taunt placeholders require
further work before those families can have a functional common contract.

## Validation record

At clean feature runtime `5e7823d63346816b333eaae34d600a0ff84b12f2`:

- **2,339/2,339** host checks pass, including the unsupported-script guard.
- Both actual interpreters match in **4 workers / 472 paired observations**,
  with zero differences against clean Gen1Recomp `535a5ec`.
- Clean upstream `13af468b97dc37015d14ad5c71d7f067c3ee810d` fails **702
  assertions per GBA profile**, with 236 differing observations per profile.
- The complete feature run passes **65/75** engine suites, SDK **3/3** and
  B30. Upstream passes **64/74**; all **27 FAIL lines across ten baseline
  suites** match exactly. Workflow lint and new-file formatting pass.

Local evidence is in ignored `tmp/ai-query-qa/`: `targeted.log`,
`contracts-clean.json`, `full.log` and `parent-differences.json`.
Hosted CI is separate from these local results. No new LÖVE or full
playthrough result is claimed.
