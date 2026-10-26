# Portable dialogue scripts

API-2 mods can opt into a bounded, prevalidated language for
`mod.world:queueScript(rows, options)`:

```json
{
  "id": "quest_dialogue",
  "name": "Quest dialogue",
  "version": "1.0.0",
  "api": 2,
  "entry": "main.lua",
  "script_format": "unified"
}
```

Check `mod.scriptFormat == "unified"` in the entry file. Older engines may
ignore unknown manifest fields; checking the marker prevents a portable row
list from silently reaching their native script runner. Omitted or explicit
`"native"` formats preserve existing API-1/API-2 queueScript behavior. Other
values, or API 1 with `"unified"`, are load errors. Content and callback format
opt-ins are independent. The engine's Mod API major remains 2.

## Contract

```lua
return function(mod)
  assert(mod.scriptFormat == "unified", "portable scripts required")

  -- Run this from an idle-world interaction/update, not at entry time.
  local function offerQuest()
    local ok, why = mod.world:queueScript({
      { "ask", "Help with the quest, {PLAYER}?" },
      { "jump_if_false", "declined" },
      { "show_text", "Thank you!" },
      { "jump", "end" },
      { "label", "declined" },
      { "text", "Maybe another time." },
    }, {
      onDone = function(completed, reason)
        if not completed then mod.log:warn("Dialogue stopped: %s", reason) end
      end,
    })
    if not ok then mod.log:warn("Dialogue not started: %s", why) end
  end
end
```

Admission returns `true`, or `nil, reason` without executing any prefix of a
rejected program. The entire list, every row/argument and every jump target is
validated and copied first, including unreachable rows. Caller edits to the
original list, choice labels/options or callback options cannot change an
accepted program. Reading the facade and an early request do not construct
Game. A request with no live save/world fails quietly.

`true` means admitted, not successfully completed. After admission,
`onDone(true)` reports completion and `onDone(false, reason)` reports a runtime
failure or cancellation. It fires exactly once, including failures during the
initial dispatch. It is not called for rejected requests. A throwing completion
callback is isolated and attributed to its mod; completion is not retried.
Already entered native work is not rolled back or automatically replayed.

Only `onDone` is accepted in options. Programs and rows must be dense plain
arrays without metatables or extra keys. Functions/userdata/native handles are
not command arguments. Choice options are a closed plain table.

## Initial command set

| Row | Meaning |
| --- | --- |
| `{ "show_text", text }` / `{ "text", text }` | Native manual TextBox; wait for all pages and final dismissal |
| `{ "ask", text }` | Native text and YES/NO overlay; YES is true, NO/B is false |
| `{ "choice", labels, opts }` | Native N-way menu; choice 1 is true, every other choice is false |
| `{ "wait", frames }` | Native logic-frame wait, integer 0–36000; zero waits until the next world update |
| `{ "label", name }` | Named jump destination |
| `{ "jump", target }` | Unconditional jump |
| `{ "jump_if_true", target }` | Jump after a true answer |
| `{ "jump_if_false", target }` | Jump after false/nil, including before any answer |
| `{ "end" }` | Finish the program |

Text is literal UTF-8, up to 4096 bytes per row, without NUL. Native TextBox
placeholder substitution (e.g. `{PLAYER}`), prose pagination, typing, scroll/
page holds and answer holds remain in use. These rows do not resolve native
text registry IDs or lower ROM script bytecode. Future pages are not skipped.

`labels` contains 1–16 nonempty UTF-8 strings of at most 128 bytes each.
Optional `opts.default` and `opts.cancel` are valid 1-based indices; defaults
are 1 and the last choice. B follows `cancel`. Answers remain internal to the
program for conditional jumps; the completion callback reports success/failure.

Labels contain letters, digits, `_`, `-` or `:`, at most 64 bytes, and are unique.
`end` is reserved. Jump targets are existing labels, valid 1-based row indices,
or the string `"end"`. No arbitrary native verbs, custom command handlers,
extra callback arguments or executable rows are accepted.

A program has at most 1024 rows and 128 KiB of text/choice labels. Execution
yields after each slice of 128 instructions and fails after 65536 instructions
in total. This bounds authored jump loops without a Lua debug hook or a frame
stall; it is not a wall-clock deadline on a player reading text.

## Ownership and cancellation

Admission requires the current overworld to own the top of the stack. Native
scripts, queued/parallel scripts, movement, transitions, field animations,
input/controller locks, link sessions and another portable program decline.
Only one portable foreground program can own a Game at a time.

An accepted program temporarily installs an isolated instance of the native
ScriptRunner. Its `isRunning()` participates in the world's existing input and
script-scheduling gates. It uses native TextBox, ChoiceBox and Menu classes,
including their normal keyboard/touch handling and delayed answer completion.
The idle runner is restored at completion/cancellation, provided it has not
already been replaced by another controller. Global runner/UI classes and the
native command registry are unchanged.

`mod.world:cancelScript()` cancels only this facade's active portable program.
It returns `true`, or `false, "no portable script"`. It cannot cancel another
mod or a native story script. Cancellation removes only the run's exact native
windows, even beneath a foreign overlay, and releases its coroutine. It does
not pop unrelated screens or release another controller's locks. A covering
foreign screen pauses normal progress. Removing an awaited owned window
externally cancels at the next input-step boundary.

A replaced Game/save/data/stack/world/map/player/runner, changed map identity or
player position/version, transition, link session, mod rollback, reload or
teardown cancels the program. Session changes are checked at input-step and UI/
runner boundaries, including while the world is covered. Retained callbacks
cannot resume a cancelled program, skip a later row's wait or pop a new screen.
Facades from an unloaded/reloaded/failed mod are retired.

Native `script.started`/`script.ended` lifecycle events retain their context
shape; `source.modId` attributes the portable run and `completed` describes its
outcome. End notification/completion follow owned cleanup. Portable rows use
this validated language rather than resolving native/custom handlers or firing
`script.command` wrappers; native-format scripts retain those contracts.
Direct changes to engine objects from such event handlers or other mods remain
outside this boundary's guarantees; this is not a mod security sandbox.

When optional capability queries are installed, unified mods can probe
`mod:supports("scripts", verb)` and `mod:supports("world", "cancelScript")`.
Unknown/unimplemented portable verbs return false. The existing native
`world/queueScript` capability is not, by itself, evidence of this opt-in.

## Scope and verification

This first adapter covers dialogue/control flow across the 15 supported
version selections (Gen 1–5). Items/Pokémon, world movement/warps,
battles, shops and other Gen1Recomp portable verbs need separately verified
adapters; they refuse the complete list before the first effect here.

The contract is informed by Gen1Recomp's
[UnifiedScripts](https://github.com/bryanthaboi/gen1recomp/blob/79ea62f45fb2ea8f65d081a109431e4eb1bbdb36/src/mods/UnifiedScripts.lua).
This implementation uses this host's native shared UI and runner architecture.

Run `luajit tests/engine/portable_world_scripts.lua` and
`LUA=luajit bash scripts/test.sh`. The ROM-free suite uses the real Loader,
ScriptRunner, state stack and native UI classes. It compares complete per-frame
native/portable dialogue traces, checks preflight/argument copying, rejection
immutability, identity/session changes, replay, cancellation/reentry, budget and
native failures. Fixture runs do not establish rendered retail-ROM coverage.

When the unified content/callback PRs are also present, run
`PORTABLE_SCRIPT_ALL_FORMATS=1 luajit tests/engine/portable_world_scripts.lua`
to repeat the suite with all three format opt-ins enabled together.

## Portable flag commands

The validated language also supports:

| Row | Meaning |
| --- | --- |
| `{ "set_flag", reference }` / `{ "setflag", reference }` | Set a private/native boolean flag. |
| `{ "clear_flag", reference }` / `{ "clearflag", reference }` | Clear it. |
| `{ "check_flag", reference }` | Set the conditional result to the flag's boolean value. |
| `{ "wait_flag", reference, timeout? }` | Yield until true or until the optional timeout expires; set conditional result true/false. |

References use [API-3 flag addressing](api3-flags.md): `mod:<key>` is private to
the initiating mod, while native symbols/numbers retain their version-specific
meaning. Crystal native references remain numeric-only; unknown hack mappings
are declined. These rows are available through the unified script opt-in and
API 3. Gen1's pinned reference does not offer the host's `scripts` capability
query surface; portable API-3 mods can use the common world/queueScript query,
while host-specific tools may inspect scripts/<verb>.

Every reference, including unreachable rows, is validated and copied before
admission. All referenced save stores are checked before the first effect;
an invalid later row never permits an earlier set_flag to execute. Native and
private writes share the public flag implementation, including private ownership,
native storage, reentry protection and Gen3 visibility synchronization. Native
flag handling uses the already resolved world and never asks the loader to boot
Game.

A timeout is a whole number from 0 to 36000 logic frames. Omission waits until
signaled or cancelled. Even a zero timeout or already-set flag yields once;
on the next condition poll a true flag wins over timeout expiry. Waiting pauses
under a foreign covering screen, preserving its lifetime and timeout. Waits do
not consume the script instruction budget on every frame. Existing cancellation,
owner/session checks, one-shot completion and instruction/slice budgets apply.
A flag store that becomes malformed after admission fails the run and restores
the original runner; already executed native writes are not rolled back.

The identical public-only shared mod verifies branching, both aliases, signal
resume, timeout and complete-list refusal on both engines for eight versions.
It extends the pinned suite to 80 comparisons /160 isolated loader runs.
Local tests additionally verify detached rows, malformed stores/timeouts, paused
foreign overlays, native flag conditions and stale-session/owner cancellation.
The existing 5268-check dialogue suite remains unchanged and passing.

## Wallet, inventory and party state commands

The bounded language also accepts these synchronous rows:

| Row | Meaning |
| --- | --- |
| `{ "give_money", amount }` / `{ "take_money", amount }` | Add/subtract money; subtraction saturates at zero. |
| `{ "check_money", amount }` | Set the conditional result to whether the current wallet covers the amount. |
| `{ "take_coins", amount }` | Subtract coins, saturating at zero. |
| `{ "check_item", itemId }` | Set the conditional result to whether the bag contains the item. |
| `{ "take_item", itemId, count? }` | Remove up to count (default one), using native Bag.remove/order cleanup. |
| `{ "check_dex_owned", amount? }` | Check the owned/caught species count, default threshold one. |
| `{ "mark_seen", speciesId }` | Mark an existing species seen using the host's native storage key. |
| `{ "heal_party" }` | Heal native party HP/status and restore PP from the current Game's move data. |

Amounts are finite whole nonnegative numbers up to Lua's exact integer limit
(2^53-1). Item count is 1–999. Item/species IDs are canonical strings, resolved
through the existing loader index rather than assumed cartridge numbers.
Missing/ambiguous content, malformed referenced wallets/inventory/dex/party
stores or malformed arguments reject the complete list before any effect,
including unreachable rows. Accepted rows are detached; live stores are checked
again when dispatching after a wait. Native effects already executed before a
later runtime failure are not rolled back.

Wallet writes retain the verified Gen1 API's generation behavior: Gen2/3
addition caps at 999999; Gen1 retains its native unbounded script wallet.
Queries and item/coin removal do not create gifts or UI. Inventory and party
structures retain this host's native layouts. The optional moves argument on
Pokemon.heal lets this path use Game.data instead of an unrelated Data singleton;
existing native callers keep their default behavior.

The same public script compares branches and resulting money, coins, item
quantity, HP/PP and seen state through both native backends on eight versions.
The full pinned checker now runs 88 comparisons /176 isolated loader runs.
Host tests add malformed/unreachable-row refusal with no prefix effects, wallet
caps, saturation, actual Bag order removal, live-store failure and argument
copying. These are ROM-free runtime/store checks, not a story playthrough.

## Item and Pokemon gifts

- `{ "give_item", itemId, count?, gotText?, bagFullText? }`: use the native
  bag gift command. Count defaults to one (1–999). Optional receipt/full-bag
  text is literal UTF-8 up to 4096 bytes; `gotText=false` suppresses the receipt.
  A full bag shows its native failure message and halts before later gift flags.
- `{ "give_pokemon", speciesId, level, skipNickname?, gotText? }`: use native
  creation, OT stamping, party/box placement and nickname flow. Level is 1–100;
  the optional flags are actual booleans. `gotText=true` requests a receipt
  before the nickname question. A full party sends the gift through native box
  storage and waits for its sent-to-box text; completely full storage leaves
  the native conditional result false for the script to branch on.

The complete row list's content references, counts/options and referenced
inventory/party/player/dex/box store shapes are checked before a prefix runs.
IDs are canonical, but native bag capacities, native Pokemon fields and native
storage layouts remain the host's. Already entered native effects are not a
transaction. Scripts cannot pass executable callbacks or native options into
these rows. Gifts do not introduce new species constructors or storage slots.

The isolated runner adopts exact native screens created by the gift operation
and screens subsequently created by those owned screens. Native receipt,
YES/NO and naming callbacks receive per-operation, per-phase one-shot guards;
an old receipt/question/naming callback cannot mutate a nickname twice, bypass
a later screen or skip the next row's wait. Cancellation removes owned screens
and retains a foreign overlay. A mod retired by its before-give hook cannot
continue into native Pokemon construction. Native callers outside the portable
context retain their existing callback/default behavior.

The same public mod on both engines verifies item and Pokemon gifts with
receipt/nickname suppressed, real native bag/party/dex effects and whole-list
preflight refusal. This extends the pinned suite to 96 comparisons /192 isolated
loader runs. Host tests additionally drive actual native receipts, bag-full
messages, YES/NO, naming, box deposits, callback replay and unload/session
cancellation on synthetic data. Rendering/pixel equivalence and retail-ROM
playthroughs are not claimed. Direct mutations of engine objects by other mods
remain outside the portable runner's ownership guarantees.


## Object and block scripts

API 3 also accepts `show_object(mapId, objectRef)`,
`hide_object(mapId, objectRef)` and `replace_block(bx, by, blockId)` on
Gen 1–3. Object references must name an existing definition; Gen 2/3
require the active map. Block coordinates use the same geometry and limits
as `mod.world:replaceBlock`. Validation covers every row before any prefix
runs, then repeats against current stores at dispatch.

These rows run through the validated native edit plans under the script's
existing foreground ownership. Ordinary public world actions retain their
idle-world admission guard. Gen 1's seamless object refresh may replace
both the map and its default runner: the script continues on that map and
restores the new idle runner when finished. Foreign overlays pause the
program; unloading, changed saves/maps and invalid live stores cancel it.
Edits already committed before cancellation are retained, and public world
events follow the native edit behavior.

## Movement and facing

On Gen1–3, API 3 accepts `move_player(dir, tiles?)`,
`move_npc(ref, dir, tiles?)`, `move_npc_to(ref, x, y)`,
`place_npc(ref, x, y, facing?)`, `face_object(ref, dir, {hold=frames}?)`,
`face_player_dir(dir)`, `face(dir)`, `face_npc()` and `face_player()`.
`face` turns the talking NPC; `face_npc` turns the player toward that NPC,
and `face_player` turns that NPC toward the player. The last three require
an existing talking-NPC context. Object references resolve existing native
actors on the active map. Counts are 0–1024 cells (default 1).

All target references and argument shapes are checked before any command
runs. Paths are computed against the live walkable map at dispatch, using
a bounded search; an unavailable path fails the admitted program. Steps
use the native movement queue and walker updates. Each completion is tied
to its exact run, step and actor. Movement only permits its own expected
player position changes. Callbacks are one-shot, and continuation waits
for a foreground logic frame, so foreign overlays pause later effects.

Cancellation removes only the run's exact queued entries and leaves foreign
tracks intact. Invalid sessions/actors, refused native steps and a stalled
step (3,600 foreground logic frames) terminate the script. A native step
which crosses into a different map ends this run; use explicit `warp` for
portable cross-map scripts when supported. These limits are intentionally
reported rather than silently claiming arbitrary native movement parity.

## Explicit travel

Gen1–3 accept `warp(mapId, x, y, facing?)` and
`remember_outdoor(mapId, x, y)`. Destination names, 0-based cell coordinates,
dimensions and facing use the public API-3 warp planner. `remember_outdoor`
sets the native outdoor/escape destination without travelling.

Preflight follows the linear row list's map context, just as the reference
engine does. Object/block and movement rows after a warp are checked against
the destination's definitions; path/block geometry requires the destination
tileset to be available. These plans do not load a live map or run callbacks.
All dispatches still validate their actual live targets. Branches and native
entry scripts can change runtime conditions, so successful preflight is not
a guarantee that an admitted asynchronous program will complete.

A warp uses the native transition and arrival bookkeeping. Its continuation
binds to the destination map and idle runner only after the native arrival
callback; it never resumes beneath a foreign overlay. A busy destination
runner is preserved and the portable run fails. Talking-NPC context is
cleared at arrival. One-shot callbacks, session checks and a 3,600-frame
native-transition/foreground deadline prevent late script effects.

The transition belongs to the engine: unloading or timing out a portable
script leaves the already admitted native warp free to finish and release
its own locks. It suppresses the script continuation, rather than undoing
committed native travel or removing the engine's transition screen.

## Wild and static battles

Gen1–3 accept `start_battle("wild", speciesId, level)`,
`static_battle(speciesId, level, beatFlag?)` and
`check_battle_result(result, ...)` (1–4 of `win`, `lose`, `run`, `caught`).
Species IDs are canonical strings. Levels are whole numbers 1–100.
All species references and optional beat flags are checked before any
prefix runs. Healthy-party admission is checked at dispatch, so an earlier
`heal_party` can repair the party before the encounter.

The private script admission guard reuses the public wild-battle adapter,
native constructors, entry transition and `afterBattle`. Ordinary public
calls retain idle-world admission. A static encounter sets its optional
beat flag and hides the talking NPC on win, catch or flee; loss skips both.
Result checks set the condition used by `jump_if_true`/`jump_if_false`.
The foreground continuation waits behind native post-battle and foreign UI.

Cancelling/unloading suppresses the script continuation while preserving
native battle screens and native cleanup for the same live game/save.
Changed sessions suppress that old-session cleanup. Native constructor,
admission and cleanup errors fail the script; late callbacks are one-shot.
No rollback of already committed battle effects is implied.

Private beat flags use this host's same namespaced flag service on every
generation. The pinned Gen1 reference delegates Gen1 static encounters to
its native command, which does not route private beat flags through that
namespace. The shared Gen1 static cases therefore exercise a real native
beat flag; host-specific private-flag behavior has separate coverage.
Trainer encounters are described below.


## Trainer encounters

`start_battle("trainer", trainerRef, partyIndex?)` uses this version's native
trainer data and constructor. Gen1 normally selects a class key and numbered
party; Gen2 accepts the native class number (resolved to the host's class
record); Gen3 accepts a native trainer number through `trainerOrder`, with
one party per trainer. Existing host keys are also accepted. These selectors
are game-specific and are not universal trainer IDs. Use an explicit party
index for shared Gen2 scripts: the pinned reference requires that argument.

Preflight validates every referenced roster before a prefix runs and repeats
that check at dispatch. Unknown species, invalid levels, empty/oversized
parties, ambiguous class aliases and unavailable Gen3 flag metadata are
refused. Native class aliases select the canonical class deterministically.
Gen3 named reference constants are not guessed from display names: use the
native trainer number for engine portability.

Trainer battles share the same owned continuation, cancellation and native
cleanup lifetime as wild encounters. Gen3 wins use the host's native trainer
victory flag and Match Call registration helpers; loss does not mark a win.
Cleanup remains valid after the originating mod retires, provided the same
native session still exists. Native battle mechanics and game-specific story
rewards remain the responsibility of this host's battle/field code.

## Native marts

`open_mart(textConstant)` opens the native mart selected by the active map's
`data:textEntry(map.label, textConstant).mart` entry. Entries hold 1–99 item
IDs; canonical names and known native item IDs resolve through this boot's
item registry. Every mart row, including a row after a warp, is validated
before any prefix runs. Missing data is refused rather than guessed from
unrelated ROM pointers. Live dispatch repeats content/store validation.

The screen factory and native buy/sell/quantity/confirmation flows remain
in charge of transactions. The script waits until the root counter closes.
UI callbacks are bound to their exact active screen and phase: closed,
cancelled, superseded or retired quantity/confirmation callbacks cannot
replay a transaction. Foreign overlays block callbacks and continuation.
Nested owned screens are removed on cancellation while foreign UI remains.
A retired constructor cannot leave its late native root on the stack.

Wallet/inventory shapes, counts and prices must be representable (whole
non-negative amounts; prices at most 999,999, inventory at most 4,096
entries). Checked sale totals must fit the exact integer range. Replaced
inventories or changed item records/prices cancel an open shop before later
callbacks run. Committed native transactions remain committed after
cancellation. The same guard covers classic lists, FireRed's inline sale
quantity and Emerald's native sell bag. Closed UI records are released
between frames rather than accumulated for a long shopping session.
