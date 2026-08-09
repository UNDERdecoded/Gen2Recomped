-- Driver: the seam where the TYPE/PP box meets the move box (#240).  pokered
-- MoveSelectionMenu (engine/battle/core.asm:2492-2501) writes '─' at (4,12) and
-- '┘' at (10,12) into the tilemap, REPLACING the tile.  Eye check, no SPEED.
--   POKEPORT_DRIVER=tests/drivers/moveselect_border_bug240_test.lua \
--     POKEPORT_IDENTITY=bug240 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Font = require("src.render.Font")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions -----------------------------------------------------
  -- a missing glyph page draws nothing in those cells, which reads as a clean
  -- seam and would pass by accident

  check("Font.BORDER.h (the '─' patch glyph) is defined",
        Font.BORDER ~= nil and Font.BORDER.h ~= nil)
  check("Font.BORDER.br (the '┘' patch glyph) is defined",
        Font.BORDER ~= nil and Font.BORDER.br ~= nil)
  check("Font.drawCode exists (the transparent blit at the heart of this)",
        type(Font.drawCode) == "function")
  check("Font.drawBox exists (the white fill the patch has to match)",
        type(Font.drawBox) == "function")
  local extra = love.filesystem.getInfo("assets/generated/fonts/font_extra.png")
  check("assets/generated/fonts/font_extra.png is in the cache", extra ~= nil)

  game.save.player.name = "bryan"
  -- CHARIZARD at 50 knows four moves, so the list fills all four rows and the
  -- PP figure sits directly above the (10,12) cell being judged
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  local lead = game.save.party[1]
  check("the lead knows at least one move", #lead.moves >= 1)
  U.log("move list:", (function()
    local names = {}
    for _, m in ipairs(lead.moves) do
      names[#names + 1] = game.data.moves[m.id].name
    end
    return table.concat(names, ", ")
  end)())

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)
  local ow = game.overworld
  check("overworld is up to push the battle from", ow ~= nil)

  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function tapUntil(cond, taps, gap)
    for _ = 1, (taps or 60) do
      if cond() then return true end
      U.tap(game, "a")
      for _ = 1, (gap or 6) do
        if cond() then return true end
        U.wait(1)
      end
    end
    return cond()
  end

  check("reached the FIGHT/PKMN/ITEM/RUN menu",
        tapUntil(function() return battle.phase == "menu" end, 60))
  check("cursor starts on FIGHT", battle.menuIndex == 1)

  -- A on FIGHT opens the move list: this is the screen being judged.
  U.tap(game, "a")
  U.wait(20)
  check("the FIGHT move list is open (#240 lives on this screen)",
        battle.phase == "moveSelect")
  check("move-list screenshot reached disk",
        U.shot(game, DIR .. "/bug240_move_list.png"))
  U.log("captured", DIR .. "/bug240_move_list.png")

  -- move the cursor down one row too: the PP figure changes, and the '┘'
  -- corner under it must stay identical
  U.tap(game, "down")
  U.wait(20)
  check("move-list screenshot on the second move reached disk",
        U.shot(game, DIR .. "/bug240_move_list_row2.png"))
  U.log("captured", DIR .. "/bug240_move_list_row2.png")

  -- ---- hand off ----------------------------------------------------------
  U.log("The FIGHT move list is open.  Judge tiles (4,12) and (10,12) on the row")
  U.log("where the TYPE/PP box meets the move box; (10,12) sits under the PP")
  U.log("count.  Both want clean border: no black blobs showing through, no")
  U.log("white gap, and no change as you move the cursor with UP/DOWN.  (#240)")

  while true do
    coroutine.yield()
  end
end
