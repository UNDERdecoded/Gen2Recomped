# Native GBA Assist and portable content

This contribution builds on #252. The unchanged Gen1 reference is
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; all changes target Gen2Recomped.

## Public mod contract

The same API-3 registration uses the canonical effect on both engines:

```lua
mod.content.moves:register("PORTABLE_ASSIST", {
  id = "PORTABLE_ASSIST", name = "PORTABLE_ASSIST", type = "NORMAL",
  power = 0, accuracy = 100, pp = 10, effect = "ASSIST",
})
```

The builtin is installed for GBA. Existing content reads return the canonical
`ASSIST` effect, and registered party moves execute their own native effects.
Mods do not need a private `BattleState` replacement or a generation-specific
implementation of the party candidate scan.

## Native command behavior

After the parent `battle.move_used` subscribers, Assist scans the current side's
party in order and the first four move slots in order. Each eligible occurrence
has its own weight. Fainted members and zero-PP party moves are eligible; the
current user, eggs, empty species and the reference's forbidden callers/moves
are excluded. Sparse move slots do not terminate the scan. Active partners can
contribute. The host's two trainer party arrays are read as one side party.

The pool is captured before the caller's PP command. PP is spent before a
successful Assist animation and its selection RNG. The child announces with
`isCalled = true`, consumes no party member PP and uses its native targeting.
Nature Power may be a child and can dispatch its own terrain move. Empty pools
preserve the previous move history, including when an outer Metronome selected
Assist. The same early-return history handling applies to failed native Mirror
Move. Native Metronome/Mirror Move children use the shared called
move targeting path in double battles.

GBA lockstep advertises command revision **15**; party codec revision stays **1**.
Revision-14 peers cannot start a native battle. The native fixture digest is
`662d7e5ee823ce82`, independently computed with the frozen parent serializer and
only the revision token changed. The legacy digest remains `e33d251961f2a41d`.

## Validation scope

The shared fixture executes the real native dispatch on the clean reference and
the actual Gen2 battle implementation. It retains full move/damage events, raw
and public PP, held-item callbacks, RNG bounds/values, queued move animations,
active state and party PP. Separate native linked-role and actual-import menu
submission tests cover the host execution path.

These checks use owned controlled definitions and separate existing imported
FireRed/Emerald data. They do not establish whole-catalog Metronome parity,
visual animation parity, arbitrary mod compatibility or a complete playthrough.
Final acceptance counts and retained negative evidence are recorded with the PR.

## Accepted source-bound results

The combined runtime passes **275/275 engine suites**, **3/3 SDK suites**, B30
and every quick tier. The isolated feature passes **157/166** and retains the
exact 25 inherited FAIL lines across the same nine suites as fresh #252
(**153/162**). No additional failure is accepted.

Each runtime passes **188 enemy/action workers / 160,724 identical paired
observations**, including **38,712 new Assist observations**. All workers exit
zero without timeout. The ordinary-damage and held-command comparisons add
**8 workers / 8,952 rows**, for **196 workers / 169,676 selected paired rows**.
Four held-item formats pass strict native schedules (**40 workers / 1,914
rows**); charge contracts pass four formats (**64 workers / 1,020 rows**), with
strict raw native policy on the combined runtime.

Actual linked host/guest/spectator menus pass **120 checks** across two turns
per profile, retaining every event and paired completed hash/state component.
Existing FireRed/Emerald imports pass **160 controlled public-submit scenarios**
with native/registered Assist, direct party children and nested Nature Power,
Choice Band and Shell Bell. The result queue returns to its native menu.

The unchanged parent differs in **4,860/6,480** complete native rows and all
**36/36** selected failed-caller histories; public `ASSIST` registration is
rejected there. Initial fixture failures, the incorrect local PP assertion,
the too-strict imported Choice Band expectation, superseded observations and
the first native-targeting RNG difference remain retained as negative evidence.

See [the receipt](qa/native-gen3-assist.json) for tested refs and raw-log digests.
Reproduce the portable comparison with the pinned LuaJIT and clean reference:

```sh
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --lua /path/to/pinned/luajit \
  --report /tmp/enemy-action-report.json
```

The actual-import CPU scenarios additionally accept an existing cache root:

```sh
luajit tools/enemy-action-contract-check/imported-assist-smoke.lua /path/to/cache
luajit tools/enemy-action-contract-check/imported-assist-smoke.lua /path/to/cache --nature-power
```
