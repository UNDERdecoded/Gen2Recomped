# Native move resolution scope

`battle.engine.resolveMove` decorates the actual `BattleState:performMove`
invocation before the existing native body starts. Encore/target correction,
PP, RNG, announcement, called/spread moves, Substitute and item frames remain
inside that unchanged body. There is no second combat executor or event queue.

An admitted source receives the existing battle/battler view identities,
the actual move key and its learned-slot index when one exists. Adapter/output
arguments are absent rather than fabricated. Base calls must return the exact
admitted arguments. The base consumes the native body at most once, caches nil
return tuples and cannot retry a failed native body. Calls outside the native
invocation cannot resolve a move.

Before consuming the body, the scope checks edition, dataset/identifier tables,
save, loader/content cohort, stack/top, queue, result, actor/position identity,
move-definition identity and the selected PP owner. Current native action records
use their already-loaded slot owner; older native bodies debit the move instance
itself. No newer action/AI module is imported to change the older native body.
A retained callback cannot move its claim to another action or native phase.

Default native and Gen2 paths remain direct. Merely importing the source module
on a non-admitted native battle does not instantiate another controller. This
packet supplies a real resolver boundary, but does not project an action-ready
phase, change UI busy semantics, permit a suspended contact continuation or
provide ownership/obedience facts. Those remain separate native-owner work.
Action Card/contact timing and complete source animation playback are not
qualified by this packet.

The initial broad source `b53a8e0875` passes155 selected CPU groups, including
133 initial resolver checks. Its exact pre-resolver source comparison
`73ad374572` matches complete HP, PP, every RNG call and frame/phase traces for
all five GBA editions, both with the new module absent and with it loaded.
Final actor/mon/PP-slot ownership guards expand the focused suite to138 checks.
Final frozen `c00886af4b` passes155 selected CPU groups. Older-public component
`96f758ec`, exact composition `64b35cafd8`, passes61 groups including the same
138 resolver checks. The owned fixture runs native battler placement explicitly
because it bypasses the native enter animation; no placement body was changed.
Only the owned method declaration/wrapper was adapted over the older native
move body, which remains intact. No newer controller/AI body was copied.

Only public engine and owned QA files change. QA uses fresh owned profiles and
a20GiB free-space floor. Player saves and private mod bytes are untouched.

Merged current main `73b2c0f8` as `80b4cc2f`: exact frozen `269e87ae07` passes164 selected CPU groups, including the new GSC sleep/status/SFX, native audio shutdown and five-edition field-return/weather battle groups. Exact actual-main predecessor `aff668b6b2` compares the unmodified `73b2c0f8` native source with this merged candidate, both module-absent and module-loaded: full HP/PP/every-RNG/frame-phase traces match in all five GBA editions.
