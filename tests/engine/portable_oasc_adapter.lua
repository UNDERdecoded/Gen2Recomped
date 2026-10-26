package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local A = dofile("examples/portable_oasc_world/WorldAdapter.lua")
local Atlas = dofile("examples/portable_oasc_world/Atlas.lua")
local function word(n)
  return string.char(n % 256, math.floor(n / 256))
end
local function graphics()
  local palettes = {}
  for p = 1, 16 do
    palettes[p] = {}
    for c = 1, 16 do
      palettes[p][c] = { c * 10, p * 10, 30 }
    end
  end
  local function bank(layer)
    return {
      tiles4bpp = string.rep(string.char(0x21), 32),
      metatileEntriesLE16 = string.rep(word(0), 8),
      layerTypes = string.char(layer),
      palettes = palettes,
    }
  end
  return {
    version = 1,
    id = "pair",
    graphicsState = "base",
    layout = { tilesInPrimary = 512, metatilesInPrimary = 512, palettesInPrimary = 6, metatileLayers = 2 },
    primary = bank(0),
    secondary = bank(1),
  }
end
local source = graphics()
local decoded = assert(Atlas.decode(source, 0))
T.eq(#decoded.under, 1024, "16px RGBA under layer")
T.eq(decoded.under:byte(1), 20, "low nibble is left color")
T.eq(decoded.under:byte(5), 30, "high nibble is right color")
T.eq(decoded.middle, decoded.under, "normal BG1 is lower half")
T.eq(assert(Atlas.decode(source, 512)).over, string.rep(string.char(0), 1024), "covered has no covering BG2")
source.primary.layerTypes = string.char(2)
T.eq(assert(Atlas.decode(source, 0)).middle, string.rep(string.char(0), 1024), "split has no middle BG1")
source.primary.layerTypes = string.char(3)
T.eq(Atlas.decode(source, 0), nil, "reserved layers are not invented")
source.primary.layerTypes = string.char(0)
source.primary.metatileEntriesLE16 = word(1024) .. source.primary.metatileEntriesLE16:sub(3)
T.eq(assert(Atlas.decode(source, 0)).under:byte(1), 30, "horizontal flip changes sampled left pixel")
source.primary.metatileEntriesLE16 = word(7 * 4096) .. source.primary.metatileEntriesLE16:sub(3)
T.eq(assert(Atlas.decode(source, 0)).under:byte(2), 80, "secondary palettes use absolute slot index")
source.primary.metatileEntriesLE16 = word(20) .. source.primary.metatileEntriesLE16:sub(3)
T.eq(Atlas.decode(source, 0), nil, "missing tile is never silently aliased")
local x, y = graphics(), graphics()
T.check(Atlas.equal(x, y), "content equality for resource reuse")
y.primary.palettes[1][1][1] = 99
T.eq(Atlas.equal(x, y), false, "same identity with new palette invalidates resource")
local calls, stale = {}, false
local data = {
  supports = function()
    return true
  end,
}
function data:snapshot(_, expected, query)
  calls[#calls + 1] = query
  if stale then
    return nil, "active map changed"
  end
  local r = query.region
  local map = query.mapId or "A"
  local grid = {
    version = 1,
    activeMapId = "A",
    mapId = map,
    tilesetId = "pair",
    region = r,
    metatiles = {},
    placements = {
      { mapId = "A", tilesetId = "pair", width = 100, height = 100, x = 0, y = 0, active = true },
      { mapId = "B", tilesetId = "pair", width = 100, height = 100, x = 100, y = 0, active = false },
    },
  }
  for i = 1, r.width * r.height do
    grid.metatiles[i] = 0
  end
  return grid
end
function data:tileset()
  return graphics()
end
local adapter = assert(A.new(data))
local frame =
  { version = 1, generation = 3, mapId = "A", camera = { x = 0, y = 0 }, viewWidth = 160, viewHeight = 160 }
local scene = assert(adapter:capture(frame))
T.eq(scene.cells, 100, "only visible 16px cells")
T.eq(#scene.maps, 1, "offscreen neighbors culled")
T.eq(scene.maps[1].ox, 0, "map offsets remain cell units")
frame.camera.x = 1592
scene = assert(adapter:capture(frame))
T.eq(#scene.maps, 2, "camera crossing includes resident neighbor")
T.eq(scene.maps[2].ox, 100, "neighbor placement retained")
T.eq(#assert(adapter:capture(frame, { neighbors = false })).maps, 1, "neighbor opt-out")
scene = assert(adapter:capture(frame, { bounds = { x = 0, y = 0, width = 1600, height = 1600 } }))
T.eq(scene.cells, 10000, "large visible maps are chunked")
for _, q in ipairs(calls) do
  T.check(q.region.width * q.region.height <= 4096, "each source read remains bounded")
end
T.eq(adapter:capture(frame, { maxCells = 1 }), nil, "total scene budget enforced")
T.eq(adapter:capture(frame, { maxCells = 1 / 0 }), nil, "invalid budget")
T.eq(adapter:capture(frame, { bounds = { x = 0, y = 0, width = 0, height = 1 } }), nil, "invalid bounds")
stale = true
local result, why = adapter:capture(frame)
T.eq(result, nil, "stale scene is declined")
T.eq(why, "active map changed", "stale reason retained")
T.eq(
  A.new({
    supports = function()
      return false
    end,
  }),
  nil,
  "unsupported host"
)
T.finish("Portable OASC world adapter and pixels")
