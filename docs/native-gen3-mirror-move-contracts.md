# Native Mirror Move integration contracts

This contract extends native Substitute fade. Its runtime change
advances the native GBA command revision from 16 to 17: additional queued
animation commands and sound callbacks change runtime behavior even with the
same imported records. Party codec revision remains 1. Older native peers
stop before party exchange; non-GBA fingerprints remain unchanged.

An independent frozen-parent serializer audit changes only the revision token.
It yields native fingerprint `351a5becf7f236a0`, replacing
`b251a4d1054d6555`; legacy fingerprint remains `e33d251961f2a41d` for Red,
Gold, Diamond and Black. The updated protocol suite passes **154 checks**.

The new actual host/guest/spectator test passes **108 checks** for FireRed and
Emerald. Each role runs two real menu turns: Mirror first fails without
received history, an incoming Tackle records the recipient's history, then
Mirror calls Tackle. All public events, parent/child PP, completed turn hashes,
state components, history and spectator HP agree. This is not a graphical or
full-playthrough test.

The separate existing-import smoke test executes **24 scenarios / 48 turns /
120 complete move-used events** through public battle snapshots and submitted
fight/move intents. It reads existing FireRed/Emerald imports, registers an
unchanged API-3 Mirror Move where requested, and tests Tackle, Scratch and Growl
with Choice Band or Shell Bell. It checks real received history, failed first
calls, copied public identities, callback errors and parent PP ownership. No
normal cache or save is written. The same helper on frozen #258 fails at the
received-history assertion, establishing a runtime negative control.

The first imported fixture used the wrong public effect spelling; that failed
log is retained. The shared API-3 effect is `MIRROR_MOVE_EFFECT`, as specified
by the existing contract and used by the earlier cross-engine tests.

The parent frozen complete command matrix is now fully equal: **32 workers /
14,528 paired cases**, no timeout or native VM diagnostic. It retains every
captured state, event, held read, RNG draw and animation row. The earlier
Substitute/Focus Band/Poison differences have been implemented and qualified,
not removed from comparison.

The exact runtime at `f9016f1c` completes 163/172 engine suites, SDK 3/3
and B30, with exactly the same 25 inherited FAIL lines as fresh #258. The
additional KO/self-target history cases pass 994 host checks and extend the
complete matrix to 14,816 equal paired observations. Combined-fork qualification
and the limits of native profile coverage are recorded in
`native-gen3-mirror-move.md`. The unchanged Gen1
reference remains read-only at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.
No Gen1 PR or write is involved. GPU scene parity and whole-synthesizer waveform
parity are not established by these CPU contracts.

Reproduce the existing-import smoke test with:

```sh
nice -n 19 /path/to/luajit \
  tools/enemy-action-contract-check/imported-mirror-smoke.lua \
  /path/to/existing/Gen2Recomp-cache
```

Raw reports and independent digest inputs are retained in
`tmp/mirror-contracts-qa/`.
