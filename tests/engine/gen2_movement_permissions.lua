-- Terrain-only queries must agree with the native Gen2 grid mover.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local C = require("src.world.Collision")
local Map = require("src.world.Map")
local World = require("src.world.OverworldController")
local Version = require("src.core.GameVersion")
local oldVersion = Version.get()
Version.set("crystal")
local Compat = require("src.core.ModCompat")
T.eq(Compat.resolve("src.world.gen2.Permissions"), C, "existing alias keeps the actual native collision owner")
for _, name in ipairs({"isIce", "currentDirection", "doorForcedDirection", "stepPermitted"}) do
  T.eq(type(C[name]), "function", "public terrain query exists: " .. name)
end
local directions = {"right", "left", "up", "down"}
local forcedDoor = {[0x71]=true, [0x79]=true, [0x7A]=true, [0x7B]=true}
for byte = 0, 255 do
  T.eq(C.isIce(byte), byte == 0x23 or byte == 0x2B, "exact native ice class")
  local current = byte >= 48 and byte <= 63 and directions[byte % 4 + 1] or nil
  T.eq(C.currentDirection(byte), current, "complete current family including waterfall caps")
  T.eq(C.doorForcedDirection(byte), forcedDoor[byte] and "down" or nil, "exact forced doorway subset")
end
T.eq(C.isIce(nil), false, "missing collision does not enable ice")
for _, invalid in ipairs({-1, 256, 0x23 + 256, 0x30 + 256, "48", false, {}, 48.5, math.huge, 0/0}) do
  T.eq(C.isIce(invalid), false, "invalid collision does not enable ice")
  T.eq(C.currentDirection(invalid), nil, "invalid collision does not force current")
  T.eq(C.doorForcedDirection(invalid), nil, "invalid collision does not force doorway")
end
T.eq(C.currentDirection(nil), nil, "missing current")
T.eq(C.doorForcedDirection(nil), nil, "missing doorway")
local tileset = {id="PERMISSIONS", blocks={}, collision={}, walkable={}}
for i = 0, 255 do tileset.walkable[#tileset.walkable+1] = i end
for i = 1, 40 do tileset.collision[i] = 0 end
local map = Map.new({id="NATIVE", generation=2, width=3, height=3, blocks={1,2,3,4,5,6,7,8,9}}, tileset)
local mover = {cellX=2, cellY=2}
local function put(x, y, byte)
  local block = map:blockAt(math.floor(x/2), math.floor(y/2))
  tileset.collision[block*4 + (y%2)*2 + x%2 + 1] = byte
end
-- This samples the native Gen2 class directly, so the contract can also run
-- independently before the separate public cellCollision byte-read change.
local function collision(x,y) return map:inBounds(x,y) and map:cellTile(x,y) or 0xFF end
-- All classes stand on terrain made passable here to isolate directional
-- fences from land/water classification, occupancy and hooks. Use real Map
-- cells and the full native mover, not a second side-wall implementation.
for _, dir in ipairs(directions) do
  local tx,ty = C.target(2,2,dir)
  for source = 0,255 do
    put(2,2,source)
    for destination = 0,255 do
      put(tx,ty,destination)
      local native = C.canMove(map, {}, mover, dir)
      T.eq(C.stepPermitted(collision,2,2,dir), native, "public directional fence agrees with actual native grid mover")
    end
  end
  put(tx,ty,0)
end
-- A perpendicular neighbor must not close this direction. Both wall and buoy
-- families retain the same directional corners and repeated low-three bits.
put(2,2,0)
for _, family in ipairs({0xB0,0xC0}) do
  for _, offset in ipairs({0,8}) do
    put(2,1,family+offset+3)
    T.eq(C.stepPermitted(collision,2,2,"up"),false,"north neighbor faces the body")
    T.eq(C.stepPermitted(collision,2,2,"right"),true,"north neighbor does not block east")
    put(2,1,0)
    put(3,2,family+offset+1)
    T.eq(C.stepPermitted(collision,2,2,"right"),false,"east neighbor faces the body")
    put(3,2,family+offset)
    T.eq(C.stepPermitted(collision,2,2,"right"),true,"east neighbor faces away")
    put(3,2,0)
  end
end
local reads=0
T.eq(C.stepPermitted(function() reads=reads+1 end,2,2,"diagonal"),false,"unknown direction fails closed")
T.eq(reads,0,"unknown direction never samples unrelated cells")
-- A terrain-only permission must never be mistaken for whole-step admission.
local npc={cellX=3,cellY=2}
T.eq(C.stepPermitted(collision,2,2,"right"),true,"directional floor is clear")
T.eq(C.canMove(map,{npc},mover,"right"),false,"native occupancy remains authoritative")
map.shutCells = {["2:1"]=true}
T.eq(C.stepPermitted(collision,2,2,"up"),true,"directional query does not claim authored closed-cell ownership")
T.eq(C.canMove(map,{},mover,"up"),false,"native closed cell remains authoritative")
map.shutCells={}
-- Public values immediately observe real script block replacement.
put(3,2,0xB1)
T.eq(C.stepPermitted(collision,2,2,"right"),false,"live wall before changeblock")
map:setBlock(1,1,1)
T.eq(C.stepPermitted(collision,2,2,"right"),true,"changeblock takes effect without permission cache")
map:clearBlockPatches()
T.eq(C.stepPermitted(collision,2,2,"right"),false,"restoring native block restores wall")
local world = setmetatable({map=map},{__index=World})
for _, version in ipairs({"gold","silver","crystal","prism"}) do
  Version.set(version)
  for byte = 0,255 do
    put(2,2,byte)
    T.eq(world:gen2IsIce(2,2), C.isIce(byte), "live native ice test shares the public predicate")
  end
end
world.map=nil
T.eq(world:gen2IsIce(2,2),false,"missing map cannot force a native ice step")
Version.set(oldVersion)
T.finish("native Gen2 directional and special-terrain permissions")
