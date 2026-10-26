package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local V = require("src.core.GameVersion")
V.set("firered")
local Fixture = require("tests.render_contract.fixture")
local function fresh()
  return Fixture.new("gen2", "firered", ".")
end
local function rejected(change, operation, message)
  local s = fresh()
  change(s)
  local ok, value, err = pcall(s.handle[operation], s.handle, 1, s.mapId)
  T.check(ok, "invalid native source must not throw")
  T.eq(value, nil, "unavailable native source has no fabricated snapshot")
  T.eq(err, message, "explicit native-source failure")
end
local s = fresh()
s.map.def.blocks = { 1, 2, 0, 2, 1, 0 }
T.same(assert(s.handle:snapshot(1, s.mapId)).metatiles, s.map.def.blocks, "table-backed layout")
s.map.def._blockArray = { 2, 1, 0, 0, 1, 2 }
T.same(assert(s.handle:snapshot(1, s.mapId)).metatiles, s.map.def._blockArray, "resident decoded layout")
s.map.blockPatch[1] = 0
T.eq(assert(s.handle:snapshot(1, s.mapId)).metatiles[1], 0, "zero-valued live patch wins")
local packed = fresh()
assert(packed.handle:snapshot(1, packed.mapId))
T.eq(packed.map.def._blockArray, nil, "packed layout stays undecoded on the engine")
rejected(function(f)
  f.map.def.width = 0
end, "snapshot", "geometry unavailable")
rejected(function(f)
  f.map.def.height = 1025
end, "snapshot", "geometry unavailable")
rejected(function(f)
  f.map.tileset.blockTiles = 4
end, "snapshot", "geometry unavailable")
rejected(function(f)
  f.map.blockPatch[1] = 1024
end, "snapshot", "metatile unavailable")
rejected(function(f)
  f.map.blockPatch[1] = false
end, "snapshot", "metatile unavailable")
rejected(function(f)
  f.game.data.map_tilesets.S = nil
end, "snapshot", "tileset unavailable")
rejected(function(f)
  f.game.data.map_tilesets.S.address = 0x7000000
end, "tileset", "tileset unavailable")
rejected(function(f)
  f.game.data.constants.gen3Layout = nil
end, "tileset", "layout unavailable")
rejected(function(f)
  f.game.data.constants.gen3Layout.metatileLayers = 3
end, "tileset", "layout unavailable")
rejected(function(f)
  f.game.data.constants.gen3Layout.tilesInPrimary = 0 / 0
end, "tileset", "layout unavailable")
for _, change in ipairs({
  function(f)
    f.game.data.map_tilesets.S.tiles = "short"
  end,
  function(f)
    f.game.data.map_tilesets.S.tiles = string.rep("a", 32769)
  end,
  function(f)
    f.game.data.map_tilesets.S.metatiles = "short"
  end,
  function(f)
    f.game.data.map_tilesets.S.attributes = ""
  end,
  function(f)
    f.game.data.map_tilesets.S.attributes = string.rep(string.char(0, 0xf0), 3)
  end,
  function(f)
    f.game.data.map_tilesets.S.palettes[16] = nil
  end,
  function(f)
    f.game.data.map_tilesets.S.palettes[1][1] = nil
  end,
  function(f)
    f.game.data.map_tilesets.S.palettes[1][1][1] = 1 / 0
  end,
  function(f)
    f.game.data.map_tilesets.S.palettes[1][1][1] = -1
  end,
  function(f)
    f.game.data.map_tilesets.S.palettes[1][1][1] = 1.5
  end,
}) do
  rejected(change, "tileset", "tileset data unavailable")
end
rejected(function(f)
  f.world.neighbors[1].cx = 0 / 0
end, "snapshot", "placement unavailable")
rejected(function(f)
  f.world.neighbors[1].map.def.width = 0
end, "snapshot", "placement unavailable")
local absolute = fresh()
absolute.game.data.map_tilesets.S.address = 0x08002000
T.eq(
  assert(absolute.handle:tileset(1, absolute.mapId)).id,
  "gba:0001000:0002000",
  "absolute and offset pointers normalize"
)
local metadata = { source = "not public", callback = function() end, image = io.stdout }
for key, value in pairs(metadata) do
  absolute.game.data.map_tilesets.S[key] = value
end
local function plain(value)
  if type(value) == "table" then
    T.eq(getmetatable(value), nil, "snapshots have no native metatables")
    for _, child in pairs(value) do
      plain(child)
    end
  else
    T.check(
      type(value) == "number" or type(value) == "string" or type(value) == "boolean",
      "only public data values"
    )
  end
end
plain(assert(absolute.handle:tileset(1, absolute.mapId)))
T.finish("Gen3 render data native sources")
