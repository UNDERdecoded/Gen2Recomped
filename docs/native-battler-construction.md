# Native battler construction without presentation resources

The shared native `BattleState.makeBattler` previously built combat data,
selected pictures and created animation resources in one function. Extract
its data construction into `src/battle/Battler.lua`, and have the existing
screen constructor hydrate that same table with its original art factories.
There is no second turn simulator, replacement Pokemon or replacement art.

This offered host retains its existing Gen2 calculation binding and poison
initialization. It does not import the fork-only `HeldItemRead` dependency
or silently introduce the fork's later toxic-counter behavior. Party/move/
stat/registry identities, badge defaults, outside-battle sleep and form
personal records retain the existing native construction semantics.

On implementation/test commit `281e5185`, fresh plain-Lua construction passes
577 checks without a LÖVE stub, with presentation-module loads rejected.
Actual wild construction and switches pass 810 checks across this host's
15 advertised editions using the real sprite and animation factories.
These are selected ROM-free checks, not complete current-host, GPU or
release qualification. The previous round-clock offer has separate scoped
RNG/link/model evidence; it does not qualify this new combined source.

This is a prerequisite for sharing native battlers with standalone model
construction. It does not implement the complete source `Battle.new`, pure
turn/event executor, arbitrary writable model fields, full unchanged-mod
visual parity or final release acceptance.

The data code is extracted from the existing engine; original authors'
rights and applicable licences remain effective. Extraction/integration
and tests by Roxas2712 are offered under
<https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md>,
including its specific permission for Cedric / UNDERdecoded with credit.
That contribution notice does not replace earlier permissions or assign
ownership of the underlying engine.
