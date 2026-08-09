local U = dofile("tests/drivers/util.lua")
local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1 end
  U.log((cond and "PASS " or "FAIL ") .. name)
end

return function(game)
  U.newGame(game); U.wait(20)
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
  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
