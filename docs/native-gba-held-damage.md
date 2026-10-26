# Native GBA held damage commands

The ordinary GBA calculator previously read the attacker's held effect twice:
once for stat items, then again for type items on finished damage. A stateful
`held_item.trigger` consumer could therefore supply incompatible answers inside
one native command. Type boosts also rounded at the wrong point.

Resolve attacker and defender held effects once per base-damage command, in
that order, and reuse the attacker answer. Apply type/stat item modifiers before
stat stages, using the current battler species. Share the native pre-stage
ability modifiers with ordinary and scripted set-damage commands. Preserve GBA
stage flooring and critical-stage bypass; apply pinch abilities and sports to
power for ordinary attacks and Flash Fire before the final base `+2`. Preserve
Spit Up's separate opcode, which does not forward field sport flags. Other profile paths retain
their existing code.

Native GBA empty hands expose `item = 0`, including the public callback view.
Zero is a native sentinel, not a content registry item. Other generations and
ordinary saved-mon item views retain their existing semantics.

This stacks on #228. Gen1 remains a clean, read-only reference at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; no Gen1 source is patched or published.

## Validation and reproduction

Accepted full-test runtimes are feature
`9ad4f6ab90524eda893d0d6dbfb6f12ab71f9e9f` and combined
`7a681ca8b81be0e77d3447ff3069459cda0bb974`. Later commits only apply
AST-verified fixture formatting and document acceptance/publication. The
formatted fixture is checked again against both engines on clean commits.

- **10,202 focused assertions**, **48 real-link assertions** and the feature's
  **154 protocol assertions** pass. Both linked roles select the GBA profile,
  complete two menu-driven turns, observe matching ordered reads and agree on
  every completed hash/component and real learned PP.
- **124 workers / 86,620 paired observations** agree with unchanged Gen1:
  2,040 held-command rows, 6,912 ordinary base-damage rows and the existing
  77,668 selection/execution observations. The new matrix includes sport-before-
  pinch flooring, Flash Fire, Charge and stateful successive commands.
- Full feature: **132/141 engine suites**, SDK **3/3**, B30. The exact Counter
  of **25 inherited FAIL lines in nine suites** equals clean #228
  `491d3a2f0b997f8f5c801ebcd12524e70ba5cf54` (130/139); its nonzero exit is
  retained. Combined: **251/251 engine suites**, SDK **3/3**, B30.
- The unchanged prerequisite fails **2,041 assertions per profile**, with all
  1,020 complete command rows differing. The additional isolated sport/pinch
  probe retained 24 differing rows across both profiles, including native 42
  versus host 44 damage; corrected ordering passes.
- Twelve existing CPU-only imported FireRed/Emerald Sleep Talk scenarios pass
  again on both branches. These are regression checks of actual loaded attack
  metadata and public menu submissions, not certification of the entire item
  catalog. No assets or normal SAVE are distributed/issued.
- Scoped StyLua (including AST verification), actionlint and whitespace pass.

The shared fixture executes the actual calculators and public API-3 hook chains
in both engines. It compares every recorded read field, ordered actor identity,
calculated damage, bounded RNG call/value and HP observation. Inputs include
empty hands, native stat/type items, species restrictions, stages, criticals,
ability combinations, burn, weather, screens, public substitutions/suppression
and a stateful answer changing between consecutive commands. Fixtures own their
in-memory inputs; no comparison rows or RNG calls are filtered.

```sh
nice -n 19 "$LUA" tests/engine/gen3_held_damage.lua
nice -n 19 "$LUA" tests/engine/gen3_held_damage_link.lua
nice -n 19 "$LUA" tests/engine/gen3_battle_protocol.lua
nice -n 19 python3 tools/held-damage-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 "$PWD" --lua "$LUA" \
  --report /tmp/held-damage-contracts.json
nice -n 19 python3 tools/gba-damage-base-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 "$PWD" --lua "$LUA" \
  --report /tmp/ordinary-damage-contracts.json
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 "$PWD" --lua "$LUA" \
  --report /tmp/enemy-contracts.json
nice -n 19 env LUA="$LUA" bash scripts/test.sh --quick
```

Local evidence is retained under `tmp/held-damage-qa/` in each worktree:
`full-complete.log`, `enemy-complete.json`, `held-complete.json`,
`base-complete.json`, `held-formatted.json`, `imported-complete.log` and
`accepted-evidence.json`. Feature evidence also retains baseline/negative,
initial mismatched-fixture, set-damage gating, link-profile and formatting
failures. The clean prerequisite's full log is in the Sleep Talk worktree's
`tmp/sleep-talk-qa/held-damage-baseline-full.log`.

The native command revision is 10; peers at revision 9 cannot enter a full
battle. Party codec remains 1. The native fixture hash changes from
`f1bec52ffc687ea3` to `3a2adb7fa1caee3b`. An independent copy of the unchanged
parent hasher with only the revision token changed produces that result; GB,
GSC, DS and BW fixture hashes remain `e33d251961f2a41d`.

## Remaining boundaries

This is base-command parity, not complete held-item script parity. The full
Sleep Talk attack trace still differs: the Choice Band check/binding is absent
and King’s Rock/Shell Bell still run separate reads. Equal total read counts do
not establish ordered payload equality. Keep the raw full-phase failure probe.
Failed awake/empty Sleep Talk and blocked ordinary-move traces are separate.

Unbadged controlled inputs are compared here. Full badge/obedience/controller
orchestration, arbitrary imported catalogs and playthrough/graphics parity are
not established by these calculator tests. The real-link fixture must explicitly
select its GBA profile: the generic link helper creates a Red save with Gen1
options. On this isolated command stack, a fresh-save probe reproduces
`gen1_faithful` for `SaveData.newGame({version = "firered"})` and Emerald.
The existing [#162 automatic-default fix](https://github.com/UNDERdecoded/Gen2Recomped/pull/162)
already resolves this and is integrated in the combined fork: the same probe
there selects `gen3_emerald` for both games. Its 926-check regression suite
also passes, including preservation of explicit selections. No duplicate
defaults fix is needed. These calculator/link fixtures explicitly select GBA.

Historical held-item workflows using a modified reference are not proof against
unchanged Gen1. The new damage comparison pins the clean reference above.
