# Native GBA order prediction and planning

The native AI commands `if_user_goes` and `if_user_doesnt_go` compare the
literal result of `GetWhoStrikesFirst(user, target, TRUE)` with their operand.
They do not select a battler through that operand. Result 0 means the user
goes first, 1 means the target has greater speed, and 2 is the odd random
result of an equal-speed tie. The inverse compares for inequality.

This adds both commands and makes actual GBA move planning share their speed
arithmetic: weather before integer stage division, native third-badge policy,
Macho Brace, paralysis, and the strict Quick Claw threshold. Speed can be zero.
Enigma Berry uses the physical holder's per-battler berry definition. Living
Cloud Nine or Air Lock holders suppress weather, including either right-hand
slot in a double battle. AI prediction ignores chosen move priority; actual
planning applies it before resolving equal-priority speed ties.

A single unsigned 16-bit word is prepared before enemy selection, reused for
both holders and actual planning, and released after planning or end of turn.
No query samples another Quick Claw word. Both successful claws set their
holder's speed to UINT32_MAX and therefore tie rather than favoring one side.
The native strict threshold can fail even at a 100-percent parameter when the
stored word is 65535. The existing actual comparator RNG interface stays
`rng(0, 1)`; AI tie queries use `rng(0, 65535)`. This tests native decisions and
draw placement, not bit-for-bit equivalence between different RNG algorithms.

Double battles compare each later pair in the native nested i,j order. Item
and switch choices form a stable position-ordered prefix and do not undergo
speed comparisons. Both enemy choices precede new-turn flag reset. The public
`battle.turn_order` chain remains active per real comparison and honors
arguments forwarded by a wrapping mod. Actual priority item reads keep the
held-item extension seam; AI reads use physical metadata.

## References and validation

The primary references are `GetWhoStrikesFirst`,
`SetActionsAndBattlersTurnOrder`, and the surrounding action-selection/turn
transitions in:

- [FireRed at ce6406d8](https://github.com/pret/pokefirered/blob/ce6406d8c2eaf46d543c8a2606de0c3cb1951982/src/battle_main.c)
- [Emerald at 731ad5bf](https://github.com/pret/pokeemerald/blob/731ad5bfd6e6f265508d0efcca0ba42f9dcf5881/src/battle_main.c)

Run the ROM-free focused suite with:

```sh
luajit tests/engine/gen3_ai_order.lua
```

The matrix executes real Gen2Recomped AI programs for both profiles over all
13 speed stages, rounding boundaries, weather masks, suppressors, badge modes,
status words, per-battler Enigma data, Quick Claw boundary words and literal
comparison operands. It also invokes the owned comparator and sorter. The
oracle compiles the original C function from pinned, read-only decompilation
checkouts. It validates the function's SHA-256 before adding observations of
its local speed variables; no native function or ROM content is copied into
this repository. The authored shim supplies declared native input data and
the relevant item, flag, weather-ability and RNG interfaces.

```sh
python3 tools/gen3-ai-order-check/check.py \
  --firered-main /path/to/pokefirered/src/battle_main.c \
  --emerald-main /path/to/pokeemerald/src/battle_main.c \
  --report /tmp/gen3-ai-order/records.json
```

The oracle covers 262 cases per profile: 5,240 actual VM queries, 524 actual
pair comparisons and 524 sorts in total. A separate real `BattleState` fixture
constructs battles, selects via a registered enemy-action consumer, plans and
executes ordinary single/double move queues, then advances through end of turn.
It covers word reuse/renewal, both claws, priority, right-slot weather abilities,
real save badge flags and forwarded hook arguments. Metadata cases inspect the
actual queued entries; complete trainer item/switch controllers are outside
that fixture's scope. Validation is CPU-only and does not claim a graphical
playthrough or complete stock AI semantic coverage.

This PR is for Gen2Recomped only. It requires no change, PR, or patched checkout
of Gen1Recomp. Gen1Recomp remains a read-only portability reference; its existing
speed-only predictor is not treated as a native correctness oracle. Existing
non-GBA ordering policies stay on their original path.
