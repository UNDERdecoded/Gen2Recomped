-- Public Gen2 queries must expose the native collision quad, not GBA bits.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Map = require("src.world.Map")
local Version = require("src.core.GameVersion")
local original = Version.get()
local function tileset()
  return {
    id = "NATIVE", blocks = {{}, {}, {}},
    -- Block zero is a sentinel even if its stored bytes happen to be land.
    collision = {0,0,0,0, 0,0x18,0x29,0xB2, 0x23,0x71,0xFF,0},
    walkable = {0,0x18,0xB2,0x23,0x71}, waterTiles = {0x29}, shoreTiles = {},
  }
end
for _, version in ipairs(Version.ORDER) do
  Version.set(version)
  local map = Map.new({id="ROOM",width=2,height=1,blocks={1,2},borderBlock=1}, tileset())
  for _, cell in ipairs({{0,0,0},{1,0,0x18},{0,1,0x29},{1,1,0xB2},
                         {2,0,0x23},{3,0,0x71},{2,1,0xFF},{3,1,0}}) do
    T.eq(map:cellCollision(cell[1],cell[2]),cell[3],version.." actual COLL_* quad")
    T.eq(map:isWalkable(cell[1],cell[2]),map:isWalkableCell(cell[1],cell[2]),"native terrain permission")
  end
  for _, cell in ipairs({{-1,0},{0,-1},{4,0},{0,2}}) do
    T.eq(map:cellCollision(cell[1],cell[2]),0xFF,"off-map is a collision sentinel")
    T.eq(map:isWalkable(cell[1],cell[2]),false,"public walkability excludes border")
  end
  T.eq(map:cellTile(-1,0),0x18,"native connection border sampling is unchanged")
  T.eq(map:isWalkable(0,1),false,"land walker rejects water")
  map:setBlock(0,0,2)
  T.eq(map:cellCollision(0,0),0x23,"changeblock updates the public collision")
  map:setBlock(0,0,0)
  T.eq(map:cellCollision(0,0),0xFF,"block zero remains a wall")
  map:clearBlockPatches()
  T.eq(map:cellCollision(0,0),0,"clearing patches restores the actual class")
  -- A one-cell GBA grid keeps collision bits separate from behaviour bytes.
  local ts = tileset();ts.blockCells=1;ts.blockTiles=2;ts.behaviourBytes=true
  ts.collision={0xB2,0x23,0x71}
  local gba=Map.new({id="GBA",width=2,height=1,blocks={0,1},collisionCells={0,1}},ts)
  T.eq(gba:cellCollision(0,0),0,"GBA clear bit remains zero")
  T.eq(gba:cellCollision(1,0),1,"GBA wall bit remains one")
  T.eq(gba:cellCollision(-1,0),1,"GBA outside remains blocked")
  gba.collisionPatch[2]=0
  T.eq(gba:cellCollision(1,0),0,"GBA runtime bits retain precedence")
  T.eq(gba:cellBehaviour(0,0),0xB2,"GBA behaviour is not a Johto collision")
  local adopted=tileset();adopted.collision=nil
  local g1=Map.new({id="ADOPTED",width=2,height=1,blocks={1,2}},adopted)
  T.eq(g1:cellCollision(0,0),0,"an adopted Gen1 tileset does not invent COLL_* bytes")
end
Version.set(original)
T.finish("native Gen2 map collision queries")
