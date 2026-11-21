-- A ROM cache in ONE FILE: a store-only ZIP archive the import writes instead
-- of 18,000 loose files, and that the game reads back through PhysFS.
--
-- WHY A CONSOLE NEEDS THIS.  On a PS5 (native title, /data) every file
-- creation costs ~11 ms for the first few thousand and then stalls 0.5-0.9 s
-- about once a second in the kernel's buffer cache (`getblk`).  A Platinum
-- import is 18,433 files: 44 minutes on the console against 27 s on a PC.
-- The same 18,433 payloads appended to ONE file took 8.3 s with no stalls --
-- so the cost is the file count, not the bytes, and the cure is one file.
--
-- WHY ZIP, AND WHY STORE-ONLY.  PhysFS reads ZIP natively, so a mounted pack
-- answers require / love.graphics.newImage / love.filesystem.newFile exactly
-- as the loose tree did, with no wrapper in the way.  Nothing is compressed:
-- the bulk is PNGs, which already are, and a stored entry can be read back by
-- a seek and a read -- which is also how this module's own reader serves
-- CacheFs.read before anything is mounted.
--
-- WHAT IT DOES NOT DO: zip64.  A plain ZIP holds at most 65,535 entries and
-- cannot point past 4 GiB.  The largest measured cache is ~18,400 files and
-- ~170 MB, so the writer REFUSES an entry that would cross either limit
-- (add returns false, "full") and CacheFs writes that file loose instead --
-- loose files are read ahead of the pack anyway, so an over-full import is
-- slower, never wrong.
--
-- Pure Lua (LuaJIT `bit`, and `ffi` when present for the CRC loop), no LÖVE:
-- it runs in the import worker's Lua state and under a bare luajit test.

local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local byte, char, sub = string.byte, string.char, string.sub

local CachePack = {}

-- One short of 0xFFFF / 0xFFFFFFFF on purpose: readers treat those exact values
-- in the end-of-central-directory record as "look for a zip64 record", and a
-- pack with no zip64 record that happens to land on one is a pack some reader
-- will call corrupt.
CachePack.MAX_ENTRIES = 0xFFFE
CachePack.MAX_BYTES = 0xFFFFFFFE

-- ---------------------------------------------------------------------------
-- CRC-32 (IEEE 802.3, the one ZIP uses).  PhysFS verifies it when an entry is
-- read to the end, so it has to be right, not merely present.
--
-- No zlib: the PS5 build only exports a fixed list of libc symbols to the FFI
-- (ports/ps5/launcher/ffi_exports.txt) and zlib's crc32 is not among them.
-- A table-driven loop over an FFI byte pointer is what LuaJIT compiles well;
-- the string.byte fallback is for a Lua without FFI.
local okFfi, ffi = pcall(require, "ffi")
if not okFfi then ffi = nil end

local TABLE = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if band(c, 1) ~= 0 then c = bxor(rshift(c, 1), 0xEDB88320)
    else c = rshift(c, 1) end
  end
  TABLE[i] = c
end
local CTABLE = nil
if ffi then
  CTABLE = ffi.new("int32_t[256]")
  for i = 0, 255 do CTABLE[i] = TABLE[i] end
end

local function unsigned(v)
  if v < 0 then return v + 4294967296 end
  return v
end

-- crc32(data [, previous [, plainLua]]) -> unsigned 32-bit value.
-- `previous` continues a running CRC; `plainLua` forces the string.byte loop
-- so a test can hold the two implementations against each other.
function CachePack.crc32(data, previous, plainLua)
  local crc = bnot(bit.tobit(previous or 0))
  local n = #data
  if CTABLE and n > 0 and not plainLua then
    local p = ffi.cast("const uint8_t *", data)
    local T = CTABLE
    for i = 0, n - 1 do
      crc = bxor(rshift(crc, 8), T[band(bxor(crc, p[i]), 255)])
    end
  else
    local T = TABLE
    for i = 1, n do
      crc = bxor(rshift(crc, 8), T[band(bxor(crc, byte(data, i)), 255)])
    end
  end
  return unsigned(bnot(crc))
end

-- ---------------------------------------------------------------------------
-- little-endian fields
local function u16(v)
  return char(v % 256, math.floor(v / 256) % 256)
end
local function u32(v)
  return char(v % 256, math.floor(v / 256) % 256,
              math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function r16(s, i)
  local a, b = byte(s, i, i + 1)
  return a + b * 256
end
local function r32(s, i)
  local a, b, c, d = byte(s, i, i + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- MS-DOS date/time of `t` (os.time), the only timestamp a plain ZIP carries.
local function dosStamp(t)
  local d = os.date("*t", t or os.time())
  local year = math.max(1980, math.min(2107, d.year))
  local date = (year - 1980) * 512 + d.month * 32 + d.day
  local time = d.hour * 2048 + d.min * 32 + math.floor(d.sec / 2)
  return time, date
end

local SIG_LOCAL = 0x04034b50
local SIG_CENTRAL = 0x02014b50
local SIG_END = 0x06054b50
local LOCAL_SIZE = 30
local CENTRAL_SIZE = 46
local END_SIZE = 22

-- ---------------------------------------------------------------------------
-- WRITER
--
-- Entries are appended as they arrive (local header + bytes); the central
-- directory is written once, by finish.  Until then the file is not a valid
-- archive, which is the point: the caller writes to a temporary name and
-- renames only after finish, so an import killed half way leaves a `.part`
-- nothing will ever mount -- never a pack that looks whole.
--
-- The SAME NAME WRITTEN TWICE: the second copy is appended and the index is
-- re-pointed at it, so the central directory names each file once and the last
-- write wins -- exactly what overwriting a loose file did.  The first copy's
-- bytes stay in the file as dead weight; `duplicates` counts them.
local Writer = {}
Writer.__index = Writer

-- CachePack.create(path) -> writer | nil, err.  Truncates `path`.
function CachePack.create(path)
  local f, err = io.open(path, "w+b")
  if not f then return nil, err end
  local time, date = dosStamp()
  return setmetatable({
    path = path, f = f, offset = 0,
    order = {},        -- names in first-write order (central-directory order)
    index = {},        -- name -> { offset, size, crc, dataAt }
    entries = 0, duplicates = 0, bytes = 0,
    time = time, date = date,
  }, Writer)
end

function Writer:count() return self.entries end

-- add(name, data) -> true | false, why.  why == "full" means the archive
-- cannot take this entry without zip64 (see MAX_ENTRIES / MAX_BYTES); the
-- caller is expected to store the file some other way.  Any other `why` is an
-- I/O failure and the pack should be abandoned.
function Writer:add(name, data)
  if not self.f then return false, "pack is closed" end
  local existing = self.index[name]
  if not existing and self.entries >= CachePack.MAX_ENTRIES then
    return false, "full"
  end
  local size = #data
  local headerAt = self.offset
  local nameLen = #name
  -- Everything this entry adds, plus the central-directory record it will
  -- need, must still leave the directory's own offset below 4 GiB.
  if headerAt + LOCAL_SIZE + nameLen + size
      + (self.cdBytes or 0) + CENTRAL_SIZE + nameLen + END_SIZE
      > CachePack.MAX_BYTES then
    return false, "full"
  end
  local crc = CachePack.crc32(data)
  local header = u32(SIG_LOCAL) .. u16(10) .. u16(0) .. u16(0)
    .. u16(self.time) .. u16(self.date) .. u32(crc) .. u32(size) .. u32(size)
    .. u16(nameLen) .. u16(0) .. name
  local ok, err = self.f:write(header, data)
  if not ok then return false, tostring(err or "write failed") end
  local entry = { offset = headerAt, size = size, crc = crc,
                  dataAt = headerAt + LOCAL_SIZE + nameLen }
  self.offset = headerAt + LOCAL_SIZE + nameLen + size
  if existing then
    self.duplicates = self.duplicates + 1
    self.bytes = self.bytes - existing.size
  else
    self.entries = self.entries + 1
    self.order[#self.order + 1] = name
    self.cdBytes = (self.cdBytes or 0) + CENTRAL_SIZE + nameLen
  end
  self.bytes = self.bytes + size
  self.index[name] = entry
  return true
end

function Writer:has(name)
  return self.index[name] ~= nil
end

-- Read an entry back while the pack is still being written: an import that
-- consults its own earlier output must see it, and it is not on disk anywhere
-- else.  The seek back to the end is what keeps the next add appending (C
-- stdio also needs a positioning call between a read and a write).
function Writer:read(name)
  local e = self.index[name]
  if not (e and self.f) then return nil end
  if e.size == 0 then return "" end
  self.f:seek("set", e.dataAt)
  local data = self.f:read(e.size)
  self.f:seek("end")
  return data
end

-- Forget an entry (CacheFs.remove during an import).  Its bytes stay; it just
-- is not in the central directory.
function Writer:remove(name)
  local e = self.index[name]
  if not e then return end
  self.index[name] = nil
  self.entries = self.entries - 1
  self.bytes = self.bytes - e.size
  self.cdBytes = self.cdBytes - CENTRAL_SIZE - #name
  for i, n in ipairs(self.order) do
    if n == name then table.remove(self.order, i) break end
  end
end

-- Write the central directory and the end record, then close.  Returns
-- true or nil, err.  The file is a valid archive only after this returns true.
function Writer:finish()
  local f = self.f
  if not f then return nil, "pack is closed" end
  local cdStart = self.offset
  local parts, count = {}, 0
  for _, name in ipairs(self.order) do
    local e = self.index[name]
    if e then
      count = count + 1
      parts[#parts + 1] = u32(SIG_CENTRAL) .. u16(20) .. u16(10) .. u16(0) .. u16(0)
        .. u16(self.time) .. u16(self.date) .. u32(e.crc) .. u32(e.size) .. u32(e.size)
        .. u16(#name) .. u16(0) .. u16(0) .. u16(0) .. u16(0) .. u32(0)
        .. u32(e.offset) .. name
      -- flushed in slices so 18,000 records are not one 1.5 MB concat
      if #parts >= 512 then
        local ok, err = f:write(table.concat(parts))
        if not ok then return nil, tostring(err) end
        parts = {}
      end
    end
  end
  if #parts > 0 then
    local ok, err = f:write(table.concat(parts))
    if not ok then return nil, tostring(err) end
  end
  local cdSize = f:seek("end") - cdStart
  local tail = u32(SIG_END) .. u16(0) .. u16(0) .. u16(count) .. u16(count)
    .. u32(cdSize) .. u32(cdStart) .. u16(0)
  local ok, err = f:write(tail)
  if not ok then return nil, tostring(err) end
  local closed, closeErr = f:close()
  self.f = nil
  if not closed then return nil, tostring(closeErr) end
  return true
end

-- Close without a central directory and delete the file.
function Writer:abort()
  if self.f then pcall(self.f.close, self.f) end
  self.f = nil
  os.remove(self.path)
end

-- ---------------------------------------------------------------------------
-- READER
--
-- CachePack.open(source) -> reader | nil, err.  `source` is one of:
--
--   * a path -- opened with io.open;
--   * a function returning a handle with read(n) / seek(absolutePos) /
--     size() / close() -- CacheFs wraps a love.filesystem File that way when
--     io.* cannot reach the save directory;
--   * such a handle itself.
--
-- A path or a function is TRANSIENT: the file is closed once the central
-- directory is read and reopened for each entry.  That costs an open per
-- read, and it is what lets the launcher keep a pack's index around without
-- holding the file open -- Windows refuses to delete or replace a file
-- somebody has open, and the next import has to do exactly that.
local Reader = {}
Reader.__index = Reader

local function ioSource(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  return {
    read = function(_, n) return f:read(n) end,
    seek = function(_, pos) return f:seek("set", pos) end,
    size = function() return f:seek("end") end,
    close = function() f:close() end,
  }
end

function CachePack.open(source)
  local opener = nil
  if type(source) == "string" then
    opener = function() return ioSource(source) end
  elseif type(source) == "function" then
    opener = source
  end
  local src, err = source, nil
  if opener then
    src, err = opener()
    if not src then return nil, err end
  end
  local size = src:size()
  if not size or size < END_SIZE then
    src:close()
    return nil, "too small to be a pack"
  end
  -- The end record is the last 22 bytes: this writer never adds a comment,
  -- and a pack with one was not written here.
  src:seek(size - END_SIZE)
  local tail = src:read(END_SIZE)
  if not tail or #tail ~= END_SIZE or r32(tail, 1) ~= SIG_END then
    src:close()
    return nil, "no end-of-central-directory record"
  end
  local count = r16(tail, 11)
  local cdSize, cdStart = r32(tail, 13), r32(tail, 17)
  src:seek(cdStart)
  local cd = cdSize > 0 and src:read(cdSize) or ""
  if not cd or #cd ~= cdSize then
    src:close()
    return nil, "truncated central directory"
  end
  local index, names = {}, {}
  local at = 1
  for _ = 1, count do
    if r32(cd, at) ~= SIG_CENTRAL then
      src:close()
      return nil, "bad central-directory record"
    end
    local method = r16(cd, at + 10)
    local crc = r32(cd, at + 16)
    local csize, usize = r32(cd, at + 20), r32(cd, at + 24)
    local nlen, xlen, clen = r16(cd, at + 28), r16(cd, at + 30), r16(cd, at + 32)
    local offset = r32(cd, at + 42)
    local name = sub(cd, at + 46, at + 45 + nlen)
    index[name] = { offset = offset, size = usize, csize = csize,
                    method = method, crc = crc }
    names[#names + 1] = name
    at = at + 46 + nlen + xlen + clen
  end
  if opener then
    src:close()
    src = nil
  end
  return setmetatable({ src = src, opener = opener, index = index,
                        names = names, fileSize = size }, Reader)
end

function Reader:count() return #self.names end
function Reader:list() return self.names end
function Reader:has(name) return self.index[name] ~= nil end
function Reader:sizeOf(name)
  local e = self.index[name]
  return e and e.size or nil
end

-- The bytes of `name`, or nil.  Stored entries only (this writer never makes
-- anything else); the local header is re-read because its extra field may
-- differ from the central one in an archive written by another tool.
local function readEntry(src, e)
  if not e.dataAt then
    src:seek(e.offset)
    local h = src:read(LOCAL_SIZE)
    if not h or #h ~= LOCAL_SIZE or r32(h, 1) ~= SIG_LOCAL then
      return nil, "bad local header"
    end
    e.dataAt = e.offset + LOCAL_SIZE + r16(h, 27) + r16(h, 29)
  end
  if e.size == 0 then return "" end
  src:seek(e.dataAt)
  return src:read(e.size)
end

function Reader:read(name)
  local e = self.index[name]
  if not e then return nil end
  if e.method ~= 0 then return nil, "compressed entry" end
  if self.src then return readEntry(self.src, e) end
  if not self.opener then return nil, "reader is closed" end
  local src, err = self.opener()
  if not src then return nil, err end
  -- A different length is a different file: the pack was replaced under this
  -- index (another Lua state re-imported).  Refuse rather than read stale
  -- offsets out of somebody else's archive.
  if src:size() ~= self.fileSize then
    src:close()
    return nil, "stale"
  end
  local data, why = readEntry(src, e)
  src:close()
  return data, why
end

-- Re-hash every entry against its recorded CRC.  For tests and diagnostics;
-- returns true or false, firstBadName.
function Reader:verify()
  local own = false
  if not self.src and self.opener then
    self.src = self.opener()
    own = true
  end
  local bad = nil
  for _, name in ipairs(self.names) do
    local data = self:read(name)
    if not data or CachePack.crc32(data) ~= self.index[name].crc then
      bad = name
      break
    end
  end
  if own then self:close() end
  if bad then return false, bad end
  return true
end

function Reader:close()
  if self.src then self.src:close() end
  self.src = nil
end

return CachePack
