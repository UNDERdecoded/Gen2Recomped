# Native GBA Baton Pass continuation

This development branch stacks on #217 and the existing held-item phase work
in #165/#166. Gen1 remains an unchanged, read-only reference.

The native move selects a healthy, non-egg replacement from its owner's
party, transfers stages and the native Baton Pass volatiles, emits the public
switch event, and applies switch-in effects. NPC selection follows the native
type heuristic, including its bounded RNG call in doubles. Player selection
uses the actual generation-specific party screen and cannot be cancelled.
Queued attacks resolve against the new occupant rather than the retired donor.

Linked players transmit their actual mid-turn selection using a validated
turn/order/owner packet. Early reliable-ordered packets are buffered; identical
duplicates are idempotent, conflicting or invalid choices reach the controller
failure path. Spectators consume the same choices without opening a personal
picker. Disconnects remain serviced while the party screen owns input.
The picker uses clamped link-party copies rather than the persistent save party.

Native command revision 3 prevents older rules from entering a full GBA battle.
The raw fixture changes from `cf73a8e083fb8a54` to `c2a03195bc4588f9`, audited
with the unchanged #217 hasher and only the explicit revision token. Native
party revision 1 and older-generation fingerprint goldens remain unchanged.

Focused commands, using the maintained pinned LuaJIT described in the contract
workflow:

```sh
LUA=/absolute/path/to/luajit
"$LUA" tests/engine/gen3_baton_pass.lua
"$LUA" tests/engine/gen3_baton_pass_ui.lua
"$LUA" tests/engine/gen3_baton_pass_link.lua
"$LUA" tests/engine/gen3_baton_pass_packets.lua
"$LUA" tests/engine/gen3_baton_pass_composition.lua
"$LUA" tests/engine/gen3_battle_protocol.lua
"$LUA" tests/engine/ui_actions.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /absolute/path/to/clean-reference --gen2 . --lua "$LUA" \
  --report /absolute/path/to/report.json
```

The shared fixtures execute both real move resolvers and the real NPC selector.
They retain all RNG calls, PP/HP, stages, volatile state, seed-source identities
and public switch events. Reference names live on `mon.nickname`; reference
infatuation has a separate active flag and owner pointer, whereas the host's
pointer is the active state. These are explicit schema mappings. Original
failed comparison reports are retained locally.

Validation at clean runtime `d5ad56afccca21d107f21b5b561b908fa650e59e`:

- 915 focused Baton Pass checks pass: 654 command, 52 actual party UI, 72 link/
  spectator/disconnect, 95 packet/signature/compatibility and 42 authored-effect/
  called-move checks. The 154 native protocol and 3,002 existing UI checks pass.
- All 88 workers / 60,132 paired observations equal clean Gen1
  `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The new mode has 156 complete
  observations per profile, including actual commands, resumed selections,
  called moves, all four slots, seeds/infatuation, excluded/reserved members,
  one/two/three Spikes layers and the real NPC type selector with empty PP.
- Full feature regression is 110/119 engine suites, SDK 3/3 and B30. The exact
  Counter of all 25 FAIL lines across nine inherited suites equals clean
  prerequisite `c27c37a667e8a40613c22506448ab4886fc9b431` (105/114). Their
  independent repairs are present in the combined fork.
- Combined runtime `86b12d7b7a816a2782ba5cfba804b103630eda5b` passes all
  231/231 engine suites, SDK 3/3 and B30, plus the same clean-reference
  comparison and imported-record smoke. Its existing 4,849 party-navigation
  checks remain green. Ordinary link screens follow live/late-installed battle
  rosters; forced owner-specific choices retain the explicit party.
- The same public canonical selector on the clean prerequisite spends PP and
  sets `wantsSwitch`, but leaves the donor active. Its failing assertion and
  raw state are retained. The initial Baton implementation also fails the
  later nested-choice item-phase checks; the fix suspends ancestor frames.
- Actual locally imported FireRed/Emerald records select canonical
  `BATON_PASS` through the public enemy-action mod, then exercise the real
  party screen and queued turn with the third member selected. Both profiles
  retain stages and spend native PP once. This is a CPU-only imported-record
  smoke; no ROM/cache assets or saves are distributed.

Evidence is retained under `tmp/baton-pass-qa/`, including complete failed and
accepted reports. Combined-fork acceptance and hosted workflow status are
recorded separately in the combined testing document and the published PR.
CPU fixtures do not certify GPU animation, pixel equality, a complete
playthrough, global RNG/VBlank scheduling or all native side/volatile producers.
