# Portable battle bottom UI visibility

`battle.bottom_ui_visible(next, state)` controls native battle text and menu
presentation on every Gen2Recomped host, through native API 1/2, unified API 2
and API 3. It complements `screen.render_visible`: a mod can hide the bottom
UI without hiding the battle scene, sprites, health/status panels or effects.

```lua
local mod = ...
local replacingBattleUI = false
mod.hooks:wrap("battle.bottom_ui_visible", function(next, state)
  if replacingBattleUI then return false end
  return next(state)
end)
```

Keep the flag active only while the mod owns the intended presentation.
Native TextBox also uses this hook outside battles, so a global false can hide
field dialogue too. Mods may instead select specific handles or state
properties. Battle metadata/layout internals differ between engines: Gen2's
native class uses `isBattleState`, while Gen1's classic classes use `isBattle`.
The Gen2 inheritance helper recognizes both without altering those classes.

The callback receives the original opaque state, with no extra arguments or
record/ID conversion. The default is true; only a literal first result of
false hides UI. Nil, zero, strings and tables remain visible. `next()` keeps
the current arguments; explicit `next(otherState)` changes downstream
predicate arguments, not the actual state or drawing target. The default
ignores the argument. Treat the callback as a pure predicate: rendering and
menu clipping may query it repeatedly during one frame.

## Native routing

The primary gate runs before BattleState dispatches its text area to classic,
GBA or DS renderers. WideBattle's separate bottom draw also honors it. On DS,
this gates the text/menu path that owns both compact and device-screen action,
move and target controls; it does not hide independent device content or
change input ownership. The Game Boy move/Mimic row clip is removed while
that menu is hidden, retaining existing unrelated field/side clips.

TextBox and ChoiceBox inherit a false decision from the nearest enclosing
battle below them on the native stack. A hidden battle short-circuits before
text frames, choice backings, glyphs and UI anchors are written. When the
battle is visible, TextBox also has its own individual predicate. ChoiceBox
only inherits: a field YES/NO prompt never becomes a battle-hook state.
A battle above an overlay is not its owner.

The predicate does not remove states, consume input or pause logic. Typewriter
updates and delayed YES/NO confirmation remain native. It does not modify
existing rendering-driven presentation counters or their timing when a drawer
is skipped. `battle.status_hud_visible` remains a separate surface with its
existing generation coverage; this change does not add missing GB/GBA HUD
producers. `screen.render_visible` may independently hide an entire state.

`mod:supports("hooks", "battle.bottom_ui_visible")` reports the native producer
before Game creation. With no subscriber the helper returns true directly;
the default function is hoisted and the unhooked path allocates no predicate
closure/payload. Existing priorities, unsubscribe, owner cleanup and failed-
entry rollback apply. Gen2's existing `claimBottom`/`releaseBottom`, claimant
introspection, reset and failing-claim removal remain intact. A legacy claim
that denies drawing wins before the public hook; a hook returning true cannot
force another owner's hidden strip visible. A wrapper error before forwarding falls through; an
error after forwarding preserves downstream results without replay. Unified
callbacks retain existing cached-continuation rules. Native renderer error
handling is unchanged, including DS's existing guarded text-area drawing.

## Verification

```sh
luajit tests/engine/battle_bottom_ui.lua
luajit tests/engine/battle_bottom_ui_routing.lua
luajit tests/engine/battle_bottom_ui_composition.lua
python3 tools/battle-bottom-ui-contract-check/check.py --gen1 /path/to/gen1recomp --api 1
python3 tools/battle-bottom-ui-contract-check/check.py --gen1 /path/to/gen1recomp
python3 tools/battle-bottom-ui-contract-check/check.py --gen1 /path/to/gen1recomp --format unified
python3 tools/battle-bottom-ui-contract-check/check.py --gen1 /path/to/gen1recomp --api 3 --format unified
```

The checker rejects dirty/unexpected Gen1 sources and pins
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The same committed example runs
through both native loaders on Red, Gold, FireRed and Emerald. It calls the
real native predicates and bottom render routes: Gen1 BattleState, Gold's
`drawBottom`, and GBA battle Ui.draw's caught-Pokemon scene, compared with
Gen2's native BattleState dispatch. GBA inheritance is exercised through its
own Ui helper; the shared classic TextBox helper is not presented as Gen1
GBA's native message implementation. Gen1 API 2 ignores the unified opt-in;
that run compares native Gen1 API 2 against unified Gen2 API 2. API 3 is
unified on both hosts, with opaque state identity preserved for this hook.

The Gen2 routing matrix covers every supported version in all four modes,
actual inherited TextBox/ChoiceBox drawers and input/update behavior, native
move clipping, cleanup and the no-mod fast path. The composition suite builds
real native wild battles across every version in classic/wide options. It
runs their compositors with asset-layer spies, retaining the actual bottom
render path, and checks field/actor/HUD/animation dispatch plus identical
native menu input and logic ticks. It also covers the GB palette-canvas path.
The CI workflow also runs the reference engine's unchanged native GBA battle
UI contract suite, covering its regular menus, HUD and native confirmations.
These are ROM-free/headless dispatch tests, not GPU pixel comparisons, live
mirrored-device output or cartridge playthroughs.
