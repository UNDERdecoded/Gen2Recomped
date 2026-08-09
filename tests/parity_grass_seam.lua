-- Regression: the tall-grass "feet overdraw" must not fire for an off-map
-- cell during a map-connection seam step (issue #217).
--
-- Walking south out of Viridian City, crossConnection lands the player on
-- ROUTE_1 at (10, 0) and parks them one cell BEFORE the seam for the walk
-- step -- cellY = 0 - 1 = -1, one row off the new map's top edge.  ROUTE_1's
-- borderBlock (11) border-extends OVERWORLD block 11, whose bottom tile row
-- is the grass tile ($52 = 82), so Map:isGrassCell(10, -1) used to return
-- TRUE and the four overworld overdraw sites painted an animated grass tuft
-- over the player's head for the ~5 frames the seam step lasted.
--
-- Tall grass ($52) is only meaningful within the loaded map view; the
-- border-block filler that back-fills off-map coordinates is never standable
-- grass (pokered engine/overworld/connections.asm loads the neighbour strip
-- but the player never collides against border filler as grass).  The fix
-- guards Map:isGrassCell with an in-bounds check.
--
-- Self-contained; run via `luajit tests/parity_grass_seam.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.VIRIDIAN_CITY) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity grass seam")
local check, eq = S.check, S.eq

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack
StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW

-- Park on Viridian City's south edge, on the exit-path column (cellX = 20),
-- facing the seam.  heightCells = 18 blocks * 2 = 36, so cellY = 35 is the
-- bottom edge row.
while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "VIRIDIAN_CITY", 20, 35, "down")
local ow = Game.stack:top()

local south = ow.map:connection("south")
check(south and south.map == "ROUTE_1", "Viridian south connects to ROUTE_1")

check(ow:crossConnection("down", south) == true, "Viridian -> Route 1 crosses")
eq(ow.map.id, "ROUTE_1", "landed on ROUTE_1")

local p = ow.player
-- the seam parks the player one cell before the entry point, off the map
eq(p.cellY, -1, "seam step parks the player at cellY = -1 (off the top edge)")
eq(ow.map:inBounds(p.cellX, p.cellY), false, "the parked cell is off-map")

-- the border filler genuinely IS the grass tile, so the guard (not a
-- different tile) is what suppresses the phantom overdraw
eq(ow.map:cellTile(p.cellX, p.cellY), ow.map.tileset.grassTile,
   "the off-map border tile decodes to the grass tile (82)")

-- THE FIX: an off-map cell is never tall grass, so no feet-overdraw fires
eq(ow.map:isGrassCell(p.cellX, p.cellY), false,
   "off-map seam cell is not grass -- no phantom overdraw over the player")

-- and the target the overdraw sites also test must not fire off-map either
if p.targetX and not ow.map:inBounds(p.targetX, p.targetY) then
  eq(ow.map:isGrassCell(p.targetX, p.targetY), false,
     "off-map seam target is not grass either")
end

-- Positive control: a real in-bounds grass cell still reports grass, so the
-- guard did not blind the encounter roll / overdraw to actual tall grass.
local gx, gy
for cy = 0, ow.map.heightCells - 1 do
  for cx = 0, ow.map.widthCells - 1 do
    if ow.map:cellTile(cx, cy) == ow.map.tileset.grassTile then
      gx, gy = cx, cy
      break
    end
  end
  if gx then break end
end
check(gx ~= nil, "ROUTE_1 has at least one in-bounds grass cell to test")
if gx then
  check(ow.map:inBounds(gx, gy), "control grass cell is in bounds")
  eq(ow.map:isGrassCell(gx, gy), true,
     "real in-bounds tall grass still detected after the fix")
end

S.finish()
