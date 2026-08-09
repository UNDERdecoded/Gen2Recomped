-- Ice Path B1F's boulder puzzle: the stone table (CmdQueue_StoneTable /
-- HandleStoneQueue).  The map's MAPCALLBACK_CMDQUEUE callback writes a
-- `stonetable <warp id>, <object event id>, <script>` row per boulder, and
-- the ROM polls them for a Strength boulder standing still on a pit tile
-- ($60 / $68); the matching row's script is what drops it to B2F.  The port
-- used to park the boulders on the holes and stop there, so the puzzle was
-- unfinishable -- see OverworldState:gen2BoulderIntoPit.
local U = require("tests.drivers.util")
local Map = require("src.world.Map")

local MAP = "ICE_PATH_B1_F"

local DIRS = {
  { dir = "up", dx = 0, dy = -1 },
  { dir = "down", dx = 0, dy = 1 },
  { dir = "left", dx = -1, dy = 0 },
  { dir = "right", dx = 1, dy = 0 },
}

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; U.log("FAIL " .. name) end
  end

  ok(Map.gen2IsPit(0x60) and Map.gen2IsPit(0x68), "CheckPitTile knows $60/$68")
  ok(not Map.gen2IsPit(0x00), "plain floor is not a pit")

  U.newGame(game)
  U.wait(10)

  local def = game.data.maps[MAP]
  ok(def ~= nil, MAP .. " is in the dataset")
  if not def then
    U.log(("RESULT FAIL (%d pass, %d fail)"):format(pass, fail))
    return false
  end

  -- warp 1 is a real doorway, so it is a safe cell to drop into
  local entry = (def.warps or {})[1]
  U.teleport(game, MAP, entry and entry.x or 5, entry and entry.y or 5)
  U.wait(30)
  local ow = game.stack:top()
  ok(ow.map and ow.map.id == MAP, "loaded " .. MAP)

  -- the cmdqueue callback must have handed the rows over on map load
  local stones = ow.stoneTable
  ok(stones ~= nil and stones.mapId == MAP and #stones.rows > 0,
     "the map registered a stone table (" ..
     (stones and #stones.rows or 0) .. " rows)")
  if not (stones and #stones.rows > 0) then
    U.log(("RESULT FAIL (%d pass, %d fail)"):format(pass, fail))
    return false
  end

  -- every row's warp id has to name a real hole, or the boulder would be
  -- matched against a doorway
  local pits = 0
  for _, row in ipairs(stones.rows) do
    local w = (ow.map.def.warps or {})[row.warp]
    if w and Map.gen2IsPit(ow.map:cellTile(w.x, w.y)) then pits = pits + 1 end
  end
  ok(pits == #stones.rows,
     "every stonetable warp sits on a pit tile (" .. pits .. "/" ..
     #stones.rows .. ")")

  -- pick a row whose boulder can actually be shoved into its hole from a
  -- cell the player can stand on
  local row, boulder, push
  for _, r in ipairs(stones.rows) do
    local w = (ow.map.def.warps or {})[r.warp]
    local npc
    for _, e in ipairs(ow.entities or {}) do
      if e.def and Map.isPushable(e.def) and (e.def.index or 0) + 1 == r.object then
        npc = e
        break
      end
    end
    if w and npc then
      for _, d in ipairs(DIRS) do
        local bx, by = w.x - d.dx, w.y - d.dy
        local px, py = bx - d.dx, by - d.dy
        if ow.map:inBounds(px, py) and ow.map:isWalkableCell(px, py)
           and ow.map:isWalkableCell(bx, by) then
          row, boulder, push = r, npc, { d = d, bx = bx, by = by, px = px, py = py,
                                         wx = w.x, wy = w.y }
          break
        end
      end
    end
    if row then break end
  end
  ok(row ~= nil, "a boulder and its hole are reachable from one another")
  if not row then
    U.log(("RESULT FAIL (%d pass, %d fail)"):format(pass, fail))
    return false
  end

  -- a boulder resting anywhere but its own hole must not fire the row
  boulder.cellX, boulder.cellY = push.px, push.py
  ok(ow:gen2BoulderIntoPit(boulder) == false,
     "a boulder off the holes does not run the stone table")
  boulder.cellX, boulder.cellY = push.wx, push.wy
  local realObject = boulder.def.index
  boulder.def.index = -99
  ok(ow:gen2BoulderIntoPit(boulder) == false,
     "a boulder in the wrong hole does not open the wrong floor")
  boulder.def.index = realObject

  -- and the real push drops it through
  boulder.cellX, boulder.cellY = push.bx, push.by
  boulder.x, boulder.y = push.bx * 16, push.by * 16
  boulder.moving = false
  ow.player.cellX, ow.player.cellY = push.px, push.py
  ow.player.x, ow.player.y = push.px * 16, push.py * 16
  ow.player.facing = push.d.dir
  ow.player.moving = false
  ow.strengthActive = true
  ow.boulderTried = nil
  ok(ow:checkBoulderPush(push.d.dir) == true,
     "STRENGTH pushes the boulder toward its hole")

  for _ = 1, 240 do
    U.wait(1)
    if game.stack:top() ~= ow then U.tap(game, "a") end
    if ow:npcAtCell(push.wx, push.wy) == nil and game.stack:top() == ow then break end
  end
  while game.stack:top() ~= ow do U.tap(game, "b"); U.wait(4) end
  U.wait(10)
  ok(ow:npcAtCell(push.wx, push.wy) == nil, "the boulder fell through the hole")

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
  return fail == 0
end
