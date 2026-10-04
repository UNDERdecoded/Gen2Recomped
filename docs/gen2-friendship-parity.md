# Gold, Silver and Crystal friendship and medicine fixes

The audit found that walking applied the generic +2/+2/+1 friendship row
every 128 steps, while several battle and item paths only called Yellow's
companion logic. Original Gold, Silver and Crystal now use their own rules:

- Walking adds one point every second 256-step cycle. Eggs are excluded,
  fainted Pokémon are included, and both cycle phases survive local saves.
  This shares the persisted byte counter used for egg hatching.
- Gym challenges increase friendship for healthy party Pokémon. Fainting
  applies the ordinary or stronger-foe penalty at the cartridge's 30-level
  boundary; repeated queued faint handling cannot apply it twice.
- Field-poison fainting applies its larger friendship penalty.
- Successful vitamins, Rare Candy, X stat items and TM/HM teaching apply
  their friendship changes. Ordinary potions, cures and revives do not.
- Crystal reads the caught landmark from existing `caughtData` for its
  larger level-up bonus in that location. Gold and Silver use the normal
  level-up row. New-catch caught-data stamping remains a separate audit.
- Energypowder heals 50 HP, Energy Root heals 200 HP, Heal Powder cures
  status and Revival Herb fully revives. Successful use applies the
  appropriate bitter penalty and displays the extracted bitter text.
  Failed use and eggs receive no effect or penalty.
- Gen 2 status cures reject fainted Pokémon. Repeated X Accuracy, Dire Hit
  and Guard Spec use is refused while the corresponding effect is active.

`python tools/run_lua_check.py tools/gen2_friendship_check.lua` passes
20,779 assertions. The suite reads each version's ROM friendship table,
exhausts all 256 happiness values for the supported events and checks egg
exclusion, local save/reload, production walking, fainting, field poison,
medicine success/refusal, heal amounts and version-specific behavior.
UI and audio are stubbed; this does not establish visual or device parity.

These are runtime changes: rebuild the application, with no ROM reimport
required specifically for this pass. Remaining friendship events and raw
cartridge step-counter import/export are outside this pass.

References:
[Gold friendship](https://github.com/pret/pokegold/blob/master/engine/events/happiness_egg.asm),
[Crystal friendship](https://github.com/pret/pokecrystal/blob/master/engine/events/happiness_egg.asm),
[Crystal step timing](https://github.com/pret/pokecrystal/blob/master/engine/overworld/events.asm),
[Crystal battle events](https://github.com/pret/pokecrystal/blob/master/engine/battle/core.asm),
[Crystal medicines](https://github.com/pret/pokecrystal/blob/master/engine/items/item_effects.asm),
[Crystal caught-location bonus](https://github.com/pret/pokecrystal/blob/master/engine/pokemon/level_up_happiness.asm).
