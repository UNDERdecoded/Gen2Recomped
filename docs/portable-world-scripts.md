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
version selections (Gen 1–5). Flags, items/Pokémon, world movement/warps,
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
