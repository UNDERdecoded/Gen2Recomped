-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Game Boy Advance cartridge reader.
--
-- src/import/Rom.lua cannot be made to do this, and it should not be asked to.
-- A Game Boy ROM is BANKED -- every accessor there is `(bank, address)` and
-- Rom.offset ASSERTS the address is $0000-$3FFF or $4000-$7FFF -- and its
-- pixels are 2 bits deep against four fixed greys.  A GBA cartridge is none of
-- those things:
--
--   * flat, addressed from $08000000, up to 32 MiB, no banks at all;
--   * pointers are four-byte words holding $08xxxxxx, and tables are reached
--     THROUGH them rather than by a symbol per entry -- so a 32-bit read is
--     the single most-used primitive, and Rom.lua has none;
--   * graphics are 4 bits per pixel against a sixteen-colour palette of
--     15-bit BGR, not 2bpp greys, so nothing in ImageWriter applies either;
--   * and almost every asset is behind the BIOS LZ77 codec.
--
-- Everything here is that gap and nothing else: no cartridge knowledge, no
-- table addresses.  Those live in the manifest, exactly as they do for Gen 2.

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local RomGba = {}
RomGba.__index = RomGba

-- Where the cartridge is mapped in the GBA's address space.  A pointer word
-- that does not start here is not a pointer -- which is the test every
-- structural search in tools/gen3_discover.py leans on.
RomGba.BASE = 0x08000000

function RomGba.new(data)
  assert(type(data) == "string", "RomGba.new wants the raw cartridge bytes")
  return setmetatable({ data = data, size = #data }, RomGba)
end

-- Reads are 0-based FLAT offsets, the way the file itself is laid out.  An
-- out-of-range read is an error rather than a zero: a bad pointer that reads
-- as zeros produces a plausible-looking empty table instead of a stack trace,
-- and that is the failure mode that costs a day.
function RomGba:u8(off)
  local b = self.data:byte(off + 1)
  if not b then error(("GBA read past the end of the ROM: %08X"):format(off)) end
  return b
end

function RomGba:u16(off)
  return self:u8(off) + self:u8(off + 1) * 256
end

function RomGba:u32(off)
  -- built as a float, not with lshift: bit.lshift is 32-bit SIGNED in LuaJIT,
  -- so a pointer with bit 31 set would come back negative
  return self:u8(off) + self:u8(off + 1) * 256
       + self:u8(off + 2) * 65536 + self:u8(off + 3) * 16777216
end

function RomGba:s8(off)
  local v = self:u8(off)
  return v >= 128 and v - 256 or v
end

-- Map events and connections are the only places signed 16- and 32-bit
-- fields appear, and both matter: a connection offset is routinely negative
-- and an object event on a map's left edge sits at a negative x.
function RomGba:s16(off)
  local v = self:u16(off)
  return v >= 32768 and v - 65536 or v
end

function RomGba:s32(off)
  local v = self:u32(off)
  return v >= 2147483648 and v - 4294967296 or v
end

-- A pointer word -> the flat offset it names, or nil when the word is not a
-- cartridge pointer at all.  Every table walk goes through this.
function RomGba:pointer(off)
  local v = self:u32(off)
  if v < RomGba.BASE or v >= RomGba.BASE + self.size then return nil end
  return v - RomGba.BASE
end

function RomGba:bytes(off, length)
  local out = {}
  for i = 0, length - 1 do out[i + 1] = self:u8(off + i) end
  return out
end

function RomGba:sub(off, length)
  return self.data:sub(off + 1, off + length)
end

-- ---------------------------------------------------------------------------
-- LZ77, BIOS compression type $10.  Behind it sits every mon sprite, every
-- palette, most tilemaps and the title-screen art.
--
-- Header word: low byte $10, high 24 bits the DECOMPRESSED size.  Then groups
-- of eight units, each group led by a flag byte read MSB first: a clear bit is
-- one literal byte; a set bit is two bytes -- length = (first >> 4) + 3 and
-- displacement = ((first & $F) << 8 | second) + 1 -- copied from what has
-- already been emitted.
--
-- THE BACK-REFERENCE MAY OVERLAP THE WRITE HEAD.  displacement 1 with length
-- 18 means "repeat the last byte eighteen times", which is how the codec
-- encodes a run, so the copy has to be byte-at-a-time.  A block copy reads
-- eighteen bytes that are not there yet and every long flat area of every
-- sprite comes out as garbage.
-- ---------------------------------------------------------------------------
function RomGba:lz77(off)
  local head = self:u32(off)
  if band(head, 0xFF) ~= 0x10 then
    return nil, ("not LZ77 at %08X (header %08X)"):format(off, head)
  end
  local size = math.floor(head / 256)
  local out, n = {}, 0
  local pc = off + 4
  while n < size do
    local flags = self:u8(pc)
    pc = pc + 1
    for b = 0, 7 do
      if n >= size then break end
      if band(flags, rshift(0x80, b)) ~= 0 then
        local b0, b1 = self:u8(pc), self:u8(pc + 1)
        pc = pc + 2
        local length = rshift(b0, 4) + 3
        local disp = bor(lshift(band(b0, 0x0F), 8), b1) + 1
        if disp > n then
          return nil, ("LZ77 back-reference before the start at %08X"):format(off)
        end
        for _ = 1, length do
          n = n + 1
          out[n] = out[n - disp]
        end
      else
        n = n + 1
        out[n] = self:u8(pc)
        pc = pc + 1
      end
    end
  end
  -- the last group may overshoot; the header size is authoritative
  for i = size + 1, n do out[i] = nil end
  return out, pc - off
end

-- ---------------------------------------------------------------------------
-- Colour.  The GBA stores fifteen bits as BGR -- blue in the HIGH bits, red in
-- the low -- five bits each.  Scaling is * 255 / 31, not << 3: shifting leaves
-- white at $F8F8F8 and every palette imperceptibly dark, which shows up as a
-- seam wherever a sprite sits on a background the engine drew itself.
-- ---------------------------------------------------------------------------
function RomGba.bgr555(word)
  return math.floor(band(word, 31) * 255 / 31),
         math.floor(band(rshift(word, 5), 31) * 255 / 31),
         math.floor(band(rshift(word, 10), 31) * 255 / 31)
end

-- 32 raw bytes -> sixteen {r,g,b} triples, 0-255.
function RomGba.palette(raw)
  local out = {}
  for i = 1, math.min(16, math.floor(#raw / 2)) do
    local lo, hi = raw[i * 2 - 1], raw[i * 2]
    local r, g, b = RomGba.bgr555(lo + hi * 256)
    out[i] = { r, g, b }
  end
  return out
end

-- ---------------------------------------------------------------------------
-- 4bpp tiles -> a row-major grid of palette INDEXES (0-15), 1-based [y][x].
--
-- 32 bytes per 8x8 tile, tiles in reading order.  Within a byte the LOW nibble
-- is the LEFT pixel -- the opposite of how the byte reads written out -- and
-- getting that backwards mirrors every two-pixel pair, which does not look
-- like a bug so much as a slightly wrong sprite.
-- ---------------------------------------------------------------------------
function RomGba.tiles4bpp(raw, cols, rows)
  local w, h = cols * 8, rows * 8
  local px = {}
  for y = 1, h do
    local line = {}
    for x = 1, w do line[x] = 0 end
    px[y] = line
  end
  for t = 0, cols * rows - 1 do
    local tx, ty = (t % cols) * 8, math.floor(t / cols) * 8
    for i = 0, 31 do
      local b = raw[t * 32 + i + 1]
      if not b then return px end
      local y, x = math.floor(i / 4), (i % 4) * 2
      px[ty + y + 1][tx + x + 1] = band(b, 0x0F)
      px[ty + y + 1][tx + x + 2] = rshift(b, 4)
    end
  end
  return px
end

-- 8bpp tiles, for the few 256-colour assets (the title screen among them).
function RomGba.tiles8bpp(raw, cols, rows)
  local w, h = cols * 8, rows * 8
  local px = {}
  for y = 1, h do
    local line = {}
    for x = 1, w do line[x] = 0 end
    px[y] = line
  end
  for t = 0, cols * rows - 1 do
    local tx, ty = (t % cols) * 8, math.floor(t / cols) * 8
    for i = 0, 63 do
      local b = raw[t * 64 + i + 1]
      if not b then return px end
      px[ty + math.floor(i / 8) + 1][tx + (i % 8) + 1] = b
    end
  end
  return px
end

return RomGba
