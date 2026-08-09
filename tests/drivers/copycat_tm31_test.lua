-- Driver: Copycat TM31 MIMIC trade (scripts/CopycatsHouse2F.asm).
-- Teleport to 2F with a POKE DOLL, talk through the mimic dialogue + gift,
-- screenshot the TM receive box, and assert flag/inventory.
--
--   SHOT_DIR=/tmp/copycat_tm31 POKEPORT_DRIVER=tests/drivers/copycat_tm31_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local TextBox = require("src.render.TextBox")

  Bag.add(game.save, "POKE_DOLL", 1)
  U.teleport(game, "COPYCATS_HOUSE_2F", 4, 4, "up")
  local ow = game.overworld

  for _, npc in ipairs(ow.npcs) do
    if npc.def and npc.def.text == "TEXT_COPYCATSHOUSE2F_COPYCAT" then
      npc.wanders, npc.moving = false, false
      npc.cellX, npc.cellY = 4, 3
      npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
      npc.facing = "down"
    end
  end
  U.wait(5)
  U.shot(game, DIR .. "/copycat_0_room.png")

  local function topBox()
    local top = game.stack:top()
    return getmetatable(top) == TextBox and top or nil
  end

  local function pageText(box)
    if not box then return "" end
    return table.concat(box.pages[box.pageIndex] or {}, "\n")
  end

  -- Advance until a fully-typed page matches pred(pageText), then stop
  -- without consuming that page (so the shot catches it).  Last pages
  -- set done (not waiting); mid-text page breaks set waiting.
  local function mashToPage(pred)
    for _ = 1, 500 do
      local box = topBox()
      if box and (box.waiting or box.done) and pred(pageText(box)) then
        return true
      end
      U.tap(game, "a")
      U.wait(3)
    end
    return false
  end

  U.tap(game, "a")
  U.wait(20)
  U.log("mimic page:", mashToPage(function(s)
    return s:find("like POKéMON", 1, true) ~= nil
      or s:find("like POK", 1, true) ~= nil
  end))
  U.shot(game, DIR .. "/copycat_1_mimic.png")

  U.log("pre-receive page:", mashToPage(function(s)
    return s:find("DOLL", 1, true) ~= nil
  end))
  U.shot(game, DIR .. "/copycat_2_prereceive.png")

  U.log("TM receive page:", mashToPage(function(s)
    return s:find("received", 1, true) ~= nil
      and s:find("TM31", 1, true) ~= nil
  end))
  U.shot(game, DIR .. "/copycat_3_received_tm31.png")

  local function mash(btn, cond)
    for _ = 1, 400 do
      if cond() then return true end
      U.tap(game, btn)
      U.wait(3)
    end
    return false
  end

  U.log("dialogue done:", mash("a", function()
    return game.stack:top() == ow
  end))
  U.shot(game, DIR .. "/copycat_4_done.png")

  U.log("EVENT_GOT_TM31:", tostring(game.save.flags.EVENT_GOT_TM31))
  U.log("bag TM_MIMIC:", tostring(game.save.inventory.TM_MIMIC),
        "POKE_DOLL:", tostring(game.save.inventory.POKE_DOLL))

  assert(game.save.flags.EVENT_GOT_TM31, "EVENT_GOT_TM31 not set")
  assert((game.save.inventory.TM_MIMIC or 0) >= 1, "TM_MIMIC missing from bag")
  assert((game.save.inventory.POKE_DOLL or 0) == 0, "POKE_DOLL not taken")

  U.tap(game, "a")
  U.wait(20)
  U.log("thanks page:", mashToPage(function(s)
    return s:find("Thanks for TM31", 1, true) ~= nil
  end))
  U.wait(2)
  U.shot(game, DIR .. "/copycat_5_thanks.png")
  mash("a", function() return game.stack:top() == ow end)

  U.log("DONE")
  love.event.quit()
end
