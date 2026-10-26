# Native GSC species-name compatibility

Retail Gold/Silver/Crystal imports store Pokémon under `SPECIES_001` through
`SPECIES_251`. The separate Gen1Recomp reference (`535a5ec0`) exposes symbolic
species identifiers such as `EEVEE` and `CHIKORITA`. Mods querying the latter
could miss an existing native species and its extracted front image.

`Gen2SpeciesNames` publishes live symbolic lookups only for verified native
slots in the declared species order. The native row, its identity and its
iteration count are unchanged. Display names are not identity evidence.
Explicit authored symbolic rows and authored lookup metatables retain
precedence. Other games and expanded hacks do not infer these aliases.

The real Pokémon registry uses the same native address for reads, patches,
full replacements, removal, conflict preferences and
rollback. New Pokémon requested by a symbolic name store the native species
ID. Existing named save records remain readable without rewriting saves.
Deleted native rows cannot be resurrected by a stale alias.

The ROM-free suite `tests/engine/gen2_species_names.lua` passes 130 checks,
including actual API2 loader success/failure and actual Pokémon creation.
CI runs the suite
alongside the existing composed engine tests.

This fixes a demonstrated name-resolution gap, not every missing overworld
image. The supplied unchanged Johto package contains a runtime-sheet manifest
but lacks the referenced runtime PNGs; valid native front images and generated
small species images were independently inspected. Live actor diagnostics and
source-bound packaged OpenGL/Metal acceptance of this change are still pending.
No private mod assets or ROM data are included in this contribution.
