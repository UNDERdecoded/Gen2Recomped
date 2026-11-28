-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A NINTENDO DS CARTRIDGE IS A FILESYSTEM, NOT AN ADDRESS SPACE.
--
-- Every extractor in this project before this one takes a ROM and reads a
-- number out of it: `rom:u16(0x3DF884)` is a tileset header because the
-- cartridge is a flat array and the manifest says where things are.  A DS
-- cartridge does not work that way at all.  Platinum is 128 MB holding 340
-- FILES in 89 directories -- `/poketool/personal/pl_personal.narc`,
-- `/msgdata/pl_msg.narc`, `/fielddata/land_data/land_data.narc` -- reached
-- through a name table (FNT) and an allocation table (FAT) in the header.
-- So the first thing Gen 4 needs is not a manifest of addresses.  It is this:
-- open the cartridge, and hand back the bytes of a named file.
--
-- WHAT THIS DELIBERATELY IS NOT.  It does not decompress NARC archives, decode
-- NCLR/NCGR graphics or know one Pokemon fact.  Those are stages that stand on
-- top of it and each one is its own problem.  This is the floor: the header,
-- the two tables, and a path -> bytes lookup that is right.
--
-- MEASURED, NOT ASSUMED.  Every offset below was read out of the project's own
-- Platinum cartridge (sha1 0862ec35..., game code CPUE, Rev 1) and the walk
-- this file performs returns 340 files in 89 directories, which is what the
-- cartridge holds.
--
-- IT NEVER READS THE WHOLE CARTRIDGE INTO MEMORY.  128 MB as one Lua string is
-- a number this engine has to run alongside on a phone, and almost every stage
-- wants one file out of it.  So the handle stays open and ranges are read on
-- demand; a caller that wants a file gets that file's bytes and nothing else.

local NdsRom = {}
NdsRom.__index = NdsRom

-- Header fields, by offset.  Names are the ones GBATEK and pokeplatinum use,
-- because a reader with either open should not have to translate.
local H = {
  TITLE = 0x000, GAME_CODE = 0x00C, MAKER = 0x010, UNIT = 0x012,
  ROM_VERSION = 0x01E,
  ARM9_ROM = 0x020, ARM9_ENTRY = 0x024, ARM9_RAM = 0x028, ARM9_SIZE = 0x02C,
  ARM7_ROM = 0x030, ARM7_ENTRY = 0x034, ARM7_RAM = 0x038, ARM7_SIZE = 0x03C,
  FNT = 0x040, FNT_SIZE = 0x044,
  FAT = 0x048, FAT_SIZE = 0x04C,
  OVT9 = 0x050, OVT9_SIZE = 0x054,
  OVT7 = 0x058, OVT7_SIZE = 0x05C,
  USED_SIZE = 0x080, HEADER_SIZE = 0x084,
}

-- The smallest cartridge that can still be one: the header is 0x200 bytes and
-- the tables live past it.  Anything shorter is not a truncated DS ROM, it is
-- a different kind of file, and saying so beats a nil arithmetic error twenty
-- frames later.
local MIN_SIZE = 0x8000

local byte = string.byte

local function readAt(self, offset, count)
  if not (self.file and count and count > 0) then return nil end
  if offset < 0 or offset + count > self.size then return nil end
  local ok = self.file:seek("set", offset)
  if not ok then return nil end
  local data = self.file:read(count)
  if not data or #data < count then return nil end
  return data
end

function NdsRom:bytes(offset, count) return readAt(self, offset, count) end

function NdsRom:u8(offset)
  local s = readAt(self, offset, 1)
  return s and byte(s)
end

-- Little-endian, and built with arithmetic rather than the `bit` library:
-- this runs under LuaJIT in the game and under plain Lua in the test suite,
-- and only one of those has `bit` without a require.
function NdsRom:u16(offset)
  local s = readAt(self, offset, 2)
  if not s then return nil end
  local a, b = byte(s, 1, 2)
  return a + b * 256
end

function NdsRom:u32(offset)
  local s = readAt(self, offset, 4)
  if not s then return nil end
  local a, b, c, d = byte(s, 1, 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- ---------------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------------

-- `path` is a real filesystem path.  love.filesystem is deliberately not used:
-- the cartridge the player picks in the launcher lives wherever they keep it,
-- not inside the game's own mount, and the importer already hands absolute
-- paths to every other extractor.
function NdsRom.open(path)
  if type(path) ~= "string" or path == "" then
    return nil, "no ROM path given"
  end
  local file, err = io.open(path, "rb")
  if not file then return nil, err or ("could not open " .. path) end
  local size = file:seek("end") or 0
  if size < MIN_SIZE then
    file:close()
    return nil, ("%s is %d bytes -- too small to be a DS cartridge"):format(path, size)
  end

  local self = setmetatable({ path = path, file = file, size = size }, NdsRom)

  -- THE GAME CODE IS THE CHECK, not the file extension.  A .nds extension is
  -- a claim anybody can make by renaming; the four bytes at 0x0C are what the
  -- hardware reads.  Refusing here means a wrong file fails at `open` with a
  -- sentence, rather than at the FNT walk with a nil index.
  local code = readAt(self, H.GAME_CODE, 4)
  if not code or not code:match("^[%u%d][%u%d][%u%d][%u%d]$") then
    file:close()
    return nil, ("%s has no DS game code at 0x0C -- not a DS cartridge"):format(path)
  end

  -- ...and the two tables have to be inside the file, or the walk below reads
  -- past the end and answers nonsense confidently.
  local fnt, fntSize = self:u32(H.FNT), self:u32(H.FNT_SIZE)
  local fat, fatSize = self:u32(H.FAT), self:u32(H.FAT_SIZE)
  if not (fnt and fntSize and fat and fatSize)
     or fnt + fntSize > size or fat + fatSize > size
     or fntSize == 0 or fatSize == 0 then
    file:close()
    return nil, ("%s has a name or allocation table outside the file -- "
                 .. "truncated or not a DS cartridge"):format(path)
  end
  return self
end

function NdsRom:close()
  if self.file then self.file:close() end
  self.file = nil
end

function NdsRom:header()
  local title = readAt(self, H.TITLE, 12) or ""
  return {
    title = (title:gsub("%z.*$", "")),
    gameCode = readAt(self, H.GAME_CODE, 4),
    makerCode = readAt(self, H.MAKER, 2),
    unitCode = self:u8(H.UNIT),
    romVersion = self:u8(H.ROM_VERSION),
    arm9 = { rom = self:u32(H.ARM9_ROM), size = self:u32(H.ARM9_SIZE),
             ram = self:u32(H.ARM9_RAM), entry = self:u32(H.ARM9_ENTRY) },
    arm7 = { rom = self:u32(H.ARM7_ROM), size = self:u32(H.ARM7_SIZE),
             ram = self:u32(H.ARM7_RAM), entry = self:u32(H.ARM7_ENTRY) },
    fnt = { at = self:u32(H.FNT), size = self:u32(H.FNT_SIZE) },
    fat = { at = self:u32(H.FAT), size = self:u32(H.FAT_SIZE) },
    -- An overlay table entry is 32 bytes, so its length IS the overlay count.
    -- Platinum carries 122 on the ARM9 and none on the ARM7.
    overlays9 = math.floor((self:u32(H.OVT9_SIZE) or 0) / 32),
    overlays7 = math.floor((self:u32(H.OVT7_SIZE) or 0) / 32),
    usedSize = self:u32(H.USED_SIZE),
    headerSize = self:u32(H.HEADER_SIZE),
    fileSize = self.size,
  }
end

-- ---------------------------------------------------------------------------
-- The filesystem
-- ---------------------------------------------------------------------------

-- FAT entry `id`: eight bytes, start then end, both absolute.  The SIZE is the
-- difference -- there is no length field, and a reader that invents one by
-- assuming files are contiguous gets away with it until the one place they
-- are not.
function NdsRom:fileRange(id)
  local fat = self:u32(H.FAT)
  local n = math.floor((self:u32(H.FAT_SIZE) or 0) / 8)
  if not (fat and id and id >= 0 and id < n) then return nil end
  local from = self:u32(fat + id * 8)
  local to = self:u32(fat + id * 8 + 4)
  if not (from and to) or to < from then return nil end
  return from, to - from
end

-- Walk the name table once and cache it.  The FNT is a directory table whose
-- entry 0 covers the root, followed by one subtable per directory; each
-- subtable is a run of length-prefixed names ending in a zero byte, where a
-- top bit set on the length marks a SUBDIRECTORY and appends its id.
--
-- Recursion is by directory id, not by walking forward through the file: the
-- subtables are not stored in tree order and a linear reader builds a
-- plausible tree with the wrong parents.
local ROOT = 0xF000

function NdsRom:index()
  if self._index then return self._index end
  local fnt = self:u32(H.FNT)
  local files, byPath, dirs = {}, {}, 0

  local seen = {}
  local function walk(dirId, path)
    -- A malformed table can point a directory at itself or at an ancestor,
    -- and the walk would then never end.  Costs one table; buys termination.
    if seen[dirId] then return end
    seen[dirId] = true
    dirs = dirs + 1

    local entry = fnt + (dirId % 0x1000) * 8
    local at = fnt + (self:u32(entry) or 0)
    local fileId = self:u16(entry + 4)
    if not fileId then return end

    while true do
      local t = self:u8(at)
      if not t or t == 0 then break end
      at = at + 1
      local len = t % 128
      local name = readAt(self, at, len)
      if not name then break end
      at = at + len
      if t >= 128 then
        local sub = self:u16(at)
        at = at + 2
        if sub then walk(sub, path .. "/" .. name) end
      else
        local from, size = self:fileRange(fileId)
        local full = path .. "/" .. name
        local record = { path = full, id = fileId, offset = from, size = size }
        files[#files + 1] = record
        byPath[full] = record
        fileId = fileId + 1
      end
    end
  end

  walk(ROOT, "")
  -- A LOCALIZED BUILD THAT MOVED ITS LANGUAGE ARCHIVES: German Platinum keeps
  -- /graphic/box.narc as /resource/ger/box/box.narc, and so on for 32 files
  -- (src/import/Gen4Regions.lua).  The US path is made to name the moved file
  -- so every reader keeps asking for the path it was written against.  Only
  -- paths the cartridge does NOT have are aliased; `files` stays the real list.
  local okR, Regions = pcall(require, "src.import.Gen4Regions")
  local aliases = okR and Regions.pathAliases(readAt(self, H.GAME_CODE, 4))
  for usPath, here in pairs(aliases or {}) do
    if not byPath[usPath] and byPath[here] then byPath[usPath] = byPath[here] end
  end
  self._index = { files = files, byPath = byPath, dirCount = dirs }
  return self._index
end

function NdsRom:list()
  return self:index().files
end

function NdsRom:stat(path)
  return self:index().byPath[path]
end

-- The bytes of one named file.  nil plus a reason rather than nil alone: a
-- missing path and a path whose FAT entry is broken are different problems and
-- the caller's log should be able to say which.
function NdsRom:read(path)
  local record = self:stat(path)
  if not record then return nil, ("no such file in the cartridge: %s"):format(tostring(path)) end
  if not (record.offset and record.size) then
    return nil, ("%s has no allocation entry"):format(path)
  end
  local data = readAt(self, record.offset, record.size)
  if not data then
    return nil, ("%s runs past the end of the cartridge"):format(path)
  end
  return data
end

function NdsRom:readId(id)
  local from, size = self:fileRange(id)
  if not from then return nil, ("no FAT entry %s"):format(tostring(id)) end
  return readAt(self, from, size)
end

-- The ARM9 binary, which is where the tables that are NOT in the filesystem
-- live -- and in Gen 4 that is a great many of them.
--
-- DECOMPRESSED WHEN IT IS STORED PACKED (HeartGold and SoulSilver; see
-- NdsBlz), once per open ROM, so every reader sees the binary the game runs.
function NdsRom:arm9()
  if self._arm9 then return self._arm9 end
  local raw = readAt(self, self:u32(H.ARM9_ROM) or 0, self:u32(H.ARM9_SIZE) or 0)
  local ok, Blz = pcall(require, "src.import.NdsBlz")
  if ok and raw then raw = Blz.arm9(raw, self:u32(H.ARM9_RAM) or 0x02000000) end
  self._arm9 = raw
  return raw
end

-- One ARM9 overlay's bytes, by overlay id.  The overlay table entry is 32
-- bytes: id, ram address, size, bss, static init start/end, FILE ID, flags --
-- and it is the file id at +0x18 that says where the bytes are, not the
-- overlay id.  Reading the two as the same number is the obvious mistake and
-- it silently returns another overlay's code.
function NdsRom:overlay(index)
  local at = self:u32(H.OVT9)
  local n = math.floor((self:u32(H.OVT9_SIZE) or 0) / 32)
  if not (at and index and index >= 0 and index < n) then return nil end
  local fileId = self:u32(at + index * 32 + 0x18)
  if not fileId then return nil end
  -- COMPRESSED WHEN THE ENTRY SAYS SO: bit 24 of the flags word at +0x1C is
  -- the SDK's "this overlay is BLZ-packed" (its low 24 bits the packed size).
  -- 127 of HeartGold's 129 overlays carry it and none of Platinum's 122, so a
  -- reader scanning for a table in Platinum sees exactly what it always did.
  local flags = self:u32(at + index * 32 + 0x1C) or 0
  local bytes = self:readId(fileId)
  if bytes and math.floor(flags / 16777216) % 2 == 1 then
    local unpacked = require("src.import.NdsBlz").decompress(bytes)
    if unpacked then bytes = unpacked end
  end
  return bytes, {
    ram = self:u32(at + index * 32 + 0x04),
    size = self:u32(at + index * 32 + 0x08),
    fileId = fileId,
  }
end

return NdsRom
