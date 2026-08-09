-- Diagnostic: POKeGEAR phone card + the post-Falkner special phone call.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Gen2Commands = require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  local pool = game.data.map_scripts

  U.newGame(game)
  U.wait(40)

  local save = game.save
  U.log("flags GOT_POKEGEAR", tostring((save.flags or {}).EVENT_GOT_POKEGEAR))
  local g2 = save.g2Phone
  if type(g2) == "table" then
    local ids = {}
    for id, on in pairs(g2) do if on then ids[#ids + 1] = tostring(id) end end
    table.sort(ids)
    U.log("g2Phone", table.concat(ids, ","))
  else
    U.log("g2Phone", type(g2))
  end

  -- register MOM + ELM the way addcellnum does, then look at the card
  Commands.g2_cellnum({ save = save }, 1, true)
  Commands.g2_cellnum({ save = save }, 4, true)
  save.flags = save.flags or {}
  save.flags.EVENT_GOT_POKEGEAR = true

  local Screens = require("src.ui.Screens")
  Screens.push(game, "PokegearMenu", {})
  U.wait(4)
  local gear = game.stack:top()
  U.log("top is", tostring(gear and gear.cards and "PokegearMenu" or "?"))
  U.log("cards", table.concat(gear.cards, ","))
  local list = gear:contacts()
  for i, e in ipairs(list) do
    U.log(("contact %d %s g2=%s call=%s"):format(i, tostring(e.name),
      tostring(e.g2),
      tostring(e.g2 and Gen2Commands.phoneCallScript(game.data, e.g2) ~= nil)))
  end

  -- switch to the PHONE card and press A on the first contact
  while gear:current() ~= "PHONE" do U.tap(game, "right"); U.wait(3) end
  U.log("card now", gear:current())
  U.tap(game, "a")
  U.wait(6)
  U.log("after A: top is overworld?",
    tostring(game.stack:top() == game.overworld))
  local q = game.overworld.pendingScripts
  U.log("pendingScripts", tostring(q and #q or 0))
  U.wait(60)
  U.log("runner running?", tostring(game.overworld.runner:isRunning()))
  U.log("stack top", tostring(game.stack:top() == game.overworld
    and "overworld" or "other"))
  U.shot(game, (os.getenv("SHOT_DIR") or ".scratchpad") .. "/pokegear_phone.png")

  -- ---- the post-Falkner egg call
  for _ = 1, 40 do
    if game.stack:top() == game.overworld
       and not game.overworld.runner:isRunning() then break end
    U.tap(game, "a")
    U.wait(6)
  end
  U.log("back on the map", tostring(game.stack:top() == game.overworld))

  U.teleport(game, "NEW_BARK_TOWN", 6, 6, "down")
  U.wait(60)
  U.log("map outdoor?", tostring(require("src.world.Map").isOutdoor(
    game.overworld.map.def)))

  local eggRows = require("src.script.Gen2ScriptVM").compile(game.data,
    "S56_4159")  -- VioletGymFalknerScript.FightDone
  U.log("S56_4159 compiled", tostring(eggRows ~= nil))
  U.log("specialCalls[3]", tostring(pool.specialCalls
    and pool.specialCalls[3] and pool.specialCalls[3].script))
  local Cmds = require("src.script.Commands")
  local realShow = Cmds.show_text
  Cmds.show_text = function(ctx, id, ...)
    local Strings = require("src.core.Strings")
    local body = type(id) == "string" and (game.data.text and game.data.text[id])
      or nil
    U.log("show_text", tostring(id), (tostring(body or ""):gsub("\n", " ")))
    return realShow(ctx, id, ...)
  end

  if eggRows then
    game.overworld.runner:run(eggRows)
    for _ = 1, 60 do
      if save.g2SpecialCall ~= nil then break end
      if not game.overworld.runner:isRunning() then break end
      U.tap(game, "a")
      U.wait(6)
    end
    U.log("g2SpecialCall armed", tostring(save.g2SpecialCall))
    for _ = 1, 60 do
      if not game.overworld.runner:isRunning() then break end
      U.tap(game, "a")
      U.wait(6)
    end
  end
  U.wait(90)
  U.log("g2SpecialCall after idle", tostring(save.g2SpecialCall))
  U.log("g2SpecialCallActive", tostring(save.g2SpecialCallActive))
  U.log("runner running?", tostring(game.overworld.runner:isRunning()))
  U.shot(game, (os.getenv("SHOT_DIR") or ".scratchpad") .. "/pokegear_call.png")

  U.log("done")
  love.event.quit()
end
