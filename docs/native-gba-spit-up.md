# Native GBA Stockpile release

Gen-3 Spit Up (effect 161) uses a native set-damage command. Its calculated
base, including the final +2, is multiplied by the operative Stockpile count
before Helping Hand, STAB and type rounding. Multiplying the move's power
inside ordinary damage calculation produces a different result: at level 30,
equal Attack/Defense and normal STAB, two stacks release 90 instead of 87.

The native path bypasses ordinary `battle.damage` and `battle.crit` hooks and
has no damage-variation roll. The accuracy hook and ordinary status
interruption still apply. This matches the reference's dedicated command,
not a fabricated ordinary hit that happens to have the same amount.

Successful release, Protect and type immunity consume the stored count;
normal misses, semi-invulnerability, sleep and absorption preserve it. An
empty use still spends ordinary PP. Four real Stockpile casts cap at three;
a second release cannot reuse spent energy. Swallow consumes the same count.
Helping Hand, exact stage ratios, pre-stage stat modifiers, screens, burn,
type rounding and clipped Substitute damage use the covered native order.
The native set-damage event retains its reference metadata (no critical and
neutral event multiplier), separately from the actual type-adjusted amount.

This feature stacks on #198. The existing record receives `rev = 1`, so
builds with the changed native effect cannot silently share an older link
fingerprint. Earlier-generation fallback behavior remains separate.

## Contract verification

```sh
luajit tests/engine/gen3_spit_up.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --report /tmp/enemy-action-report.json
# With the canonical effect adapter (#121) integrated:
luajit tests/spit_up/public_effect.lua
```

The same API-3 consumer and fixture use the actual native planner/action
selection and move executors on unchanged read-only Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The matrix includes all four user
positions and counts 0–3, physical and authored special types, STAB, single
and dual resistance, immunity/Foresight, Helping Hand, wide/low stats,
Protect, Substitute, Endure at one HP, miss/sleep/semi-invulnerability,
absorption, burn/screens, rain/sun, selected ability/item/stage combinations,
Stockpile's cap, repeated release and Swallow interaction. Actual move/hit
events, HP, operative counter, PP and public damage/critical callback counts
are compared. Native sessions use equal stats and synthetic imported-shaped
rows; this is not a fresh ROM import or full graphical playthrough.

The focused suite passes **8,292 checks**. The full comparison passes
**32 isolated workers / 3,974 paired observations**, including the existing
enemy-choice, selector, record, target, Follow Me and Helping Hand contracts.
The unchanged #198 host fails **770 assertions** in the new FireRed cases.
The full quick feature run passes **87/96** engine suites versus **86/95** on
clean #198. Exact Counters of all **25 inherited FAIL lines across nine
suites** match, with no additions. SDK 3/3 and B30 pass.

Counters compare the operative native operands: `expStockpile` on the
reference and `stockpile` on this host. The reference's legacy `stockpile`
alias remains stale after Protect; raw alias equality is not claimed.
Native set-damage event metadata is checked explicitly, not replaced by the
ordinary calculator's effectiveness metadata.

## Pinned test runtime

Both sides and the contract workflow use maintained LuaJIT v2.1 commit
[`a4c064539ea931274d407e1249b4bb575424a0f4`](https://github.com/LuaJIT/LuaJIT/commit/a4c064539ea931274d407e1249b4bb575424a0f4),
reporting `LuaJIT 2.1.1792588164`, with JIT enabled. It is built from the
official mirror, not patched engine code. LuaJIT's
[release policy](https://luajit.org/status.html) uses a maintained rolling
branch; the workflow pins the exact source revision for reproducibility.

The former local ARM64 runtime `2.1.1700008891` produced JIT-dependent Thick
Fat results in unchanged reference code (30 rather than 33 in one covered
case). Disabling JIT on that old VM removes the discrepancy; the maintained
VM passes the unfiltered comparison with JIT enabled. The original failing
report is retained separately under ignored QA output. This is not a claim
of parity on that older VM, and no source-reference patch or row/value filter
is used to make the comparison pass.

Only the reviewed Spit Up record revision changes the fixture fingerprint:
`032184f68094e9ca` becomes `397df21576af62f1`, and the `move_effects` section
changes from `52cc8398513ed12c` to `c62807cde682a669`. All six other populated
sections remain identical. Removing only that revision restores the former
full digest. The combined checkout must update its audited section pin.

Full ability/item/badge coverage, ordinary damage's remaining ordering gaps,
other set/delayed executors, RNG traces outside these recorded operations,
called/link controller execution, animation and full gameplay remain separate
surfaces. Gen1 is a read-only reference; no Gen1 publication is required.
