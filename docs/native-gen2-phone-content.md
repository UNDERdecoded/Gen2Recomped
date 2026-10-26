# Semantic contacts in the native Gen2 phone book

`phone_contacts` presents imported numeric records through explicit phone and
trainer identity metadata. Changes reach `map_scripts.phone`, the actual
Pokegear, native incoming-call selector and Gen2ScriptVM phone scripts. The
non-trainer `number` is kept separate from native map group/number fields.
Names remain imported or authored text; localized trainer names never select
trainer identities. Ambiguous map spellings are not guessed.

New contacts append after the full imported row bound, including reserved
holes. Existing indices cannot move; removed records retain reservations
within the load. Explicit indices are recommended when changing enabled mod
sets. Saved numeric slots are never rewritten. Reads and iterator rows are
detached; finite/cycle, identity, index, mask and native-script validation
happens before journaling the operation. Failed entries roll back, reload
retires unchanged owned rows, and external native edits survive. Other
generations report an unavailable target and perform no native writes.

Caller/callee names and `callerKey`/`calleeKey` currently address existing
imported native script keys. Native VM execution remains authoritative.
Authored new scripts, forward references, the complete legacy Phone facade,
rematch-event semantics and actual story/hardware acceptance remain open.
This is a native content bridge, not a complete phone parity claim.

The focused synthetic suite runs the actual Loader, Pokegear saved book,
incoming selector, Gen2ScriptVM and ScriptRunner across Gold/Silver/Crystal,
API1/2 native. It also checks invalid-entry rollback,
index ownership, detached reads, reload, external changes and target isolation.
No GPU or complete playthrough claim follows from these tests.

Original implementation by Roxas2712; existing upstream and third-party rights
and credits remain applicable. See the [specific PR contribution permission and credits](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md).
