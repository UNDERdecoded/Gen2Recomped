# Complete native GSC animation data

Contributions by Roxas2712. Existing interpreter and identifier provenance
and applicable licences remain in `compat/gen1-gsc/` and `NOTICE.md`.

The importer previously stored a private flat program per animation index.
The player converted only its selected program into VM rows. Consequently
`AnimRunner.scriptForMove(data.battle_anims, move)` returned nothing and a
runner's data omitted every unselected move and shared call-only program.

The ROM decoder now retains actual instruction addresses. The importer
publishes the complete native interpreter schema: `moves`, named `ids`,
`scripts`, `scriptOrder`, objects, framesets, OAM sets, GFX and palettes.
Programs use their genuine hexadecimal ROM address, including shared
subroutines and the dummy table entry. Each program appears once; different
bytes claiming the same address are rejected. Branches contain one resolved
target key, without leftover pointer bytes. Registered non-ROM flat test
programs use an explicit `program:<id>:<index>` namespace rather than
pretending to have cartridge addresses.

Native `Gen2AnimPlayer` and its actual runtime/view use that complete imported
table directly. Changing moves changes the entry point and VM state, not the
data owner. Standalone source calls and source edits observe the same pool.
The original source-native `generation=2` schema is accepted directly,
without requiring the fork's private format or legacy index flags.
The previous flat input remains accepted for existing program registrations;
there is still one real interpreter, object pool and battle clock.

Gen2 cache revision 3 requests reimport of earlier generated animation data.
Saves and unrelated generation cache markers retain their existing contracts.
The import edition supplies the BG-function order independently of whatever
cartridge happens to be selected by a test or loader.

`tests/engine/gen2_animation_catalog.lua` reads generated ROM bytes through
the actual extractor and player, checks shared and call-only programs,
unselected moves, numeric/dummy entries, source edits and native wait/return
time. The GPU row fixture now also enters through the complete native data
schema. Actual ROM differential and GPU acceptance results belong to their
recorded source revisions; adding this path alone is not full unchanged-mod,
Windows or packaged-release acceptance. No mod or ROM program is edited or
committed.
