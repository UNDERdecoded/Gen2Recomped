-- scratch: replay a Gen2 map script's applymovements with the real map
-- loaded and log where every object ends up, so a scripted walk can be
-- checked against the ROM's own object_event coordinates.
--   PLAYMAP=TEAM_ROCKET_BASE_B2F  PLAYSCRIPT=S45_4C67  [PLAYAT=x,y]
local U = require("tests.drivers.util")

return function(game)
  U.newGame(game)
  U.wait(10)

  local mapId = os.getenv("PLAYMAP")
  local label = os.getenv("PLAYSCRIPT")
  local ow = game.stack:top()
  U.teleport(game, mapId, 14, 15)
  U.wait(20)
  ow = game.stack:top()

  local at = os.getenv("PLAYAT")
  if at then
    local x, y = at:match("(%d+),(%d+)")
    if x then
      local p = ow.player
      p.cellX, p.cellY = tonumber(x), tonumber(y)
      p.px, p.py = p.cellX * 16, p.cellY * 16
    end
  end

  local function snapshot(tag)
    local out = { tag }
    local p = ow.player
    out[#out + 1] = ("P(%d,%d)"):format(p.cellX, p.cellY)
    for i = 1, 14 do
      local n = ow:npcByIndex(i)
      if n then
        local walk = ow.map:isWalkableCell(n.cellX, n.cellY)
        out[#out + 1] = ("%d:(%d,%d)%s"):format(i, n.cellX, n.cellY,
          walk and "" or "!WALL")
      end
    end
    U.log(table.concat(out, " "))
  end

  snapshot("start")

  local Commands = require("src.script.Commands")
  local realMove = Commands.g2_move
  local step = 0
  Commands.g2_move = function(ctx, target, movementLabel)
    step = step + 1
    local rows = game.data.map_scripts.movements[movementLabel]
    local names = {}
    for _, r in ipairs(rows or {}) do names[#names + 1] = r[1] end
    U.log(("-> move %s %s  [%s]"):format(tostring(target),
      tostring(movementLabel), table.concat(names, ",")))
    realMove(ctx, target, movementLabel)
    snapshot(("after#%d %s"):format(step, tostring(movementLabel)))
  end
  -- keep the run headless: no battles, no textboxes
  Commands.show_text = function() end
  Commands.g2_start_battle = function(ctx) ctx.lastCheck = false end
  Commands.g2_winloss = function() end

  local VM = require("src.script.Gen2ScriptVM")
  local ScriptRunner = require("src.script.ScriptRunner")
  local rows = VM.compile(game.data, label)
  local runner = ScriptRunner.new(game, ow)
  runner:run(rows, { npc = { def = {} } })
  for _ = 1, 4000 do
    if not runner:isRunning() then break end
    U.wait(1)
    runner:update()
  end
  Commands.g2_move = realMove
  snapshot("end")
  U.log("RESULT PASS")
end
