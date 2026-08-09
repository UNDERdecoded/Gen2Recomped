-- Gen2 CUT: the CutTreeBlockPointers swap table, the TryCutOW overworld
-- A-press prompt, the party-menu field-move list, and readvar VAR_FACING
-- (the Ilex Forest Farfetch'd branches on it).
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else
      fail = fail + 1
      U.log("FAIL " .. what)
    end
  end

  U.newGame(game)
  U.wait(2)

  -- 1. extracted swap table -------------------------------------------------
  local trees = game.data.field.gen2CutTrees
  ok(type(trees) == "table", "field.gen2CutTrees exists")
  trees = trees or {}
  for _, name in ipairs({ "TilesetJohto", "TilesetJohtoModern", "TilesetKanto",
                          "TilesetPark", "TilesetForest" }) do
    ok(type(trees[name]) == "table" and #trees[name] > 0, name .. " has rows")
  end
  ok(trees.TilesetJohto and trees.TilesetJohto[1].before == 0x03
     and trees.TilesetJohto[1].after == 0x02
     and trees.TilesetJohto[1].anim == "tree", "JOHTO tree 03->02 is a tree anim")
  ok(trees.TilesetForest and trees.TilesetForest[1].before == 0x0F
     and trees.TilesetForest[1].after == 0x17
     and trees.TilesetForest[1].anim == "grass", "FOREST 0F->17 is a grass anim")

  local Map = require("src.world.Map")
  ok(Map.gen2IsCutTree(0x12) and Map.gen2IsCutTree(0x1A), "cut-tree collisions")
  ok(not Map.gen2IsCutTree(0x00) and not Map.gen2IsCutTree(0x13),
     "non-tree collisions rejected")

  -- 2. the texts the ROM prints --------------------------------------------
  ok((game.data.text._AskCutText or ""):find("CUT"), "_AskCutText present")
  ok((game.data.text._CanCutText or ""):find("CUT"), "_CanCutText present")

  -- 3. a real tree in Ilex Forest ------------------------------------------
  U.teleport(game, "ILEX_FOREST", 10, 10)
  U.wait(4)
  local ow = game.stack:top()
  ok(ow and ow.map and ow.map.id == "ILEX_FOREST", "in Ilex Forest")
  local tx, ty
  if ow and ow.map then
    for cy = 0, ow.map.heightCells - 1 do
      for cx = 0, ow.map.widthCells - 1 do
        if Map.gen2IsCutTree(ow.map:cellTile(cx, cy)) then tx, ty = cx, cy end
      end
      if tx then break end
    end
  end
  ok(tx ~= nil, "Ilex Forest has a cut-tree cell")
  if tx then
    local swap = ow:gen2CutSwap(tx, ty)
    ok(swap ~= nil, "the tree cell resolves to a swap row")
    ok(swap == nil or swap.after == 0x17, "swap replaces with block 0x17")

    -- TryCutOW with no CUT mon: the "this tree can be CUT!" statement only
    local depth = #game.stack.states
    ok(ow:tryCutOW(tx, ty), "tryCutOW fires with no CUT mon")
    ok(#game.stack.states > depth, "a text box was pushed")
    while #game.stack.states > depth do game.stack:pop() end
  end

  -- 4. party menu lists CUT once the mon knows it and has the badge --------
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(game.data, "SPECIES_001", 20)
  mon.moves = { { id = "CUT", pp = 30 } }
  game.save.party = { mon }
  game.save.flags = game.save.flags or {}

  local PartyMenu = require("src.ui.PartyMenu")
  local function press(menu)
    game.stack:push(menu)
    U.wait(1)
    U.tap(game, "a")
    U.wait(3)
    local out = {}
    for _, it in ipairs(menu.subItems or {}) do out[#out + 1] = it.action end
    while game.stack:top() ~= ow do game.stack:pop() end
    return table.concat(out, ",")
  end

  game.save.flags.HIVEBADGE = nil
  local noBadge = press(PartyMenu.new(game))
  ok(not noBadge:find("cut"), "CUT hidden without HIVEBADGE (" .. noBadge .. ")")

  game.save.flags.HIVEBADGE = true
  local withBadge = press(PartyMenu.new(game))
  ok(withBadge:find("cut") ~= nil, "CUT listed with HIVEBADGE (" .. withBadge .. ")")

  -- 5. readvar VAR_FACING drives the Farfetch'd branch ----------------------
  local VM = require("src.script.Gen2ScriptVM")
  require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  local expect = { down = 0, up = 1, left = 2, right = 3 }
  for facing, want in pairs(expect) do
    ow.player.facing = facing
    local ctx = { save = game.save, overworld = ow }
    Commands.g2_readvar(ctx, 9)
    ok(ctx.g2Var == want,
       ("readvar 9 facing %s -> %d (got %s)"):format(facing, want, tostring(ctx.g2Var)))
  end
  local rows = VM.compile(game.data, "S45_6920")
  local sawReadvar = false
  for _, r in ipairs(rows or {}) do
    if r[1] == "g2_readvar" and r[2] == 9 then sawReadvar = true end
  end
  ok(sawReadvar, "S45_6920 lowers readvar 9")

  U.log(("RESULT %s (%d pass, %d fail)"):format(fail == 0 and "PASS" or "FAIL",
                                                pass, fail))
  love.event.quit()
end
