# Native GBA Choice Band and move selection

This change is stacked on #230. It brings the native Choice Band command,
manual/AI selection consumers and forced-move PP ownership into the shared
Gen2 engine for FireRed and Emerald.

## Behavior

The move-end command performs its held-effect read unless the action was
disobedient. A new choice remembers the selected native caller, excludes
Struggle and successful Baton Pass, and clears when the move disappears from
learned slots. Losing the item retains a still-learned choice. Planner queries
read the current held effect again instead of caching a previous hook answer.

Manual admission checks physical item 186. The AI's four-slot limitations
command uses the held-effect hook and combines Choice Band with PP, Disable,
Encore, Taunt, Torment and Imprison. Ordinary wild selection uses that mask
for the all-unusable shortcut; otherwise it draws nonempty native slots before
forced planning. Explicit non-link unlimited-enemy-PP rules remain supported.

Forced planning binds the actual learned slot, priority and target byte while
keeping the declared turn event separate. Replacing the move table rebinds PP
to the current slot. Removing the selected slot still permits the planned move
without spending retired records or another current move's PP. Pressure spends
two PP when that replacement slot exists.

Native caller provenance is explicit. Sleep Talk and unchanged default
Mirror Move/Metronome selectors differ from custom `ctx.callMove` handlers.
Active Baton Pass frames follow the replacement battler; failed Baton Pass
can bind a choice while successful Baton Pass does not. Failed native Mirror
Move returns before move-end. Custom callers retain both commands and resolve
canonical GBA move references such as `ctx.callMove("TACKLE")`.

API-1/2 native choice handles retain their identity. Selection-only metadata
stays private until execution; API-3 positional actions remain separate from
learned records. Public snapshots, stale-intent checks and the actual keyboard
refusal/message-queue return path use the same native restrictions.

GBA Struggle skips STAB and the type chart while retaining ordinary base,
critical and random-damage commands. Other-generation paths remain guarded.

## Linked roles and protocol

Choice identity participates in GBA link state and public-intent staleness.
Host, guest and actual spectator use canonical actor order for held scans,
planning and speed reads. Initial item-entry waits for both send-outs; later
individual switches keep their normal entry command. The link test retains
complete ordered held payloads and a stateful damage override depending on
all earlier reads, rather than accepting equal hashes alone.

Native command revision is **11**; party codec remains **1**. Older peers are
refused before party exchange. An independent audit applies only the revision
10-to-11 token change to the unchanged #230 hasher and reproduces native digest
`3e2986da83083f86`; the legacy digest remains `e33d251961f2a41d`.

## Local acceptance

Production was tested at feature `60d5a6fe` (runtime change `137d775b`) and
combined candidate `83346a19` (runtime change `bdd07012`). Later documentation
and workflow-path changes do not change those production sources.

| Check | Isolated feature | Combined candidate |
| --- | --- | --- |
| Engine suites | 143/152 | 262/262 |
| SDK suites | 3/3 | 3/3 |
| Quick tiers including B30 | same inherited engine-tier failure | all pass |
| Enemy/action contracts | 148 workers, 80,132 paired rows | same counts, all equal |
| Ordinary GBA damage | 6,912 paired rows | same counts, all equal |
| Imported FireRed/Emerald scenarios | both modes pass | both modes pass |

The isolated feature retains exactly the same Counter of 25 anchored FAIL
lines across nine inherited suites as a fresh unchanged #230 parent. No
failures are filtered. The combined candidate has zero FAIL lines.

All four held-item CI formats also pass the strict native-schedule gate:
API-1 native, API-2 native, API-2 unified and API-3 unified; 40 workers / 1,914
paired rows. The removed-slot/Pressure comparison passes 276 rows over both
profiles. The exact saved old module fails 24 rows by spending retired PP;
its output is retained as the negative control.

The complete matrix executes unchanged Gen1 reference
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; held-item CI uses its separately
pinned `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Both checkouts stay clean
and read-only. The maintained LuaJIT runtime is pinned at
`a4c064539ea931274d407e1249b4bb575424a0f4`, matching contract CI. Tests run
with `nice -n 19`. New Lua sources/fixtures pass AST-verified formatting;
the workflow passes actionlint. Actual imported scenarios use explicit GBA
rules, constructed parties and public menus without a normal SAVE or
ROM/cache distribution.

Raw local successes, failures, interrupted matrices, negative controls and
full-suite logs remain under `tmp/choice-band-qa/`. Interrupted matrices were
repeated completely on clean commits before these acceptance results.

## Remaining native execution gaps

The planner comparison retains all recorded RNG, events, HP, learned moves,
current/retired PP and complete planning held payloads. It does not observe
PP inside `battle.move_used` or certify the entire damaging script.

A separate 72-row actual-script diagnostic retains 48 differences: ordinary
and Pressure callbacks observe PP before reduction in Gen1 and after reduction
in Gen2; native zero-PP failures still emit the event whereas Gen2 does not.
The initial probe incorrectly supplied a PP slot for an ordinary called child;
its raw result is retained separately from the corrected native-call probe.
No observation fields were dropped to obtain the corrected result.

A separate complete held-read phase probe still observes 10 native reads
versus 11 host reads for successful Sleep Talk; awake, empty-pool and blocked
probes retain their matching 2/2/4 counts. King's Rock/Shell Bell command
ordering remains open. Successful Mirror Move target/history selection,
Metronome catalog/RNG parity, other attack-canceller phases and full native
playthrough/graphics are also not certified by this PR.
