# Native Gen2 party item results

Gen2 party-target items keep the actual PartyMenu above the battle through
HP fill and result confirmation. The effect and inventory mutation still run
once in ItemEffects. Only after native A/B acknowledgment does the same battle
controller queue its normal enemy action and end-of-turn effects.

The native result surface follows Gen1Recomp 535a5ec0 PartyMenu/HpBar:
`showItemResult`, `itemResultClimbing`, `shownHpFor`, and `updateItemResult`.
HP display walks one point per tick below 48 maximum HP, otherwise
`ceil(maxHp / 48)`, then holds confirmation for 50 ticks. Native row rendering
reads that display value without changing the real party mon. Status and PP
results use the same owner with no HP animation. Longer shared-engine text
continues on another native two-row page instead of silently dropping its tail.
The item effect already plays the imported heal cue; result presentation does
not replay it.

The shared `heal` hold refers to the same result object, so existing party
navigation cannot advance a second input/animation clock. Once the party result
finishes, the active battler's displayed HP catches up before battle drawing
resumes. The normal low-health alarm can then reevaluate the actual HP.

A controller-owned post-draw pass preserves the result text when a consumer
replaces the party view. It runs after that view, before later modal children,
in classic, expanded native and window-resolution rendering. The graphics
boundary restores caller state even if a replaceable view leaks a push or
changes canvas. A consumer drawing HP directly from `mon.hp` still displays
that real final value; the engine does not rewrite gameplay HP to animate an
independently authored view. Such a view can use `shownHpFor` for native timing.

Targeted contracts cover actual PACK/target/move-selection input, Potion,
status cure, revive and PP restoration; native timing, cancellation, no-effect
refusal, one item and one enemy action; render ordering and error restoration.
Local source-frozen execution and unchanged-client GPU qualification must be
recorded separately. This document does not claim release or full parity
acceptance from the presence of these tests.
