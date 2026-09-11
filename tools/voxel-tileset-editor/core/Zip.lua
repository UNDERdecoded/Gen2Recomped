-- A zip writer, method 0.
--
-- STORED, NOT DEFLATED, and that is not laziness.  A zip entry can be
-- raw-deflated, and LOVE's compressor emits ZLIB-wrapped deflate, which is
-- a different thing with a two-byte header a zip reader rejects.  Method 0
-- is a length, a CRC and the bytes; there is nothing in it to get subtly
-- wrong, and a profile pack is a few tens of kilobytes of text.
--
-- NO TIMESTAMPS EITHER.  Every date field is zero, so re-exporting an
-- unchanged authoring produces a byte-identical archive and a diff of two
-- packs is about their content rather than about when they were built.

local Zip = {}

-- CRC32, table-driven, with no bit library: LOVE runs LuaJIT (Lua 5.1) on
-- some platforms and 5.3 semantics on none of them.
local crcTable

-- The longhand xor the whole file leans on.
local function xor32(a, b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local ab, bb = a % 2, b % 2
    if ab ~= bb then r = r + bit end
    a = (a - ab) / 2
    b = (b - bb) / 2
    bit = bit * 2
  end
  return r
end

local function crcInit()
  crcTable = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c % 2 == 1 then
        c = xor32(3988292384, math.floor(c / 2))
      else
        c = math.floor(c / 2)
      end
    end
    crcTable[i] = c
  end
end

function Zip.crc32(s)
  if not crcTable then crcInit() end
  local crc = 4294967295
  for i = 1, #s do
    local idx = xor32(crc % 256, s:byte(i))
    crc = xor32(crcTable[idx], math.floor(crc / 256))
  end
  return xor32(crc, 4294967295)
end

local function u16(v)
  v = v % 65536
  return string.char(v % 256, math.floor(v / 256))
end

local function u32(v)
  v = v % 4294967296
  local b1 = v % 256; v = math.floor(v / 256)
  local b2 = v % 256; v = math.floor(v / 256)
  local b3 = v % 256; v = math.floor(v / 256)
  return string.char(b1, b2, b3, v % 256)
end

-- files: an ORDERED list of { name = "path/in/zip", data = "..." }.  Order
-- is preserved rather than sorted, because the central directory records
-- real offsets built in the same pass -- and because a caller that wants a
-- deterministic archive can sort its own list and see that it did.
function Zip.build(files)
  local out, central, offset = {}, {}, 0
  for _, f in ipairs(files) do
    local name, data = f.name, f.data or ""
    local crc = Zip.crc32(data)
    local local_ = "PK\3\4" .. u16(20) .. u16(0) .. u16(0)
        .. u16(0) .. u16(0)
        .. u32(crc) .. u32(#data) .. u32(#data)
        .. u16(#name) .. u16(0) .. name
    out[#out + 1] = local_
    out[#out + 1] = data
    central[#central + 1] = "PK\1\2" .. u16(20) .. u16(20) .. u16(0) .. u16(0)
        .. u16(0) .. u16(0)
        .. u32(crc) .. u32(#data) .. u32(#data)
        .. u16(#name) .. u16(0) .. u16(0) .. u16(0) .. u16(0)
        .. u32(0) .. u32(offset) .. name
    offset = offset + #local_ + #data
  end
  local dir = table.concat(central)
  return table.concat(out) .. dir .. "PK\5\6" .. u16(0) .. u16(0)
      .. u16(#files) .. u16(#files) .. u32(#dir) .. u32(offset) .. u16(0)
end

return Zip
