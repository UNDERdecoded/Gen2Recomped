# Crystal caught-data native owners: upstream offer

This payload builds on the separately offered source-identity integration
(#402 and its stated prerequisites). Its independently qualified implementation
is `6ce0e17c8999f82a5ba0aa3deded8342f78c57cd`, against original upstream main
`8d5b4387420cc1fdcadf58ad4ca78a7d8596e41d` plus those offered dependencies.

The source Mon caught-data APIs share one owner with actual native catch/box,
contest, GivePoke, fixed-OT/NPC trade and hatch arrivals. Friendship and trade
OT marks read live canonical fields. The Crystal SRAM layout imports/exports
those fields in every party/box/daycare record. Gold/Silver and unreviewed hack
layouts retain their opaque reserved word. Legacy native packed-only records
hydrate at validation without replacing the Pokemon, its moves or stats.

The first real combined test found missing native Gen2Landmarks and
Gen2Save.pokemonRecord dependencies in the older host. Their actual shared
implementations are included: landmark identities/orders are cartridge/version
aware; the record exporter calls the same existing encodeMon/name owners.
No fabricated facade, private mod implementation or changed outcome assertions
is used to make the tests pass. No newer options-record constructor is claimed. The final public setters also
retain any opaque historical word, matching the source semantics. The codec
fixtures now call both setters directly on all reserved layouts, rather than
only assigning canonical fields by hand.

Selected ROM-free suites passed on the qualified implementation:

- source caught-data arithmetic/signatures: 393,307 checks, all 65,536 pairs;
- native SRAM codec and layout preservation: 7,970 checks;
- actual SDK/arrival/consumer and saved RTC paths: 133 checks;
- source fields on native constructors/validation: 170 checks;
- native trainer friendship: 24,270 checks;
- source identity arithmetic: 262,168 checks;
- source identity actual SDK/native callbacks: 450 checks.

This proves selected semantics on the actual older combined host. It does not
claim the full official suite, GPU/window acceptance, final packages or full
source Mon/Battle/VASC parity. Supplied mods, ROMs, reference and player profiles
were not edited. The corresponding fork change has its own exact-tree gates.

Contributions by Roxas2712 — https://github.com/Roxas2712
Original additions are offered to Cedric/UNDERdecoded under LICENSE-ROXAS2712.md.
Existing upstream and Gen1/third-party grants and authorship remain effective;
no whole foreign file is assigned to Roxas2712 by this contribution.
