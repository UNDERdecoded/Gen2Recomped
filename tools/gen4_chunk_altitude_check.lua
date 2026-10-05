-- Run:  texlua tools/gen4_chunk_altitude_check.lua <rom path>
--
-- A CHUNK IS DRAWN AT ITS MATRIX ALTITUDE.
--
-- Reported from play at Oreburgh: *"map boundaries arent at the proper
-- height"* -- the chunks around the city stood at the wrong level, with the
-- void showing through the seams as stretched strips.
--
-- `LandDataManager_CalculateRenderingPosition` (pokeplatinum
-- src/overlay005/land_data.c) places every loaded chunk's model and props at
--
--     position->y = altitude * (MAP_OBJECT_TILE_SIZE / 2);
--
-- with the altitude read from the matrix's own altitude section. The port
-- parsed that section in `Gen4Maps.matrix` and nothing ever drew with it.
--
-- WHY THIS IS MEASURED RATHER THAN ASSERTED: the walkable height does NOT get
-- the altitude (`TerrainCollisionManager`'s GetHeight reads the BDHC and adds
-- nothing), which makes "the model is lifted" sound wrong until it is tested.
-- The test is the seams: across the overworld, two neighbouring chunks of
-- DIFFERENT altitude meet at the same height only when each is lifted by
-- eight units a step -- and every other scale makes them worse. The chunks
-- that need it are the shared FILLER chunks (the sea, the mountain mass),
-- modelled flat at 0 and placed by this number alone.

package.path = './?.lua;./?/init.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local romPath = arg and arg[1]
if not romPath or romPath == '' then
  print('usage: texlua tools/gen4_chunk_altitude_check.lua <rom path>')
  os.exit(2)
end

-- ============================ 1. the renderer's arithmetic, without a GPU
--
-- `Gen4Ground` is loaded with a stub `love` so its pure helpers can be graded
-- here; nothing below draws.
love = love or { math = { random = math.random } }
local okG, Ground = pcall(require, 'src.render.Gen4Ground')
check(okG, 'Gen4Ground must load: ' .. tostring(Ground))
if okG then
  local fake = setmetatable({
    grid = { width = 3, height = 2, land = { 1, 2, 3, 4, 5, 6 } },
    altitudes = { 0, 1, 0, 0, 26, 0 },
    terrain = { pixelsPerUnit = 1 },
  }, { __index = Ground })
  check(fake:chunkLift(0, 0) == 0, 'altitude 0 lifts nothing')
  check(fake:chunkLift(1, 0) == 8, 'altitude 1 is MAP_OBJECT_TILE_SIZE / 2 = 8 units')
  check(fake:chunkLift(1, 1) == 208, 'altitude 26 is 208 units -- Mt. Coronet')
  local bare = setmetatable({ grid = fake.grid, terrain = fake.terrain },
                            { __index = Ground })
  check(bare:chunkLift(1, 1) == 0,
        'a matrix with no altitude section (an interior) lifts nothing')

  -- liftMatrix(m, h) must equal m * translation(0, h, 0) for ANY m -- a
  -- shortcut that only moved the y column would be right for an identity and
  -- wrong for the live pass's oblique projection.
  local Model = require('src.render.Gen4Model')
  local m = { 0.5, 0.1, -0.2, 3, 0.3, -0.7, 0.9, -1, 0.05, -0.4, -0.6, 2, 0, 0, 0, 1 }
  local want = Model.multiply(m, { 1, 0, 0, 0, 0, 1, 0, 40, 0, 0, 1, 0, 0, 0, 0, 1 })
  local got = Ground.liftMatrix(m, 40)
  local same = true
  for i = 1, 16 do if math.abs(got[i] - want[i]) > 1e-9 then same = false end end
  check(same, 'liftMatrix must be m * translation(0, lift, 0)')
  check(Ground.liftMatrix(m, 0) == m, 'and a zero lift must hand back the same matrix')
end

-- Every draw path has to ask for the lift, or one of them keeps the old seams.
local src = io.open('src/render/Gen4Ground.lua'):read('a')
local asks = select(2, src:gsub('self:chunkLift%(cx, cy%)', ''))
check(asks >= 4,
      'the live, free, baked and canopy paths must all lift their chunks -- got '
      .. asks .. ' call sites')
check(src:find('gen4_map_matrices', 1, true),
      'and the ground must read altitudes from the cache every import has had')
-- ...AND THE GAME MUST ACTUALLY LOAD THAT CACHE MODULE. The first version of
-- this fix read `data.gen4_map_matrices` and was confirmed in a harness that
-- loaded the file by hand -- while `Data.lua` never listed it, so in the game
-- the lift was zero and the report came straight back: *"i reloaded the game
-- and the borders still looks the same"*.
local dataSrc = io.open('src/core/Data.lua'):read('a')
local listed = dataSrc:match('local GEN4_PREFIXED = (%b{})') or ''
local live = {}
for line in listed:gmatch('[^\n]+') do
  if not line:match('^%s*%-%-') then live[#live + 1] = line end
end
check(table.concat(live, '\n'):find('"gen4_map_matrices"', 1, true),
      'Data.lua must load gen4_map_matrices, or the altitudes never reach the game')
local terrainSrc = io.open('src/import/Gen4Terrain.lua'):read('a')
check(terrainSrc:find('altitudes = altitudes', 1, true),
      'and the importer must carry them onto the terrain grid for new caches')

-- ======================= 2. the seams say eight units a step, on the ROM
local NdsRom   = require('src.import.NdsRom')
local Narc     = require('src.import.NarcArchive')
local Gen4Maps = require('src.import.Gen4Maps')
local Nsbmd    = require('src.import.Gen4Nsbmd')

local rom = assert(NdsRom.open(romPath))
local land = assert(Narc.parse(assert(rom:read('/fielddata/land_data/land_data.narc'))))
local mats = assert(Narc.parse(assert(rom:read('/fielddata/mapmatrix/map_matrix.narc'))))
local m0 = assert(Gen4Maps.matrix(mats:get(0)))
check(m0.altitudes and #m0.altitudes == m0.width * m0.height,
      'the overworld matrix must carry an altitude per cell')
local nonzero = 0
for _, a in ipairs(m0.altitudes or {}) do if a ~= 0 then nonzero = nonzero + 1 end end
-- MEASURED on Rev 1: 299 of 900.
check(nonzero >= 250, 'and hundreds of them must be non-zero, got ' .. nonzero)

-- The highest model vertex on each tile of a chunk's four edges.
local edgesOf = {}
local function edges(id)
  if edgesOf[id] ~= nil then return edgesOf[id] end
  local out = false
  local L = Gen4Maps.land(land:get(id))
  local set = L and #L.model > 0 and Nsbmd.parse(L.model)
  local model = set and set.models and set.models[1]
  if model then
    local sc = model.posScale or 1
    local node = model.bones and model.bones[1] and model.bones[1].matrix
    local tx, ty, tz = 0, 0, 0
    if type(node) == 'table' then tx, ty, tz = node[4] or 0, node[8] or 0, node[12] or 0 end
    out = { W = {}, E = {}, N = {}, S = {} }
    for _, shape in ipairs(model.shapes or {}) do
      for _, v in ipairs(shape.vertices or {}) do
        local x, y, z = v.x * sc + tx, v.y * sc + ty, v.z * sc + tz
        local function put(side, k)
          if k >= 0 and k < 32 and (out[side][k] == nil or y > out[side][k]) then
            out[side][k] = y
          end
        end
        if math.abs(x + 256) < 1 then put('W', math.floor((z + 256) / 16)) end
        if math.abs(x - 256) < 1 then put('E', math.floor((z + 256) / 16)) end
        if math.abs(z + 256) < 1 then put('N', math.floor((x + 256) / 16)) end
        if math.abs(z - 256) < 1 then put('S', math.floor((x + 256) / 16)) end
      end
    end
  end
  edgesOf[id] = out
  return out
end

-- Share of edge samples across DIFFERENT-altitude seams that meet within two
-- units, when each chunk is lifted by `factor` per altitude step.
local function matching(factor)
  local n, ok = 0, 0
  for y = 0, m0.height - 1 do
    for x = 0, m0.width - 1 do
      local a = m0.altitudes[y * m0.width + x + 1]
      for _, nb in ipairs({ { 1, 0, 'E', 'W' }, { 0, 1, 'S', 'N' } }) do
        local bx, by = x + nb[1], y + nb[2]
        if bx < m0.width and by < m0.height then
          local b = m0.altitudes[by * m0.width + bx + 1]
          local ia, ib = Gen4Maps.chunkAt(m0, x, y), Gen4Maps.chunkAt(m0, bx, by)
          if a ~= b and ia and ib and ia ~= 0xFFFF and ib ~= 0xFFFF then
            local A, B = edges(ia), edges(ib)
            if A and B then
              for k = 0, 31 do
                local ya, yb = A[nb[3]][k], B[nb[4]][k]
                if ya and yb then
                  n = n + 1
                  if math.abs((ya + a * factor) - (yb + b * factor)) <= 2 then
                    ok = ok + 1
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return n > 0 and ok / n or 0, n
end

local at8, samples = matching(8)
local at0 = matching(0)
print(('seams between chunks of different altitude: %d edge samples; '
       .. '%.1f%% meet unlifted, %.1f%% lifted by 8 a step')
      :format(samples, at0 * 100, at8 * 100))
check(samples > 1000, 'there must be seams to measure, got ' .. samples)
-- MEASURED on Rev 1: 13.4% unlifted, 55.7% at eight.
check(at8 > at0 * 3,
      ('the cartridge\'s lift must close the seams: %.1f%% -> %.1f%%')
        :format(at0 * 100, at8 * 100))
for _, other in ipairs({ 4, 16 }) do
  local at = matching(other)
  check(at < at8, ('and %d a step must do worse than 8 (%.1f%% vs %.1f%%)')
                    :format(other, at * 100, at8 * 100))
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
