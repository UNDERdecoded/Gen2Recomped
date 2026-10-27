# Semantic tileset pair identities

Compatibility texture names resolve from the exact original primary AND
secondary bank addresses. A map name or shared primary graphics is insufficient:
two layouts may share graphics yet use different secondary metatiles/attributes.
`src.compat.gen1.PairIdentity` translates source identity metadata without
renaming native maps, mutating shared pair/bank records, building textures or
changing the native renderer.

`lookup(edition, primaryAddress, secondaryAddress)` returns the semantic pair,
primary and secondary names, and original dataset tileset alias. `bind(nativePairs, nativeBanks, edition)` creates
an owned binding with `nativeId(name)`, `canonicalId(nativeId)`,
`descriptor(nameOrNativeId)` and `release()`. Descriptors are fresh tables and
expose semantic names, the original dataset tileset alias and explicit native pair/bank keys. They contain no raw
bank or GPU object. The binding retains the supplied native owner until release.
Unknown source pairs fail explicitly; no primary-only or map-name fallback is
used. Replacing a native record, changing its source address, role or pair keys
retires that lookup. Rebind to a new dataset owner after a session change.
Aliases to the same exact definition are safe. Different native definitions
claiming one semantic pair make reverse lookup ambiguous instead of choosing
one arbitrarily. Release drops all native table references.

The metadata contains 303 original pairs across five US cartridge editions:
FireRed 60, LeafGreen 60, Emerald 75, Ruby 54 and Sapphire 54. It is numeric
source-address and public semantic-name metadata, not cartridge bytes or art.
It applies to the pinned retail identities in the native manifests. It does
not claim automatic recognition of arbitrary modified ROM layouts.

## Verification and regeneration

Run `luajit tests/engine/compatibility_pair_identity.lua`: 4,339 checks cover all
303 rows and original dataset tileset aliases, round trips, independent descriptor edits, alias/ambiguity handling,
unknown secondary sources, owner/bank replacement, source/role/key changes,
release and weak ownership canaries. The metadata generator is byte-stable.

For regeneration, use a clean public reference at
`37a49b31f458d51ea9e00b90f2a247272ad09cb8` and your locally owned US cartridges.
Verify the complete ROM SHA1 against `tools/rom_manifest_EDITION.json` before
running each export from the reference directory:

```sh
luajit /absolute/engine/tools/pair-identities/export.lua EDITION /absolute/ROM SHA1 /absolute/exports/EDITION.json
```

Create one JSON per edition: firered, leafgreen, emerald, ruby and sapphire.
`export.lua` invokes the original complete map census/registration, recording
resolved semantic pair names and both physical source header addresses.
`assemble.py` rejects contradictory pair/bank names and duplicate map entries:

```sh
python3 tools/pair-identities/assemble.py /absolute/exports --output /tmp/PairNames.lua
cmp src/compat/gen1/PairNames.lua /tmp/PairNames.lua
```

For the real native cross-check, put the five absolute ROM paths in
`exports/inputs.json` keyed by edition and create a fresh output directory.
With companion map identity #239 and cartridge registrations #183/#186/#187:

```sh
POKEPORT_IDENTITY=oasc-gen2recomp-qa-pairs-UNIQUE \
PAIRS_ENGINE=/absolute/engine PAIRS_ORACLE=/absolute/exports \
PAIRS_OUT=/absolute/fresh-output love /absolute/engine/tools/pair-identities/rom-host
```

Use LÖVE 12 and retain at least 8 GiB free. The host has no graphics, window or
audio; it checks each ROM SHA1, runs real layout/map/tileset extraction with
only image generation/writes bypassed, and verifies pair names/addresses and
reverse native ownership for every actual map. It matched all 2,156 maps and
303 pairs. Source hashes/counts are in `docs/qa/native-pair-identities.json`.
These are new CPU import/identity measurements; no GPU/gameplay acceptance is
claimed. No player profiles or saves are used.

The helper is an internal atlas-identity prerequisite. Native texture leases,
animated palette revisions and the full older atlas API remain to be connected.
It is not installed as a replacement field or tileset runtime. Full unchanged
Origami execution and overall feature parity remain open.

The frozen composed source at `f9f95603` passes 329/329 engine suites,
SDK 3/3 and Dramatic Shape B30. These results include the existing Gen2
regression suites; they are not a full visual or story-parity certification.

The source dataset tileset alias is verified independently, rather than
guessed from the pair spelling. The native map facade needs this additional
name while preserving its explicit native pair key. Real source/native
comparison agrees on all 303 aliases and 2,156 map assignments.

The source-alias addition also passes the final composed regression at
`9fcc703e`: engine 329/329, SDK 3/3 and Dramatic Shape B30.
