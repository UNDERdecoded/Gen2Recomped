# Native GBA Beat Up party strikes

Beat Up (Gen-3 effect 154) calculates a separate hit for each healthy,
non-egg party member. It reads that member's level and species base Attack,
and the target species' base Defense; the active battler's ordinary combat
stats, STAB and type effectiveness do not substitute for those values.
The ordinary multi-hit calculator previously reused one ordinary damage
result for the entire party.

The native path reads the party after accuracy and rechecks eligibility
between hits. Mod callbacks can wake, poison, faint or change the species of
upcoming participants. The current user's live HP/status takes precedence
for its party slot. Each hit applies Helping Hand before its own native
critical and variation rolls. Ordinary `battle.damage` and `battle.crit`
callbacks do not run for this dedicated command. Accuracy and interruption
hooks remain active, and owned PP is consumed once.

Remaining participants continue after breaking a Substitute and stop when
the target faints. Substitute event amounts are clipped to its remaining
HP. The source's scripted event metadata is retained: special damage,
neutral multiplier and `crit=false`, including when the actual hit was a
critical. Special counter memory keeps the last non-Substitute strike,
including zero HP loss under Endure, rather than summing the entire move.
Earlier-generation fallback behavior remains separate.

## Reproduction

```sh
luajit tests/engine/gen3_beat_up.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --report /tmp/enemy-action-report.json
# With the canonical public effect adapter (#121) integrated:
luajit tests/beat_up/public_effect.lua
```

The composed public patch uses canonical `EFFECT_BEAT_UP` (semantic 154);
`BEAT_UP` is a native move name, not that public effect ID.

The shared API-3 consumer is loaded through each engine's real mod SDK.
FireRed and Emerald comparisons use unchanged read-only Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, all four user positions and
six mixed party members. Cases include filtering, empty/blocked parties,
per-member base/level rounding, independent critical rolls, low variation,
Helping Hand, type/battle-stat independence, Protect, sleep, hidden targets,
misses, Substitute, K. o., Endure and changes inside public callbacks.
The active target species is read separately from its retained party species,
while an attacker's transformed species does not replace the party-member
Attack operand. These cases seed the native battler fields; they do not claim
the entire Transform animation/controller path.
A second shared entry patches MEW's base Attack through the public content
API and verifies that the actual native executor consumes that patch.

The focused suite passes **1,330 checks**. The full shared comparison passes
**40 isolated workers / 4,486 paired observations**, including the existing
action, target, Follow Me, Helping Hand and Spit Up contracts.
The full local quick run passes **88/97 engine suites** versus **87/96** on
clean #203; exact Counters of all **25 inherited FAIL lines across nine
suites** match with no additions. SDK 3/3 and B30 pass. The unchanged #203 host fails 168
assertions in the new FireRed cases. Both sides use JIT-enabled LuaJIT v2.1
commit `a4c064539ea931274d407e1249b4bb575424a0f4`, as pinned in the contract
workflow. RNG observations normalize native critical/variation operands;
they do not claim a complete raw engine RNG trace.

This change stacks on #203. `BEAT_UP_EFFECT.rev = 1` intentionally changes
the fixture fingerprint from `397df21576af62f1` to `d518411055f17444`, and
only its `move_effects` section from `c62807cde682a669` to
`f45a80ce5e45ef42`. Removing only that revision restores the prior digest;
all six other populated sections remain unchanged.

The native adjustment schedule for Focus Band, joined multi-trainer/link
parties, intro/tutorial controllers, animation fidelity and full gameplay
are separate remaining acceptance surfaces. Synthetic imported-shaped rows
and ordinary side parties are used here; a complete ROM playthrough or all
held-item/controller parity is not claimed. Gen1 remains read-only and
requires no source change or publication.
