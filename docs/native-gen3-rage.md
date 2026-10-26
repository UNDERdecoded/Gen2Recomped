# Native GBA Rage state and move-end boosts

The shared legacy Rage handler installs `rageMove`: it locks later choices and
can exempt a continued move from PP. GBA Rage instead owns a boolean `rage`
state. A separately selected use spends its learned PP, and the player can
choose another move, item, switch or escape.

The native builtin adapter activates Rage after successful accuracy and before
damage/type handling. Accuracy misses, Protect and absorption clear it; type
immunity after accuracy retains the native flag. A cancelled same-Rage action
preserves the previous flag, and called moves retain their native PP bypass.
Known authored Rage effects do not require cartridge indices to activate.

Rage raises the defender's Attack once at the completed incoming move boundary,
after public hit/secondary events and before move-end item reads. The native
guards require a living opposing defender, a landed positive-power attack and
Attack below +6. Substitute and zero HP loss under Endure still count. Ally,
self, missed/ineffective and residual damage do not build Rage. An ordinary
multi-hit attack builds it once, including after a Substitute breaks; a later
immunity prevents the boost.

The actual planners clear Rage for a different effective choice before actions
and turn-start observers, including Encore-forced choices. Native double choices
are resolved once and reused. Spent non-move actions prepare one enemy reply
before Rage cleanup, including successful escape cleanup and capture replies.
Switches and Baton Pass do not transfer the flag. Older generations and explicit
legacy `rageMove` controllers retain their existing behavior.

Native AI STATUS2 queries read bit `0x800000`. Changed Rage state invalidates an
old offered mod command. Host builtin adaptation occurs per dataset before mods
capture/delegate `afterDamage`; complete authored overrides keep their own policy.
The native accuracy-stage callback is private (`gbaAfterAccuracy`), not a new
portable public effect stage.

## Dependencies and compatibility

This feature stacks on #222 and includes the already published #188 native
AI/order prerequisite. The separate clean prerequisite checkout is
`fa5cb30ec4050980dc940e2181d6943a9de669b4`: #222 plus #188, preserving held-item
reads, original declared actions, Encore and cached native enemy selections.
The combined fork already contained #188; it is not applied twice there.

GBA command revision is **7**, native party codec remains **1**. Active hashes
include Rage and treat false/absent as the same inactive state. Revision 6 is
refused before party exchange. The raw fixture digest changes from
`a7db0874db78aec0` to `dcc938191b0bb075`, independently calculated with the
unchanged #222 hasher and only the command token changed from 6 to 7.
Older-generation goldens were not reblessed.

## Accepted validation

Feature runtime: `03c4a841ee327d232ca504a1ae5df1c5159064b6`.
Combined runtime: `e1a9295e57c1545ec69deec2c4541a4da193b7b6`.
Gen1 remains clean, unchanged and read-only at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. No Gen1 development or publication
is performed.

- **796 focused checks** pass: 584 native command/planning/lifecycle, 122 host
  public-command/composition/reply/legacy and 90 actual link/compatibility checks.
  Native protocol and the reused native AI/order regression suite also pass.
- Both clean runtimes match Gen1 in **104 workers / 75,210 paired observations**.
  The new Rage mode adds **357 complete rows per FireRed/Emerald profile**,
  retaining every bounded RNG call/value, accuracy-hook state, move/damage event,
  all battler HP/PP/status/substitute HP/Attack/last move and native/legacy flags.
  Cases cover all four actor slots, activation/failure/cancellation/called/custom
  moves, repeated PP, opponent/ally/self attacks, ordinary multi-hits, stage caps,
  Substitute/Endure, later immunity, residuals, actual planners and Encore choices.
- Move planning compares actual turn-word preparation with fixed choices. The
  non-move planning observations begin with the same explicitly prepared word;
  they compare the actual committed reply/cleanup boundary. Original unmatched
  planner reports remain retained. This does not certify earlier/global enemy
  selection, capture/escape RNG orchestration or all controller timing.
- Full feature: **123/132 engine suites**, SDK **3/3**, B30 passed. The exact
  Counter of all **25 inherited FAIL lines across nine suites** equals the clean
  #222+#188 prerequisite (120/129). The full command retains its nonzero exit.
- Combined: **243/243 engine suites**, SDK **3/3**, B30, the same complete
  comparison and all four imported smoke scenarios pass. Changes after the
  runtime snapshots only record validation/publication.
- The unchanged prerequisite fails all **four** assertions of the same public
  selector/delegated-native continuation: no native flag, a legacy lock, only one
  PP spent across two uses, and a locked menu. Raw negative output is retained.
- Two real link roles complete four turns: Rage twice, one side choosing a
  multi-hit while the other retains Rage, then both selecting Tackle. All paired
  completed hashes/components, PP and Attack stages agree. The whole incoming
  multi-hit increases Attack once; the cleared owner gets no stale boost.
- Four CPU-only scenarios using actual local FireRed/Emerald imports pass public
  FIGHT/move submissions, repeated Rage PP, alternative Tackle and the actual
  committed item-reply pipeline. Imported Rage is move 99 / effect 81; PP goes
  20 to 18. Accuracy/power/type/PP are retained with controlled valid hit rolls.
  No ROM/cache/save data is distributed and no normal SAVE is issued. The item
  test starts at the spent-item callback, not a full bag/healing playthrough.
- Scoped StyLua, actionlint and whitespace checks pass.

Host content overrides/delegation are tested separately from native default
behavior in the shared checker. An additional synthetic Gen1 GBA content probe
could not retrieve `RAGE_EFFECT`; its raw failure is retained. This is not proof
of effect-catalog ID/delegation equivalence across engines and needs a separate
catalog/fixture audit. The public event views used by contract tests are detached;
controlled live fixture mutations do not assert event-view write-through.

```sh
nice -n 19 "$LUA" tests/engine/gen3_rage.lua
nice -n 19 "$LUA" tests/engine/gen3_rage_continuation.lua
nice -n 19 "$LUA" tests/engine/gen3_rage_link.lua
nice -n 19 "$LUA" tests/engine/gen3_battle_protocol.lua
nice -n 19 python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --gen2 . --lua "$LUA" \
  --report /tmp/rage-contracts.json
nice -n 19 env LUA="$LUA" \
  LUA_INIT='io.stdout:setvbuf("no"); io.stderr:setvbuf("no")' \
  bash scripts/test.sh --quick
```

Use the workflow's maintained LuaJIT pin
`a4c064539ea931274d407e1249b4bb575424a0f4`. Private evidence is retained in
`tmp/rage-qa/`, including accepted full/comparison/import logs, exact baseline
FAIL-Counter evidence and negative/exploratory reports. Combined evidence is in
`tmp/rage-full-accepted.log`, `tmp/rage-contracts-accepted.json`,
`tmp/rage-imported-accepted.log` and `tmp/rage-accepted-evidence.json`.

Broader canceller ordering, all full/custom/delayed scripts, Ruby/Sapphire
per-hit scheduling, complete content-catalog parity, all AI/item/capture/escape
controllers, whole-game RNG/VBlank, rendering and full playthroughs remain work.
Hosted CI is reported separately in the published PR.
