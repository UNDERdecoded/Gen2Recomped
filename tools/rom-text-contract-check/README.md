# ROM-text portability work

This branch is preparing the separate `mod.content.rom_text` registry. The
registry now covers Gen-2 native battle prose and GBA Pokemon-storage actions.
Other GBA engine/UI readers still need explicit bindings; this is not blanket
coverage of every cartridge label.

`check-format.py --gen1 /clean/gen1 --lua luajit` compares actual native
GB/Gen-2 prose formatting against the clean reference at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. The host's real battle reader uses
the common formatter. Cases cover named and ordinal substitutions, deferred
player/rival tokens, end markers, missing prose and mismatch/fallback policy.
Printf-shaped strings do not invent dynamic slots in this native contract.

`generate-labels.py --gen1 /clean/gen1 --lua luajit` regenerates name/address
facts from the reference's public import metadata. `--check` verifies all
committed bytes without rewriting either checkout. No cartridge prose, ROM,
importer implementation or source scripts are copied. Gen-2 manifests supply
runtime prose-label membership. The GBA fixtures retain exact provenance for
the ten storage action/description labels that this change binds. The full
GBA catalog is not shipped as unused runtime data. A lazy host accessor avoids
loading unneeded Gen-2 profile tables.

These facts establish provenance. They do not, by themselves, prove that a
host menu reads a label dynamically: pre-extracted UI constants need explicit
bindings and native consumer tests before the public registry is published.
