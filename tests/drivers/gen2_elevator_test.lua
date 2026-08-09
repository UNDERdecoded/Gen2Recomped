-- Gen2 elevators and the script-driven vertical menus the Game Corner prize
-- counters run on.  Both opcodes used to lower to nothing: `elevator` left
-- the car's LAST_WARP doors pointing back at the floor you got in from, and
-- `loadmenu`/`verticalmenu` left the vendors greeting you and then standing
-- there with no list to pick from.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL", what) end
  end

  U.newGame(game)
  U.wait(10)

  local VM = require("src.script.Gen2ScriptVM")
  local Commands = require("src.script.Commands")
  require("src.script.Gen2Commands")
  local scripts = game.data.map_scripts.scripts

  local function rowsOf(label, op)
    for _, row in ipairs(scripts[label] or {}) do
      if row[1] == op then return row end
    end
  end

  -- 1. the extractor resolved both elevator data blocks
  local gold = rowsOf("S57_6728", "elevator")
  local celadon = rowsOf("S5E_49C9", "elevator")
  ok(gold and type(gold[2]) == "table",
     "GoldenrodDeptStoreElevatorData resolved to a floor list")
  ok(celadon and type(celadon[2]) == "table",
     "CeladonDeptStoreElevatorData resolved to a floor list")
  ok(gold and #gold[2] == 7, ("Goldenrod has 7 floors (got %s)")
     :format(gold and #gold[2]))
  ok(celadon and #celadon[2] == 6, ("Celadon has 6 floors (got %s)")
     :format(celadon and #celadon[2]))
  ok(gold and gold[2][1].floor == 3
     and gold[2][1].map == "GOLDENROD_DEPT_STORE_B1_F",
     "Goldenrod's first row is B1F")
  ok(celadon and celadon[2][1].floor == 4
     and celadon[2][1].map == "CELADON_DEPT_STORE1_F",
     "Celadon's first row is 1F")
  local mapped = 0
  for _, floor in ipairs(gold and gold[2] or {}) do
    if type(floor.map) == "string" and game.data.maps[floor.map]
       and game.data.maps[floor.map].warps[floor.warp] then
      mapped = mapped + 1
    end
  end
  ok(mapped == 7, ("every Goldenrod floor names a real warp (%d/7)")
     :format(mapped))

  -- every `elevator` row in the ROM must have resolved; a leftover number
  -- means the data block moved and the row would silently do nothing.  Only
  -- the headers a `verticalmenu` consumes have to resolve: the Academy
  -- blackboard's is a 2D grid (rows/cols packed in one byte) and _2dmenu is
  -- still unimplemented, so the reader is expected to refuse it.
  local rawElevators, rawMenus, menus = 0, 0, 0
  for _, rows in pairs(scripts) do
    local vertical = false
    for _, row in ipairs(rows) do
      if row[1] == "verticalmenu" then vertical = true end
    end
    for _, row in ipairs(rows) do
      if row[1] == "elevator" and type(row[2]) ~= "table" then
        rawElevators = rawElevators + 1
      elseif row[1] == "loadmenu" and vertical then
        if type(row[2]) == "table" then menus = menus + 1
        else rawMenus = rawMenus + 1 end
      end
    end
  end
  ok(rawElevators == 0, ("no unresolved elevator rows (%d)"):format(rawElevators))
  ok(menus > 0 and rawMenus == 0,
     ("%d vertical menu headers resolved, %d left raw"):format(menus, rawMenus))

  -- 2. the compiler no longer drops them
  ok(type(Commands.g2_elevator) == "function", "g2_elevator is registered")
  ok(type(Commands.g2_loadmenu) == "function", "g2_loadmenu is registered")
  ok(type(Commands.g2_verticalmenu) == "function",
     "g2_verticalmenu is registered")

  local function compiledOps(label)
    local seen = {}
    for _, row in ipairs(VM.compile(game.data, label) or {}) do
      seen[row[1]] = true
    end
    return seen
  end
  ok(compiledOps("S57_6728").g2_elevator == true,
     "the Goldenrod elevator script compiles a g2_elevator row")
  local vendor = compiledOps("S57_67A7")
  ok(vendor.g2_loadmenu and vendor.g2_verticalmenu,
     "the TM prize vendor compiles both menu rows")

  -- 3. the prize counters' menu labels came out of MenuData intact
  local tmMenu = rowsOf("S57_67A7", "loadmenu")
  ok(tmMenu and #tmMenu[2] == 4, "the TM counter offers 4 rows")
  ok(tmMenu and tmMenu[2][4] == "CANCEL", "the last row is CANCEL")
  ok(tmMenu and tmMenu[2][1]:find("TM", 1, true) == 1,
     ("the first row is a TM (%s)"):format(tmMenu and tmMenu[2][1]))
  local monMenu = rowsOf("S57_6880", "loadmenu")
  ok(monMenu and monMenu[2][1]:find("ABRA", 1, true) == 1,
     ("the mon counter leads with ABRA (%s)"):format(monMenu and monMenu[2][1]))

  -- 4. floor names match ElevatorFloorNames (04:$7945)
  local NAMES = require("src.script.Gen2Commands").FLOOR_NAMES
  ok(NAMES[0] == "B4F" and NAMES[3] == "B1F" and NAMES[4] == "1F"
     and NAMES[9] == "6F" and NAMES[15] == "ROOF", "floor names line up")

  -- 5. coins live in save.coins, the field the COIN CASE and the slot
  -- machine screen read -- the Game Corner used to pay into its own g2Coins
  local ctx = { game = game, save = game.save }
  game.save.coins, game.save.g2Coins = nil, nil
  Commands.g2_give_coins(ctx, 100)
  ok(game.save.coins == 100, "g2_give_coins credits save.coins")
  Commands.g2_check_coins(ctx, 50)
  ok(ctx.lastCheck == true and ctx.g2Var == 0, "100 coins covers a 50 price")
  Commands.g2_check_coins(ctx, 5500)
  ok(ctx.lastCheck == false and ctx.g2Var == 1, "100 coins is short of 5500")
  game.save.coins, game.save.g2Coins = nil, 42
  Commands.g2_check_coins(ctx, 0)
  ok(game.save.coins == 42, "an old g2Coins balance migrates to save.coins")

  -- 6. picking a floor re-points the car's LAST_WARP doors, which is exactly
  -- what Elevator_GoToFloor does (it writes wBackupWarpNumber/Group/Number)
  local ow = game.overworld
  U.teleport(game, "GOLDENROD_DEPT_STORE_ELEVATOR", 1, 1, "down")
  U.wait(4)
  ow.backupWarp = { id = "GOLDENROD_DEPT_STORE1_F", x = 0, y = 0 }
  game.save.backupWarp = ow.backupWarp
  ow:queueScript(VM.compile(game.data, "S57_6728"))
  U.wait(30)
  U.tap(game, "a")   -- dismiss "Which floor?"
  U.wait(30)
  -- the floor menu is up: 1F is filtered out, so row 1 is B1F
  U.tap(game, "a")
  U.wait(30)
  local after = game.save.backupWarp
  ok(after and after.id == "GOLDENROD_DEPT_STORE_B1_F",
     ("the chosen floor becomes the walk-out warp (%s)")
       :format(after and after.id))
  local b1 = game.data.maps.GOLDENROD_DEPT_STORE_B1_F
  ok(after and b1 and after.x == b1.warps[2].x and after.y == b1.warps[2].y,
     "and it lands on that floor's warp 2")

  U.log(("RESULT %s (%d pass, %d fail)"):format(fail == 0 and "PASS" or "FAIL",
                                                pass, fail))
  love.event.quit()
end
