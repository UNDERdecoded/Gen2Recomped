# Gold, Silver and Crystal Day Care fixes

The Day Care audit corrected several differences from the three cartridges:

- Retrieval recalculates stats, restores full HP and PP (including PP Ups),
  clears status and applies the ROM's minimum EXP for the retrieved level.
  This intentionally retains the cartridge's EXP-rounding behavior.
- Grown Pokémon require the initial "want to see" confirmation followed by
  the growth/price confirmation. Both numeric RAM operands are substituted
  separately using their order in the extracted text. Declining either
  confirmation leaves the boarded Pokémon and money unchanged.
- Insufficient money takes precedence over a full party, as in the ROM.
- Breeding rejects matching Defense DVs and matching lower three Special-DV
  bits, including Ditto pairs. The yard reports this as "brimming with
  energy"; ordinary compatible pairs use the appropriate other text.
- Egg attempts start after 150–255 steps, then use random byte countdowns.
  Zero wraps to 256 steps. Per-attempt thresholds are 10/256, 30/256,
  40/256 or 80/256 according to species and trainer-ID compatibility.
- Accepting an egg restarts the initial countdown. A full party retains the
  pending egg. Yard dialogue names the keeper and plays the Pokémon cry;
  retrieval also plays its cry.
- Eggs inherit Defense and the lower three Special-DV bits from Ditto or
  the parent of the opposite gender. Attack, Speed and the upper Special
  bit remain random; HP DVs and stats are recalculated afterward.
- Nidoran eggs use the cartridge's equal male/female split. Inherited moves
  follow the father's slot order, retaining the four most recent distinct
  eligible moves rather than processing separate move categories.
- Hatching uses a shared 256-step cycle and stops at the first ready egg.
  It records current-trainer ownership, updates seen/owned Pokédex entries,
  sets the Togepi story flag and offers a nickname.

`python tools/run_lua_check.py tools/gen2_daycare_check.lua` uses all three
extracted datasets, checks egg-roll thresholds against actual ROM bytes,
and exhausts all 256 random rolls for each compatibility class. It covers
both keepers, grown and unchanged levels, declined confirmations, funds,
party capacity, matching Ditto DVs and egg transfer. UI prompts and audio
are stubbed, so these checks do not establish device or visual parity.

`python tools/run_lua_check.py tools/gen2_egg_inheritance_check.lua` passes
18,141 assertions across Gold, Silver and Crystal. It exhausts Attack and
Special DV combinations for ordinary and Ditto pairs, all 256 Nidoran
random rolls, inherited move ordering, party egg cycles and both nickname
choices through the production hatch entry point.

The daily/lottery and contest flow checks continue to pass. No ROM reimport
is required specifically for these Day Care runtime changes; rebuild the
application to include them. Hatching animation, visual layout and exact
ROM text remain unverified; these changes do not establish full ROM parity.

References: [Crystal Day Care events](https://github.com/pret/pokecrystal/blob/master/engine/events/daycare.asm),
[Crystal breeding](https://github.com/pret/pokecrystal/blob/master/engine/pokemon/breeding.asm),
[Gold retrieval](https://github.com/pret/pokegold/blob/master/engine/pokemon/move_mon.asm).
