# Portable charge-turn decisions

`battle.charge_required(next, ctx)` lets a mod skip the initial charge turn
of a native two-turn move. Gen1–3 hosts expose it; DS reports unavailable and
retains its current native move flow.

```lua
local mod = ...
if mod:supports("hooks", "battle.charge_required") then
  mod.hooks:wrap("battle.charge_required", function(next, ctx)
    if myOptions.instantChargeMoves then return false end
    return next(ctx)
  end)
end
```

The context has `battle`, `user`, `target`, `move`, `charge = true` and
`isCalled`. `next(ctx)` returns `ctx.charge`. Only an explicit false skips the
charge; nil, zero and other values retain it, as in the reference engines.
Setting `ctx.charge = false` before `next(ctx)` is another way to bypass.

The native pipeline invokes the hook only when it would otherwise enter a
first charge turn. Regular moves, releases and native sunny SolarBeam skips do
not invoke it. It cannot force a charge turn for an ordinary move or override
a native weather skip. Called moves set `isCalled = true` and keep their
existing caller-owned PP semantics.

A bypass continues ordinary native damage/effects on the same turn. It stores
no charge continuation or semi-invulnerable state. GBA's queued move animation
uses the release branch (`moveTurn = 1`). A delegated charge retains native
continuation, invulnerability, charge text and animation; release clears that
state and does not spend a second player PP. No subscriber means the engine
does not call Runtime for this seam. Unsubscribe and failed-entry rollback
restore this path. Wrapper errors retain normal hook-bus recovery; repeated
API-3 `next` calls reuse the downstream verdict.

API 3 and Gen2Recomped's API-2 unified mode expose common move/actor records.
Legacy native IDs and object layouts remain engine-specific; forward opaque
battle handles and use API 3 for portable field access. The producer does not
translate the whole battle implementation into the other engine's layout.

## Validation and remaining native differences

`examples/portable_charge_required` has no engine imports. The same entry is
loaded through both SDKs. The shared harness drives the actual GB
`BattleState:performMove`, Gold `Battle:useMove` and GBA `Engine.resolveMove`
paths in Gen1Recomp, and Gen2Recomped's native `BattleState:performMove`.
Fixtures supply native data/cache records; the hook producer, verdict,
charge state and damage pipeline are not mocked.

Tests cover SolarBeam, Fly, Dig, Razor Wind, Skull Bash and Sky Attack, player
and enemy actions, release, caller PP, native sunlight, context/ID formats,
false versus nil/zero, errors, API-3 replay, unsubscribe, genuine no-mod cases
and failed-entry rollback. Native tests cover every registered host, SDK mode,
DS exclusion and the GBA release animation branch.

This proves the tested public decision contract, not identical damage amounts,
text, all move side effects or every underlying battle rule. With the automatic
ruleset selection, Gold/Silver/Crystal now use `gen2_finite_pp`: ordinary enemy
moves spend one PP, as in the reference. Explicit saved `gen1_faithful` still
keeps unlimited enemy PP. The checker records raw `native_policy` costs and
`--require-native-policy-parity` compares them exactly; the enemy-PP workflow
requires that stricter mode in all four SDK configurations. Secondary move
effects remain host-owned, including Skull Bash's defense increase. See
[automatic rulesets and enemy PP](native-ruleset-defaults.md) for the bounded
correction and existing-settings behavior.

```sh
luajit tests/engine/charge_required_contract.lua
python3 tools/charge-required-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified \
  --report /tmp/charge-required.json
```

The reference is pinned to
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Red/Blue/Yellow,
Gold/Silver/Crystal and FireRed/Emerald are compared in four SDK modes.
Gen1 API 2 has no unified opt-in; that run compares Gen2's adapter against
Gen1's native callback. Imported-data native smoke checks remain bounded;
they do not establish full-playthrough, whole-battle or pixel parity.
