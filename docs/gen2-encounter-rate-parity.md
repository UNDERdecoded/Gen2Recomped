# Gen 2 encounter rate and surfing fixes

Gold, Silver and Crystal now extract the surfing level comparison operands,
Bug Contest grass rates and super-tall collision classes from their own ROMs.
The cache marker is `gen2-field-encounters-v7`; rebuild and reimport these games
to regenerate the fields. Older caches use the verified original-ROM defaults.

Walking in contest grass now rolls the encounter rate before choosing a mon,
rather than starting a battle every step. Normal grass uses 51/256; super-tall
grass uses 102/256. Repel compares the selected level against the first healthy
party member; equal levels are allowed. Sweet Scent still skips the walking
rate and Repel checks.

Surfing encounters, including Sweet Scent while surfing, now add 0–4 levels.
The byte boundaries are 89, 165, 216 and 242. Fishing, land encounters and other
generations retain their own level rules. Slot tables are never mutated.

The currently playing March or Ruins of Alph radio track doubles the encounter
rate with the native byte wrap; Lullaby halves it. Cleanse Tag applies afterward,
including in contest grass. This fixes rate calculation, not the unfinished
radio station tuning UI or scheduling of its programs.

`python tools/run_lua_check.py tools/gen2_encounter_rates_check.lua` verifies
83,726 cases across all three actual ROMs: extracted operands, all water-level
RNG bytes, production walking integration, rate bytes with all relevant music
and held-item states, contest collision classes and Repel boundaries.
Related field, contest-flow, swarm and wild-intro checks also pass. These are
headless behavioral checks; handheld controls, graphics and radio playback
still need device testing. Full ROM parity remains ongoing.

Sources:

- [Gold/Silver wild encounters](https://github.com/pret/pokegold/blob/master/engine/overworld/wildmons.asm)
- [Crystal wild encounters](https://github.com/pret/pokecrystal/blob/master/engine/overworld/wildmons.asm)
- [Gold/Silver contest steps](https://github.com/pret/pokegold/blob/master/engine/overworld/events.asm)
- [Crystal contest steps](https://github.com/pret/pokecrystal/blob/master/engine/overworld/events.asm)
