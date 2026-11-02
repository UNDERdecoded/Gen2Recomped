-- Port of 3ds_port/scripts/dump_region_art.py: a tileset's metatiles as the
-- console's atlas composes them (layer 0 opaque, layer 1 keyed on colour
-- index 0, palettes split at 6 as the GBA does).
--
-- Lua shapes:
--   incbin_map(kind)  kind "Metatiles" | "MetatileAttributes" stands for the
--                     Python regex pattern; returns {["gTileset_X"] = path}
--                     (a fresh table, like Python's dict copy)
--   read_u16(path)    a SHARED 1-based array (Python returns a fresh list):
--                     read it, copy before changing it
--   load_graphics(name) -> tiles (string), palettes (1-based array of 16
--                     0-based arrays of packed rgb)
--   Tilesets(p, s):subtile(tile_id, palette_id) -> rgb, idx: two 0-based
--                     arrays of 64 (row major)
--   metatile_image(entries, ts) -> a 16x16 RGBA Image (entries 1-based)

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local Image = V.require("bake/Image")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local floor = math.floor
local sbyte = string.byte
local tree = S.tree

M.ROOT = ""
local NUM_PRIMARY = 512
local TILES_PER_TILESET = 512
M.NUM_PRIMARY, M.TILES_PER_TILESET = NUM_PRIMARY, TILES_PER_TILESET

local _INCBIN = {}
local _GRAPHICS = {}

local function _incbin_map(kind)
  local text = tree:must("src/data/tilesets/metatiles.h")
  local out = {}
  for n, p in text:gmatch("g" .. kind .. "_([%w_]+)%[%]%s*=%s*INCBIN_U16%(\"([^\"]+)\"%)") do
    out["gTileset_" .. n] = p
  end
  -- A tileset whose data goes by another name (gTileset_Building is drawn
  -- from gMetatiles_InsideBuilding): headers.h says which.
  local headers = tree:must("src/data/tilesets/headers.h")
  for name, body in headers:gmatch("const struct Tileset (gTileset_[%w_]+)%s*=%s*{(.-)};") do
    local m = body:match("%.metatiles%s*=%s*gMetatiles_([%w_]+)")
    if m and out[name] == nil and out["gTileset_" .. m] ~= nil then
      out[name] = out["gTileset_" .. m]
    end
  end
  return out
end

function M.incbin_map(kind)
  if _INCBIN[kind] == nil then _INCBIN[kind] = _incbin_map(kind) end
  local copy = {}
  for k, v in pairs(_INCBIN[kind]) do copy[k] = v end
  return copy
end

function M.read_u16(path)
  return tree:cached("u16:" .. path, function() return py.u16_list(tree:must(path)) end)
end

function M.tileset_dir(name)
  local snake = py.snake(name:sub(#"gTileset_" + 1))
  for _, kind in ipairs({ "primary", "secondary" }) do
    local path = "data/tilesets/" .. kind .. "/" .. snake
    if tree:isdir(path) then return path end
  end
  return nil
end

local MAGENTA = 0xFF00FF
local function magenta16()
  local p = {}
  for i = 0, 15 do p[i] = MAGENTA end
  return p
end

local function _load_graphics(name)
  local base = M.tileset_dir(name)
  if base == nil then return "", {} end
  local tiles = tree:read(base .. "/tiles.4bpp") or ""
  local palettes = {}
  for i = 0, 15 do
    local raw = tree:read(base .. ("/palettes/%02d.gbapal"):format(i))
    if raw == nil then
      palettes[i + 1] = magenta16()
    else
      local pal = {}
      for k = 0, 15 do
        local c = sbyte(raw, 2 * k + 1) + sbyte(raw, 2 * k + 2) * 256
        pal[k] = floor(band(c, 31) * 255 / 31) * 65536
               + floor(band(rshift(c, 5), 31) * 255 / 31) * 256
               + floor(band(rshift(c, 10), 31) * 255 / 31)
      end
      palettes[i + 1] = pal
    end
  end
  return tiles, palettes
end

-- tiles, palettes (shared: callers only read them)
function M.load_graphics(name)
  local g = _GRAPHICS[name]
  if g == nil then
    local t, p = _load_graphics(name)
    g = { t, p }
    _GRAPHICS[name] = g
  end
  return g[1], g[2]
end

-- ── Tilesets ─────────────────────────────────────────────────────────────
local Tilesets = {}
Tilesets.__index = Tilesets
M.TilesetsClass = Tilesets

function M.Tilesets(primary, secondary)
  local self = setmetatable({}, Tilesets)
  self.pt, self.pp = M.load_graphics(primary)
  self.st, self.sp = M.load_graphics(secondary)
  return self
end

local MAG64_RGB, MAG64_IDX = {}, {}
for i = 0, 63 do MAG64_RGB[i] = MAGENTA; MAG64_IDX[i] = 0 end

-- One 8x8 block: rgb, idx (0-based arrays of 64, row major).  An unreadable
-- tile is magenta with index 0 everywhere (the arrays are then shared).
function Tilesets:subtile(tile_id, palette_id)
  local tiles, palettes, loc
  if tile_id < TILES_PER_TILESET then
    tiles, palettes, loc = self.pt, self.pp, tile_id
  else
    tiles, palettes, loc = self.st, self.sp, tile_id - TILES_PER_TILESET
  end
  local base = loc * 32
  if base + 32 > #tiles then return MAG64_RGB, MAG64_IDX end
  -- Emerald's palette split: 0-5 primary, 6-12 secondary, whichever
  -- tileset the subtile came from
  palettes = palette_id < 6 and self.pp or self.sp
  local pal = palettes[palette_id + 1] or magenta16()
  local rgb, idx = {}, {}
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

-- 16x16 RGBA, layers composed the way voxel_atlas.c composes them
function M.metatile_image(entries, ts)
  local img = Image.new("RGBA", 16, 16, { 0, 0, 0, 0 })
  for layer = 0, 1 do
    for quad = 0, 3 do
      local entry = entries[layer * 4 + quad + 1]
      local tile_id = band(entry, 0x3FF)
      local flip_x = band(entry, 0x400) ~= 0
      local flip_y = band(entry, 0x800) ~= 0
      local palette_id = band(rshift(entry, 12), 0xF)
      local rgb, idx = ts:subtile(tile_id, palette_id)
      local ox, oy = (quad % 2) * 8, floor(quad / 2) * 8
      for y = 0, 7 do
        for x = 0, 7 do
          local sx = flip_x and 7 - x or x
          local sy = flip_y and 7 - y or y
          local k = sy * 8 + sx
          if not (layer ~= 0 and idx[k] == 0) then
            local c = rgb[k]
            img:put(ox + x, oy + y, floor(c / 65536), floor(c / 256) % 256, c % 256, 255)
          end
        end
      end
    end
  end
  return img
end

return M
