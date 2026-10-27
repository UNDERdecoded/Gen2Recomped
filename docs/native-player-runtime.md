# Native player phase compatibility

The compatibility player module operates on the live native GBA actor. It does
not create a second avatar or copy the source movement/event simulation.

Importing it alone leaves ordinary native input unchanged. A wrapper of its
`update(game,input)` entry point is dispatched from the real overworld player
phase. The base update accepts an input proxy, preserving the native field
handler's interaction, movement, collision, bike and movement-hook ownership.
An idle `tick` is deferred until a wrapper has had the opportunity to submit
its `forcedStep(direction,1)` arrival. There is at most one native player clock
advance in that phase; the shared native `finishPlayerStep` runs synchronously
before the wrapper resumes. Repeated ticks cannot duplicate arrivals. Scripted
NPC/player ordering, including a script queue draining on its landing frame,
continues through the original native path.

Position, movement and elevation fields address the current native actor;
fractional body coordinates are preserved. Bike state addresses the native
in-memory save. Running eligibility asks the existing native rules without
requiring the B button to be held. Position synchronization changes only the
in-memory native player record and never calls persistence. Input proxies are
restored even when a handler raises. Menu/script/transition ownership prevents
additional input, and actual loader teardown unwinds wrappers and retires phase
observations without bootstrapping compatibility modules on native-only boots.

## Verification

`luajit tools/player-runtime/check.lua` runs 261 ROM-free checks across all five
GBA editions and checks the three native GBC editions keep their original phase.
It uses the real native player clock, input handler and arrival bookkeeping on
small synthetic fields, with authored event handlers replaced by counting
callbacks. Coverage includes fractional writes, forced arrivals, repeat ticks,
running gates, surf bob, script queue drain ordering, input exceptions, world
replacement and real loader teardown. It is also registered in the engine tier.

The composed fork passes 330/330 engine suites, SDK 3/3 and Dramatic Shape B30.
A read-only SDK probe of the full unchanged 1.0.9 source package now reaches
the missing `src.core.game3.collision` interface on all five editions. A previous
reduced source fixture lacks vendor metadata after this point and is excluded
from that result. These are loader/CPU checks, not GPU or gameplay acceptance.

## Remaining contracts

This is the player phase foundation, not complete mod compatibility. The
distinct Game3 session facade, collision/field services, full scripted avatar
operations and pose/atlas resources still need integration. In particular, do
not claim all surf/dive/ledge/bike transitions or unchanged rendering have been
accepted from these synthetic checks. Real maps, actual events and visuals
must be verified after the remaining modules allow the package to initialize.

The standalone upstream branch runs 108 checks on its two registered GBA
editions; LeafGreen, Ruby and Sapphire are explicitly skipped there until
cartridge PRs #183, #186 and #187 are integrated. All five run in the composed
fork. On pristine upstream main `13af468b`, the engine tier has 10 existing
failures (64/74 suites). The player branch has the same 10 failures (65/75),
with no newly failing suite. The composed fork includes the existing fixes.
