# Emerald field poison and walking friendship

Field poison now includes badly poisoned Pokémon, applies the native friendship loss on fainting, uses the extracted `FIELD_POISON` effect, and displays the native fainted wording. A healthy egg cannot prevent ordinary field blackout. Secret Bases pause both damage and the poison step counter. Already-fainted poisoned residents are resolved once, with status cleared to avoid repeated penalties.

New Emerald Pokémon receive their extracted species friendship value. Walking checks each non-egg resident independently at 128-step boundaries, with a 50% chance of +1, then Luxury Ball and matching region-section bonuses. The phase lives in the save; fainted residents remain eligible. Soothe Bell rounds the base walking gain back to +1. Older residents missing friendship are initialized when walking or poison handling first needs it.

References: [field poison](https://github.com/pret/pokeemerald/blob/master/src/field_poison.c), [field step counters](https://github.com/pret/pokeemerald/blob/master/src/field_control_avatar.c), [Pokémon creation and friendship](https://github.com/pret/pokeemerald/blob/master/src/pokemon.c), and [native fainted string](https://github.com/pret/pokeemerald/blob/master/src/strings.c).

New functional checks: `tools/emerald_field_poison_check.lua` (1,598) and `tools/emerald_friendship_check.lua` (437). Related daycare, breeding, and Gen2/Gen4 checks also pass. No reimport is required.

The existing poison screen flicker remains an approximation of Emerald's mosaic effect. Battle-facility poison loss scripts, all friendship events, and exact cartridge RNG streams are outside this batch. The fainted line uses native English wording as a fallback because older extracted caches omit that global UI string.
