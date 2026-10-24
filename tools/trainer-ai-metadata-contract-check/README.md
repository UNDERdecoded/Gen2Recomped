# Native trainer AI metadata

```sh
python3 tools/trainer-ai-metadata-contract-check/check.py --gen1 /path/to/gen1 --lua /path/to/luajit
```

The reference must be clean at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.
Six isolated workers compare native importer outputs, using only synthetic
cartridge bytes. Gen 2 reads two real seven-byte attribute rows through each
engine's actual trainer/group reader, including duplicate/empty stocked slots.
Manifest/symbol-table IO is fixture data; the attribute producer is not mocked.

For FireRed and Emerald, the reference's actual item-pack extractor reads 583
effect-byte combinations and serializes its native cache records. The host
reads the same bytes through `RomGba` and its new raw-effect reader. Coverage
includes every byte-4/byte-5 mask independently and compound EV/PP/friendship
masks. The synthetic reference item-table fixture is bounded to native row 13;
other cartridge records/assets are not needed or copied. The paired results
include 1,168 exact metadata records in total.

This is an importer/format contract, not mod-callback, AI policy, full-ROM
reimport, native gameplay, presentation or save compatibility proof. The host
unit suite also executes its actual item-effects stage, checks that existing
parsed healing/friendship values survive, round-trips the emitted cache data,
and refuses missing/truncated/invalid attribute/effect records.
