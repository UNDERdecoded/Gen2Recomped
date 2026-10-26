-- Test/reference adapter for pinned Gen1Recomp; not an upstream public API.
-- Reads resident LayoutNative handles and already extracted map-tree files.
-- The caller supplies the existing cache, never a path chosen by the mod.
local Map = require("src.core.game3.map")
local Catalog = require("src.import.gba.map_catalog")
local Family = require("src.import.gba.family")
local Version = require("src.core.GameVersion")
local M = {}
local function int(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end
local function id(s)
  return type(s) == "string" and #s > 0 and #s <= 160
end
local function dims(def)
  local l = def and def.midLayout
  local w, h = l and (l.trueWidth or l.width), l and (l.trueHeight or l.height)
  if not (int(w, 1, 1024) and int(h, 1, 1024)) then
    return nil
  end
  return w, h
end
function M.new(getGame, cache)
  local generation = Version.generation()
  local handle = {}
  function handle:supports(v)
    return v == 1 and generation == 3
  end
  local function active(v, expected)
    if v ~= 1 then
      return nil, "unsupported render data version"
    end
    if not handle:supports(v) then
      return nil, "unsupported generation"
    end
    if not id(expected) then
      return nil, "invalid map id"
    end
    local game = getGame()
    if not game or game.phase ~= "field" or not Map.current then
      return nil, "no overworld"
    end
    if Map.current ~= expected then
      return nil, "active map changed"
    end
    local def = game.data and game.data.maps and game.data.maps[expected]
    if not dims(def) then
      return nil, "geometry unavailable"
    end
    return def
  end
  local function pair(mapId)
    local slot = Catalog.slotKeyFor(mapId)
    local json = slot and cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/header.json")
    local a = json and json:match('"primaryTileset"%s*:%s*"(ts_%x+)"')
    local b = json and json:match('"secondaryTileset"%s*:%s*"(ts_%x+)"')
    local function offset(s)
      local n = s and tonumber(s:sub(4), 16)
      if n and n >= 0x08000000 then
        n = n - 0x08000000
      end
      return int(n, 0, 0x01ffffff) and ("%07x"):format(n) or nil
    end
    local ai, bi = offset(a), offset(b)
    if not ai or not bi then
      return nil
    end
    return { id = "gba:" .. ai .. ":" .. bi, a = a, b = b }
  end
  local function resident(expected, target)
    if target == nil then
      target = expected
    end
    if not id(target) then
      return nil, "invalid target map id"
    end
    if target == expected then
      return getGame().data.maps[target], target
    end
    if #Map.world > 128 then
      return nil, "too many placements"
    end
    for _, n in ipairs(Map.world) do
      if n.id == target then
        return n.def, target
      end
    end
    return nil, "map not resident"
  end
  function handle:snapshot(v, expected, query)
    local def, err = active(v, expected)
    if not def then
      return nil, err
    end
    if query == nil then
      query = {}
    end
    if type(query) ~= "table" or getmetatable(query) then
      return nil, "invalid render query"
    end
    for k in pairs(query) do
      if k ~= "mapId" and k ~= "region" then
        return nil, "invalid render query"
      end
    end
    local selected, target = resident(expected, query.mapId)
    if not selected then
      return nil, target
    end
    def = selected
    local w, h = dims(def)
    if not w then
      return nil, "geometry unavailable"
    end
    local r = query.region
    if r == nil then
      r = { x = 0, y = 0, width = w, height = h }
    end
    if type(r) ~= "table" or getmetatable(r) then
      return nil, "invalid region (maximum 4096 cells)"
    end
    for k in pairs(r) do
      if k ~= "x" and k ~= "y" and k ~= "width" and k ~= "height" then
        return nil, "invalid region (maximum 4096 cells)"
      end
    end
    if
      not (
        int(r.x, 0, w - 1)
        and int(r.y, 0, h - 1)
        and int(r.width, 1, w)
        and int(r.height, 1, h)
        and r.x + r.width <= w
        and r.y + r.height <= h
        and r.width * r.height <= 4096
      )
    then
      return nil, "invalid region (maximum 4096 cells)"
    end
    local p = pair(target)
    if not p then
      return nil, "tileset unavailable"
    end
    local out = {
      version = 1,
      generation = 3,
      coordinateBase = 0,
      tileSize = 8,
      cellSize = 16,
      activeMapId = expected,
      mapId = target,
      tilesetId = p.id,
      width = w,
      height = h,
      region = { x = r.x, y = r.y, width = r.width, height = r.height },
      metatiles = {},
      placements = {},
    }
    for y = r.y, r.y + r.height - 1 do
      for x = r.x, r.x + r.width - 1 do
        -- Native getters are pure and include script-written layout overrides.
        local mid = def.midLayout:midAt(x, y)
        if not int(mid, 0, 1023) then
          return nil, "metatile unavailable"
        end
        out.metatiles[#out.metatiles + 1] = mid
      end
    end
    local seen = {}
    local function add(mid, md, x, y, isActive)
      if not (id(mid) and int(x, -1048576, 1048576) and int(y, -1048576, 1048576)) then
        return nil
      end
      local mw, mh = dims(md)
      local mp = pair(mid)
      if not mw or not mp then
        return nil
      end
      local key = #mid .. ":" .. mid .. ":" .. x .. ":" .. y
      if seen[key] then
        return true
      end
      if #out.placements >= 128 then
        return nil
      end
      seen[key] = true
      out.placements[#out.placements + 1] =
        { mapId = mid, width = mw, height = mh, x = x, y = y, active = isActive, tilesetId = mp.id }
      return true
    end
    if not add(expected, getGame().data.maps[expected], 0, 0, true) then
      return nil, "placement unavailable"
    end
    if #Map.world > 128 then
      return nil, "too many placements"
    end
    for _, n in ipairs(Map.world) do
      if not add(n.id, n.def, n.ox, n.oy, false) then
        return nil, "placement unavailable"
      end
    end
    table.sort(out.placements, function(a, b)
      if a.active ~= b.active then
        return a.active
      end
      if a.y ~= b.y then
        return a.y < b.y
      end
      if a.x ~= b.x then
        return a.x < b.x
      end
      return a.mapId < b.mapId
    end)
    return out
  end
  function handle:tileset(v, expected, targetMapId)
    local def, err = active(v, expected)
    if not def then
      return nil, err
    end
    local selected, target = resident(expected, targetMapId)
    if not selected then
      return nil, target
    end
    if not dims(selected) then
      return nil, "geometry unavailable"
    end
    local p = pair(target)
    if not p then
      return nil, "tileset unavailable"
    end
    local f = Family.active()
    local function bank(name)
      local root = "data/generated/gba/map_tree/tilesets/" .. name .. "/"
      local tiles, mids = cache:read(root .. "tiles.4bpp"), cache:read(root .. "metatiles.bin")
      local attrs, pal = cache:read(root .. "attributes.bin"), cache:read(root .. "palettes.bin")
      if
        not (
          type(tiles) == "string"
          and #tiles >= 32
          and #tiles <= 32768
          and #tiles % 32 == 0
          and type(mids) == "string"
          and #mids >= 16
          and #mids <= 16384
          and #mids % 16 == 0
          and type(attrs) == "string"
          and #attrs == #mids / 16 * f.attrBytes
          and type(pal) == "string"
          and #pal == 512
        )
      then
        return nil
      end
      local layers, palettes = {}, {}
      for i = 1, #attrs, f.attrBytes do
        local word = 0
        for b = 0, f.attrBytes - 1 do
          word = word + attrs:byte(i + b) * 256 ^ b
        end
        local layer = f.layerOf(word)
        if not int(layer, 0, 3) then
          return nil
        end
        layers[#layers + 1] = string.char(layer)
      end
      for pi = 0, 15 do
        palettes[pi + 1] = {}
        for c = 0, 15 do
          local i = pi * 32 + c * 2 + 1
          local word = pal:byte(i) + pal:byte(i + 1) * 256
          palettes[pi + 1][c + 1] = {
            math.floor(word % 32 * 255 / 31),
            math.floor(math.floor(word / 32) % 32 * 255 / 31),
            math.floor(math.floor(word / 1024) % 32 * 255 / 31),
          }
        end
      end
      return {
        tiles4bpp = tiles,
        metatileEntriesLE16 = mids,
        layerTypes = table.concat(layers),
        palettes = palettes,
      }
    end
    local a, b = bank(p.a), bank(p.b)
    if not a or not b then
      return nil, "tileset data unavailable"
    end
    return {
      version = 1,
      generation = 3,
      id = p.id,
      graphicsState = "base",
      tileSize = 8,
      cellSize = 16,
      coordinateBase = 0,
      paletteFormat = "rgb8-floor",
      primary = a,
      secondary = b,
      layout = {
        tilesInPrimary = f.numPrimaryTiles,
        metatilesInPrimary = f.numPrimaryMetatiles,
        palettesInPrimary = f.numPalsInPrimary,
        metatileLayers = 2,
      },
    }
  end
  return handle
end
return M
