# Native Gen2 resolution/message screen contract

Gen2 queue writers publish `resolving`, retaining `messages` for other editions.
The native queue accepts earlier Gen2 records and publishes its actual current
text through `message` and its manual acknowledgment hold through `messageTimer`.
The existing typer, prompt delays, choice callback and queue remain authoritative.
Decision boundaries clear the text; classic/wide composition and link completion
recognize the same queue predicate. No mod or game data is included.

The screen contract was checked against Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`,
`src/ui/gen2/BattleState.lua`. Existing project rights and notices remain applicable.

`tests/engine/gen2_battle_queue_view.lua` exercises actual native refusal,
manual text advancement, legacy queued children and delayed YES/NO ownership
across five Gen2 editions, with Red/FireRed/Emerald regressions. This independent
upstream adaptation uses only its available native modules. It does not imply
a new client/GPU check, whole-PR acceptance or complete event/page/animation API
parity. The separately observed white view still needs causal GPU diagnosis.
