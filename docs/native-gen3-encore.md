# Native GBA Encore

This branch stacks on #218. Gen1 is an unchanged read-only reference.

Encore records its target's last known move and original slot. It rejects
Struggle, Encore, Mirror Move, unknown/removed moves, exhausted slots and an
already-active Encore after the native accuracy check. A successful command
draws `0..3` and stores three to six residual phases. Known authored moves do
not require a cartridge index. Existing custom handlers and older-generation
policies retain their execution paths.

Turn planning uses the forced move's priority while preserving a chosen
target. An Encore applied after planning also changes the queued action,
recomputing its target with native bounded draws and redirection. Execution
spends the actual learned slot's PP, preserves called-move PP rules and emits
the actual move through public events. Forced FIGHT returns a native move
instance rather than an unrecognized nested descriptor.
`battle.turn_started` retains the original declared action. A planned action
also retains its PP binding if Encore is cleared before execution.

Actual residual processing cancels Encore on expiry, depleted PP or a changed
original slot. It does not transfer through Baton Pass. Link state components
include move, slot and duration. Native command revision 4 refuses older battle
rules before party exchange; the native party codec revision stays unchanged.
The raw fixture changes from `c2a03195bc4588f9` to `8be423c61a4477a2`, audited
with the unchanged #218 hasher and only the explicit revision token.

Focused commands:

```sh
LUA=/absolute/path/to/pinned/luajit
"$LUA" tests/engine/gen3_encore.lua
"$LUA" tests/engine/gen3_encore_continuation.lua
"$LUA" tests/engine/gen3_encore_link.lua
"$LUA" tests/engine/gen3_battle_protocol.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /absolute/path/to/clean-reference --gen2 . --lua "$LUA" \
  --report /absolute/path/to/report.json
```

The shared matrix retains every bounded RNG call, PP/HP for all battlers,
move/slot/timer state and public move events, including their actual target.
The reference's `expEncore*` fields and numeric move IDs are mapped explicitly
to the host's native fields and fixture registry IDs. Failed/raw reports remain
under `tmp/encore-qa/`; the checker never edits source code or filters calls.

The public-choice/planning cases start with the same explicit prepared
Quick Claw word. The combined fork's C-validated native AI-order controller
prepares that word earlier than Gen1's standalone command; the original failed
comparison retains that extra `0..65535` call. This is an input-state boundary,
not proof that the engines' complete selection/RNG orchestration agrees. The
comparison retains every subsequent bounded draw and records the prepared word.

## Validation

Clean feature runtime `6998a429a99dcc94d3f7c8b9a337ddfbcdaea3ba` passes:

- **637 focused Encore checks**: 480 command/lifecycle, 99 public-command/
  queue/authored-policy/legacy checks, and 58 actual link/compatibility checks.
  The native protocol suite also passes 154 checks.
- **92 workers / 61,356 paired observations** agree with clean Gen1
  `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The new mode retains 612 complete
  observations per profile, including all four slots, all duration draws,
  native failure guards, custom moves without cartridge indices, actual
  residual expiry/slot edits, called moves, late retargeting, public choices
  and cancellation after planning. No compared observations or calls are removed.
- Full ROM-free feature run: **113/122 engine suites**, SDK 3/3 and B30.
  The exact Counter of all **25 inherited FAIL lines across nine suites** equals
  clean #218 (110/119); the combined fork carries their independent repairs.
- The same public canonical command on unchanged #218 returns three phases
  and no slot binding, failing both native assertions. Its raw state/failures
  remain in `tmp/encore-qa/negative-command.log`.
- Both link roles complete three ordinary native turns: Tackle, a faster
  Encore overriding the queued opposing Encore, then an independently selected
  Scratch overridden again. Actual PP ownership and every paired completed
  turn hash/state component agree. Older rules are refused even with an equal
  custom fingerprint.
- Actual local FireRed/Emerald records pass four CPU-only scenarios: the public
  canonical enemy selector applies Encore, then public FIGHT or a separately
  selected move runs a real turn. The bound Tackle slot spends PP once and the
  actual residual scheduler ages the timer. No ROM/cache assets or saves are
  distributed, and no normal SAVE is issued.
- Scoped StyLua, actionlint and whitespace checks pass.

Clean combined runtime `ae385bae803e8a94eb4b2c73e2c1425d1a68868d` passes all
**234/234 engine suites**, SDK 3/3, B30, the same 92/61,356 comparisons and the
same imported-record smoke. Integration preserves the existing native AI-order
word preparation and both preselected double-battle enemy actions. Its first
unprepared-input mismatch is retained in `tmp/encore-contracts-first.json`.

These CPU fixtures do not certify a complete playthrough, GPU/pixel equality,
global RNG/VBlank orchestration, or every other native state producer and its
interactions (including legacy repeated-move controllers). The broader native
alignment goal remains open. Publication and hosted-CI status are recorded in
the PR and the combined testing document.
