# Native Gen2 summary and move-screen ownership

The Gen2 summary alias now accepts native `party`/`index` options as well as
an isolated `mon` and the existing positional shared constructor. It resolves
the actual Pokemon and native catalogs instead of treating an options table
as a Pokemon. Party navigation refreshes pictures and native identity in
place, preserving installed draw methods, surface ownership and callbacks.

Native status pages retain directional wrapping; A closes the final blue
page. SELECT on the green page opens the real move manager. Moving a slot
reorders the existing move record, preserving PP and PP Ups; cancellation,
egg skipping and close continuations retain their native owners. Species,
move, held-item, type, OT and growth queries read the actual engine data.
The move-detail frame uses native border glyphs rather than requiring Unicode
box characters in the imported text font. No consumer or mod patch is used.

The ROM-free `tests/engine/gen2_summary_contract.lua` regression fails on the
preceding implementation and passes 326 checks across five Gen2 editions,
with shared Red/FireRed/Emerald navigation regressions. Together with the
existing live-model, party and FireRed suites, 807 checks pass on this
independently adapted upstream-PR composition. These are source/input
checks with synthetic fixtures, not full-client, Windows or release acceptance.

A separate fork-only unchanged-client Metal smoke reached the Team and status/move pages,
then exposed an unavailable reference-engine sound resolver during the first
actual move swap. That candidate is rejected. This fork's importer already
installs the native sound label, so the adapted swap now uses this branch’s existing Sound.play
path directly. The regression includes a present imported cue even with no
audio device and fails on the preceding candidate. Visible swap/close/Potion
acceptance for the correction is still pending; the earlier visible pages do
not qualify that complete workflow or the new package.

Layout/input provenance: Gen1Recomp `535a5ec0`,
`src/ui/gen2/SummaryMenu.lua`. Existing author rights and notices remain
applicable; integration additions by Roxas2712 follow the contribution terms
published in
<https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md>.
