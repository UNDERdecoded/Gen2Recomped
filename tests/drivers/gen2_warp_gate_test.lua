-- Gen2 warp gating: GetDestinationWarpNumber (0:$22AD) farcalls
-- CheckWarpCollision (05:$4A18) before it looks a warp up, so a warp_event
-- only fires from collision $60, $68 or $70-$7F.  The Ruins of Alph chambers,
-- the Ecruteak/Blackthorn gym floors and the Ice Path holes all rely on it:
-- the warp is always in the map, the callback swaps the block underneath.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_warp_gate_test.lua love .

local U = dofile("tests/drivers/util.lua")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL " .. name) end
end

-- RuinsOfAlphKabutoChamber's callback (44:$44CE) is
-- `checkevent $02A1 / iffalse .close / endcallback / changeblock 2,2,1 /
-- changeblock 4,2,2`: the map's own blockdata is the OPEN hole, and the
-- callback walls it back up until the Unown puzzle is solved.
local PUZZLE_EVENT = "EVENT_G2_0673"

return function(game)
  U.newGame(game)
  U.wait(20)

  U.teleport(game, "RUINS_OF_ALPH_KABUTO_CHAMBER", 4, 6)
  U.wait(30)
  local map = game.stack:top().map
  check("chamber loaded", map.id == "RUINS_OF_ALPH_KABUTO_CHAMBER")
  check("unsolved wall is block 1", map:blockAt(1, 1) == 1)
  check("unsolved wall is block 2", map:blockAt(2, 1) == 2)
  check("unsolved hole (3,3) does not warp", map:warpAtCell(3, 3) == nil)
  check("unsolved hole (4,3) does not warp", map:warpAtCell(4, 3) == nil)
  check("the chamber exit still warps", map:warpAtCell(3, 9) ~= nil)

  game.save.flags = game.save.flags or {}
  game.save.flags[PUZZLE_EVENT] = true
  U.teleport(game, "RUINS_OF_ALPH_OUTSIDE", 14, 8)
  U.wait(20)
  U.teleport(game, "RUINS_OF_ALPH_KABUTO_CHAMBER", 4, 6)
  U.wait(30)
  map = game.stack:top().map
  check("solved hole keeps block 24", map:blockAt(1, 1) == 24)
  check("solved hole keeps block 25", map:blockAt(2, 1) == 25)
  local w = map:warpAtCell(3, 3)
  check("solved hole warps to the inner chamber",
        w and w.def.destMap == "RUINS_OF_ALPH_INNER_CHAMBER")

  -- Game-wide: the collision under a warp must be an entrance class, or the
  -- warp is one of the deliberately shut ones.  Both counts are sentinels --
  -- a regression in the collision or block export moves them.
  local Data = require("src.core.Data")
  local Map = require("src.world.Map")
  local MapLoader = require("src.world.MapLoader")
  local open, shut, seen = 0, 0, {}
  for id, def in pairs(Data.maps) do
    if type(def) == "table" and def.id == id and not seen[id] then
      seen[id] = true
      local ok, m = pcall(MapLoader.load, Data, id)
      if ok and m then
        for _, warp in ipairs(def.warps or {}) do
          if Map.gen2IsEntrance(m:cellTile(warp.x, warp.y)) then
            open = open + 1
          else
            shut = shut + 1
          end
        end
      end
    end
  end
  check(("open warp cells %d >= 1600"):format(open), open >= 1600)
  check(("shut warp cells %d <= 300"):format(shut), shut <= 300)

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
