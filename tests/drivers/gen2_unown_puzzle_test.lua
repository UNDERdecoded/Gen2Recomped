local U = dofile("tests/drivers/util.lua")
local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1 end
  U.log((cond and "PASS " or "FAIL ") .. name)
end

return function(game)
  U.newGame(game); U.wait(20)
  -- U.newGame lands on CONTINUE when a save already exists, so a playthrough
  -- that already solved this puzzle would start with the wall open
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_G2_0673 = nil
  U.teleport(game, "RUINS_OF_ALPH_KABUTO_CHAMBER", 4, 6); U.wait(30)
  local ow = game.stack:top()
  check("blocks start closed", ow.map:blockAt(1, 1) == 1)

  ow:queueScript(require("src.script.Gen2ScriptVM").compile(game.data, "S44_44DE"))
  U.wait(20)
  local top = game.stack:top()
  U.log("top state: " .. tostring(top.__name or (top.def and "puzzle") or "?"))
  local UnownPuzzle = require("src.ui.UnownPuzzle")
  check("puzzle pushed", getmetatable(top) == UnownPuzzle)
  if getmetatable(top) == UnownPuzzle then
    -- Gen 2 is native GBC, so the ROM's own puzzle palette has to reach the
    -- pieces in every COLORS mode -- SGB paints no zone over this screen, so
    -- gating the recolour on ADVANCED left it in flat greys.
    local PaletteFX = require("src.render.PaletteFX")
    local before = PaletteFX.mode
    local coloured = true
    for _, mode in ipairs({ "redpp", "gbc", "ogred", "og", "classic" }) do
      PaletteFX.setMode(mode)
      local pal = top:palette()
      if not (pal and pal[2] and (pal[2][1] ~= pal[2][2] or pal[2][2] ~= pal[2][3])) then
        coloured = false
      end
    end
    PaletteFX.setMode(before)
    check("the puzzle keeps its ROM colours in every COLORS mode", coloured)
    for i = 1, top.def.width * top.def.height do
      top.board[i] = top.def.solved[i] or 0
    end
    check("board reads solved", top:solved())
    top:finish(true)
  end
  U.wait(60)
  local ow2 = game.stack:top()
  U.log("after: top=" .. tostring(getmetatable(ow2) == UnownPuzzle and "puzzle" or "overworld"))
  check("flag 673 set", game.save.flags and game.save.flags.EVENT_G2_0673 == true)
  check("wall opened to 24", ow2.map and ow2.map:blockAt(1, 1) == 24)
  check("wall opened to 25", ow2.map and ow2.map:blockAt(2, 1) == 25)
  check("hole warps now", ow2.map and ow2.map:warpAtCell(3, 3) ~= nil)

  -- .PuzzleComplete ends on `warpcheck`, and the player who read the sign is
  -- standing on the block that just became a hole: RuinsOfAlphKabutoChamber
  -- warp 3 (3,9 is the exit, 3,3 is the hole) lands on
  -- RUINS_OF_ALPH_INNER_CHAMBER warp 4, cell (15,3).  Passing warpAtCell's
  -- { index, def } record to takeWarp instead of the def sent the player to
  -- warp 1 of the last outdoor map -- the ruins entrance -- instead.
  U.teleport(game, "RUINS_OF_ALPH_KABUTO_CHAMBER", 3, 3, "up"); U.wait(30)
  local ow3 = game.stack:top()
  check("still standing on the open hole", ow3.map:warpAtCell(3, 3) ~= nil)
  ow3:queueScript({ { "g2_warpcheck" } })
  U.wait(150)
  -- the arrival script talks (RuinsOfAlphInnerChamber's Unown text), so clear
  -- whatever text box is sitting on the overworld before reading the map
  for _ = 1, 120 do
    local top = game.stack:top()
    if top and top.map then break end
    U.tap(game, "a")
    U.wait(4)
  end
  local ow4 = game.stack:top()
  U.log("warpcheck landed on " .. tostring(ow4.map and ow4.map.id)
        .. " at " .. tostring(ow4.player and ow4.player.cellX)
        .. "," .. tostring(ow4.player and ow4.player.cellY))
  check("warpcheck drops into the inner chamber",
        ow4.map and ow4.map.id == "RUINS_OF_ALPH_INNER_CHAMBER")
  check("landed on inner chamber warp 4",
        ow4.player and ow4.player.cellX == 15 and ow4.player.cellY == 3)

  -- ------------------------------------------------------------ UNOWN MODE
  -- UpdateUnownDex appends each new letter to wUnownDex, so the dex's UNOWN
  -- MODE lists them in catch order rather than alphabetically.
  local save = game.save
  save.pokedex = save.pokedex or { seen = {}, owned = {} }
  save.pokedex.unownForms = { [3] = true, [1] = true, [26] = true }
  save.pokedex.unownDex = { 3, 1, 26 }
  save.flags = save.flags or {}
  -- what the research-center scientist's `setflag ENGINE_UNOWN_DEX` writes
  save.flags.EVENT_GOT_UNOWN_DEX = true

  local PokedexUnownMode = require("src.ui.PokedexUnownMode")
  require("src.ui.Screens").push(game, "PokedexUnownMode")
  U.wait(2)
  local unown = game.stack:top()
  check("UNOWN MODE screen opened", getmetatable(unown) == PokedexUnownMode)
  if getmetatable(unown) == PokedexUnownMode then
    check("letters listed in catch order",
          unown.letters[1] == 3 and unown.letters[2] == 1
          and unown.letters[3] == 26 and #unown.letters == 3)
    U.tap(game, "b"); U.wait(5)
    check("B leaves UNOWN MODE", game.stack:top() ~= unown)
  end

  -- Pokedex_PrintNumberIfOldMode: only OLD #DEX MODE numbers the listing.
  local PokedexMenu = require("src.ui.PokedexMenu")
  save.dexMode = PokedexMenu.MODE_OLD
  local oldList = PokedexMenu.new(game, {})
  check("OLD mode numbers the listing",
        (oldList.items[1].label or ""):match("^%d") ~= nil)
  save.dexMode = PokedexMenu.MODE_NEW
  local newList = PokedexMenu.new(game, {})
  check("NEW mode prints no number",
        (newList.items[1].label or ""):match("^%d") == nil)
  save.dexMode = nil

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
