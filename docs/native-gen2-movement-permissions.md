# Native Gen2 movement permission queries

The existing `src.world.gen2.Permissions` module alias resolves to the native
`src.world.Collision` table. It now exposes four terrain queries used by Gen2
camera controls:

| Method | Result |
| --- | --- |
| `isIce(coll)` | Whether the actual `COLL_*` byte is either native ice class |
| `currentDirection(coll)` | Forced direction for the current family, including waterfall tiles |
| `doorForcedDirection(coll)` | Downward movement for the native forced-door subset |
| `stepPermitted(collOf, x, y, direction)` | Whether the standing and destination cells permit crossing their directional side walls |

The first three consume Gen2 collision bytes. They do not classify a later
generation's blocking bits. The side-wall query shares `Map.gen2SideWall` with
the native grid mover; it does not replace map bounds, walkability, occupants,
scripted closed cells, or the `movement.collision` hook. Callers must retain
those checks. Runtime block replacement is observed through the supplied
collision reader, without a second collision cache. Unknown directions are
refused before sampling cells.

The native Gen2 ice controller uses the same predicate. This change does not
install `FieldMoves`, activate continuous controls, or start forced movement
from any of the query methods. Those integrations require their own native
landing and handoff verification.

## Verification

Run `luajit tests/engine/gen2_movement_permissions.lua`. It checks all 256
collision classes and all 262,144 source/destination/direction combinations
against actual `Map` cells and `Collision.canMove`, isolating directional
permission from other collision reasons. It also checks occupants, scripted
closed cells, block replacement, invalid values, module identity, and the live
ice controller in Gold, Silver, Crystal and Prism. No ROM or mod is needed.

`tools/gen2_permissions_contract.lua` produces a deterministic behavioral
dump. The workflow compares its complete output for Crystal with public Gen1
reference commit `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Each engine runs
from its own checkout. The comparison covers 768 byte queries and 262,144
directional cases; it does not claim complete movement or rendering parity.

These are CPU contract tests. Actual mod camera movement, special movement
handoffs, full rendering and GPU acceptance remain separate requirements.
