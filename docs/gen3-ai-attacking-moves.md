# Native GBA AI attacking-move predicates

`if_user_has_attacking_move` and `if_user_has_no_attacking_moves` now run in
the native GBA AI interpreter. They inspect exactly four current user move
slots and check whether a non-NONE move has a nonzero declared power.

The test is independent of remaining PP, Disable, Taunt, considered move,
move category, chosen target and opposing/partner moves. A power-one fixed
or variable-damage move counts as attacking; a fifth slot never counts.
Current battle moves take precedence over the persistent learned list, with
a mon-list fallback when no separate current list exists. Named imported
records and physical numeric indices resolve live metadata. Missing nonzero
move definitions raise an error, preserving the source boundary; a known
attacking move short-circuits before later invalid slots. Reads do not change
battle data, reveal history, invoke hooks or consume RNG.

Other missing opcodes remain gated. This is an internal native-AI contract,
not a new public API or a complete move-selection/battle parity claim.

Primary references:
[FireRed AI commands](https://github.com/pret/pokefirered/blob/master/src/battle_ai_script_commands.c),
[Emerald AI commands](https://github.com/pret/pokeemerald/blob/731ad5bfd6e6f265508d0efcca0ba42f9dcf5881/src/battle_ai_script_commands.c).

## Reproduce

```sh
luajit tests/engine/gen3_ai_attacking_moves.lua
python3 tools/gen3-ai-attacking-moves-contract-check/check.py --gen1 /path/to/gen1
```

The checker pins clean upstream Gen1Recomp dev
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. These two source predicates already
implement the native rule; no counterpart production fix is needed. The same
fixture file runs through both actual interpreters with equivalent declared
move rows. No ROM, generated assets or graphical process is required.

The shared matrix checks all 256 byte power values in each of four slots,
all user positions, target independence, current versus learned moves,
sparse slots, zero PP, NONE, extra slots, short-circuit order, missing-record
errors, read purity and no RNG. Ordinary nonempty/usable contexts execute
actual VM programs. Empty or all-zero-PP contexts have no native considered
move, so they exercise each engine's actual opcode dispatch directly; this
does not invent an ordinary decision for an unusable board.

## Local validation

- Host focused checks: **21,264/21,264**.
- Source workers pass **8,528** checks each; **4 workers / 4,272 paired
  observations** match for FireRed/Emerald, with no differences.
- Unchanged host main is a negative control: **4,256** failed assertions and
  **2,136** differing observations per profile.
- Full feature run: **65/75** engine suites, SDK **3/3**, B30 passes. Its exact
  **27 FAIL lines in ten suites** match clean main (**64/74**).
- Authored Lua formatting, workflow lint and diff checks pass.

Reports remain in ignored `tmp/ai-attacking-moves-qa/` and external QA logs.
These are bounded CPU VM/opcode checks. Native controller, full gameplay,
complete stock-AI and graphical equivalence remain separate work.
