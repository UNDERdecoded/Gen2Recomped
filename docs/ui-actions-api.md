# Public UI actions

`mod.ui:snapshot()` and `mod.ui:submit(intent)` drive the **currently open**
native party, bag or dialogue screen. They are additive for API 1 and 2, with
no manifest opt-in. Existing `mod.ui.insertBefore`, `insertAfter`, step-list
helpers and their dot-call signatures remain available. Each mod receives its
own facade. If the optional capability-query feature is installed,
`mod:supports("ui", "snapshot")` and `mod:supports("ui", "submit")` return true.
This describes the interface, not whether the current screen accepts an action.

The battle API can open the native party/bag menu. This API then selects its
rows and follows the native target, item, confirmation and message flow. It
does not open a menu from arbitrary world/script states.

## Snapshot and intents

A snapshot returns a detached table, or `nil, reason` if the top screen is
absent or unsupported. It never searches through a covering screen. Reading
early does not bootstrap Game, load a screen, poll input or render graphics.

| Field | Meaning |
| --- | --- |
| `revision` | Positive per-facade context revision; obtain it from this facade |
| `kind` | `party`, `party_actions`, `bag`, `bag_actions`, `text` or `choice` |
| `rows` | Ordered options, including disabled placeholders; empty for text |
| `index` | Native selected row, where applicable |
| `locked` | Animation, typing, controller or script currently owns input |
| `canBack`, `canAdvance`, `canPocket` | Which non-selection intents are offered |
| `pocket` | Optional native pocket identifier; diagnostic, not portable |
| `page` | DS battle bag stage: `menu`, `pocket` or `use` |

Every row has `index` and `enabled`. Depending on the native screen it can also
carry a string `label`/`action`, portable `item`/`species` ID, item `count`, or
`partyIndex`, `hp`, `maxHp`. Missing fields remain absent. The current dataset
resolves IDs, including numeric DS IDs and ROM-hack aliases. Labels can be
localized; native action strings are diagnostic, not a common semantic action
enumeration. There are no callbacks, native objects or future dialogue pages
in the public record.

`select.index` is **1-based in the returned rows**. It is not always a party
slot or item number: party confirmation/cancel rows, DS list headers, GBA
blank action cells, and DS battle-bag navigation buttons retain their native
positions. Disabled rows cannot be submitted. In field bags the rows cover the
current pocket in native order; HGSS/BW scroll/page cursors are positioned for
the selected row. DS battle bags expose only their current page's six item
slots plus previous/next/back buttons.

Intents must be plain tables with exactly the fields below:

```lua
{ id = 1, revision = snapshot.revision, kind = "select", index = 2 }
{ id = 2, revision = snapshot.revision, kind = "back" }
{ id = 3, revision = snapshot.revision, kind = "advance" }
{ id = 4, revision = snapshot.revision, kind = "pocket", direction = 1 }
```

`id` is a strictly increasing positive safe integer **per UI facade**;
`revision` must come from a fresh snapshot returned by that facade. Pocket
`direction` is exactly `-1` or `1`. Unknown fields/kinds, malformed integers,
missing/disabled rows, stale contexts and unavailable actions return
`nil, reason` before native dispatch. Failed admission does not consume the ID.
Keep the ID counter across menu/Game changes.

```lua
local nextId = 0
local function chooseRow(index)
  local snapshot, why = mod.ui:snapshot()
  if not snapshot then return nil, why end
  local row = snapshot.rows[index]
  if snapshot.locked or not row or not row.enabled then
    return nil, "row is not currently available"
  end
  nextId = nextId + 1
  return mod.ui:submit({
    id = nextId, revision = snapshot.revision, kind = "select", index = index,
  })
end
```

Take a new snapshot after each accepted action or native input/update. Revisions
track native screen/option/callback identity, live party/inventory and relevant
selection/control state. A private per-Game guard/epoch serializes UI and battle
submissions, rejects callback reentry and expires other mods' old and in-flight
snapshots. A snapshot obtained during dispatch reports `locked = true`.

## Native behavior and limits

- Party lists/pickers, swap/field/item submenus, forced replacement and team
  selection retain their native eligibility, callback and cancellation paths.
  `back` uses that screen's B behavior; it may clear a pending swap or submenu
  instead of closing. The underlying battle decides how a cancelled forced
  replacement is reopened. GB/GBA/DS each keep their own return semantics.
- Bags preserve native pocket order, item-use eligibility, target pickers and
  consumption. The classic bag's own action menu and GBA item action grid are
  supported; unrelated generic menus/lists are not inferred from their shape.
  DS battle-bag presses complete on subsequent native updates, including their
  page/category return paths. `true` does not mean an item has already run.
- `advance` handles a ready manual page/line break or final text, a bag's
  result message, or a DS party notice. Typing and page/scroll holds are never
  skipped. Multi-page question/auto/stay text can advance its intermediate
  manual pages; the final script-owned page stays with its controller.
- TextBox's native choice creates the separate YES/NO screen on the next
  native update. `select` chooses YES/NO; `back` selects NO. The native answer
  hold and delayed callback are preserved, so the answer cannot be replayed
  while pending.
- Scripts, no-input/tutorial states, healing fills, pending answer/DS battle
  button animations, item sorting and quantity entry are locked. QuantityBox,
  summary screens, PC/shop-specific auxiliary screens, TM cases/berry pouches,
  arbitrary custom menus and custom screen subclasses have no adapter here;
  they return `nil, reason`. This is not a generic UI automation API.

`true` means a native action was admitted and entered. It may open another
screen, display a native refusal or schedule work. IDs are consumed **before**
native code. An error after partial native effects returns
`nil, "UI action failed; intent consumed: ..."`; the guard is released, but no
rollback or automatic retry occurs. Inspect a fresh snapshot before continuing.
The read/validation boundary is not a security sandbox for mods that directly
replace native engine methods or mutate Game themselves.

## Reproducible tests

Run `luajit tests/engine/ui_actions.lua` and `LUA=luajit bash scripts/test.sh`.
The focused suite uses real Loader/native menus, Pokémon, item effects and text
updates with the ROM-free fixture data across all 15 supported version IDs.
It checks native A/B parity, copied reads, full-graph immutability on refusal,
identity/revision/replay checks, callbacks and recovery after partial errors.
DS UI fixtures include native pocket/answer/press delays. Imported-ROM gameplay
and rendered cartridge scenes require a separate ROM-backed run.
