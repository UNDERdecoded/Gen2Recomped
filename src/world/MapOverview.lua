-- Generation-neutral terrain grid; optional GB tile luminance. All cells are
-- zero based. The scratch Map shares read-only data, but never the cold block
-- decoder's mutable definition or streamed renderer.
local Map = require("src.world.Map")
local Assets = require("src.render.Assets")
local Overview = {}
local shades = {}
Assets.register(function()
  shades = {}
end)

local function digit(sum, count)
  return tostring(math.max(0, math.min(3, math.floor((1 - sum / count) * 3 + 0.5))))
end

local function visual(map)
  local ts = map.tileset
  -- GBA metatiles are composed/paletted by their renderer; their opaque tileAt
  -- identifiers do not index a GB atlas. DS maps do not have one either.
  if
    map.blockCells ~= 2
    or not ts.blocks
    or type(ts.image) ~= "string"
    or type(ts.tilesPerRow) ~= "number"
    or ts.tilesPerRow < 1
    or ts.tilesPerRow >= math.huge
    or ts.tilesPerRow ~= math.floor(ts.tilesPerRow)
  then
    return nil
  end
  local path = Assets.resolve(ts.image)
  local cache = shades[path]
  if not cache then
    if not (love and love.image and love.image.newImageData) then
      return nil
    end
    local ok, pixels = pcall(love.image.newImageData, path)
    if not ok or not pixels then
      return nil
    end
    cache = { pixels = pixels, tiles = {} }
    shades[path] = cache
  end
  local rows, details, pixels = {}, {}, cache.pixels
  local width, height = pixels:getDimensions()
  for y = 0, map.heightCells * 2 - 1 do
    local row, top, bottom = {}, {}, {}
    for x = 0, map.widthCells * 2 - 1 do
      local tile = map:tileAt(x, y)
      if type(tile) ~= "number" or tile < 0 or tile ~= math.floor(tile) then
        return nil
      end
      local ox, oy = tile % ts.tilesPerRow * 8, math.floor(tile / ts.tilesPerRow) * 8
      if ox + 8 > width or oy + 8 > height then
        return nil
      end
      local key = ts.tilesPerRow .. ":" .. tile
      local s = cache.tiles[key]
      if not s then
        local sums = { 0, 0, 0, 0 }
        for py = 0, 7 do
          for px = 0, 7 do
            local r, g, b = pixels:getPixel(ox + px, oy + py)
            local q = math.floor(py / 4) * 2 + math.floor(px / 4) + 1
            sums[q] = sums[q] + r * 0.2126 + g * 0.7152 + b * 0.0722
          end
        end
        s = {
          digit(sums[1] + sums[2] + sums[3] + sums[4], 64),
          digit(sums[1], 16),
          digit(sums[2], 16),
          digit(sums[3], 16),
          digit(sums[4], 16),
        }
        cache.tiles[key] = s
      end
      row[#row + 1], top[#top + 1], bottom[#bottom + 1] = s[1], s[2] .. s[3], s[4] .. s[5]
    end
    rows[#rows + 1] = table.concat(row)
    details[#details + 1], details[#details + 2] = table.concat(top), table.concat(bottom)
  end
  return rows, details
end

local function integer(n)
  return type(n) == "number" and n >= 0 and n < math.huge and n == math.floor(n)
end

function Overview.build(game, ow)
  local map = ow.map
  local w, h = map.widthCells, map.heightCells
  if not integer(w) or not integer(h) or w == 0 or h == 0 then
    return nil, "invalid map dimensions"
  end
  -- Outdoor DS terrain lives in lazily streamed renderer chunks. Walking that
  -- renderer from a query can load/cache chunks. Interior permission grids are
  -- already resident and can use the same pure Map classifiers below.
  if map.def.generation == 4 and not map.def.behaviorCells then
    return nil, "map overview unavailable for streamed terrain"
  end
  local scratch, def = {}, {}
  for k, v in pairs(map) do
    scratch[k] = v
  end
  for k, v in pairs(map.def) do
    def[k] = v
  end
  scratch.def, scratch.renderer = def, nil
  setmetatable(scratch, Map)
  -- blockArray() writes only into the private definition on a cold GBA map.
  -- It may reuse the warm immutable array, and honors the live block patches.
  local rows, markers = {}, {}
  local function marker(kind, x, y)
    if integer(x) and integer(y) and x < w and y < h then
      markers[#markers + 1] = { kind = kind, x = x, y = y }
    end
  end
  for _, warp in ipairs(def.warps or {}) do
    marker("warp", warp.x, warp.y)
  end
  -- The active object list is the result of native flag, session, time and
  -- scripted spawn filters. Re-running those filters can consult another Game
  -- singleton or initialize sprite state. Use the objects actually present.
  for _, npc in ipairs(ow.npcs or {}) do
    local obj = npc.def or {}
    if obj.item and obj.item ~= 0 and obj.item ~= "0" and not npc.hidden and not obj.fruitTree then
      marker("item", npc.cellX, npc.cellY)
    end
  end
  local save = game.save or {}
  local hidden = game.data and game.data.field and game.data.field.hiddenItems
  for _, item in ipairs(hidden and hidden[map.id] or {}) do
    if not (save.hiddenTaken and save.hiddenTaken[map.id .. "_" .. item.x .. "_" .. item.y]) then
      marker("hidden", item.x, item.y)
    end
  end
  -- Gen2/3 imports also carry hidden-item sign events, with their own taken
  -- key and event flag (e.g. Cerulean Gym's Machine Part).
  for _, item in ipairs(def.signs or {}) do
    if
      item.item
      and item.item ~= 0
      and item.item ~= "0"
      and not (item.eventFlag and save.flags and save.flags[item.eventFlag] == true)
      and not (save.hiddenTaken and save.hiddenTaken[map.id .. "_sign_" .. item.x .. "_" .. item.y])
    then
      marker("hidden", item.x, item.y)
    end
  end
  for y = 0, h - 1 do
    local row = {}
    for x = 0, w - 1 do
      row[#row + 1] = scratch:isWarpTileCell(x, y) and "+"
        or scratch:isWaterCell(x, y) and "~"
        or scratch:isWalkableCell(x, y) and "."
        or " "
    end
    rows[#rows + 1] = table.concat(row)
  end
  local tiles, details = visual(scratch)
  return {
    mapId = map.id,
    width = w,
    height = h,
    rows = rows,
    markers = markers,
    tileRows = tiles,
    tileWidth = tiles and w * 2,
    tileHeight = tiles and h * 2,
    tileDetailRows = details,
    tileDetailWidth = details and w * 4,
    tileDetailHeight = details and h * 4,
  }
end

return Overview
