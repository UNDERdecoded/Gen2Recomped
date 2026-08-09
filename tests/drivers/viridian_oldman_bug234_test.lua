-- Driver: the Viridian old-man swap is re-applied for an imported save (#234).
-- pokered data/maps/toggleable_objects.asm:48 ships the sleeper ON and the
-- walker OFF; only OaksLabOakGivesPokedexScript flips the pair.  GenSave does
-- not model wToggleableObjectFlags, so story.lua's onEnter re-derives it.
--   POKEPORT_DRIVER=tests/drivers/viridian_oldman_bug234_test.lua \
--     POKEPORT_IDENTITY=bug234 POKEPORT_VERSION=red SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapScripts = require("data.scripts.init")
  local OverworldState = require("src.world.OverworldController")
  local Pokemon = require("src.pokemon.Pokemon")

  local MAP = "VIRIDIAN_CITY"
  local SLEEPER = "VIRIDIANCITY_OLD_MAN_SLEEPY"
  local WALKER = "VIRIDIANCITY_OLD_MAN"
  local MAP_LABEL = "ViridianCity"
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- ../pokered/data/maps/objects/ViridianCity.asm:
  --   object_event 18, 9, SPRITE_GAMBLER_ASLEEP, STAY, NONE, ..._OLD_MAN_SLEEPY
  --   object_event 17, 5, SPRITE_GAMBLER,        WALK, LEFT_RIGHT, ..._OLD_MAN
  local SLEEPER_XY = { x = 18, y = 9 }
  local WALKER_XY = { x = 17, y = 5 }
  -- (18,7) sits in the three-cell north corridor with the sleeper's patch two
  -- cells south and the walker two north, so one screen holds both
  local VIEW = { x = 18, y = 7, facing = "down" }
  -- (17,6) is the only free floor under the walker's home cell ((16,6) is wall)
  local TALK = { x = 17, y = 6, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function objDef(name)
    for _, o in ipairs(game.data.maps[MAP].objects or {}) do
      if o.name == name then return o end
    end
    return nil
  end

  local function npcNamed(name)
    local ow = game.overworld
    for _, n in ipairs((ow and ow.npcs) or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- ---- preconditions the eye cannot check --------------------------------
  local hooks = mapScripts.get(MAP)
  check(MAP .. " has a map-script table", type(hooks) == "table")
  -- a base file that replaces the whole M.VIRIDIAN_CITY entry leaves the
  -- sleeper exactly where the bug left him, with nothing on screen to say why
  check(MAP .. ".onEnter survived the base-script merge",
        type(hooks) == "table" and type(hooks.onEnter) == "function")

  local sleeperDef, walkerDef = objDef(SLEEPER), objDef(WALKER)
  check(SLEEPER .. " exists in the map data", sleeperDef ~= nil)
  check(WALKER .. " exists in the map data", walkerDef ~= nil)
  if sleeperDef then
    check(("%s sits at (%d,%d) as in ViridianCity.asm")
            :format(SLEEPER, SLEEPER_XY.x, SLEEPER_XY.y),
          sleeperDef.x == SLEEPER_XY.x and sleeperDef.y == SLEEPER_XY.y)
    -- toggleable_objects.asm has him ON, so the extractor must NOT mark him
    -- hidden: that default is the whole reason he is still there
    check(SLEEPER .. " defaults to VISIBLE (toggle_object_state ... ON)",
          not sleeperDef.hidden)
  end
  if walkerDef then
    check(("%s sits at (%d,%d) as in ViridianCity.asm")
            :format(WALKER, WALKER_XY.x, WALKER_XY.y),
          walkerDef.x == WALKER_XY.x and walkerDef.y == WALKER_XY.y)
    check(WALKER .. " defaults to HIDDEN (toggle_object_state ... OFF)",
          walkerDef.hidden == true)
    check(WALKER .. " is the pacing GAMBLER, not the asleep sprite",
          walkerDef.sprite == "SPRITE_GAMBLER")
  end

  -- A at the walker has to reach the catch-tutorial script, or the right
  -- sprite in the right place is still the wrong NPC
  local talkRows = mapScripts.talkScript(MAP, "TEXT_VIRIDIANCITY_OLD_MAN")
  check("TEXT_VIRIDIANCITY_OLD_MAN has a talk script",
        type(talkRows) == "table" and #talkRows > 0)
  local sawAsk, sawDemo = false, false
  for _, row in ipairs(talkRows or {}) do
    if row[1] == "ask" then sawAsk = true end
    if row[1] == "old_man_demo" then sawDemo = true end
  end
  check("the walker's script opens the \"in a hurry?\" ask", sawAsk)
  check("the walker's script leads into the catch demo", sawDemo)
  -- ViridianCityOldManText vs ViridianCityOldManSleepyText are one label apart
  -- in the ROM, so check the pointer lands on his line and not the sleeper's
  local hurry = game.data:resolveText(MAP_LABEL, "TEXT_VIRIDIANCITY_OLD_MAN")
  check("TEXT_VIRIDIANCITY_OLD_MAN resolves to a string",
        type(hurry) == "string" and hurry ~= "")
  check("it is the coffee/hurry line, not the sleeper's grumble",
        type(hurry) == "string" and hurry:find("hurry", 1, true) ~= nil)
  if type(hurry) == "string" then
    U.log("walker's opening line reads:", (hurry:gsub("\n", " / ")))
  end
  local sleepyText = game.data:resolveText(MAP_LABEL,
                                           "TEXT_VIRIDIANCITY_OLD_MAN_SLEEPY")
  check("the sleeper's own line still resolves (he is not deleted, just hidden)",
        type(sleepyText) == "string"
        and sleepyText:find("private", 1, true) ~= nil)

  -- a playable party so the hand-off is a real game, not a locked window
  game.save.party = {
    Pokemon.new(game.data, "CHARMANDER", 12),
    Pokemon.new(game.data, "PIDGEY", 10),
  }

  -- ---- BEFORE control: no Pokedex ----------------------------------------
  -- Proof that the sleeper renders at all; without it, "the ground is empty"
  -- could just mean the object never spawns.
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_POKEDEX = nil
  game.save.objectToggles = {}          -- exactly what an import leaves behind
  U.teleport(game, MAP, VIEW.x, VIEW.y, VIEW.facing)
  U.wait(20)

  local ctrlSleeper = npcNamed(SLEEPER)
  local ctrlWalker = npcNamed(WALKER)
  check("BEFORE (no Pokedex): the sleeper is on the map", ctrlSleeper ~= nil)
  if ctrlSleeper then
    check(("BEFORE: he is lying on (%d,%d)"):format(SLEEPER_XY.x, SLEEPER_XY.y),
          ctrlSleeper.cellX == SLEEPER_XY.x and ctrlSleeper.cellY == SLEEPER_XY.y)
  end
  check("BEFORE: the walking old man is NOT on the map", ctrlWalker == nil)
  if not U.shot(game, SHOT_DIR .. "/bug234_before_pokedex.png") then
    U.log("FAIL could not capture the BEFORE screenshot")
  else
    U.log("captured", SHOT_DIR .. "/bug234_before_pokedex.png")
  end

  -- ---- AFTER: the reported case ------------------------------------------
  -- EVENT_GOT_POKEDEX set and objectToggles empty is byte-for-byte the state
  -- a converted .sav arrives in; re-entering the map is what the reporter did.
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.objectToggles = {}
  U.teleport(game, MAP, VIEW.x, VIEW.y, VIEW.facing)
  U.wait(20)

  local toggles = (game.save.objectToggles or {})[MAP] or {}
  check("onEnter recorded HideObject TOGGLE_LYING_OLD_MAN",
        toggles[SLEEPER] == false)
  check("onEnter recorded ShowObject TOGGLE_OLD_MAN", toggles[WALKER] == true)
  if sleeperDef then
    check("objectVisible now says the sleeper is hidden",
          OverworldState.objectVisible(game.save, MAP, sleeperDef) == false)
  end
  if walkerDef then
    check("objectVisible now says the walker is shown",
          OverworldState.objectVisible(game.save, MAP, walkerDef) == true)
  end

  local liveSleeper, liveWalker = npcNamed(SLEEPER), npcNamed(WALKER)
  check("AFTER: the sleeper is gone from the live NPC list", liveSleeper == nil)
  check("AFTER: the walking old man is in the live NPC list", liveWalker ~= nil)
  local ow = game.overworld
  check(("AFTER: nothing occupies (%d,%d) any more")
          :format(SLEEPER_XY.x, SLEEPER_XY.y),
        ow and ow:npcAtCell(SLEEPER_XY.x, SLEEPER_XY.y) == nil)
  if liveWalker then
    U.log(("walker is pacing around (%d,%d)"):format(liveWalker.cellX, liveWalker.cellY))
  end
  if not U.shot(game, SHOT_DIR .. "/bug234_after_pokedex.png") then
    U.log("FAIL could not capture the AFTER screenshot")
  else
    U.log("captured", SHOT_DIR .. "/bug234_after_pokedex.png")
  end

  -- ---- walk up to him and talk, so the box is open on hand-off ----------
  -- He paces LEFT_RIGHT, so TALK is only right while he is on his home column;
  -- fall back to any free walkable neighbour of wherever he actually is.
  local stand = TALK
  if liveWalker and not (ow.map:isWalkableCell(stand.x, stand.y)
                         and not ow:npcAtCell(stand.x, stand.y)) then
    -- {dx, dy, facing}: offset from the walker to the stand cell, plus the
    -- direction that looks back at him (+1 on x means facing left)
    local sides = { { 0, 1, "up" }, { 0, -1, "down" },
                    { 1, 0, "left" }, { -1, 0, "right" } }
    for _, s in ipairs(sides) do
      local cx, cy = liveWalker.cellX + s[1], liveWalker.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("approach cell (%d,%d) is blocked, standing on")
                :format(TALK.x, TALK.y), cx, cy, "facing", s[3])
        stand = { x = cx, y = cy, facing = s[3] }
        break
      end
    end
  end
  U.teleport(game, MAP, stand.x, stand.y, stand.facing)
  U.wait(15)

  local talked = false
  for _ = 1, 90 do
    local cur = game.overworld
    local man = npcNamed(WALKER)
    if cur and man then
      local fx, fy = cur.player:facingCell()
      if cur:npcAtCell(fx, fy) == man then
        U.tap(game, "a")
        U.wait(30)
        if game.stack:top() ~= cur then
          talked = true
          break
        end
      end
    end
    U.wait(4)
  end
  check("pressing A at the walking old man opened his box", talked)
  if talked then
    if U.shot(game, SHOT_DIR .. "/bug234_oldman_talk.png") then
      U.log("captured", SHOT_DIR .. "/bug234_oldman_talk.png")
    end
  end

  -- ---- hand off -----------------------------------------------------------
  U.log("You are under the walking old man at (17,5) with his box already up.")
  U.log("With the Pokedex, (18,9) should be bare ground and a GAMBLER should")
  U.log("be pacing at (17,5); #234 was the sleeper still lying at (18,9) and")
  U.log("nobody at (17,5). The other imported-save toggles are a separate job.")

  while true do
    coroutine.yield()
  end
end
