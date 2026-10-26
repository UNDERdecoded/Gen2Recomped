package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = assert(arg[1]), assert(arg[2]), assert(arg[3]), tonumber(arg[4]) or 2
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
V.set(version)
local fixture = dofile(root .. "/tests/render_contract/fixture.lua")
local s = fixture.new(backend, version, root)
local Loader = require("src.mods.Loader")
if backend == "gen1" then
  local original = Loader._api
  Loader._api = function(self, mod)
    local out = original(self, mod)
    out.renderData = s.handle -- explicitly a reference extension, not native upstream support
    return out
  end
end
local f = assert(io.open(root .. "/tests/render_contract/consumer.lua", "rb"))
local entry = f:read("*a")
f:close()
local run = T.sdk.loadMods({ "mods/render_contract" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs({
    ["mods/render_contract/manifest.json"] = '{"id":"render_contract","name":"Render contract",'
      .. '"version":"1.0.0","api":'
      .. api
      .. ',"entry":"main.lua","affects_link":false,'
      .. '"game_version":">=0.0.0","games":["gen1","gen2","gen3"],"gen2compat":true}',
    ["mods/render_contract/main.lua"] = entry,
  }),
})
assert(#run.errors == 0, "actual loader must accept the identical consumer")
run.loader.game = s.game
local exports = assert(run.loader.exports.render_contract)
local r = assert(exports.handle)
local count = 0
local function eq(a, b, msg)
  count = count + 1
  assert(a == b, msg or (tostring(a) .. " ~= " .. tostring(b)))
end
local function errorIs(fn, message)
  local result, err = fn()
  eq(result, nil)
  eq(err, message)
end
local function stable(value, seen)
  if type(value) ~= "table" then
    return tostring(value)
  end
  seen = seen or {}
  if seen[value] then
    return "<cycle>"
  end
  seen[value] = true
  local keys, out = {}, {}
  for k in pairs(value) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(keys) do
    out[#out + 1] = stable(k) .. "=" .. stable(value[k], seen)
  end
  return "{" .. table.concat(out, ";") .. "}"
end
local outputs = {}
if V.generation() ~= 3 then
  eq(r:supports(1), false)
  errorIs(function()
    return r:snapshot(1, s.mapId)
  end, "unsupported generation")
  errorIs(function()
    return r:tileset(1, s.mapId)
  end, "unsupported generation")
else
  eq(r:supports(1), true)
  eq(r.getGame, nil)
  eq(r.generation, nil)
  for _, query in ipairs({ false, { path = "outside" }, setmetatable({}, {}) }) do
    errorIs(function()
      return r:snapshot(1, s.mapId, query)
    end, "invalid render query")
  end
  for _, target in ipairs({ false, 42, "" }) do
    errorIs(function()
      return r:snapshot(1, s.mapId, { mapId = target })
    end, "invalid target map id")
    errorIs(function()
      return r:tileset(1, s.mapId, target)
    end, "invalid target map id")
  end
  s.game.data.maps.UNLOADED = {}
  errorIs(function()
    return r:snapshot(1, s.mapId, { mapId = "UNLOADED" })
  end, "map not resident")
  errorIs(function()
    return r:tileset(1, s.mapId, "UNLOADED")
  end, "map not resident")
  for _, v in ipairs({ 0, 2, "1", false }) do
    eq(r:supports(v), false)
    errorIs(function()
      return r:snapshot(v, s.mapId)
    end, "unsupported render data version")
    errorIs(function()
      return r:tileset(v, s.mapId)
    end, "unsupported render data version")
  end
  for _, id in ipairs({ false, 1, "", string.rep("x", 161) }) do
    errorIs(function()
      return r:snapshot(1, id)
    end, "invalid map id")
  end
  for _, region in ipairs({
    false,
    {},
    { x = -1, y = 0, width = 1, height = 1 },
    { x = 0, y = 0, width = 0, height = 1 },
    { x = 2, y = 0, width = 2, height = 1 },
    { x = 0 / 0, y = 0, width = 1, height = 1 },
    { x = 0, y = 0, width = 1 / 0, height = 1 },
    { x = 0, y = 0, width = 1, height = 1, path = "outside" },
    setmetatable({ x = 0, y = 0, width = 1, height = 1 }, {}),
  }) do
    errorIs(function()
      return r:snapshot(1, s.mapId, { region = region })
    end, "invalid region (maximum 4096 cells)")
  end
  -- Trap side effects during reads; fixture construction happens before this.
  local function forbidden()
    error("observations must not perform IO/GPU/RNG/loads")
  end
  local oldRandom, oldOpen = math.random, io.open
  local oldFs, oldGraphics, oldImage = love.filesystem, love.graphics, love.image
  math.random, io.open = forbidden, forbidden
  love.filesystem, love.graphics, love.image =
    setmetatable({}, {
      __index = function()
        return forbidden
      end,
    }), setmetatable({}, {
      __index = function()
        return forbidden
      end,
    }), setmetatable({}, {
      __index = function()
        return forbidden
      end,
    })
  local before = stable(s.capture())
  local result = assert(exports.observe(s.mapId))
  local g, t = result.grid, result.graphics
  eq(g.version, 1)
  eq(g.width, 3)
  eq(g.height, 2)
  eq(g.cellSize, 16)
  eq(g.tileSize, 8)
  eq(g.coordinateBase, 0)
  eq(g.metatiles[2], s.split)
  eq(#g.metatiles, 6)
  eq(#g.placements, 3)
  eq(g.placements[1].active, true)
  eq(g.placements[2].x, -3)
  eq(g.placements[3].x, 3)
  eq(g.tilesetId, "gba:0001000:0002000")
  eq(g.placements[2].tilesetId, "gba:0001000:0003000")
  eq(t.id, g.tilesetId)
  eq(t.graphicsState, "base")
  eq(t.paletteFormat, "rgb8-floor")
  eq(t.layout.metatilesInPrimary, s.split)
  eq(t.layout.tilesInPrimary, s.split)
  eq(t.primary.tiles4bpp:byte(1), 0x21)
  eq(t.secondary.metatileEntriesLE16, s.bank.metatiles)
  eq(t.primary.layerTypes, string.char(0, 1, 2))
  eq(t.primary.palettes[1][2][1], 8)
  eq(t.primary.palettes[1][2][3], 8)
  eq(stable(s.capture()), before, "snapshots must leave native source tables/caches untouched")
  outputs.base = result
  local neighbor = assert(exports.observe(s.mapId, { mapId = s.neighborId }))
  eq(neighbor.grid.activeMapId, s.mapId)
  eq(neighbor.grid.mapId, s.neighborId)
  eq(neighbor.graphics.id, "gba:0001000:0003000")
  eq(neighbor.grid.placements[1].mapId, s.mapId)
  eq(neighbor.graphics.secondary.layerTypes:byte(1), 2)
  eq(result.graphics.secondary.layerTypes:byte(1), 0)
  outputs.neighbor = neighbor
  eq(stable(s.capture()), before)
  -- Returned tables can be changed freely; subsequent reads are independent.
  local detached = assert(exports.observe(s.mapId))
  detached.grid.placements[1].x = 777
  detached.grid.metatiles[1] = 777
  detached.grid.region.x = 777
  detached.graphics.primary.palettes[1][2][1] = 777
  detached.graphics.layout.tilesInPrimary = 777
  eq(stable(assert(exports.observe(s.mapId))), stable(result))
  eq(stable(s.capture()), before)
  local crop = assert(r:snapshot(1, s.mapId, { region = { x = 1, y = 0, width = 2, height = 2 } }))
  eq(#crop.metatiles, 4)
  eq(crop.metatiles[1], s.split)
  eq(crop.metatiles[3], s.split + 1)
  outputs.crop = crop
  -- Restore environment before exercising native mutation APIs.
  math.random, io.open = oldRandom, oldOpen
  love.filesystem, love.graphics, love.image = oldFs, oldGraphics, oldImage
  s.patch(s.split + 2)
  local patched = assert(r:snapshot(1, s.mapId))
  eq(patched.metatiles[2], s.split + 2)
  outputs.patched = patched
  s.patchNeighbor(s.split + 1)
  local neighborPatched = assert(r:snapshot(1, s.mapId, { mapId = s.neighborId }))
  eq(neighborPatched.metatiles[1], s.split + 1)
  eq(assert(r:snapshot(1, s.mapId)).metatiles[1], 0)
  outputs.neighborPatched = neighborPatched
  s.loaded = false
  run.loader.game = nil
  local oldGame, oldPreload = package.loaded["src.core.Game"], package.preload["src.core.Game"]
  package.loaded["src.core.Game"] = nil
  package.preload["src.core.Game"] = function()
    error("must not bootstrap Game")
  end
  errorIs(function()
    return r:snapshot(1, s.mapId)
  end, "no overworld")
  s.loaded = true
  run.loader.game = s.game
  package.loaded["src.core.Game"], package.preload["src.core.Game"] = oldGame, oldPreload
  s.stale()
  errorIs(function()
    return r:snapshot(1, s.mapId)
  end, "active map changed")
  errorIs(function()
    return r:tileset(1, s.mapId)
  end, "active map changed")
  -- Destructive negative fixtures are isolated from one another.
  local missing = fixture.new(backend, version, root)
  missing.missing()
  errorIs(function()
    return missing.handle:tileset(1, missing.mapId)
  end, "tileset data unavailable")
  local corrupt = fixture.new(backend, version, root)
  corrupt.corrupt()
  errorIs(function()
    return corrupt.handle:snapshot(1, corrupt.mapId)
  end, "metatile unavailable")
  local large = fixture.new(backend, version, root)
  large.large()
  errorIs(function()
    return large.handle:snapshot(1, large.mapId)
  end, "invalid region (maximum 4096 cells)")
  eq(
    #assert(large.handle:snapshot(1, large.mapId, { region = { x = 1, y = 1, width = 64, height = 64 } })).metatiles,
    4096
  )
  local overflow = fixture.new(backend, version, root)
  overflow.placementsOverflow()
  errorIs(function()
    return overflow.handle:snapshot(1, overflow.mapId)
  end, "too many placements")
  local title = fixture.new(backend, version, root)
  title.title()
  errorIs(function()
    return title.handle:snapshot(1, title.mapId)
  end, "no overworld")
end
local Json = require("src.link.Json")
local function wire(value)
  if type(value) == "string" then
    return "hex:" .. (value:gsub(".", function(c)
      return ("%02x"):format(c:byte())
    end))
  end
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = wire(v)
  end
  return out
end
if arg[5] == "quiet" then
  print(("Render data contract: %d checks passed"):format(count))
else
  print("RENDER_CONTRACT " .. assert(Json.encode(wire({ checks = count, outputs = outputs }))))
end
