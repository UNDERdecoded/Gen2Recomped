# Gold, Silver and Crystal field encounters

Sweet Scent now prints the ROM's used-move text before selecting an encounter.
It checks grass/water/cave terrain, excludes ice, requires a nonzero ordinary
encounter table, and selects directly without walking rate, Repel or Cleanse
Tag checks. During the Bug-Catching Contest it selects ContestMons and enables
the contest battle rules. Failure uses the extracted nothing-appeared text.

RockMonEncounter now uses the extracted RockMonMaps allowlist and corresponding
tree set, with a 40% encounter chance and the ROM's species/level weights. It
clears stale battle data and mirrors wTempWildMonSpecies at each cartridge's
own WRAM address. The subsequent ROM readmem/iffalse/startbattle sequence can
therefore start exactly one battle or end without looping.

The tree extractor now reads GetTreeMons' set limit. Gold/Silver have three
valid sets; Crystal has seven. The former seven-set assumption read encounter
bytes as pointers on Gold/Silver and discarded their Headbutt tables.

Validation: `python tools/run_lua_check.py tools/gen2_field_encounters_check.lua`
reads all three cartridges and checks every extracted tree row, rock map,
all 1,000 rate/slot combinations per version through the compiled ROM script
tail and production runner, terrain failures, time tables, surfing and contest
Sweet Scent. Graphics and input are stubbed; this is not a device playthrough.

Rebuild and reimport Gold/Silver/Crystal to obtain the new extracted fields.
The Gen2 cache revision has been bumped so stale imports are detected.

Headbutt now passes its encounter kind and time of day into wild battle
initialization and uses PokemonFellFromTreeText. Fishing now resolves the
Gen2 HookedPokemonAttackedText label rather than falling back to generic text.
Crystal's morning/day/night sleeping species lists and sleep duration are
extracted from its ROM. Sleeping tree encounters omit the opening cry.
Gold/Silver's direct species comparisons and duration are extracted separately:
their sleep rule also applies to ordinary wild encounters, and their opening
cry still plays. Those version differences are retained.

`python tools/run_lua_check.py tools/gen2_wild_intro_check.lua` constructs real
battles for all 251 species at each time of day, with and without the tree
encounter kind, checks status/counters/cries and extracted intro text, and
exercises sleep countdown and the overworld Headbutt entry point. No graphics
or audio hardware is exercised by these headless checks.

Remaining audit work includes the global no-wild-encounters flag lifecycle,
native field-move visuals and Crystal's complete front-sprite animation flow.

Primary references:
- [Gold/Silver Sweet Scent](https://github.com/pret/pokegold/blob/master/engine/events/sweet_scent.asm)
- [Crystal Sweet Scent](https://github.com/pret/pokecrystal/blob/master/engine/events/sweet_scent.asm)
- [Gold/Silver tree encounters](https://github.com/pret/pokegold/blob/master/engine/events/treemons.asm)
- [Crystal tree encounters](https://github.com/pret/pokecrystal/blob/master/engine/events/treemons.asm)
