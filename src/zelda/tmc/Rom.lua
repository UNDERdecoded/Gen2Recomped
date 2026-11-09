-- A Minish Cap cartridge reader on top of src/import/RomGba: bus-address
-- reads ($08xxxxxx), LZ77 straight to strings, and the small structure
-- readers the importer shares (MapDataDefinition lists, Transitions).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local RomGba = require("src.import.RomGba")
local Layout = require("src.zelda.tmc.Layout")

local Rom = {}
Rom.__index = Rom

local BASE = Layout.ROM_BASE

function Rom.new(data)
  local g = RomGba.new(data)
  return setmetatable({ g = g, data = data, size = #data }, Rom)
end

function Rom.open(path)
  local f = io.open(path, "rb")
  local data
  if f then
    data = f:read("*a")
    f:close()
  elseif love and love.filesystem then
    data = love.filesystem.read(path)
  end
  if not data then return nil, "could not read " .. tostring(path) end
  return Rom.new(data)
end

function Rom:valid(p)
  return type(p) == "number" and p >= BASE and p < BASE + self.size
end

function Rom:u8(p) return self.g:u8(p - BASE) end
function Rom:u16(p) return self.g:u16(p - BASE) end
function Rom:u32(p) return self.g:u32(p - BASE) end
function Rom:s8(p) return self.g:s8(p - BASE) end
function Rom:s16(p) return self.g:s16(p - BASE) end
function Rom:ptr(p)
  local v = self.g:u32(p - BASE)
  if self:valid(v) then return v end
  return nil
end

-- raw bytes [p, p+n) as a string, clamped to the cartridge
function Rom:str(p, n)
  local o = p - BASE
  if o < 0 or o >= self.size then return "" end
  return self.data:sub(o + 1, math.min(self.size, o + n))
end

local char, unpack_ = string.char, unpack or table.unpack
function Rom.bytesToString(t, n)
  n = n or #t
  local parts, k = {}, 0
  for i = 1, n, 4096 do
    k = k + 1
    parts[k] = char(unpack_(t, i, math.min(n, i + 4095)))
  end
  return table.concat(parts)
end

-- LZ77 (BIOS type $10) at bus address p -> string
function Rom:lz77(p)
  local out, err = self.g:lz77(p - BASE)
  if not out then return nil, err end
  return Rom.bytesToString(out)
end

-- A MapDataDefinition list (include/map.h): {src, dest, size} records,
-- src bit 31 = another record follows, size bit 31 = LZ77-compressed.
-- dest == 0 means "load palette group (src & 0xFFFF)".
function Rom:mapDefs(p, limit)
  local defs = {}
  limit = limit or 64
  while #defs < limit do
    local src = self:u32(p)
    local dest = self:u32(p + 4)
    local size = self:u32(p + 8)
    local more = band(src, 0x80000000) ~= 0
    local d = {
      src = band(src, 0x7FFFFFFF),
      dest = dest,
      size = band(size, 0x7FFFFFFF),
      compressed = band(size, 0x80000000) ~= 0,
    }
    if dest == 0 then d.paletteGroup = band(src, 0xFFFF) end
    defs[#defs + 1] = d
    p = p + 12
    if not more then break end
  end
  return defs
end

-- the bytes one MapDataDefinition loads
function Rom:mapDefData(def)
  local at = Layout.gMapData + def.src
  if def.compressed then return self:lz77(at) end
  return self:str(at, def.size)
end

-- Transition (include/transitions.h), 20 bytes
function Rom:transition(p)
  return {
    warpType = self:u16(p),
    startX = self:u16(p + 2), startY = self:u16(p + 4),
    endX = self:u16(p + 6), endY = self:u16(p + 8),
    shape = self:u8(p + 10), area = self:u8(p + 11), room = self:u8(p + 12),
    layer = self:u8(p + 13), kind = self:u8(p + 14), facing = self:u8(p + 15),
    sfx = self:u16(p + 16), unk2 = self:u8(p + 18), unk3 = self:u8(p + 19),
  }
end

-- EntityData (include/room.h), 16 bytes; kind $FF ends a list
function Rom:entityList(p, limit)
  local list = {}
  limit = limit or 128
  while #list < limit do
    local kind = self:u8(p)
    if kind == 0xFF then break end
    -- entity_raw (asm/macros/entity.inc): type | collision << 4, pool,
    -- subtype, paramA, paramB, x, y, paramC (an NPC's script pointer)
    list[#list + 1] = {
      kind = band(kind, 0x0F), collision = rshift(kind, 4),
      pool = self:u8(p + 1), id = self:u8(p + 2), paramA = self:u8(p + 3),
      paramB = self:u32(p + 4),
      x = self:u16(p + 8), y = self:u16(p + 10),
      paramC = self:u32(p + 12),
    }
    p = p + 16
  end
  return list
end

return Rom
