-- Versioned observations of loaded Gen3 terrain. No renderer, map loader,
-- filesystem or runtime cache is invoked by this module.
local RenderData = {}
local Handle = {}
Handle.__index = Handle

local function integer(n, low, high)
  return type(n) == "number" and n == math.floor(n) and n >= low and n <= high
end

local function identifier(s)
  return type(s) == "string" and #s > 0 and #s <= 160
end

local function overworld(game)
  if type(game) ~= "table" then
    return nil
  end
  local states = game and game.stack and game.stack.states
  for i = #(states or {}), 1, -1 do
    if states[i].isOverworld then
      return states[i]
    end
  end
  local ow = game and game.overworld
  return ow and ow.isOverworld and ow.map and ow or nil
end

local function dimensions(map)
  local def, ts = map and map.def, map and map.tileset
  if
    not (
      type(def) == "table"
      and type(ts) == "table"
      and ts.blockTiles == 2
      and ts.blockCells == 1
      and integer(def.width, 1, 1024)
      and integer(def.height, 1, 1024)
    )
  then
    return nil, "geometry unavailable"
  end
  return def.width, def.height
end

local function identity(record)
  local a = type(record) == "table" and record.address
  if not integer(a, 0, 0x09ffffff) then
    return nil
  end
  if a >= 0x08000000 then
    a = a - 0x08000000
  end
  if a > 0x01ffffff then
    return nil
  end
  return ("%07x"):format(a)
end

local function pair(game, map)
  local ts = map and map.tileset
  local store = game and game.data and game.data.map_tilesets
  if type(ts) ~= "table" or type(store) ~= "table" then
    return nil, "tileset unavailable"
  end
  local a, b = store[ts.primaryKey], store[ts.secondaryKey]
  local ai, bi = identity(a), identity(b)
  if not ai or not bi then
    return nil, "tileset unavailable"
  end
  return { id = "gba:" .. ai .. ":" .. bi, primary = a, secondary = b }
end

function RenderData.new(getGame, generation)
  local context = setmetatable({ getGame = getGame, generation = generation }, Handle)
  -- Keep the host resolver private: a public data handle must not itself
  -- become another route to mutable engine objects.
  return {
    supports = function(_, version)
      return context:supports(version)
    end,
    snapshot = function(_, ...)
      return context:snapshot(...)
    end,
    tileset = function(_, ...)
      return context:tileset(...)
    end,
  }
end

-- This reports contract/host support, not whether a map is currently resident.
function Handle:supports(version)
  return version == 1 and self.generation == 3
end

local function active(self, version, mapId)
  if version ~= 1 then
    return nil, "unsupported render data version"
  end
  if not self:supports(version) then
    return nil, "unsupported generation"
  end
  if not identifier(mapId) then
    return nil, "invalid map id"
  end
  local game = self.getGame()
  local ow = overworld(game)
  if not ow or not ow.map then
    return nil, "no overworld"
  end
  if ow.map.id ~= mapId then
    return nil, "active map changed"
  end
  return { game = game, world = ow, map = ow.map }
end

local function resident(ctx, mapId)
  if mapId == nil then
    mapId = ctx.map.id
  end
  if not identifier(mapId) then
    return nil, "invalid target map id"
  end
  if mapId == ctx.map.id then
    return ctx.map
  end
  local neighbors = ctx.world.neighbors or {}
  if #neighbors > 128 then
    return nil, "too many placements"
  end
  for _, n in ipairs(neighbors) do
    if n.map and n.map.id == mapId then
      return n.map
    end
  end
  return nil, "map not resident"
end

local function regionFor(region, w, h)
  if region == nil then
    region = { x = 0, y = 0, width = w, height = h }
  end
  if type(region) ~= "table" or getmetatable(region) ~= nil then
    return nil
  end
  for k in pairs(region) do
    if k ~= "x" and k ~= "y" and k ~= "width" and k ~= "height" then
      return nil
    end
  end
  local x, y, rw, rh = region.x, region.y, region.width, region.height
  if
    not (
      integer(x, 0, w - 1)
      and integer(y, 0, h - 1)
      and integer(rw, 1, w)
      and integer(rh, 1, h)
      and x + rw <= w
      and y + rh <= h
      and rw * rh <= 4096
    )
  then
    return nil
  end
  return { x = x, y = y, width = rw, height = rh }
end

local function blockAt(map, index)
  local patch = map.blockPatch and map.blockPatch[index]
  if patch ~= nil then
    return patch
  end
  local def = map.def
  -- The renderer may already have decoded this packed layout. Do not create
  -- that cache as a side effect, but honor it when it is authoritative.
  local blocks = def._blockArray or def.blocks
  if type(blocks) == "table" then
    return blocks[index]
  end
  if type(blocks) == "string" and index * 2 <= #blocks then
    return (blocks:byte(index * 2 - 1) + blocks:byte(index * 2) * 256) % 1024
  end
end

function Handle:snapshot(version, mapId, query)
  local ctx, err = active(self, version, mapId)
  if not ctx then
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
  local map, reason = resident(ctx, query.mapId)
  if not map then
    return nil, reason
  end
  local w, h = dimensions(map)
  if not w then
    return nil, h
  end
  local r = regionFor(query.region, w, h)
  if not r then
    return nil, "invalid region (maximum 4096 cells)"
  end
  local p, why = pair(ctx.game, map)
  if not p then
    return nil, why
  end
  local out = {
    version = 1,
    generation = 3,
    coordinateBase = 0,
    tileSize = 8,
    cellSize = 16,
    activeMapId = mapId,
    mapId = map.id,
    tilesetId = p.id,
    width = w,
    height = h,
    region = r,
    metatiles = {},
    placements = {},
  }
  for y = r.y, r.y + r.height - 1 do
    for x = r.x, r.x + r.width - 1 do
      local mid = blockAt(map, y * w + x + 1)
      if not integer(mid, 0, 1023) then
        return nil, "metatile unavailable"
      end
      out.metatiles[#out.metatiles + 1] = mid
    end
  end
  local seen = {}
  local function add(map, x, y, isActive)
    if
      not (map and identifier(map.id) and integer(x, -1048576, 1048576) and integer(y, -1048576, 1048576))
    then
      return nil
    end
    local mw, mh = dimensions(map)
    local mp = pair(ctx.game, map)
    if not mw or not mp then
      return nil
    end
    local key = #map.id .. ":" .. map.id .. ":" .. x .. ":" .. y
    if seen[key] then
      return true
    end
    if #out.placements >= 128 then
      return nil
    end
    seen[key] = true
    out.placements[#out.placements + 1] =
      { mapId = map.id, x = x, y = y, width = mw, height = mh, active = isActive, tilesetId = mp.id }
    return true
  end
  if not add(ctx.map, 0, 0, true) then
    return nil, "placement unavailable"
  end
  local neighbors = ctx.world.neighbors or {}
  if #neighbors > 128 then
    return nil, "too many placements"
  end
  for _, n in ipairs(neighbors) do
    if not add(n.map, n.cx or 0, n.cy or 0, false) then
      return nil, "placement unavailable"
    end
  end
  -- Active first; neighbors have a deterministic spatial order independent
  -- of the host's traversal order. Repeated map IDs at distinct offsets stay.
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

local function bank(record)
  if type(record) ~= "table" or type(record.palettes) ~= "table" then
    return nil
  end
  local tiles, mids, attrs = record.tiles, record.metatiles, record.attributes
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
      and #attrs == #mids / 8
    )
  then
    return nil
  end
  local layers = {}
  for i = 1, #attrs, 2 do
    local layer = math.floor((attrs:byte(i) + attrs:byte(i + 1) * 256) / 4096)
    if not integer(layer, 0, 3) then
      return nil
    end
    layers[#layers + 1] = string.char(layer)
  end
  local palettes = {}
  for p = 1, 16 do
    local src = record.palettes and record.palettes[p]
    if type(src) ~= "table" then
      return nil
    end
    palettes[p] = {}
    for c = 1, 16 do
      local rgb = src[c]
      if type(rgb) ~= "table" then
        return nil
      end
      palettes[p][c] = {}
      for channel = 1, 3 do
        if not integer(rgb[channel], 0, 255) then
          return nil
        end
        palettes[p][c][channel] = rgb[channel]
      end
    end
  end
  return {
    tiles4bpp = tiles,
    metatileEntriesLE16 = mids,
    layerTypes = table.concat(layers),
    palettes = palettes,
  }
end

function Handle:tileset(version, mapId, targetMapId)
  local ctx, err = active(self, version, mapId)
  if not ctx then
    return nil, err
  end
  local map, reason = resident(ctx, targetMapId)
  if not map then
    return nil, reason
  end
  local w, why = dimensions(map)
  if not w then
    return nil, why
  end
  local p, pairError = pair(ctx.game, map)
  if not p then
    return nil, pairError
  end
  local layout = ctx.game.data.constants and ctx.game.data.constants.gen3Layout
  if
    not (
      type(layout) == "table"
      and integer(layout.tilesInPrimary, 1, 1023)
      and integer(layout.metatilesInPrimary, 1, 1023)
      and integer(layout.palettesInPrimary, 1, 15)
      and layout.metatileLayers == 2
    )
  then
    return nil, "layout unavailable"
  end
  local a, b = bank(p.primary), bank(p.secondary)
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
    layout = {
      tilesInPrimary = layout.tilesInPrimary,
      metatilesInPrimary = layout.metatilesInPrimary,
      palettesInPrimary = layout.palettesInPrimary,
      metatileLayers = 2,
    },
    primary = a,
    secondary = b,
  }
end

return RenderData
