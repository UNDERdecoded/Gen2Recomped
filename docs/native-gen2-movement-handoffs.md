# Native Gen2 special movement handoffs

Gen2 controls can return special movement to the existing native overworld
through `tryConnection(direction)`, `tryLedgeJump(direction)` and
`tryPushBoulder(direction, x, y)`. The last method requires the actual adjacent
cell in that direction. These methods use the existing map/warp, ledge and
boulder handlers, player interpolation, script queues and completion events.

Admission requires the current Gen2 world and save, a standing actor, no
overlay or battle, and no active or pending native script, field action or
transition. Both the persistent world with an empty overlay stack and the
legacy world on top of its stack are supported. An expired numeric whirlpool
hold is clear; a positive hold retains control. Nested admission from a
synchronous native callback is refused, and a handler error remains visible
without leaving a permanent admission lock.

The connection path retains directional carpet exits. A carpet is an input
action, so an integration must not substitute an immediate arrival warp.
Ordinary seam steps also check directional walls on the standing and
destination cells before changing map. Scripted seams keep their deliberate
collision bypass.

The native Strength handler checks directional walls on both the player's
approach and the boulder's step. Previously, its land/water check admitted
those walls. Both the existing grid path and the new public handoff now refuse
that push before queuing movement. Native occupancy, Strength activation,
object classification, destination passability and completion effects retain
their existing ownership.

## Verification and limits

`luajit tests/engine/gen2_movement_handoffs.lua` exercises actual map definitions,
native connection selection, all four seam directions, native player/NPC
interpolation, two-cell ledge queues and boulder completion. Only graphics/map
materialization and the audio device are substituted. Native directional
carpet fades are advanced to completion. The suite also checks busy owners,
invalid directions, exact boulder coordinates, callback reentry, error cleanup,
and the unchanged scripted collision bypass.

The directional-wall regressions cover Gold, Silver, Crystal and Prism. A
complete valid-byte/directional query comparison with the pinned Gen1 engine
is covered by the prerequisite terrain-query contract. This follow-up builds
on that implementation; it does not replace any generation's world controller.

These are native CPU tests. They do not establish complete continuous-movement
activation, the FieldMoves facade, all special terrain/landing behavior, or
actual VASC GPU acceptance. The full generated VASC model renderer remains
blocked by the separately documented compiler limit.
