# Native GSC Protect and Endure

Run GSC protection on the real shared-controller battler, with the source
model's nonzero-byte odds (`255 >> prior successes`), first-side and Substitute
restrictions. Actual action entry records the first side for that round,
including switches and failed/recharge actions; called effects retain it.
The next round replaces it. GSC self-protection bypasses the generic incoming
status gate so the real handler can clear its failed-use counter.

Changed command/RNG semantics advertise `gsc-1` in link hello and a separate
GSC fingerprint domain. Older rules cannot enter the changed lockstep battle;
the compatibility screen names the native rules difference. Other generations
retain their existing handlers and fingerprints. This older host does not
carry the fork's semantic-checkpoint backend, so no checkpoint result is
claimed here.

References: read-only Gen1Recomp Gen2 revision
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, its protection handlers and
`Effects.protectSucceeds`; `pret/pokecrystal`
`5c877ef55197039c9676e8e3eec6d254b1c40fe8`,
`engine/battle/move_effects/protect.asm`. The nonzero-domain native RNG call
matches the source model convention; this does not emulate a hardware PRNG or
claim raw zero-rejection trace parity.

The native model/volatile/priority prerequisites remain separate offered PRs.
Independent results on this offered host: 3796 native effect/queued-order/PP/
switch checks, 66 host/guest/spectator and admission checks, 37 actual protocol/
cache/digest checks, 423 volatile checks and 83 priority checks pass. The frozen
Gen1 comparison independently passes 30,624 actual effect cases / 165,336
comparisons. A separate Python integer-FNV audit confirms this host's legacy
fixture digest e33d251961f2a41d and GSC digest 40df18dc503213c8. Tests drive this
older host's actual queue-row closures; they do not assume the newer fork's
runQueueAction or beginTurn helpers exist. Fork-only checkpoint and complete
release acceptance are not inherited. GPU, complete called-move/turn mechanics,
unchanged-mod gameplay and full Gen1 feature parity remain separate work.

Native integration/tests by Roxas2712, offered to Cedric / UNDERdecoded under
the fork's specific PR contribution permission, with existing rights intact.
