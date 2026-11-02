-- emerald3ds_builder/recipe.py: how to rebuild each input file from the ROM.
--
-- The release's recipe container is LZMA.  The mod ships, instead, the part
-- of it the voxel tree needs, converted once (scratch tools/convert_recipe.py)
-- to zlib'd JSON in lib/bake/recipes/<game code>.vtree: the `inputs`
-- entries and `vtree` (names, ROM offsets, sizes and CRCs).  None of the
-- inputs references the literal pool, so the shipped files hold no bytes of
-- any game file at all, only where to find them in the player's ROM.
--
-- Operations (as recipe.py):
--   {"C", rom_offset, length}   copy bytes from the ROM
--   {"F", byte, length}         repeat one byte
--   {"L", literal_offset, len}  bytes from the literal pool
--   {"Z", rom_offset}           GBA BIOS LZ77 (type 0x10) at rom_offset
--   {"R", rom_offset, src_stride, dst_stride, count, bitmap_index}
-- and "patches" {dst, literal_offset, length} written over the result.

local V = ...
local bit = require("bit")
local json = V.require("bake/json")
local band, bxor, rshift, bnot, bor, lshift = bit.band, bit.bxor, bit.rshift, bit.bnot, bit.bor, bit.lshift
local sbyte, schar, ssub = string.byte, string.char, string.sub
local concat = table.concat

local recipe = {}

-- ── CRC-32 (zlib.crc32) ──────────────────────────────────────────────────

local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if band(c, 1) ~= 0 then c = bxor(rshift(c, 1), 0xEDB88320) else c = rshift(c, 1) end
  end
  CRC[i] = c
end

function recipe.crc32(s, crc)
  local c = bnot(crc or 0)
  for i = 1, #s do
    c = bxor(CRC[band(bxor(c, sbyte(s, i)), 0xFF)], rshift(c, 8))
  end
  c = bnot(c)
  if c < 0 then c = c + 4294967296 end
  return c
end

-- ── GBA LZ77 ─────────────────────────────────────────────────────────────

function recipe.lz77_decompress(src, offset)
  local p = offset + 1
  if sbyte(src, p) ~= 0x10 then
    error(("RecipeError: no LZ77 header at %#x"):format(offset), 0)
  end
  local size = sbyte(src, p + 1) + sbyte(src, p + 2) * 256 + sbyte(src, p + 3) * 65536
  local out, n = {}, 0
  local pos = p + 4
  while n < size do
    local flags = sbyte(src, pos)
    pos = pos + 1
    for b = 0, 7 do
      if n >= size then break end
      if band(flags, rshift(0x80, b)) ~= 0 then
        local a, c = sbyte(src, pos, pos + 1)
        pos = pos + 2
        local length = rshift(a, 4) + 3
        local back = bor(lshift(band(a, 0xF), 8), c) + 1
        for _ = 1, length do
          n = n + 1
          out[n] = out[n - back]
        end
      else
        n = n + 1
        out[n] = sbyte(src, pos)
        pos = pos + 1
      end
    end
  end
  -- bytes(out[:size]); chars in chunks (unpack has a stack limit)
  local parts = {}
  for i = 1, size, 4096 do
    parts[#parts + 1] = schar(unpack(out, i, math.min(size, i + 4095)))
  end
  return concat(parts)
end

-- ── R: remapped records ──────────────────────────────────────────────────

local function apply_bitmap(src, srcpos, dst, bitmap)
  -- src: string, record at srcpos (1-based); dst: array of bytes (0-based)
  for i = 0, #bitmap - 1 do
    local s = bitmap[i + 1]
    local b
    if s == -1 then b = 0
    elseif s == -2 then b = 1
    else b = band(rshift(sbyte(src, srcpos + rshift(s, 3)) or 0, band(s, 7)), 1) end
    local k = rshift(i, 3)
    if b ~= 0 then dst[k] = bor(dst[k], lshift(1, band(i, 7)))
    else dst[k] = band(dst[k], bnot(lshift(1, band(i, 7)))) end
  end
end

function recipe.build_entry(entry, rom, literals, bitmaps)
  local parts = {}
  local path = entry.path
  for _, op in ipairs(entry.ops) do
    local kind = op[1]
    if kind == "C" then
      local off, length = op[2], op[3]
      if off < 0 or off + length > #rom then
        error(("RecipeError: %s: ROM range out of bounds"):format(path), 0)
      end
      parts[#parts + 1] = ssub(rom, off + 1, off + length)
    elseif kind == "F" then
      parts[#parts + 1] = string.rep(schar(op[2]), op[3])
    elseif kind == "L" then
      parts[#parts + 1] = ssub(literals, op[2] + 1, op[2] + op[3])
    elseif kind == "Z" then
      parts[#parts + 1] = recipe.lz77_decompress(rom, op[2])
    elseif kind == "R" then
      local off, src_stride, dst_stride, count, index = op[2], op[3], op[4], op[5], op[6]
      local bitmap = bitmaps[index + 1]
      for k = 0, count - 1 do
        local record = {}
        for j = 0, dst_stride - 1 do record[j] = 0 end
        apply_bitmap(rom, off + k * src_stride + 1, record, bitmap)
        local bytes = {}
        for j = 0, dst_stride - 1 do bytes[j + 1] = schar(record[j]) end
        parts[#parts + 1] = concat(bytes)
      end
    else
      error(("RecipeError: %s: unknown operation %s"):format(path, tostring(kind)), 0)
    end
  end
  local data = concat(parts)
  if entry.patches then
    for _, p in ipairs(entry.patches) do
      local dst, off, length = p[1], p[2], p[3]
      data = ssub(data, 1, dst) .. ssub(literals, off + 1, off + length) .. ssub(data, dst + length + 1)
    end
  end
  local crc = recipe.crc32(data)
  if #data ~= entry.size or crc ~= entry.crc then
    error(("RecipeError: %s does not match the expected result (size %d/%d, CRC %08x/%08x)")
      :format(path, #data, entry.size, crc, entry.crc), 0)
  end
  return data
end

-- ── the shipped .vtree files ─────────────────────────────────────────────

-- recipe.load(blob, inflate): blob is a lib/bake/recipes/*.vtree file,
-- inflate(bytes) -> bytes undoes zlib (love.data.decompress("string",
-- "zlib", s) in the game).  Returns {release, rom_sha1, code, inputs =
-- {{path, size, crc, ops, patches}}, bitmaps, literals, vtree}.
function recipe.load(blob, inflate)
  local doc = json.decode(inflate(blob))
  if doc.format ~= "e3ds-vtree-1" then
    error("RecipeError: not an Emerald 3DS voxel-tree recipe", 0)
  end
  local inputs = {}
  for i, e in ipairs(doc.inputs) do
    inputs[i] = { path = e[1], size = e[2], crc = e[3], ops = e[4], patches = e[5] }
  end
  return {
    release = doc.release, rom_sha1 = doc.rom_sha1, code = doc.code,
    inputs = inputs, bitmaps = doc.bitmaps, literals = "", vtree = doc.vtree,
  }
end

-- Which shipped recipe a ROM needs, by its game code (header 0xAC).
recipe.CODES = { BPEE = true, BPES = true, BPEF = true, BPEI = true }

function recipe.rom_code(rom)
  return ssub(rom, 0xAC + 1, 0xB0)
end

return recipe
