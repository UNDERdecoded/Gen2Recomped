# Native GBA critical context and hit events

Ordinary damage and dedicated Beat Up strikes now share the native critical
command policy. Birch's first battle and Wally's tutorial return before the
critical random draw. Teachy TV consumes that draw and then discards its
result. FireRed's Oak predicate also checks the inflicted-damage flag;
the HP-damage command advances it after the public hit event and only for
player damage to a non-Substitute opponent. This includes later strikes of
the same Beat Up action. Old-man control cases still roll normally.

The actual first-battle script forwards its metadata through the ordinary
battle constructor, and the existing Wally/Teachy TV constructors provide
their native state. Ordinary critical hooks retain their override/delegation
semantics; dedicated Beat Up bypasses them. Both hooked and unhooked ordinary
paths share the policy. Earlier-generation policies remain unchanged.

## Public context and native stages

The shared public `battle.crit` context carries battle, target, canonical
move ID, numeric move ID and the current critical stage. Stage calculation
uses native physical item IDs: Scope Lens, Lucky Punch and Stick; the last
two inspect the current battler species rather than the retained party mon.
Mutating a physical Scope Lens's held-effect metadata does not remove its
native stage bonus, and custom Scope-Lens-like metadata does not give an
unrelated item that native ID's behavior. Portable custom behavior can use
the shared public critical hook instead.

Focus Energy, high-critical effects and the native cap are covered. Lansat
Berry uses the Focus Energy marker and is not consumed when that marker is
already active. Ordinary GBA hit events now also carry physical/special kind
and the Substitute flag; scripted Beat Up retains its native special kind
and noncritical event metadata even for critical damage.

## Verification

```sh
luajit tests/engine/gen3_critical_context.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --report /tmp/enemy-action-report.json
```

The same API-3 consumer uses actual action selection and move executors on
unchanged read-only Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The new matrix has 27 FireRed
and 29 Emerald cases at all four positions, each with ordinary damage and
scripted Beat Up. It compares critical/variation operands, damage and hit
metadata, public context fields, callbacks and the Oak flag's event timing.
Cases cover normal and special damage, Focus Energy, native/custom held
items, active species, high-critical effects/cap, the actual Lansat producer,
armor, hook force/delegation/suppression, unhooked paths, first-battle kinds,
Wally, Poke Dude, old-man controls and Substitute.

Gen2 first-battle cases run `Gen3Commands.firstBattle` through
`Commands.start_battle` and `BattleState.newWild`. Wally and Teachy TV use
their actual constructors. The source fixture seeds the native kind fields;
Oak laboratory flags and detached/current species are also seeded explicitly.
Stats are controlled and imported-shaped; full controller/intro playback,
constructor stat generation, advice text, animations and a fresh ROM import
are not claimed.

The focused suite passes **3,396 checks**, including non-GBA passthrough
controls. The complete comparison passes **52 isolated workers / 5,214
paired observations**. #210 fails **288 assertions** in the new FireRed
cases. The full feature quick run passes **92/101 engine suites** versus
**91/100** on clean #210; exact Counters of the **25 inherited FAIL lines
across nine suites** match with no additions. SDK 3/3 and B30 pass.

Both engines and the workflow use JIT-enabled LuaJIT v2.1 commit
`a4c064539ea931274d407e1249b4bb575424a0f4`. Critical operands are normalized
across native range conventions; complete raw RNG traces and full
link/multi-owner controller execution remain separate surfaces.

The feature stacks on #210. The scripted Beat Up policy change increments
`BEAT_UP_EFFECT.rev` from 2 to 3. The fixture digest changes from
`fdbfa30b20cbbaef` to `a000e3862d11a73a`; only `move_effects` changes, from
`e4d28f474c15cd8b` to `cca86e08b893522c`. Restoring revision 2 restores the
prior full digest; all six other populated sections remain identical.
Gen1 remains read-only and requires no source change or publication.
