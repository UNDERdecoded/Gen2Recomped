# Native Gen2 connection targets

Gen1Recomp's native Gen2 world reads a connection's string `mapId` before
`map`. The shared world previously read only `map`, so a native record could
be absent from neighbor residency and fail the ordinary seam transition.
A numeric `map` can be cartridge group/map metadata; it must not be rewritten
into a string destination.

`Map.connectionTarget` resolves that record once per query, scoped to Gen2.
The same owner supplies neighbor discovery, the strip extent search, landing,
the actual map handoff and deferred seam music. Other generations keep `map`.
No map definitions or source connection records are synthesized or mutated.
The separate fork's physical-alias publication and extra movement/fishing
adapters are not part of this independent upstream patch.

An omitted strip offset means zero, matching the native reference. Strip
selection skips unavailable destinations before trying later rows; it keeps
the existing inclusive strip bounds, collision tests, multi-strip selection,
block/cell conversions and native movement interpolation. An unknown planner
root returns an empty resident set instead of dereferencing a missing map.

`tests/engine/gen2_connection_targets.lua` exercises all four directions in
Gold, Silver, Crystal and Prism with native/shared records, numeric metadata,
conflicting native/shared names and positive/negative/zero offsets. It calls
the existing planner, landing and real crossing controller. Renderer/map
materialization is substituted at the boundary; movement selection and
interpolation remain native. It also checks omitted offsets, missing first
strips, missing roots and existing Red/Emerald/FireRed/Platinum behavior.

The dedicated connection-target CI includes the complete native/shared
record matrix and the shared-generation crossing regressions in this suite. These ROM-free tests do not
establish current client graphics, story completion or desktop release parity.
Reference: Gen1Recomp `535a5ec0`, `src/world/gen2/World.lua`,
`computeNeighbors`, `cellCollisionAcross` and `tryConnection`.
