# Native Gen2 model boundary

`src.battle.gen2.Battle` is a distinct model class attached to the shared
native battle controller by `Gen2BattleView`. It is not a name alias for
`BattleState`, a second controller, or a detached copy of the saved party.
Methods resolve through the class so an SDK-owned decoration also reaches
already-created models and is restored by loader retirement.

The boundary supplies live `moveDef`, `speciesDef`, `sideOf`, raw `battleStat`
and `endBattle` operations. Damage, speed, status immunity, weather and shared
move effects consult the native bound reads. Stages, badge/status/item
modifiers, RNG and PP stay with their existing native owners. With no
decoration the read returns the original native table, without a copy.
Temporary stat/type answers do not replace a species registry row, party
statistics, wrapper identity or checkpoint data. Explicit native
Conversion/Transform types keep their priority over a species decoration.

The native finish path invokes the model's end operation, including the
skipped battle path. It raises one finish notification and permits transient
cleanup before subscribers observe it. `completeBattle` runs the existing
screen finish/return path, with repeated completion prevented from popping
another screen. Existing native consumers retain the screen in the event's
`battle`; the distinct model is available in `model`.

This is an implemented boundary, not complete source-model parity. The split
Gen2 model contract was inspected at Gen1Recomp `535a5ec0` and its current
`e46d1eb2` counterpart. That model additionally has constructors and a pure
turn/event API, which are not guessed from screen methods here. Its inspected
class has no `battleStat` method; the raw-stat operation above is an explicit
native extension, not a claim that all source versions expose it. Source
event payload normalization and the remaining model operations still require
separate implementation and acceptance. Existing project and third-party
credits remain applicable.

ROM-free coverage uses an SDK-loaded generic decorator and actual native
damage, speed, status, switch, Transform and completion calls. It also checks
restoration and direct table identity in other generations. It does not prove
an unchanged client, GPU presentation, a full story run or a release package.
