-- Regression: a ledge hop whose landing is on the CONNECTED map still hops
-- (#223).  engine/overworld/ledges.asm HandleLedges only simulates two button
-- presses and never looks at where the hop lands, so a ledge on a map's last
-- row legitimately drops onto the neighbour.  The port gated every hop on
-- self.map:inBounds(lx, ly), which refused all nine such cells in the game.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROUTE_4) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Map = require("src.world.Map")
local MapLoader = require("src.world.MapLoader")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity ledge seam hop")
local check, eq = S.check, S.eq

-- ---- ground truth: the ledge rows, the cells, the connection -------------
local route4 = MapLoader.load(Data, "ROUTE_4")
local route3 = MapLoader.load(Data, "ROUTE_3")
local route17 = MapLoader.load(Data, "ROUTE_17")
local route18 = MapLoader.load(Data, "ROUTE_18")

-- data/tilesets/ledge_tiles.asm has two DOWN rows: $39 over $36, $39 over $37
local rows = {}
for _, l in ipairs(Data.field.ledges) do
  if l.facing == "down" and l.input == "down" and l.standingTile == 0x39 then
    rows[l.ledgeTile] = true
  end
end
check(rows[0x36] and rows[0x37],
      "LedgeTiles has both DOWN rows ($39 over $36 and $39 over $37)")

eq(route4:cellTile(13, 16), 0x39, "ROUTE_4 (13,16) is the ledge's standing tile")
eq(route4:cellTile(13, 17), 0x37, "ROUTE_4 (13,17) is a DOWN ledge tile")
eq(route4:cellTile(12, 16), 0x39, "ROUTE_4 (12,16) is the ledge's standing tile")
eq(route4:cellTile(12, 17), 0x36, "ROUTE_4 (12,17) is a DOWN ledge tile")
eq(route4.def.height * 2, 18, "ROUTE_4 is 18 cells tall, so row 18 is off the map")
check(not route4:inBounds(13, 18), "the landing two south is off ROUTE_4")

local south4 = route4:connection("south")
check(south4 and south4.map == "ROUTE_3", "ROUTE_4 connects south to ROUTE_3")
eq(south4 and south4.offset, -25, "at block offset -25 (destX = curX + 50)")
check(route3:isWalkableCell(63, 0), "the landing ROUTE_3 (63,0) is walkable")
check(route3:isWalkableCell(62, 0), "and ROUTE_3 (62,0) beside it")

eq(route17:cellTile(7, 142), 0x39, "ROUTE_17 (7,142) is the ledge's standing tile")
eq(route17:cellTile(7, 143), 0x37, "ROUTE_17 (7,143) is a DOWN ledge tile")
local south17 = route17:connection("south")
check(south17 and south17.map == "ROUTE_18", "ROUTE_17 connects south to ROUTE_18")
check(route18:isWalkableCell(7, 0), "the landing ROUTE_18 (7,0) is walkable")

-- ---- live engine ---------------------------------------------------------
Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW

local function stand(mapId, x, y)
  Input:reset()
  Game.save.onBike = false
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, mapId, x, y, "down")
  local ow = Game.stack:top()
  ow.player.moving = false
  ow.player.turnTimer = 0
  return ow
end

-- One fixed step of the parts of OverworldState:update a hop rides on:
-- updateScriptMoves retires a finished move (its onDone is where the seam
-- crossing is handed to checkEdgeExit) and starts the next; Player:update
-- advances the current one.
local function runFrames(ow, n)
  for _ = 1, n do
    ow:updateScriptMoves()
    ow.player:update()
  end
end

-- The Mt Moon plaza drop: ROUTE_4 (13,16) -> ROUTE_3 (63,0).
do
  local ow = stand("ROUTE_4", 13, 16)
  Input.state.down = true
  Input.pressed = {}
  local hopped = ow:checkLedgeHop("down")
  check(hopped, "holding DOWN on ROUTE_4 (13,16) starts the hop")
  eq(ow.player.hopFrames, 32, "the 32-frame jump arc is armed")
  runFrames(ow, 120)
  eq(ow.map.id, "ROUTE_3", "the hop carries the player across the seam")
  eq(ow.player.cellX, 63, "landing x on ROUTE_3")
  eq(ow.player.cellY, 0, "landing y on ROUTE_3 (the top row)")
  check(not ow.player.moving, "the two-cell hop has finished")
  eq(#ow.scriptMoves, 0, "no scripted move is left hanging")
  Input:reset()
end

-- Its neighbour, the other half of the 2-cell terrace.
do
  local ow = stand("ROUTE_4", 12, 16)
  Input.state.down = true
  Input.pressed = {}
  check(ow:checkLedgeHop("down"), "ROUTE_4 (12,16) hops too")
  runFrames(ow, 120)
  eq(ow.map.id, "ROUTE_3", "(12,16) also lands on ROUTE_3")
  eq(ow.player.cellX, 62, "landing x on ROUTE_3")
  eq(ow.player.cellY, 0, "landing y on ROUTE_3")
  Input:reset()
end

-- The last drop off Cycling Road: ROUTE_17 (7,142) -> ROUTE_18 (7,0).
do
  local ow = stand("ROUTE_17", 7, 142)
  Input.state.down = true
  Input.pressed = {}
  check(ow:checkLedgeHop("down"), "holding DOWN on ROUTE_17 (7,142) starts the hop")
  runFrames(ow, 120)
  eq(ow.map.id, "ROUTE_18", "Cycling Road's last ledge crosses onto ROUTE_18")
  eq(ow.player.cellX, 7, "landing x on ROUTE_18 (south offset 0)")
  eq(ow.player.cellY, 0, "landing y on ROUTE_18")
  Input:reset()
end

-- Ordinary in-map ledges are untouched: two cells, same map, no seam.
do
  local ow = stand("ROUTE_4", 72, 4)
  Input.state.down = true
  Input.pressed = {}
  check(ow:checkLedgeHop("down"), "the in-map ledge at ROUTE_4 (72,4) still hops")
  runFrames(ow, 120)
  eq(ow.map.id, "ROUTE_4", "an in-map hop does not change maps")
  eq(ow.player.cellX, 72, "x unchanged")
  eq(ow.player.cellY, 6, "landed two cells south")
  Input:reset()
end

-- Refusals that must survive the split.  All nine real off-map ledges do have
-- a connection, so the stub below is the only way to express "none behind it".
do
  local ow = stand("ROUTE_4", 13, 16)
  Input.state.down = true
  Input.pressed = {}
  local realConnection = ow.map.connection
  ow.map.connection = function() return nil end
  check(ow:checkLedgeHop("down") == false,
        "an off-map landing with no connection is still refused")
  eq(#ow.scriptMoves, 0, "and nothing was queued")
  ow.map.connection = realConnection

  -- ...and the landing is validated the way crossConnection validates it
  local dest, ts, cx, cy = ow:connectionLanding("down")
  check(dest ~= nil and ts ~= nil, "connectionLanding resolves the ROUTE_3 strip")
  eq(cx, 63, "connectionLanding agrees on the landing x")
  eq(cy, 0, "connectionLanding agrees on the landing y")
  check(Map.defPassable(dest, ts, cx, cy, false),
        "Map.defPassable passes the ROUTE_3 landing on foot")

  -- a plain floor cell is not a ledge no matter which way you lean
  local plain = stand("ROUTE_4", 13, 14)
  Input.state.down = true
  Input.pressed = {}
  check(plain:checkLedgeHop("down") == false, "a non-ledge cell does not hop")
  check(plain:checkLedgeHop("left") == false, "and neither does a sideways lean")
  Input:reset()
end

S.finish()
