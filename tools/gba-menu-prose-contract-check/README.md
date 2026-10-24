# Native GBA menu-prose contracts

Use a clean Gen1Recomp checkout at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`:

```sh
python3 tools/gba-menu-prose-contract-check/generate-facts.py --gen1 /path/to/gen1 --check
python3 tools/gba-menu-prose-contract-check/check.py --gen1 /path/to/gen1
python3 tools/gba-menu-prose-contract-check/check.py --gen1 /path/to/gen1 --host-api 2
```

The unchanged public consumer runs through each real SDK in separate workers.
The reference calls its actual party action producer. Emerald receives a generated
manifest fixture through filesystem IO, so it exercises its profile's named-label
branch instead of silently falling back to FireRed's table keys. The actual
reference party-footer and FireRed Item-PC draw functions run with captured font
output and fixture artwork/palette/item data. No text producer is replaced.

Each configuration compares 261 native text values across both profiles: baseline,
replacement, wrong-profile isolation, primary TAKE/action CANCEL separation,
empty strings, line/page/scroll controls, removal and failed-owner rollback. The host also runs native
action/render integration checks. These tests do not prove pixel equivalence,
complete battle flow, every party message, Item-PC quantity/results, or DS support.
The source's native API 2 is not claimed as a portable source-string registry;
the host API-2 check explicitly uses `content_format: unified`.

`label-facts.json` contains public import name/address/table facts, no ROM text.
Regenerate by omitting `--check`; it is test provenance, not a runtime address map.
