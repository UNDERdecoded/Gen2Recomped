# Emerald daycare resident handling

The deposit special restores move PP, including PP Up bonuses, using the extracted move registry. Withdrawal returns the boxed resident at full HP with persistent status cleared and stats calculated at its resulting level. Already-level-100 residents retain their original experience instead of receiving banked steps. Growth reports and price quotes now fill both native text buffers: resident nickname first, level gain or cost second.

References: [daycare routines](https://github.com/pret/pokeemerald/blob/master/src/daycare.c) (`StorePokemonInDaycare`, `TakeSelectedPokemonFromDaycare`, `GetNumLevelsGainedForDaycareMon`, `PrepareDaycareCostStringForSelectedMon`) and [Pokémon routines](https://github.com/pret/pokeemerald/blob/master/src/pokemon.c) (`BoxMonToMon`, `BoxMonRestorePP`).

`tools/emerald_daycare_resident_check.lua` passes 3,265 headless checks. Coverage includes every extracted move with zero through three PP Ups, fainted and statused residents, banked levels, prices, both resident text buffers, Shedinja, refusal when both pens are occupied, and shared Center healing. Existing timing, inheritance, egg-cycle, reported-issue, and Gen2 daycare checks also pass.

No reimport is needed. These changes do not establish full daycare visual parity, mail handling, or cartridge RNG timing.
