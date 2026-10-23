# Portable raw input hooks

Gen2Recomped dispatches `input.key`, `input.gamepad`, and `input.wheel`
through `mod.hooks:wrap`, matching the native Gen1Recomp callbacks at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. A mod overlay can observe or
capture input without replacing engine methods or importing private modules.

| Hook | Callback arguments after `next` | Payload |
| --- | --- | --- |
| `input.key` | `game, event` | `{ phase = "pressed" or "released", key = key }` |
| `input.gamepad` | `game, event` | Button: `{ phase = "pressed" or "released", joystick = joystick, button = button }` |
| `input.gamepad` | `game, event` | Axis: `{ phase = "axis", joystick = joystick, axis = axis, value = value }` |
| `input.wheel` | `game, dy` | Original numeric vertical delta, including fractions and zero |

`game` and `joystick` retain their native identities. The joystick is an
opaque host handle, not a portable serializable record. Button events do not
include axis fields, and axis events do not include `button`. Keyboard
scancodes/repeat flags and horizontal wheel deltas are not part of this
contract.

```lua
local mod = ...
local captured = false
mod.hooks:wrap("input.key", function(next, game, event)
  if captured then return end
  return next(game, event)
end)
```

Omitting `next` suppresses the entire normal Game callback, including its
hotkeys, top-state capture, Input updates and axis transitions. It also
suppresses wheel zoom. A returned boolean has no independent consume meaning:
calling `next` and then returning `true` or `false` has already forwarded the
event. `next()` forwards the current hook arguments. As in Gen1Recomp,
`next(game, replacement)` changes what downstream wrappers see; the native
body still acts on the original callback arguments. This is not a synthetic
input API.

Releases can be captured too. If a mod forwards a press, it must also let the
matching release through or deliberately manage its capture lifecycle;
otherwise the native held state remains set. Prefer capturing complete
press/release pairs. Activating an overlay between a forwarded press and its
release needs particular care. Unsubscribing removes callbacks, not held state.

Hooks run at the live Game boundary. Launcher/importer/editor routing and
accelerometer filtering outside that boundary retain their existing behavior.
Within Gen2Recomped, existing native routing is preserved: emergency hotkeys
precede top-state key capture, releases update Input before capture observers,
and the free camera keeps its existing wheel behavior (including zero delta).
Gen1-specific gamepad polling/watchdog bookkeeping is still owned by Gen1;
this contract does not promise identical internal input algorithms.

When no hook chain is installed, calls bypass the hook bus and allocate no
hook payload or continuation closure. Existing bus priority, error handling, unsubscribe and
owner cleanup apply. Wrappers that fail before `next` are skipped; a failure
after forwarding does not replay native side effects; native errors propagate.

The hooks work with native API 1/2, unified API 2 and API 3. The central
callback and capability catalogs include them, so
`mod:supports("hooks", name)` reports availability before the mod entry runs.
This change builds on the common API-3 entry feature (PR #102).

## Verification

```sh
luajit tests/engine/portable_input_hooks.lua
luajit tests/engine/portable_input_routing.lua
python3 tools/input-hook-contract-check/check.py --gen1 /path/to/gen1recomp
python3 tools/input-hook-contract-check/check.py --gen1 /path/to/gen1recomp --format unified
python3 tools/input-hook-contract-check/check.py --gen1 /path/to/gen1recomp --api 3 --format unified
```

The ROM-free checker loads the same committed example entry chunk through
each engine's real mod loader and invokes its native Game callbacks with the
real Input singleton. It covers Red, Gold, FireRed and Emerald, checking raw
payloads/identity, forwarded and suppressed input, held releases, fractional
and zero wheel values, continuation rewrites, callback errors and unsubscribe.
It compares input-state journals across engines and refuses a dirty or
unexpected Gen1 reference. It does not replace Gen1 callback implementations.
The Gen2 routing suite additionally covers every supported host version,
menu capture, engine hotkeys, touch bookkeeping and free-camera zoom.
