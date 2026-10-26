# Native GBA Triple Kick execution

Triple Kick previously used the legacy approximation: one accuracy/critical/
damage calculation, repeated three times at twice the extracted power. Native
GBA effect 104 instead checks every reached kick, assigns power 10/20/30 and
calculates each critical and damage roll independently. Rounding, misses and
move-end state make the approximation observably different.

This change stacks on #225. It adapts the builtin per dataset before mods
capture it and preserves the shared static fallback for other generations.
Complete authored records own their script; captured records retain native
behavior, authored counts, explicit damage handlers and `neverMiss` policy.
The native damage hook receives the assigned power in `ctx.opts.power`; a
public wrapper can delegate or change that value independently per kick.

Stop before unreachable kicks when either battler faints, the user sleeps
outside the existing Sleep Talk continuation, a new accuracy/protection/hidden
check fails, a reached damage calculation is immune, or actual Endure ends the
sequence. Continue through a broken Substitute; Focus Band can save subsequent
strikes. A separately selected attack costs one learned PP regardless of how
many kicks land. Called execution keeps its own PP semantics.

FireRed/Emerald move-end Rage runs once for a completed qualifying attack.
A later missed kick retains success from earlier kicks; a reached immunity
suppresses it. Accuracy failure precedes the next damage/type calculation, so
an immunity introduced after hit one does not suppress Rage when kick two
misses before reaching that calculation.

## Verification

At clean feature runtime `10a5c325a7852c6e8f7fea1502fafd9cfdc4a393`:

- **2,220 focused checks** pass: 2,100 command/hook/lifecycle, 70 content
  composition and 50 real link/compatibility checks. The 154-check native
  protocol suite also passes.
- **108 workers / 76,362 paired observations** agree with unchanged, clean,
  read-only Gen1 `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.
  The new mode contributes **576 complete rows per FireRed/Emerald profile**:
  singles/doubles and all four actor slots; each possible missed kick;
  critical stages/items; unchanged and edited extracted power; public damage
  power overrides; Substitute, Endure, Focus Band, faint/sleep, called moves,
  immunity/protection/hidden state before and after hit one, and Rage.
- Every bounded RNG call/value, public accuracy/damage calculation, hit/move
  event and all battler HP/PP/status/Substitute/last-move/Attack/Rage observations
  stay in the comparison. Public events are detached views; lifecycle probes
  mutate and assert the fixture's owned live battlers. No draws or mismatches
  are filtered out.
- Full feature: **126/135 engine suites**, SDK **3/3**, B30. The exact Counter
  of **25 inherited FAIL lines across nine suites** equals clean #225
  `8e543618bc3a6ec9e0c6d8f1f31f9e12b5259f2e` (**123/132**). The full command's
  nonzero exit remains retained. Their independent repairs are in the combined
  branch, whose runtime `c1dac0994aa9fe0d1659e510874065697dca2534` passes
  **246/246 engine suites**, SDK **3/3**, B30 and the same full comparison.
- Unchanged #225 fails **240 assertions** with the exact final fixture;
  **396/576** complete FireRed rows differ from the unchanged reference.
  Exploratory failures, the initial hook-signature error and all raw negatives
  remain retained separately from accepted evidence.
- Two actual link roles complete three turns (Triple Kick, Tackle, Triple Kick)
  with every completed paired hash/component equal and correct learned PP.
  Native command revision **8** refuses revision 7 before party selection;
  party codec remains **1**. Raw fixture `dcc938191b0bb075` becomes
  `b9ec4e8a94f4ba6e`, audited using the unchanged #225 hasher with only its
  explicit revision token changed. Other-generation goldens are unchanged.
- **Twelve CPU-only scenarios with actual local FireRed/Emerald imports** pass
  public move submission and the completed turn/menu: three landed kicks,
  misses on kick 1/2/3, Substitute breaking, and a faster enemy actually using
  Endure. Extracted effect/power/accuracy and type metadata remain intact;
  controlled valid RNG exercises the branches. Public events use canonical
  `TRIPLE_KICK`, without relying on private move-index fields. No ROM/cache/
  save files are distributed and no normal SAVE is issued.
- Scoped StyLua, actionlint and whitespace checks pass.

Reproduce the ROM-free tests with the maintained pinned LuaJIT
`a4c064539ea931274d407e1249b4bb575424a0f4`:

```sh
nice -n 19 "$LUA" tests/engine/gen3_triple_kick.lua
nice -n 19 "$LUA" tests/engine/gen3_triple_kick_composition.lua
nice -n 19 "$LUA" tests/engine/gen3_triple_kick_link.lua
nice -n 19 env LUA="$LUA" bash scripts/test.sh --quick
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 "$PWD" --lua "$LUA" \
  --report /tmp/triple-kick-contracts.json
```

Optional imported-data test (the root contains `firered/data/generated` and
`emerald/data/generated`):

```sh
nice -n 19 "$LUA" tools/enemy-action-contract-check/imported-triple-kick-smoke.lua \
  /path/to/local/Gen2Recomp
```

Feature acceptance is retained in `tmp/triple-kick-qa/accepted-evidence.json`,
`full-feature-accepted.log`, `contracts-feature-accepted.json` and
`imported-final.log`; combined evidence is in `tmp/triple-kick-accepted-evidence.json`,
`tmp/triple-kick-full-accepted.log`, `tmp/triple-kick-contracts-accepted.json`
and `tmp/triple-kick-imported-accepted.log`. Later commits only document results.
Hosted workflow execution is recorded separately on the PR.

## Catalog boundary and remaining work

The earlier `RAGE_EFFECT` retrieval failure is a confirmed catalog difference,
not a missing fixture import. At the pinned Gen1 reference, generation-3
`Builtins.registries(3)` seeds only types, growth and evolution. Both
`RAGE_EFFECT` and `TRIPLE_KICK_EFFECT` are absent from its public effect catalog;
Gen2 exposes both. A minimal authored primary effect registers successfully in
both engines, tested through the same public loader for FireRed and Emerald.
Raw audits are `tmp/triple-kick-qa/catalog-gen1.log` and `catalog-gen2.log`.

Portable consumers must not assume native builtin capture/delegation is a
shared GBA contract. Host composition checks here are separate from the
cross-engine native execution comparison. This change neither publishes nor
requires any Gen1 modification. Complete builtin catalogs, full Sleep Talk/
other controllers, Ruby/Sapphire per-hit scheduling, global RNG/selection
orchestration, rendering and full playthrough parity remain separate work.
