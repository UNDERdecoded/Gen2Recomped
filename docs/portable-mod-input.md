# Portable logical mod input

`mod.input` implements Gen1Recomp's source-owned logical input contract in
Gen2Recomped, for native API 1/2, unified API 2 and API 3. The signatures are:

| Method | Result | Effect |
| --- | --- | --- |
| `mod.input:tap(game, button)` | `nil` | Queue an edge for the next fixed step and immediately release this call's source |
| `mod.input:press(game, button)` | opaque token | Queue an edge and hold this call's source until released |
| `mod.input:release(token)` | boolean | Release this mod's token once; return `false` for missing, foreign, forged, retired or already released tokens |

Buttons are exactly `up`, `down`, `left`, `right`, `a`, `b`, `start`, and
`select`, in lowercase. They are logical actions, independent of keyboard
aliases or user rebindings. Unknown buttons raise an error before input is
changed. The common contract does not include shoulder or DS face buttons.

Wait for `game.ready` to obtain the live game; both `tap` and `press` take
that explicit handle. Constructing or reading `mod.input` does not create a
Game/Input instance, register callbacks, or require graphics.

```lua
local mod = ...
mod.events:on("game.ready", function(event)
  local game = event.game
  mod.input:tap(game, "a")
  local token = mod.input:press(game, "right")
  -- Later, when this mod's action ends:
  mod.input:release(token)
end)
```

Keep tokens in memory; they carry no editable fields and cannot be copied or
serialized. Each press owns a separate source. Releasing one token preserves
other tokens for the same button, other mods, keyboard/gamepad input and
virtual controls. Multiple taps before the same fixed step coalesce into that
step's single `wasPressed` edge. A tap's own source never remains held, but
another source can still hold the button.

The normal Input queue determines edge lifetime. Releasing a token or
cleaning up a mod releases its held source; it does not undo an edge already
queued. A press followed by a release before the next step still yields one
edge and no held state. An Input reset also clears queued edges.

Gen2Recomped retires tokens whenever their Input instance resets, including
focus/visibility changes, controller removal and input initialization. The
handle remains usable after recovery. Rollback retires the failing mod's
handle; hot reload, a new loader session and launcher teardown retire old
handles. A retired handle refuses new taps/presses. Tokens cannot release
sources belonging to a replacement session, even for the same mod ID.
Outstanding holds remain registered for teardown even if the caller loses
its token or loader references.

Logical input goes directly to Input's per-source bookkeeping. It does not
synthesize OS events or dispatch `input.key`, `input.gamepad`, `input.wheel`
or engine display hotkeys. A raw-input hook can therefore request a logical
button without recursively entering itself.

## Verification

The reference is unmodified Gen1Recomp
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The checker loads the same example
entry chunk through both native mod loaders, emits `game.ready`, and checks
the real Input singleton's held/edge state on Red, Gold, FireRed and Emerald.
It tests the shared contract; the Gen2 lifecycle suite separately verifies
Gen2's reset and retired-handle behavior.

```sh
luajit tests/engine/portable_mod_input.lua
luajit tests/engine/mod_input_lifecycle.lua
luajit tests/engine/mod_input_headless.lua
python3 tools/mod-input-contract-check/check.py --gen1 /path/to/gen1recomp
python3 tools/mod-input-contract-check/check.py --gen1 /path/to/gen1recomp --format unified
python3 tools/mod-input-contract-check/check.py --gen1 /path/to/gen1recomp --api 3 --format unified
```

The lifecycle tests cover all supported Gen2Recomped host versions under
API 1, native/unified API 2 and API 3. The checks are ROM-free and headless;
they do not measure OS event delivery or physical controller hardware.
