# Emerald: Secret Power, bicycles, evolution, EXP and naming

The Secret Power entrance script captures its base ID before the script reuses
VAR_0x8004 for a party slot. Creation and relocation use that captured ID, reject
ID zero, and store the entrance map's region section in VAR_SECRET_BASE_MAP.
The existing native room and return-warp handling remains in use.

Bicycles now consult the extracted no-running terrain rules for both mounting
and stepping. Long grass remains walkable on foot and blocks bicycles.

Nincada's completed evolution creates Shedinja after Ninjask learns its evolution
moves, if the party has room. The new Pokémon receives an independent copy of
the evolved Pokémon's moves, personality, IVs and EVs, clears its item/status/
ribbons/markings/mail, has one HP, and registers in the Pokédex. Emerald does
not require or consume a spare Poké Ball. Evolution also retains Gen3 IV/EV/
nature stats rather than recalculating with Gen1 DVs.

The opening lead now counts for EXP even before side slots are initialized.
Switching an undamaged Ralts out therefore splits EXP with the finishing
Pokémon. Gen3 divides the computed base EXP by participants, with the native
integer rounding order.

Naming uses Emerald's own BG tiles, tilemaps, palettes, cursor, button plates,
page labels, caret and underscores. It uses the native font and nickname
heading, four-row keyboard and separate three-button column. START selects OK;
A confirms. The Emerald import marker forces regeneration of old naming art.

## Verification

- `python tools/run_lua_check.py tools/emerald_reported_issues_check.lua`:
  regression checks with the real Emerald dataset, including the complete
  extracted Secret Power script, creation/relocation, party sizes 1–6, the actual
  battle EXP award, integer rounding and naming controls.
- `EMERALD_REPO=<repo> lovec tools/emerald_naming_render`: extracts the retail ROM
  assets and renders six production UI screens using real fonts/icons. All three
  pages were visually inspected. Output is ignored by Git; extracted cartridge
  graphics are not source assets.
- Existing field suite: 1,166 checks pass after correcting Windows source-file
  discovery and two stale source-search assertions.
- Existing battle-transition suite: 154 checks pass.
- Existing special-handler inventory suite remains stale: it expects 468 named
  specials, but the engine includes additional handlers from earlier work.
  Its other 1,836 checks pass; its two inventory assertions fail.

These checks do not establish an emulator framebuffer match or Android device
validation. The render is a real desktop LOVE render of production UI code.

## ROM references

- [Secret-base ownership and location](https://github.com/pret/pokeemerald/blob/master/src/secret_base.c)
- [Bike terrain collision](https://github.com/pret/pokeemerald/blob/master/src/bike.c)
- [Shedinja creation after evolution](https://github.com/pret/pokeemerald/blob/master/src/evolution_scene.c)
- [Naming layout and controls](https://github.com/pret/pokeemerald/blob/master/src/naming_screen.c)

`tools/emerald_naming_addresses.py` identifies the naming graphics from the
retail ROM's SpriteSheet table and palette references. Extraction addresses
are guarded to Emerald and recorded in `RomExtractorGen3.EMERALD_NAMING`.
