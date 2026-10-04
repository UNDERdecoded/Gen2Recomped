# Gold, Silver and Crystal swarms

Fishing now consults the stored Qwilfish/Remoraid swarm type. GetFishGroupIndex's
comparisons and alternate group operands are extracted from each ROM. Crystal's
daily fishing flag is resolved through its engine flag table. Gold/Silver do
not check that flag, preserving their cartridge behavior after a daily reset.
Nonmatching groups and types retain ordinary fishing tables.

Grass/water swarm records are extracted separately from ordinary encounters.
The Gold/Silver swarm command takes only a map pair; Crystal takes a swarm kind
and a map pair. The extractor now resolves both forms correctly. Gold/Silver
keep one selected map, while Crystal keeps independent Dunsparce/Yanma maps,
each controlled by its native flag. Walking and Sweet Scent consult the active
table before selecting the current morning/day/night slots. Missing alternate
terrain falls back to the ordinary table without mutating the imported data.

Validation: `python tools/run_lua_check.py tools/gen2_fishing_swarm_check.lua`
reads all three actual ROMs. Checks cover all rod slot bytes, native bite
thresholds, all time periods, swarm types/daily enable states, alternate land
records, actual extracted phone command map operands, production activation,
save/reload and daily reset. These headless checks do not test device input,
phone ringing/choreography or graphics.

Rebuild and reimport Gold/Silver/Crystal for the new tables and script operands.
The cache revision is bumped to invalidate earlier extracts.

Radio music rate modifiers and native surfing level variation are now covered
by the encounter-rate checks. Further encounter audit work includes radio UI
tuning/playback, cartridge-save swarm-state conversion and the complete phone
call scheduler. Full ROM parity is not established by these changes.

References:
- [Gold/Silver fishing](https://github.com/pret/pokegold/blob/master/engine/events/fish.asm)
- [Crystal fishing](https://github.com/pret/pokecrystal/blob/master/engine/events/fish.asm)
- [Gold/Silver wild lookup](https://github.com/pret/pokegold/blob/master/engine/overworld/wildmons.asm)
- [Crystal wild lookup](https://github.com/pret/pokecrystal/blob/master/engine/overworld/wildmons.asm)
