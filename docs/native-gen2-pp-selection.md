# Native Gen2 PP selection and maximum

The Gen2 party-target ETHER, MAX ETHER, MYSTERYBERRY and PP UP route uses the native `Gen2MoveDeleter` screen from
Gen1Recomp 535a5ec0. It retains the actual party mon and moves. The ordinary
PP cursor stops at both ends; the native forget layout wraps. Only the
caller's normal choose/cancel continuation controls stack lifetime. The
move-list window preserves the party underneath, and B drops only that list.
Field PP selection also keeps its party parent until its existing result
flow closes it. No consumer files need changing.

`Gen2PP` owns Gen2's `ComputeMaxPP` arithmetic. Each PP Up adds
`min(floor(basePP / 5), 7)`, so a move with 40 base PP and three PP Ups has
61 maximum PP. Legacy slots with a valid stored `maxPp` infer their existing
bonus without a mutation during reads. PP Up refuses Sketch and a fourth
bonus. Shared maximum readers accept an explicit destination generation for
cross-game reconstruction, while other generations retain their existing
maximum rule.

Item restoration, PP Up, party healing, daycare retrieval, classic/wide battle
labels, summary, held-item restoration and link reconstruction use the common
maximum. Fork-only public records and Bank modules are not present in this
upstream branch; this adaptation does not invent or claim those interfaces.

Fresh automatic settings select the finite-enemy-PP Gen2 compatibility rule.
An explicit saved ruleset remains effective, including an intentional Gen1
unlimited-PP choice. The options row can return to AUTO without reserving a
string id from mods. Only the enemy PP policy differs from the previous Gen2
host rule fields; complete Gen2 battle-rule parity remains unproven.

The native move-list and forget-list layouts preserve reference provenance.
Sound uses the existing imported cue and actual Sound.play service; the
reference's unavailable Sound.resolve is not introduced.

Contracts exercise the real screen registry, native input, bounds and forget
wrapping, cartridge drawing coordinates, callback/cue lifetime and immutable
party reads; actual item effects, native maxima/legacy counters, healing,
link clamping. The battle PACK suite additionally
requires its real ETHER route to open this controller. Qualification results,
including baseline failures and unchanged-client GPU acceptance, must be
recorded separately; the presence of contracts does not prove full parity.
