# Native GSC species identities

An unchanged consumer can use the native Pokemon's `species` to select its
model. Numbered importer placeholders such as `SPECIES_155` previously stayed
on the runtime Pokemon, even though named registry lookups were available.
That lookup alone cannot satisfy a catalog keyed by `CYNDAQUIL`.

The normal pre-mod `Data:seedDefaults` pass now canonicalizes a complete native
Gold/Silver/Crystal graph. It requires all 251 declared slots, matching record
IDs, native indices and dex numbers, and no authored lookup/collision. Partial
datasets, other generations and alternative cartridges retain their own IDs.
The names are stable constants rather than localized display names.

Species records, encounter/trainer/gift/evolution references and species-keyed
runtime tables change together, in place, after an atomic collision preflight.
Existing table identity, native indices, art paths and literal text/provenance
remain intact. `FARFETCHD` and `MR_MIME` use the public punctuation convention;
their earlier spellings remain lookup aliases. Numbered addresses also remain
aliases, so registry editing, rollback, replacement and deletion still share
one stored record. A second default-seeding pass cannot revive a deleted row.

Native script byte operands resolve through the current species order. Numeric
writeback reads the native definition's index. Ditto/Nidoran breeding, Togepi
hatching, party queries, gifts, trades and roamers use the same identity space.
Save validation folds old IDs in party, sparse boxes, day care, held parties,
Hall of Fame, roaming and Pokedex state. It preserves true dex bits, native
health/moves and literal nicknames. The ordinary save codec owns persistence;
there is no file migration or original-save write in this normalization.

ROM-free regressions exercise the normal Data publication pass, actual Pokemon
construction for all 251 slots in three editions, the real registry, native
script compiler/executor, breeding/hatching and save encode/decode/validation.
The private unchanged-source diagnostic separately passes native Pokemon and
frozen Gen1-reference Pokemon through the supplied real model selector and
catalog: the preceding fork rejected 753/753 identities, and the corrected
graph accepts 753/753. That is selector evidence, not complete model rendering,
Windows, whole-mod or release qualification. GPU observations are recorded
separately. No mod source or protected installation is changed.

Original contributions by Roxas2712; see `LICENSE-ROXAS2712.md`. Existing
source rights and notices remain effective.
