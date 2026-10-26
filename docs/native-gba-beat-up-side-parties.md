# Native GBA Beat Up side parties

A two-trainer opponent side and a player/ally side each use one native party
for Beat Up. Gen2Recomped stores the trainers' parties separately for
replacement, payout and defeat handling. Its Beat Up helper previously used
only the active trainer's party, so three eligible members produced three
strikes where the reference used the combined six.

Keep the owning arrays separate and expose a private, live indexed view to
the native Beat Up executor. Both positions use primary-party slots followed
by partner-party slots. A battle-scoped player party takes precedence over
the save party. Eligibility and replacement of an upcoming member are read
live; the active user's current HP/status still overrides its party slot,
including a detached active battler with an explicit native party index.

The source captures the current party array for a move. Reassigning the
battle's entire party field in a hit callback therefore does not replace
that in-flight iteration. The host likewise retains its owning array
references for the move while reading each upcoming slot live. This avoids
copying a stale list of member objects or rereading a newly assigned party.
Native six-slot bounds and the ordinary single-owner fallback remain.

## Verification

```sh
luajit tests/engine/gen3_beat_up_side_party.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --report /tmp/enemy-action-report.json
```

The same API-3 consumer and shared native fixture run on unchanged read-only
Gen1Recomp `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Gen1 uses the actual
native State constructor with player/foe ownership halves. Gen2 uses the
actual trainer constructor, `setAlly`, `addOpponentTrainer` and
`sendOutSecondPair`, with prebuilt imported-shaped party members. Source
ownership guards and host replacement benches are checked before action
execution. A separately seeded battle-scoped player view is also exercised;
this is not a new replacement/selection API.

Eighteen cases at all four positions on FireRed/Emerald cover six/five
members, filtering, either owner having no eligible members, a fully blocked
side, a participant awakened in the accuracy hook, waking/blocking/replacing
an upcoming member in hit callbacks, whole-array reassignment, live active
HP and a detached active battler, Substitute, fainting, criticals and low
variation. Actual PP, hit amounts/order, public event metadata, callback
counts, special counter memory and semantic critical/variation observations
are compared. The focused suite passes **1,728 checks**; the complete matrix
passes **48 isolated workers / 4,766 paired observations**. #209 without this
change fails **58 assertions** in the new FireRed cases.
The full feature quick run passes **91/100 engine suites** versus **90/99**
on clean #209; exact Counters of the **25 inherited FAIL lines across nine
suites** match with no additions. SDK 3/3 and B30 pass.

The runtime is JIT-enabled LuaJIT v2.1 commit
`a4c064539ea931274d407e1249b4bb575424a0f4`, also pinned in the contract
workflow. Full raw RNG-trace parity, graphical intros/animations, arbitrary
mid-move ownership reshaping, link/multi-owner controller execution and
complete gameplay remain separate surfaces.

The feature stacks on #209. `BEAT_UP_EFFECT.rev` increases from 1 to 2, so
builds with different native party execution cannot silently negotiate the
same link fingerprint. The fixture digest changes from `d518411055f17444`
to `fdbfa30b20cbbaef`; only `move_effects` changes, from `f45a80ce5e45ef42` to
`e4d28f474c15cd8b`. Restoring revision 1 restores the prior full digest; all
six other populated sections remain identical. No Gen1 source edit or
publication is required.
