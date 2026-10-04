# Emerald field-move audit

The party menu listed Surf and Waterfall but did not dispatch either move.
They now close the party menu, show the selected Pokémon's field-move sweep,
and call the existing mount/climb implementation. Waterfall checks surfing,
north-facing, the actual waterfall behavior and the required badge. Surf
uses the existing shore, collision, badge and fast-water checks and refuses
the party-menu action while already surfing.

Fly and Teleport now share Emerald's four allowed map types: town, city,
route and ocean route. Underwater is outdoors for other purposes, but cannot
be used as a Fly or Teleport departure map.

Dig checks the map header's allowEscaping flag as well as a recorded entrance.
Emerald now records that entrance when an outdoor map leads indoors; cave
floor transitions retain it. Its escape destination is the cell south of
the entrance. Escape Rope selects this destination instead of the heal point,
and refuses without consuming an item if no entrance has been recorded.
Gen 2 continues to record and return to the entrance cell itself.

Strength requires a facing pushable boulder and sets the native Strength flag.
Its used-message prefers the extracted field-move text. Sweet Scent checks
Emerald's wider land-encounter behaviors (including cave floor and sand),
and its water encounters no longer run Gen 2's separate water-level modifier.

## References

- [Travel gates and UpdateEscapeWarp](https://github.com/pret/pokeemerald/blob/master/src/overworld.c)
- [Teleport setup](https://github.com/pret/pokeemerald/blob/master/src/fldeff_teleport.c)
- [Strength setup](https://github.com/pret/pokeemerald/blob/master/src/fldeff_strength.c)
- [Sweet Scent encounter selection](https://github.com/pret/pokeemerald/blob/master/src/wild_encounter.c)

## Verification and remaining scope

`python tools/run_lua_check.py tools/emerald_field_menu_check.lua` checks
travel and Dig gates for all 519 extracted maps, recorded entrance routing,
party-menu dispatch/refusal, selected Pokémon propagation, Strength's flag,
Sweet Scent tile eligibility/water levels, Escape Rope consumption and Gen 2
escape recording. The existing reported-issue, Gen 3 field and Dive/Waterfall
suites were also run.

These changes use existing field animations. Their frame timing is not yet
verified against emulator footage. The party-menu Secret Power/Cut/Rock Smash
paths and party healing moves are covered by subsequent audits; mail still
needs further work. This audit does
not establish complete Emerald parity. No cache regeneration is required for
this batch. Device testing on Android remains outstanding.
