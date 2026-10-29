-- Adapted from Gen1Recomp 535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91.
-- Copyright (C) 2026 BOIS CLUB GAMES, LLC. GPLv3 with Section 7 terms;
-- see licenses/GEN1RECOMP-TOUCH-SKINS.md. Native integration by Roxas2712.
local SkinZip = {}

local bxor
do
  local ok, bit = pcall(require, "bit")
  if ok and bit and bit.bxor then
    bxor = function(a, b) return bit.bxor(a, b) % 0x100000000 end
  else
    local byteXor = {}
    local function xor8(a, b)
      local key = a * 256 + b
      local memo = byteXor[key]
      if memo then return memo end
      local r, bitv = 0, 1
      local x, y = a, b
      for _ = 1, 8 do
        if (x % 2) ~= (y % 2) then r = r + bitv end
        x, y, bitv = math.floor(x / 2), math.floor(y / 2), bitv * 2
      end
      byteXor[key] = r
      return r
    end
    bxor = function(a, b)
      local r, mul = 0, 1
      for _ = 1, 4 do
        r = r + xor8(a % 256, b % 256) * mul
        a, b, mul = math.floor(a / 256), math.floor(b / 256), mul * 256
      end
      return r
    end
  end
end

local crcTable
local function crc32(s)
  if not crcTable then
    crcTable = {}
    for i = 0, 255 do
      local c = i
      for _ = 1, 8 do
        if c % 2 == 1 then
          c = bxor(math.floor(c / 2), 0xEDB88320)
        else
          c = math.floor(c / 2)
        end
      end
      crcTable[i] = c
    end
  end
  local crc = 0xFFFFFFFF
  for i = 1, #s do
    crc = bxor(crcTable[bxor(crc, s:byte(i)) % 256], math.floor(crc / 256))
  end
  return bxor(crc, 0xFFFFFFFF) % 0x100000000
end

local function le16(n)
  n = math.floor(n) % 0x10000
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function le32(n)
  n = math.floor(n) % 0x100000000
  return string.char(n % 256, math.floor(n / 256) % 256,
                     math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

function SkinZip.encode(entries)
  local out, central, offset = {}, {}, 0
  for _, entry in ipairs(entries) do
    local name, data = entry.name, entry.data or ""
    local crc, size = crc32(data), #data
    local local_ = "PK\3\4" .. le16(20) .. le16(0) .. le16(0)
      .. le16(0) .. le16(0)
      .. le32(crc) .. le32(size) .. le32(size)
      .. le16(#name) .. le16(0) .. name
    out[#out + 1] = local_
    out[#out + 1] = data
    central[#central + 1] = "PK\1\2" .. le16(20) .. le16(20) .. le16(0) .. le16(0)
      .. le16(0) .. le16(0)
      .. le32(crc) .. le32(size) .. le32(size)
      .. le16(#name) .. le16(0) .. le16(0) .. le16(0) .. le16(0)
      .. le32(0) .. le32(offset) .. name
    offset = offset + #local_ + #data
  end
  local dir = table.concat(central)
  return table.concat(out) .. dir
    .. "PK\5\6" .. le16(0) .. le16(0) .. le16(#entries) .. le16(#entries)
    .. le32(#dir) .. le32(offset) .. le16(0)
end

return SkinZip
