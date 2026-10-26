package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = assert(arg[1]), assert(arg[2]), assert(arg[3]), tonumber(arg[4]) or 2
local fixture = dofile(root .. "/tests/portable_world/fixture.lua").new(root, backend, version, api)
local s, run, exports = fixture.state, fixture.run, fixture.exports
local Json = require("src.link.Json")
local stats = dofile(root .. "/tests/portable_world/gpu_stub.lua").install()
local P = require("src.render.Pipelines")
P.install(run.data)
P.setLevel("portable_oasc_world", 1)
local raw = {
  state = { map = { id = s.mapId }, private = true },
  cam = { x = -16, y = 0 },
  vw = 144,
  vh = 64,
  width = 288,
  height = 128,
  pixelWidth = 288,
  pixelHeight = 128,
  unitWidth = 144,
  unitHeight = 64,
  level = 1,
}
local checks = 0
local function eq(a, b, message)
  checks = checks + 1
  assert(a == b, message or (tostring(a) .. " ~= " .. tostring(b)))
end
local reports = {}
eq(P.worldPipeline(), "portable_oasc_world", "the reference extension must actually select its world pass")
local function draw()
  stats.draws = {}
  local canvas = P.drawWorld("portable_oasc_world", raw)
  assert(canvas, exports.pass.lastError)
  eq(canvas:getWidth(), raw.pixelWidth)
  eq(canvas:getHeight(), raw.pixelHeight)
  local trace = stats.draws
  stats.draws = {}
  return trace
end
reports.base = draw()
eq(#reports.base, 28, "visible root and repeated neighbor placements")
eq(stats.images, 6, "three layers for each distinct pair")
local count = stats.images
reports.reused = draw()
eq(stats.images, count, "unchanged graphics reuse GPU resources")
s.patch(s.split + 2)
s.patchNeighbor(s.split + 1)
reports.patched = draw()
eq(stats.images, count, "live cells do not rebake unchanged graphics")
if backend == "gen2" then
  s.game.data.map_tilesets.S.palettes[rawget(s.game.data.constants.gen3Layout, "palettesInPrimary") + 1][2][1] =
    0
else
  local split = require("src.import.gba.family").active().numPalsInPrimary
  local key = "data/generated/gba/map_tree/tilesets/ts_08002000/palettes.bin"
  local bytes = s.files[key]
  local at = split * 32 + 3
  local word = bytes:byte(at) + bytes:byte(at + 1) * 256
  word = word - word % 32
  s.files[key] = bytes:sub(1, at - 1) .. string.char(word % 256, math.floor(word / 256)) .. bytes:sub(at + 2)
end
reports.recolored = draw()
eq(stats.images, count + 3, "same pair ID with changed palette rebuilds only its atlas")
eq(stats.releasedImages, 3, "superseded source images released")
raw.pixelWidth = 576
raw.pixelHeight = 256
reports.resized = draw()
eq(stats.canvases, 2, "new physical target on resize")
eq(stats.releasedCanvases, 1, "old target released")
P.invalidate()
eq(stats.releasedImages, stats.images, "all atlas resources released")
eq(stats.releasedQuads, stats.quads, "all quads released")
eq(stats.releasedCanvases, stats.canvases, "all targets released")
local G = love.graphics
local newImage, newCanvas = G.newImage, G.newCanvas
G.newImage = function()
  error("injected image allocation failure")
end
eq(P.drawWorld("portable_oasc_world", raw), nil, "failed image allocation falls back")
eq(stats.releasedImages, stats.images, "failed image construction releases partial resources")
G.newImage = newImage
G.newCanvas = function()
  error("injected canvas allocation failure")
end
eq(P.drawWorld("portable_oasc_world", raw), nil, "failed target allocation falls back")
eq(stats.releasedImages, stats.images, "failed target construction releases atlases")
eq(stats.releasedQuads, stats.quads, "failed target construction releases quads")
G.newCanvas = newCanvas
reports.rebuilt = draw()
s.missing()
eq(P.drawWorld("portable_oasc_world", raw), nil, "missing data falls back to native world")
eq(stats.releasedImages, stats.images, "failed observation releases previous resources")
eq(stats.releasedCanvases, stats.canvases, "no stale frame after failed capture")
P.setLevel("portable_oasc_world", 0)
P.update(1 / 60)
eq(P.worldPipeline(), nil, "mode off restores native world")
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
print("PORTABLE_WORLD " .. Json.encode(wire({
  checks = checks,
  frames = reports,
  resources = { images = stats.images, quads = stats.quads, canvases = stats.canvases },
})))
