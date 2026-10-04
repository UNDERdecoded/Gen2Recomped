# Emerald party field moves

Cut and Rock Smash previously fell through the party-menu dispatcher to a refusal even when a valid object was in front of the player. They now start the facing object's extracted script at its field effect, skipping the interaction-only used-move dialogue as the native party callbacks do. Badge and elevation checks run before dispatch. The selected party slot feeds the cartridge's buffers and field effect; the native movement, object-removal flag, release, and Rock Smash encounter branches are retained.

Secret Power now dispatches the extracted cave, tree, or shrub creation callback from the party menu. It requires a north-facing player, a closed entrance carrying a valid base ID, and no owned base. The entrance ID is captured before the selected party slot can replace temporary variables. Existing-base relocation remains available through the overworld interaction script.

Reference implementation: [Cut](https://github.com/pret/pokeemerald/blob/master/src/fldeff_cut.c), [Rock Smash](https://github.com/pret/pokeemerald/blob/master/src/fldeff_rocksmash.c), and [Secret Power](https://github.com/pret/pokeemerald/blob/master/src/fldeff_misc.c). Script branches and text are read from the extracted Emerald ROM data, rather than rewritten dialogue.

Validation: `python tools/run_lua_check.py tools/emerald_party_field_moves_check.lua` executes real extracted programs against a headless overworld, checking selected-member effects, removal, encounter dispatch, refusals, and all three base creation callbacks. The broader field-menu, reported-issues, and map-popup checks also pass.

This does not establish full visual parity. Grass-clearing Cut and the cartridge's individual tree/rock/base effect particles still need work. Headless Secret Power creation ends locked because the destination map's load script takes over; this harness verifies creation and the destination warp, but does not run that map-load handoff. No new ROM extraction is required for this change.
