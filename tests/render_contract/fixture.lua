-- Synthetic native data only: no ROM, player identity or disk cache.
local F = {}
local function le(n, bytes)
  local out = {}
  for i = 1, bytes do
    out[i] = string.char(n % 256)
    n = math.floor(n / 256)
  end
  return table.concat(out)
end
function F.new(backend, version, root)
  local frlg = version ~= "emerald" and version ~= "ruby" and version ~= "sapphire"
  local split, palSplit = frlg and 640 or 512, frlg and 7 or 6
  local prefix = ({ firered = "FR", leafgreen = "FR", ruby = "RU", sapphire = "SA", emerald = "EM" })[version]
    or "FR"
  local mapId = prefix .. (frlg and "_PALLET_TOWN" or "_LITTLEROOT_TOWN")
  local neighborId = prefix .. (frlg and "_ROUTE_1" or "_ROUTE101")
  local s = { mapId = mapId, neighborId = neighborId, split = split, files = {}, loaded = true }
  local words = { 0, split, 1, 2, split + 1, split + 2 }
  local palettes = {}
  for p = 0, 15 do
    for c = 0, 15 do
      palettes[#palettes + 1] = le((c + p) % 32 + (p * 2 % 32) * 32 + c * 1024, 2)
    end
  end
  palettes = table.concat(palettes)
  local entries = {}
  for mid = 0, 2 do
    for k = 0, 7 do
      -- Both banks, all flips, and absolute palette slot numbering.
      entries[#entries + 1] =
        le((k % 2 == 0 and 0 or split) + k % 2 + (k % 4) * 1024 + (k % 2 == 0 and 1 or palSplit) * 4096, 2)
    end
  end
  local bank = {
    tiles = string.rep(string.char(0x21), 32) .. string.rep(string.char(0x43), 32),
    metatiles = table.concat(entries),
    palettes = palettes,
  }
  local attrs, normalized = {}, {}
  for layer = 0, 2 do
    attrs[#attrs + 1] = le(layer * (frlg and 0x20000000 or 4096) + 0x42, frlg and 4 or 2)
    normalized[#normalized + 1] = le(layer * 4096 + 0x42, 2)
  end
  bank.attributes = table.concat(attrs)
  s.bank = bank
  s.game = { phase = "field", data = { maps = {} }, stack = { states = {} } }
  function s.getGame()
    return s.loaded and s.game or nil
  end
  if backend == "gen2" then
    local Map, Rom = require("src.world.Map"), require("src.import.RomGba")
    s.game.data.map_tilesets = {}
    s.game.data.constants = {
      gen3Layout = {
        tilesInPrimary = split,
        metatilesInPrimary = split,
        palettesInPrimary = palSplit,
        metatileLayers = 2,
      },
    }
    local function record(address)
      local pals = {}
      for p = 0, 15 do
        local raw = {}
        for i = 1, 32 do
          raw[i] = palettes:byte(p * 32 + i)
        end
        pals[p + 1] = Rom.palette(raw)
      end
      return {
        address = address,
        tiles = bank.tiles,
        metatiles = bank.metatiles,
        attributes = table.concat(normalized),
        palettes = pals,
      }
    end
    s.game.data.map_tilesets.P = record(0x1000)
    s.game.data.map_tilesets.S = record(0x2000)
    s.game.data.map_tilesets.T = record(0x3000)
    s.game.data.map_tilesets.T.attributes = le(2 * 4096 + 0x42, 2) .. table.concat(normalized):sub(3)
    local function map(id, secondary)
      local def = { id = id, width = 3, height = 2, blocks = "" }
      for i, mid in ipairs(words) do
        def.blocks = def.blocks .. le(mid + (i % 4) * 1024 + 0x6000, 2)
      end
      local ts = {
        id = "same-render-alias",
        blockTiles = 2,
        blockCells = 1,
        primaryKey = "P",
        secondaryKey = secondary,
      }
      local m = Map.new(def, ts)
      s.game.data.maps[id] = def
      return m
    end
    s.map, s.neighbor = map(mapId, "S"), map(neighborId, "T")
    s.world = {
      isOverworld = true,
      map = s.map,
      neighbors = {
        { map = s.neighbor, cx = 3, cy = 0 },
        { map = s.neighbor, cx = -3, cy = 0 },
        { map = s.neighbor, cx = 3, cy = 0 },
        { map = s.map, cx = 0, cy = 0 },
      },
    }
    s.game.overworld = s.world
    s.game.stack.states = { s.world, { isMenu = true } }
    s.handle = require("src.mods.RenderData").new(s.getGame, require("src.core.GameVersion").generation())
    function s.patch(mid)
      s.map:setBlock(1, 0, mid)
    end
    function s.patchNeighbor(mid)
      s.neighbor:setBlock(0, 0, mid)
    end
    function s.corrupt()
      s.map.def.blocks = ""
    end
    function s.badPalette()
      s.game.data.map_tilesets.S.palettes[1][1][1] = -1
    end
    function s.missing()
      s.game.data.map_tilesets.S.tiles = nil
    end
    function s.stale()
      s.map.id = neighborId
    end
    function s.title()
      s.world.isOverworld = false
    end
    function s.capture()
      return {
        s.map.def,
        s.neighbor.def,
        s.map.blockPatch,
        s.map.tileset,
        s.game.data.map_tilesets,
        s.world.neighbors,
        s.game.stack.states,
      }
    end
    function s.large()
      s.map.def.width, s.map.def.height = 65, 65
      s.map.def.blocks = string.rep(le(0, 2), 65 * 65)
    end
    function s.placementsOverflow()
      for i = 1, 129 do
        s.world.neighbors[i] = { map = s.neighbor, cx = i * 3, cy = 0 }
      end
    end
  else
    local Map = require("src.core.game3.map")
    local Pack = require("src.import.gba.native_pack")
    local Layout = require("src.core.game3.layout_native")
    local Catalog = require("src.import.gba.map_catalog")
    local function map(id)
      -- One padding column verifies that logical width differs from stride.
      local cells = {}
      for y = 0, 1 do
        for x = 0, 3 do
          cells[#cells + 1] = { mid = x < 3 and words[y * 3 + x + 1] or 999, coll = 0, elev = 6 }
        end
      end
      local blob =
        Pack.encodeMidLayout({ width = 4, height = 2, trueWidth = 3, trueHeight = 2, cells = cells })
      local def = {
        id = id,
        midLayout = Layout.fromDecoded(assert(Pack.decodeMidLayout(blob)), id, "same-render-alias", blob),
      }
      s.game.data.maps[id] = def
      return def
    end
    s.map, s.neighbor = map(mapId), map(neighborId)
    Map.current, Map._def = mapId, s.map
    Map.world = {
      { id = neighborId, def = s.neighbor, ox = 3, oy = 0 },
      { id = neighborId, def = s.neighbor, ox = -3, oy = 0 },
      { id = neighborId, def = s.neighbor, ox = 3, oy = 0 },
      { id = mapId, def = s.map, ox = 0, oy = 0 },
    }
    local function header(id, secondary)
      local slot = assert(Catalog.slotKeyFor(id), "native catalog must resolve fixture identity")
      s.files["data/generated/gba/map_tree/maps/" .. slot .. "/header.json"] = '{"primaryTileset":"ts_08001000","secondaryTileset":"ts_'
        .. secondary
        .. '"}'
    end
    header(mapId, "08002000")
    header(neighborId, "08003000")
    for _, name in ipairs({ "08001000", "08002000", "08003000" }) do
      local dir = "data/generated/gba/map_tree/tilesets/ts_" .. name .. "/"
      s.files[dir .. "tiles.4bpp"], s.files[dir .. "metatiles.bin"] = bank.tiles, bank.metatiles
      s.files[dir .. "attributes.bin"], s.files[dir .. "palettes.bin"] = bank.attributes, bank.palettes
    end
    local variantAttrs = "data/generated/gba/map_tree/tilesets/ts_08003000/attributes.bin"
    s.files[variantAttrs] = le(2 * (frlg and 0x20000000 or 4096) + 0x42, frlg and 4 or 2)
      .. bank.attributes:sub((frlg and 4 or 2) + 1)
    local cache = {
      read = function(_, path)
        return s.files[path]
      end,
    }
    s.handle = dofile(root .. "/tools/gen3-render-contract/gen1_reference.lua").new(s.getGame, cache)
    function s.patch(mid)
      s.map.midLayout:applyOverride(1, 0, mid, 0, 6)
    end
    function s.patchNeighbor(mid)
      s.neighbor.midLayout:applyOverride(0, 0, mid, 0, 6)
    end
    function s.corrupt()
      s.map.midLayout.cells[1].mid = -1
    end
    function s.missing()
      s.files["data/generated/gba/map_tree/tilesets/ts_08002000/tiles.4bpp"] = nil
    end
    function s.stale()
      Map.current = neighborId
    end
    function s.title()
      s.game.phase = "title"
    end
    function s.capture()
      return { s.map, s.neighbor, s.files, Map.world }
    end
    function s.large()
      local l = s.map.midLayout
      l.width, l.height, l.trueWidth, l.trueHeight = 65, 65, 65, 65
      for i = 1, 65 * 65 do
        l.cells[i] = { mid = 0, coll = 0, elev = 6 }
      end
    end
    function s.placementsOverflow()
      for i = 1, 129 do
        Map.world[i] = { id = neighborId, def = s.neighbor, ox = i * 3, oy = 0 }
      end
    end
  end
  return s
end
return F
