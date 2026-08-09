-- The MYSTERY EGG errand, hand-ported from pokegold maps/MrPokemonsHouse.asm
-- (MrPokemonScript / ProfOakScript) and the ElmDirections / ElmAfterTheft
-- halves of maps/ElmsLab.asm.
--
-- Object order comes from the map's MapEvents block:
--   MR_POKEMONS_HOUSE_OBJ_001 = MR.POKéMON (SPRITE_GENTLEMAN)
--   MR_POKEMONS_HOUSE_OBJ_002 = PROF.OAK   (SPRITE_OAK, event flag $6C9)
--
-- Flow: talk to MR.POKéMON -> he hands over the MYSTERY EGG -> OAK walks
-- the player through the POKéDEX and registers his number -> back to ELM,
-- who takes the EGG.  ELM's own errand branch lives in elms_lab.lua and
-- reads the same flags.

local Errand = {}

Errand.GOT_STARTER = "EVENT_G2_GOT_STARTER"
Errand.GOT_EGG = "EVENT_G2_GOT_MYSTERY_EGG"
Errand.GOT_DEX = "EVENT_G2_GOT_POKEDEX"
Errand.DELIVERED = "EVENT_G2_DELIVERED_MYSTERY_EGG"
Errand.EGG_ITEM = "ITEM_069" -- MYSTERY EGG

-- Registering a number is what makes the POKéGEAR's PHONE card useful;
-- the unit itself has no bag entry in Gen2 (see src/ui/PokegearMenu.lua).
function Errand.registerPhone(save, name, text)
  save.phone = save.phone or {}
  for _, entry in ipairs(save.phone) do
    if entry.name == name then return end
  end
  save.phone[#save.phone + 1] = { name = name, text = text }
end

-- MrPokemonScript: the four intro lines, the EGG, then OAK's two lines and
-- the POKéDEX.  Written as a function rather than a row list because the
-- phone registration has no script command of its own.
local function mrPokemonTalk(game, ow, npc, done)
  local save = game.save
  local rows = { { "face_player" } }

  if save.flags[Errand.GOT_EGG] then
    rows[#rows + 1] = { "show_text", "MrPokemonText_ImDependingOnYou" }
    ow.runner:run(rows, { npc = npc, onDone = done })
    return
  end

  if not save.flags[Errand.GOT_STARTER] then
    -- no partner yet: ELM has not sent the player, so this is just flavor
    rows[#rows + 1] = { "show_text", "MrPokemonText_AlwaysNewDiscoveries" }
    ow.runner:run(rows, { npc = npc, onDone = done })
    return
  end

  rows[#rows + 1] = { "show_text", "MrPokemonIntroText1" }
  rows[#rows + 1] = { "show_text", "MrPokemonIntroText2" }
  -- MrPokemonsHouse_GotEggText is the "received MYSTERY EGG" line, so it
  -- rides give_item rather than being printed separately.  give_item halts
  -- the rest of the script when the bag is full, so the flag below cannot
  -- burn the gift -- make room and talk again, as in the original.
  rows[#rows + 1] = { "give_item", Errand.EGG_ITEM, 1,
                      "MrPokemonsHouse_GotEggText" }
  rows[#rows + 1] = { "set_flag", Errand.GOT_EGG }
  rows[#rows + 1] = { "show_text", "MrPokemonIntroText3" }
  rows[#rows + 1] = { "show_text", "MrPokemonIntroText4" }
  rows[#rows + 1] = { "show_text", "MrPokemonIntroText5" }
  -- OAK is standing right there and takes over (ProfOakScript)
  rows[#rows + 1] = { "show_text", "MrPokemonsHouse_OakText1" }
  if not save.flags[Errand.GOT_DEX] then
    rows[#rows + 1] = { "show_text", "MrPokemonsHouse_GetDexText" }
    rows[#rows + 1] = { "set_flag", Errand.GOT_DEX }
    -- the engine's own dex gate, so the START menu row appears
    rows[#rows + 1] = { "set_flag", "EVENT_GOT_POKEDEX" }
  end
  rows[#rows + 1] = { "show_text", "MrPokemonsHouse_OakText2" }
  rows[#rows + 1] = { "show_text", "MrPokemonText_ImDependingOnYou" }

  ow.runner:run(rows, { npc = npc, onDone = function()
    Errand.registerPhone(save, "MR.POKéMON",
      "Any new discoveries?\nDo tell me!")
    Errand.registerPhone(save, "PROF.OAK",
      "How is your POKéDEX\ncoming along?")
    if done then done() end
  end })
end

-- ProfOakScript: before the EGG changes hands OAK only comments; after it
-- he explains the POKéDEX.  Talking to him first used to do nothing at all
-- because this map had no script module registered.
local function oakTalk(game, ow, npc, done)
  local save = game.save
  local rows = { { "face_player" } }
  if save.flags[Errand.GOT_EGG] then
    rows[#rows + 1] = { "show_text", "MrPokemonsHouse_OakText2" }
  else
    rows[#rows + 1] = { "show_text", "MrPokemonsHouse_OakText1" }
    -- .Nudge: OAK points the player back at MR.POKéMON rather than
    -- leaving them with a dead end
    rows[#rows + 1] = { "show_text", "MrPokemonText_GimmeTheScale" }
  end
  ow.runner:run(rows, { npc = npc, onDone = done })
end

Errand.MR_POKEMONS_HOUSE = {
  talk = {
    TEXT_MR_POKEMONS_HOUSE_OBJ_001 = mrPokemonTalk,
    TEXT_MR_POKEMONS_HOUSE_OBJ_002 = oakTalk,
  },
}

return Errand
