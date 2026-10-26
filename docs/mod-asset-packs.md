# Portable asset packs

Mods may declare `required_assets` and `optional_assets` arrays:

```json
{"required_assets":[{"importer":"lttp","pack":"sprites","version":">=1.0.0"}],
 "optional_assets":[{"importer":"lttp","pack":"music"}]}
```

Identities are lowercase letters, numbers, `_` and `-`. Requirements must be
dense arrays, unique across both lists; versions use the existing dependency
range grammar. Unknown optional packs stay unavailable. Missing, incompatible
or incomplete required packs stop the mod before its entry executes and block
hard dependents. The manager reports `missing_assets` and stages a restart once
the requirement is satisfied. The launcher displays the missing pack identity.

`mod.packs` provides `list`, `info(importer, pack)`, `entries(importer, pack)`,
`entry(importer, pack, entryId)`, `read(importer, pack, entryId)` and
`metadata(importer, pack, entryId)`. Calls return data or `nil, reason`.
Enumerated entries are sorted; nested metadata is detached from the stored
descriptor. Undeclared packs cannot be read through this API.

## Installing an existing extracted pack

Copy a portable pack directory, including its `pack.lua` and referenced files,
to `imports/asset_packs/<importer>/<pack>/` in the active game-data folder.
Select **Import asset packs from inbox** in the launcher's Mods panel. This
directory flow works with phone file sharing, Android storage and Switch MTP,
without requiring a desktop file picker or a shell command. It preserves the
original inbox files and reports independent failures within a batch.

The current catalogue recognizes `gen5_bw/battle_sprites`, `pmd_red/sprites`,
and `lttp/sprites`, `lttp/tiles`, `lttp/palettes`, `lttp/sfx`, `lttp/music`.
The final two are catalogue placeholders; no audio extraction is claimed.

A format-1 `pack.lua` returns a literal table with `format`, `importer`, `pack`,
`kind`, `version`, `source` (cartridge `md5`, optional `name`/`size`) and keyed
`entries`. Each entry records `file`, `size` and optional display/sprite fields.
`metadata={file="animation.lua",size=123}` references another literal table.
The supported kinds are sprite, tileset, palette, font, sfx, music and sample;
their file extensions are checked. No cartridge bytes or extracted assets are
included in the repository or tests.

Reads are bounded to 8 MiB per descriptor, metadata file or asset. File sizes
are checked before allocation. Data files support literal tables, arrays,
strings, booleans and finite numbers; they are parsed without executing Lua,
with byte, nesting and node limits. Paths cannot leave their pack directory.

The installer yields after each entry, writes content-addressed objects,
verifies staged bytes and atomically replaces `pack.lua` only after copying all
referenced data. Failed writes, truncated writes, failed replacements and
abandoned jobs leave the previous descriptor and its assets usable. Identical
objects are reused. Unreferenced objects after an interrupted install are
retained; the installer never deletes user source directories or guesses which
old assets are safe to remove. Concurrent installations into one destination
are not offered by the launcher.

## Native SNES graphics source

The same inbox action also checks `imports/asset_sources/lttp.sfc` (or
`lttp.smc`) in the active game-data folder. The native extractor recognizes the
1 MiB US revision with MD5 `608c22b8ff930c62dc2de54bcd6eba72`; a 512-byte copier
header is accepted and excluded from source identity. Unknown revisions fail
before extraction. No source cartridge is included or downloaded.

The extractor writes version `1.1.0` of three packs: 116 tile entries, 109
sprite entries, and six palette entries. These include 223 graphics sheets,
the 4bpp player sheet, and a 1024×1024 atlas of 4096 overworld metatiles with
map palettes and quadrant flips. Sheet defaults retain palette identities and
transparent index zero in entry attributes. This does not provide audio packs.

Extraction yields progress between sheets and atlas batches. Each pack uses
the same bounded immutable-object store and atomic descriptor publication as
the portable installer. Errors preserve the previous descriptor for the failed
pack. A changed destination root aborts publication. Complete matching packs
are reused. Raw sources run before portable inbox packs, so an explicitly
provided portable pack wins; independent source errors do not block those
portable installs. Inputs are preserved.

`src.import.PackProducer` also provides a shared engine-side producer with
`put`, `alias`, `finish`, `cancel` and `state`. It validates and detaches input
data, scopes the destination, stages and verifies writes, and publishes only a
complete nonempty pack. This is not an additional mod write permission.

## Scope and remaining work

This implements the portable pack producer/consumer lifecycle and an initial
native SNES graphics producer. Native extraction for the other two catalogue
families, background extraction workers, real-cartridge image/animation parity
and physical device gameplay remain open. A working contract does not establish that
an entire mod initializes or is playable. New engine changes also need a fresh
test release before they are present in distributed phone/console packages.

Validation: `luajit tests/engine/asset_pack_contracts.lua` exercises actual mod
loading, dependent recovery, required/optional semantics, detached metadata,
bounded reads, atomic failure recovery, inbox batching and launcher job paths.
The platform flags in this ROM-free test exercise the shared control flow;
they are not physical-device launch or gameplay evidence.

`luajit tests/engine/native_pack_producers.lua` additionally checks decompression,
bitplane decoding, palettes, metatile flips, bounded producer writes, cancellation,
scope changes and failure preservation. `tests/native_pack_runtime` exercises the
complete native extractor through actual LÖVE filesystem and PNG APIs, including
reuse and inbox overrides, under a fresh owned QA identity. Its inputs are
generated format fixtures. No real source cartridge was available for pixel
comparison; the resulting pack counts are not a visual-parity claim.
