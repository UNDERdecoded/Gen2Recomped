# Portable logical input example

Copy this directory into `mods/`. The unchanged entry chunk runs on both
Gen1Recomp and Gen2Recomped. It obtains the Game through `game.ready` and
exports `tap(button)`, `press(button)` and `release(token)` helpers, together
with the underlying public `input` handle for contract tests. It does not
send input until a helper is called.

`press` returns an opaque token which must be released by the same mod.
Available buttons are `up`, `down`, `left`, `right`, `a`, `b`, `start`, and
`select`. Do not store tokens in saves. See
[the contract and lifecycle rules](../../docs/portable-mod-input.md).

The manifest uses API 2. The contract runner also exercises the exact same
entry chunk with unified API-2 and API-3 manifests.
