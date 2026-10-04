# Emerald egg-cycle audit

Emerald previously decremented each egg's remaining steps independently. It now advances a saved byte counter, processes eggs at phase 255, and wraps on the next step. An egg that reaches zero cycles waits until the next processing phase to hatch. The first ready egg stops the scan, leaving later eggs untouched for that phase.

Flame Body or Magma Armor on any non-egg party member doubles the cycle decrement. Fainted helpers count, multiple helpers do not stack, and a one-cycle remainder reaches zero safely. Bad eggs are skipped. Collecting or rejecting a daycare egg resets the shared phase. These changes are limited to Emerald.

Existing saves retain the `eggSteps` representation. At processing time, partial remaining cycles round upward, then the cycle result is stored as equivalent steps. An older save with no shared counter starts its new phase at zero; its historical phase cannot be reconstructed.

References: [daycare.c](https://github.com/pret/pokeemerald/blob/master/src/daycare.c) and [egg_hatch.c](https://github.com/pret/pokeemerald/blob/master/src/egg_hatch.c).

`python tools/run_lua_check.py tools/emerald_egg_cycles_check.lua` verifies phase boundaries, hatch delay, ability selection, helper rules, party order, bad eggs, legacy progress, overworld dispatch, daycare resets, and FireRed isolation. Hatch-scene visual parity and complete breeding inheritance are outside this audit. No reimport is needed.
