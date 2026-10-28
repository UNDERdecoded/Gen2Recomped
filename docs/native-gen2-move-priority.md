# Native GSC move priority

Older native GSC caches mark priority-hit moves explicitly, but leave Protect,
Endure, Mirror Coat and other priority classes without a `priority` field.
The shared comparator then treated them as ordinary moves. A slow Pokemon
could take damage before its Protect action; the live Gen2 model also reported
neutral priority for these moves.

`Gen2MovePriority` supplies the cartridge's missing priority classes at the
actual native comparator and live-model query. Protect/Endure use +3;
Counter/Mirror Coat and Vital Throw use -1. Roar/Whirlwind use -1 by their
native IDs because the existing cache combines their effect with Teleport;
Teleport remains neutral. Explicit native cartridge/mod priority values,
including zero, take precedence. Other generations retain their own rules.
This does not require a re-import, change a move record or registry fingerprint,
or replace the native battle engine. It adds no RNG draw.

The reference is the GSC `GetMovePriority`/effect-priority table also represented
by the read-only Gen1Recomp Gen2 model at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. This is an implementation in the
native shared controller, not an alias to a second combat simulator.

The exact old-source regression reproduces 57 failed assertions, including
actual HP loss before slow Protect. The corrected 83-check contract exercises
Gold/Silver/Crystal, renamed effect-equivalent moves, explicit overrides,
unknown moves and the public model. It executes the real queued native actions
and verifies Protect/Endure state and PP; the enemy's real attack is blocked
after Protect. Cross-generation comparator checks and existing battle/model,
queue and held-item regressions remain separate checks. These ROM-free fixtures
are not a claim of complete move parity, unchanged-mod story/window behavior,
or release acceptance. Full model-constructor and other Gen1 behavior gaps
remain open.
