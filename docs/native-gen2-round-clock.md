# Native Gen2 model round clock

An API2 reader of `screen.battle.turn` previously received `nil` even while
the native controller emitted numbered turn events. The frozen Gen1 Gen2
model starts its `turn` field at zero and increments at round admission
(`src/battle/gen2/Battle.lua`, reference revision
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`).

The source model now reads the existing native `turnCount`, or zero before
its first round. There is no second counter, timer, event or random stream.
The native controller still owns round admission. Repeated reads, individual
moves, residuals and switches do not advance or reset that clock. Link hosts,
guests and spectators read their actual lockstep controller. Semantic
checkpoint reconstruction reads its restored native count.

Validation uses actual native constructors, queued actions, API2 event
callbacks, lockstep participants/spectator and semantic checkpoint restore.
The corrected queue probe on the preceding engine reports 295 failures in
400 checks: the public clock is absent at initialization and actual execution
edges. With the engine reader, all 400 pass across Gold, Silver, Crystal,
Prism and Polished Crystal. The link probe passes 210 checks, checkpoint
probe 57, unchanged RNG probe 7951, calculation/completion probe 252 and
friendship checkpoint probe 30 on the fork. The earlier queue-probe drafts
had test-harness mistakes; only its corrected negative run supports the
295-failure comparison.

This closes the missing live clock observation. It does not implement the
source standalone constructor/turn executor, arbitrary writes to source
model fields, every battle event, full mod visual parity or release-package
acceptance. Those remain separate parity requirements. No mod or original
Gen1/player installation is changed. Implementation and tests are original
contributions by Roxas2712 under `LICENSE-ROXAS2712.md`.
