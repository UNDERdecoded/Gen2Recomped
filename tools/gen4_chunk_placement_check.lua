-- Run:  texlua tools/gen4_chunk_placement_check.lua <rom path>
--
-- A CHUNK'S GEOMETRY STANDS WHERE ITS NODE PUTS IT.
--
-- Reported from play: *"the bike routes building entrance also isnt rendering
-- properly above oreburg, its putting the npcs and players in a dark area and
-- the building area is to the right"*.
--
-- A land chunk's model is an NSBMD like every other model on this cartridge:
-- its shapes are drawn through a NODE, and `Gen4ModelPack.pack` has carried
-- `nodes` and `ops` all along -- with a comment saying why they must not be
-- baked into the vertices. `Gen4Terrain.append` wrote neither into the cache,
-- so the whole mechanism stopped there and every chunk was drawn as though its
-- node were the identity.
--
-- 649 of the 666 chunks it IS, which is why this survived so long. The rest
-- carry a real translation, and the maps that sit on them put their players in
-- a dark patch beside their own building.

package.path = './?.lua;./?/init.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local romPath = arg and arg[1]
if not romPath or romPath == '' then
  print('usage: texlua tools/gen4_chunk_placement_check.lua <rom path>')
  os.exit(2)
end

local NdsRom   = require('src.import.NdsRom')
local Narc     = require('src.import.NarcArchive')
local Gen4Maps = require('src.import.Gen4Maps')
local Nsbmd    = require('src.import.Gen4Nsbmd')
local Pack     = require('src.import.Gen4ModelPack')
local Terrain  = require('src.import.Gen4Terrain')

local rom = assert(NdsRom.open(romPath))
local land = assert(Narc.parse(assert(rom:read('/fielddata/land_data/land_data.narc'))))
check(land.count == 666, 'the cartridge must hold 666 land chunks, got ' .. tostring(land.count))

local UNIT, HALF = 16, 256
local function identity(m)
  if type(m) ~= 'table' then return true end
  for i = 1, 16 do
    local want = (i == 1 or i == 6 or i == 11 or i == 16) and 1 or 0
    if math.abs((m[i] or want) - want) > 1e-6 then return false end
  end
  return true
end

-- ============================ 1. the cartridge really does move some chunks
local moved, still = {}, {}
for m = 0, land.count - 1 do
  local L = Gen4Maps.land(land:get(m))
  local set = L and #L.model > 0 and Nsbmd.parse(L.model)
  local model = set and set.models and set.models[1]
  if model then
    local any = false
    for _, bone in ipairs(model.bones or {}) do
      if not identity(bone.matrix) then any = true break end
    end
    if any then moved[#moved + 1] = m else still[#still + 1] = m end
  end
end
check(#moved > 0,
      'some chunks must carry a non-identity node, or there is nothing here to '
      .. 'fix and this check is testing a fiction')
check(#still > #moved * 10,
      'and the great majority must be the identity -- that is why drawing them '
      .. 'all at the origin looked right; moved ' .. #moved .. ', still ' .. #still)

-- ======================= 2. the importer carries them, and only when they say
--
-- `nodes` on all 666 would be thousands of numbers stating that nothing moves,
-- in a cache file already 163,899 lines long.
local function entryFor(m)
  local chunk = Terrain.chunk(land:get(m))
  if not chunk then return nil end
  local state = Terrain.newBlob()
  return Terrain.append(state, chunk), chunk
end

local sampleMoved = moved[1]
local entryMoved = entryFor(sampleMoved)
check(entryMoved and entryMoved.nodes ~= nil,
      'a chunk whose node moves must carry its nodes into the cache (member '
      .. tostring(sampleMoved) .. ')')
check(entryMoved and entryMoved.ops ~= nil,
      'and its render ops -- the nodes alone do not say which shape binds which')

local sampleStill = still[1]
local entryStill = entryFor(sampleStill)
check(entryStill and entryStill.nodes == nil,
      'a chunk whose node is the identity must carry none (member '
      .. tostring(sampleStill) .. ')')
check(entryStill and entryStill.ops == nil, 'nor its ops')

-- ================== 3. posing moves the geometry onto the map's own walls
--
-- THE PROPERTY, and the one that says this is the right fix rather than a
-- plausible one. Each chunk carries its own 32x32 permission grid -- the
-- cartridge's statement of where a player may stand -- and that is independent
-- of the mesh. If applying the node moves the geometry ONTO those tiles and
-- leaving it off does not, the node is what was missing.
local function walkBox(L)
  local minx, maxx, miny, maxy = 32, -1, 32, -1
  for y = 0, 31 do
    for x = 0, 31 do
      local w = Gen4Maps.permissionAt(L, x, y)
      -- A tile the cartridge never filled in reads 0 and is the chunk's void;
      -- a real floor carries a behaviour word or the blocked bit.
      if w and w ~= 0 then
        if x < minx then minx = x end
        if x > maxx then maxx = x end
        if y < miny then miny = y end
        if y > maxy then maxy = y end
      end
    end
  end
  if maxx < 0 then return nil end
  return minx, maxx, miny, maxy
end

-- The model's own extent, in tiles, with and without its node applied.
local function meshTiles(model, apply)
  local lo1, hi1, lo2, hi2 = math.huge, -math.huge, math.huge, -math.huge
  local sc = model.posScale or 1
  local node = model.bones and model.bones[1] and model.bones[1].matrix
  for _, shape in ipairs(model.shapes or {}) do
    for _, v in ipairs(shape.vertices or {}) do
      local x, z = v.x * sc, v.z * sc
      if apply and type(node) == 'table' then
        x = x + (node[4] or 0)
        z = z + (node[12] or 0)
      end
      if x < lo1 then lo1 = x end
      if x > hi1 then hi1 = x end
      if z < lo2 then lo2 = z end
      if z > hi2 then hi2 = z end
    end
  end
  if lo1 == math.huge then return nil end
  return (lo1 + HALF) / UNIT, (hi1 + HALF) / UNIT,
         (lo2 + HALF) / UNIT, (hi2 + HALF) / UNIT
end

-- ONLY CHUNKS WHOSE PERMISSION GRID IS LOCALISED.
--
-- An outdoor chunk is walkable corner to corner, so its "walkable box" is the
-- whole 32x32 and says nothing about where anything stands -- a mesh sitting
-- at the chunk centre scores a perfect match against it by accident. Six of
-- the twelve single-node chunks are like that, and two of those carry meshes
-- two tiles across: props, placed somewhere specific in open ground, which
-- this test cannot speak to either way. Testing them anyway would be reading
-- noise as a result in both directions.
--
-- What IS testable is a chunk whose grid describes a ROOM: walls, a floor, and
-- void around it. There the grid is an independent statement of where the
-- geometry belongs, and the node either lands on it or does not.
local tested, landed, skipped = 0, 0, 0
for _, m in ipairs(moved) do
  local L = Gen4Maps.land(land:get(m))
  local model = Nsbmd.parse(L.model).models[1]
  local wx0, wx1, wy0, wy1 = walkBox(L)
  if wx0 and model and model.bones and #model.bones == 1 then
    local localised = (wx1 - wx0) < 28 and (wy1 - wy0) < 28
    if not localised then
      skipped = skipped + 1
    else
      local ax0, ax1, az0, az1 = meshTiles(model, true)
      local bx0, bx1, bz0, bz1 = meshTiles(model, false)
      if ax0 and bx0 then
        tested = tested + 1
        -- THE POSED MESH MUST COVER THE ROOM, measured as overlap rather
        -- than by its corner.
        --
        -- A corner test is wrong here and said so: the geometry is sometimes
        -- NARROWER than the walkable box, because a doorway's threshold and
        -- the tiles under an archway are standable with nothing modelled over
        -- them. What must be true is that the room and the mesh are in the
        -- same place, which is an overlap.
        local function overlap(mx0, mx1, mz0, mz1)
          local ox = math.max(0, math.min(mx1, wx1 + 1) - math.max(mx0, wx0))
          local oz = math.max(0, math.min(mz1, wy1 + 1) - math.max(mz0, wy0))
          local area = (wx1 + 1 - wx0) * (wy1 + 1 - wy0)
          return area > 0 and (ox * oz) / area or 0
        end
        local posed = overlap(ax0, ax1, az0, az1)
        local raw = overlap(bx0, bx1, bz0, bz1)
        -- BOTH HALVES OF THE CLAIM, because either alone is satisfiable by
        -- something that is not the fix.
        --
        -- "Posed covers the room" alone would pass a node that moved nothing,
        -- on a chunk whose geometry already sat right. "Posed beats raw" alone
        -- would pass a node that merely moved the mesh from very wrong to less
        -- wrong. So: the posed geometry must substantially cover the room, AND
        -- posing must substantially improve on not posing.
        --
        -- Neither threshold is near 1, and both numbers are the cartridge's
        -- rather than mine. Member 507's room runs 25 tiles deep with only its
        -- first 12 modelled, so demanding full coverage would assert something
        -- Platinum does not do; member 501 is displaced by 7 tiles INSIDE an
        -- 18-tile room, so its raw overlap is 0.37 rather than 0 and demanding
        -- "raw is nowhere near" would fail a chunk the node fixes perfectly
        -- (0.37 -> 1.00).
        if posed >= 0.4 and posed >= raw + 0.25 then landed = landed + 1 else
          print(('   note: member %d overlap raw %.2f -> posed %.2f  '
                 .. '(posed x[%.1f..%.1f] z[%.1f..%.1f] vs walls x[%d..%d] y[%d..%d])')
            :format(m, raw, posed, ax0, ax1, az0, az1, wx0, wx1, wy0, wy1))
        end
      end
    end
  end
end
check(tested >= 5,
      'there must be room-shaped moved chunks to test, got ' .. tested
      .. ' (skipped ' .. skipped .. ' open-ground chunks)')
check(landed == tested,
      'applying the node must put the geometry ON the room its own permission '
      .. 'grid describes, and the raw geometry must NOT already be there -- '
      .. 'otherwise there was nothing to fix; ' .. landed .. ' of ' .. tested)

-- ...AND THE RENDERER MUST ASK FOR THEM. An importer that carries nodes into a
-- cache nothing reads is the same bug one layer along.
local ground = io.open('src/render/Gen4Ground.lua'):read('a')
check(ground:match('nodes = record%.nodes, ops = record%.ops'),
      'the chunk model must be built with the nodes and ops the cache carries')

rom:close()
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
