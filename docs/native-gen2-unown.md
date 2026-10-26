# Native GSC Unown state

`src.pokemon.Gen2Unown` shares native Gold/Silver/Crystal form identity and
catch-order state between sprite selection, battle captures, script gifts,
VAR_UNOWNCOUNT, the native Unown dex and public consumers. Stored reference
letter overrides and DV-derived forms use the same sprite/counter decision.
The byte calculation follows the existing native GetUnownLetter arithmetic.

`src.core.gen2.Unown` is an explicit adapter to this service. `word(letter)`
reads the active native `Game.data.unown_dex.words`; an explicit native dataset
may be supplied as a second argument. No retail word catalogue or picture
paths are embedded in the adapter. `forms(pokemon)` maps A–Z names to the
actual numeric native form records; `formSprite` resolves the same records.
Reads follow the current dataset instead of retaining an old edition's data.

The native save remains `save.pokedex.unownDex` and `unownForms`. Public `dex`
reads return a detached list. Known ordered forms keep their order; missing
valid entries from an older set-only save are appended alphabetically. Reads
do not migrate saves. A new form writes the normalized ordered list and set;
no separate `save.unownDex` is created. New party and PC captures and script
gifts register only after successful transfer. Eggs and refused transfers do
not register a form.

`unown.unlocked` reports a newly recorded form once, after native state is
committed. Payload fields are `letter`, `name`, imported `word` and `count`.
Native API1/2 consumers use this same producer. Repeated catches,
reentrant duplicate writes and another species do not fire the event.

## Verification and limits

ROM-free coverage includes all 65,536 packed DV byte combinations, native
sprite and stored-letter selection, actual party/PC capture and gift paths,
old save reads, refused full storage, native counter/menu agreement, imported
word replacement, actual Loader consumers and event rollback boundaries.
Real-ROM checks are separate private receipts; ROM data is never committed.

This does not establish the complete reference Unown API: unlocked-set/wild
DV selection, puzzle/encounter gates, direct mutation of reference-shaped view
tables and the remaining legacy Pokédex screen protocol need further work.
Polished Crystal's 28 forms and other editions retain their previous native
catch paths. Full Unown story/GPU/hardware and complete VASC/Gen1 parity are
not claimed. VASC files and protected Gen1/player instances are unchanged.
