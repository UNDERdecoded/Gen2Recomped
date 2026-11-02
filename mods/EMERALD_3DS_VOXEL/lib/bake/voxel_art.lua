-- Port of 3ds_port/scripts/voxel_art.py: tileset art as pixels.
--
-- Reads the decomp-layout files (tiles.4bpp, palettes/*.gbapal,
-- metatiles.bin) and answers what a metatile's lower and upper layers draw,
-- pixel by pixel.
--
-- Lua shapes (see ARCHITECTURE.md):
--   * a pixel position (x, y) of a cell is p = y*16 + x (0..255)
--   * an rgb triple is packed r*65536 + g*256 + b
--   * layer_pixels(m, layer) -> {[p] = rgb}: the SAME cached table on every
--     call (Python returns a fresh dict): read it, or M.copy() it before
--     changing it.  len() is M.count(px); `if px:` is next(px) ~= nil;
--     `a == b` is M.same(a, b).

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local floor = math.floor
local sbyte = string.byte
local tree = S.tree

local CELL = 16
local TILES_PER_TILESET = 512
M.CELL, M.TILES_PER_TILESET = CELL, TILES_PER_TILESET

-- {"gTileset_" .. n: path} for every INCBIN line naming kind ("Metatiles" or
-- "MetatileAttributes")
local function _incbin(kind)
  local text = tree:must("src/data/tilesets/metatiles.h")
  local out = {}
  for n, p in text:gmatch("g" .. kind .. "_([%w_]+)%[%]%s*=%s*INCBIN_U16%(\"([^\"]+)\"%)") do
    out["gTileset_" .. n] = p
  end
  return out
end
M._incbin = _incbin

M.METATILES = _incbin("Metatiles")
M.ATTRIBUTES = _incbin("MetatileAttributes")

function M.read_u16(path)
  return tree:cached("u16:" .. path, function() return py.u16_list(tree:must(path)) end)
end

function M.tileset_dir(symbol)
  local snake = py.snake(symbol:sub(#"gTileset_" + 1))
  for _, kind in ipairs({ "primary", "secondary" }) do
    local path = "data/tilesets/" .. kind .. "/" .. snake
    if tree:isdir(path) then return path end
  end
  return nil
end

-- One tileset's 4bpp tiles and sixteen palettes (16 packed rgbs, 0-based,
-- or false where the file is missing)
local function Graphics(symbol)
  local self = { tiles = "", palettes = {} }
  local base = M.tileset_dir(symbol)
  if base == nil then return self end
  self.tiles = tree:read(base .. "/tiles.4bpp") or ""
  for i = 0, 15 do
    local raw = tree:read(base .. ("/palettes/%02d.gbapal"):format(i))
    if raw == nil then
      self.palettes[i + 1] = false
    else
      local pal = {}
      for k = 0, 15 do
        local c = sbyte(raw, 2 * k + 1) + sbyte(raw, 2 * k + 2) * 256
        local r = floor(band(c, 31) * 255 / 31)
        local g = floor(band(rshift(c, 5), 31) * 255 / 31)
        local b = floor(band(rshift(c, 10), 31) * 255 / 31)
        pal[k] = r * 65536 + g * 256 + b
      end
      self.palettes[i + 1] = pal
    end
  end
  return self
end

local _GRAPHICS = {}
function M.graphics(symbol)
  local g = _GRAPHICS[symbol]
  if not g then g = Graphics(symbol); _GRAPHICS[symbol] = g end
  return g
end

-- ── Pair ─────────────────────────────────────────────────────────────────
local Pair = {}
Pair.__index = Pair
M.PairClass = Pair

function M.Pair(primary, secondary)
  local self = setmetatable({}, Pair)
  self.gfx = { M.graphics(primary), M.graphics(secondary) }
  self.meta = { M.METATILES[primary] and M.read_u16(M.METATILES[primary]) or {},
                M.METATILES[secondary] and M.read_u16(M.METATILES[secondary]) or {} }
  self.attr = { M.ATTRIBUTES[primary] and M.read_u16(M.ATTRIBUTES[primary]) or {},
                M.ATTRIBUTES[secondary] and M.read_u16(M.ATTRIBUTES[secondary]) or {} }
  self._layers = {}
  return self
end

-- the metatile's 8 entries as a 1-based array, or nil
function Pair:entries(metatile)
  local which = metatile < TILES_PER_TILESET and 0 or 1
  local index = metatile - which * TILES_PER_TILESET
  local tbl = self.meta[which + 1]
  if (index + 1) * 8 > #tbl then return nil end
  local out = {}
  for i = 1, 8 do out[i] = tbl[index * 8 + i] end
  return out
end

function Pair:attribute(metatile)
  local which = metatile < TILES_PER_TILESET and 0 or 1
  local index = metatile - which * TILES_PER_TILESET
  local tbl = self.attr[which + 1]
  return tbl[index + 1] or 0
end

-- 8x8 as two 0-based arrays (packed rgb, colour index), row major, or nil
-- where unreadable.  Tiles split at 512, palettes at 6 (voxel_atlas.c).
function Pair:subtile(tile_id, palette_id)
  local which = tile_id < TILES_PER_TILESET and 0 or 1
  local loc = tile_id - which * TILES_PER_TILESET
  local gfx = self.gfx[which + 1]
  local base = loc * 32
  if base + 32 > #gfx.tiles then return nil end
  local palettes = self.gfx[palette_id < 6 and 1 or 2].palettes
  local pal = palettes[palette_id + 1]
  if not pal then return nil end
  local rgb, idx = {}, {}
  local tiles = gfx.tiles
  for y = 0, 7 do
    for x = 0, 7 do
      local packed = sbyte(tiles, base + y * 4 + floor(x / 2) + 1)
      local i = (x % 2 == 1) and rshift(packed, 4) or band(packed, 0xF)
      rgb[y * 8 + x] = pal[i]
      idx[y * 8 + x] = i
    end
  end
  return rgb, idx
end

-- Drawn pixels of one layer: {[y*16+x] = rgb}.  Index 0 is not drawn, on
-- BOTH layers.  Cached and shared: do not modify (M.copy).
function Pair:layer_pixels(metatile, layer)
  local key = metatile * 2 + layer
  local hit = self._layers[key]
  if hit == nil then
    hit = self:_layer_pixels(metatile, layer)
    self._layers[key] = hit
  end
  return hit
end

function Pair:_layer_pixels(metatile, layer)
  local entries = self:entries(metatile)
  local out = {}
  if entries == nil then return out end
  for quad = 0, 3 do
    local entry = entries[layer * 4 + quad + 1]
    local rgb, idx = self:subtile(band(entry, 0x3FF), band(rshift(entry, 12), 0xF))
    if rgb ~= nil then
      local flip_x, flip_y = band(entry, 0x400) ~= 0, band(entry, 0x800) ~= 0
      local ox, oy = (quad % 2) * 8, floor(quad / 2) * 8
      for y = 0, 7 do
        for x = 0, 7 do
          local sx = flip_x and 7 - x or x
          local sy = flip_y and 7 - y or y
          local k = sy * 8 + sx
          if idx[k] ~= 0 then
            out[(oy + y) * 16 + ox + x] = rgb[k]
          end
        end
      end
    end
  end
  return out
end

-- ── helpers for the {[p] = rgb} dicts ────────────────────────────────────
function M.count(px)
  local n = 0
  for _ in pairs(px) do n = n + 1 end
  return n
end

function M.copy(px)
  local out = {}
  for k, v in pairs(px) do out[k] = v end
  return out
end

-- dict == dict
function M.same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- frozenset(px.items()) as a string key (equal sets <=> equal keys)
function M.frozen(px)
  local parts = {}
  for p = 0, 255 do
    local v = px[p]
    if v ~= nil then parts[#parts + 1] = p .. ":" .. v end
  end
  return table.concat(parts, ",")
end

return M
