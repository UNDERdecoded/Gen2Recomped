-- THE PACKED CACHE: the store-only ZIP the import writes on the PS5 instead of
-- ~18,000 loose files (src/import/CachePack, CacheFs "THE PACKED CACHE").
--
-- What has to hold, and what each block below proves:
--
--   * the CRC is the real CRC-32 -- PhysFS verifies it when an entry is read
--     to the end, so a wrong one is a cache that loads half a sprite and then
--     fails -- and the FFI loop agrees with the plain one;
--   * a pack round-trips: every name, every byte, empty files and all 256 byte
--     values included; a name written twice keeps the LAST bytes, like an
--     overwritten loose file;
--   * an import can read back what it already wrote, before the archive has a
--     central directory;
--   * the zip64 limits are refused rather than silently corrupting the
--     archive, and CacheFs then writes the file loose so the cache is still
--     whole;
--   * CacheFs.read / exists answer from the pack once the import is over, with
--     a loose file of the same name winning.
--
-- No PhysFS here (mount behaviour is checked by the headless import/boot runs
-- in the acceptance notes); this is the bytes.
--   python tools/run_lua_check.py tools/cache_pack_check.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local CachePack = require("src.import.CachePack")
local CacheFs = require("src.import.CacheFs")

local SEP = package.config:sub(1, 1)
local TMP = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp")
  .. SEP .. ("g2r_cache_pack_%d_%d"):format(os.time(), math.random(1, 1e6))
CacheFs.mkdirReal(TMP)

local made = {}
local function path(name)
  local p = TMP .. SEP .. name
  made[#made + 1] = p
  return p
end

local function readAll(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- ---------------------------------------------------------------- CRC-32
eq(CachePack.crc32("123456789"), 0xCBF43926, "CRC-32 check value")
eq(CachePack.crc32(""), 0, "CRC-32 of nothing")
eq(CachePack.crc32("The quick brown fox jumps over the lazy dog"), 0x414FA339,
  "CRC-32 of the pangram")
do
  local parts = {}
  for i = 0, 255 do parts[#parts + 1] = string.char(i) end
  local all = table.concat(parts):rep(37)
  eq(CachePack.crc32(all), CachePack.crc32(all, nil, true),
    "the FFI loop and the plain loop agree")
  eq(CachePack.crc32(all:sub(1001), CachePack.crc32(all:sub(1, 1000))),
    CachePack.crc32(all), "a running CRC continues")
end

-- ---------------------------------------------------------------- round trip
local bytes256
do
  local parts = {}
  for i = 0, 255 do parts[#parts + 1] = string.char(i) end
  bytes256 = table.concat(parts)
end

local files = {
  ["data/generated/constants.lua"] = "return { answer = 42 }\n",
  ["data/generated/empty.lua"] = "",
  ["assets/generated/gen4/sprites/a.png"] = bytes256:rep(300),
  ["assets/generated/gen4/deep/er/still/b.bin"] = ("\0\255"):rep(5000),
}

local packPath = path("round.zip")
local w = assert(CachePack.create(packPath))
for name, data in pairs(files) do
  check(w:add(name, data), "add " .. name)
end
-- written twice: last write wins, counted as a duplicate
check(w:add("data/generated/constants.lua", "return 'second'"), "re-add")
files["data/generated/constants.lua"] = "return 'second'"
-- added and then removed (CacheFs.remove mid-import)
check(w:add("data/generated/gone.lua", "x"), "add a file to remove")
w:remove("data/generated/gone.lua")

-- read back BEFORE finish: an import that consults its own earlier output
eq(w:read("assets/generated/gen4/sprites/a.png"), files["assets/generated/gen4/sprites/a.png"],
  "an entry reads back while the pack is still being written")
eq(w:read("data/generated/constants.lua"), "return 'second'",
  "the in-progress read sees the last write")
check(w:add("data/generated/after_read.lua", "appended after a read"),
  "an add after a read still appends")
files["data/generated/after_read.lua"] = "appended after a read"
check(not w:has("data/generated/gone.lua"), "a removed entry is gone")
eq(w.duplicates, 1, "one rewritten entry")
check(w:finish(), "finish")

local r = assert(CachePack.open(packPath))
local count = 0
for _ in pairs(files) do count = count + 1 end
eq(r:count(), count, "every name once in the central directory")
for name, data in pairs(files) do
  eq(r:read(name), data, "round trip " .. name)
end
check(not r:has("data/generated/gone.lua"), "the removed entry is not listed")
check(r:verify(), "every stored CRC matches its bytes")

-- the end record says what the central directory says
do
  local raw = readAll(packPath)
  local tail = raw:sub(-22)
  local function r16(s, i) local a, b = s:byte(i, i + 1) return a + b * 256 end
  check(tail:sub(1, 4) == "PK\5\6", "end-of-central-directory signature")
  eq(r16(tail, 9), count, "entries on this disk")
  eq(r16(tail, 11), count, "entries in total")
  check(raw:sub(1, 4) == "PK\3\4", "starts with a local header")
end

-- a corrupt tail is refused, not misread
do
  local bad = path("bad.zip")
  local f = io.open(bad, "wb"); f:write("not a zip at all, honestly"); f:close()
  check(CachePack.open(bad) == nil, "a file with no end record is not a pack")
end

-- ---------------------------------------------------------------- limits
do
  local full = path("full.zip")
  local fw = assert(CachePack.create(full))
  local okAll = true
  for i = 1, CachePack.MAX_ENTRIES do
    if not fw:add(("e/%05d"):format(i), "x") then okAll = false break end
  end
  check(okAll, "a pack takes " .. CachePack.MAX_ENTRIES .. " entries")
  local ok, why = fw:add("e/one-too-many", "x")
  check(not ok and why == "full", "entry " .. (CachePack.MAX_ENTRIES + 1) .. " is refused as full")
  check(fw:add("e/00001", "y"), "rewriting an existing name is still allowed when full")
  check(fw:finish(), "a full pack still finishes")
  local fr = assert(CachePack.open(full))
  eq(fr:count(), CachePack.MAX_ENTRIES, "and reads back with every entry")
  eq(fr:read("e/00001"), "y", "including the rewritten one")
  eq(fr:read(("e/%05d"):format(CachePack.MAX_ENTRIES)), "x", "and the last one")
  check(CachePack.MAX_ENTRIES < 0xFFFF, "the entry cap stays below the zip64 marker")
end
do
  local saved = CachePack.MAX_BYTES
  CachePack.MAX_BYTES = 4096
  local big = path("big.zip")
  local bw = assert(CachePack.create(big))
  check(bw:add("a", ("a"):rep(1000)), "under the byte cap")
  local ok, why = bw:add("b", ("b"):rep(4000))
  check(not ok and why == "full", "an entry that would cross the byte cap is refused")
  bw:abort()
  check(readAll(big) == nil, "abort deletes the partial file")
  CachePack.MAX_BYTES = saved
end

-- ---------------------------------------------------------------- CacheFs
-- The import's view: CacheFs.write into the pack, read-back during the
-- import, overflow to loose, then reads through the finished pack.
do
  local root = TMP .. SEP .. "root"
  CacheFs.mkdirReal(root)
  local realRoot = CacheFs.root
  CacheFs.root = function() return root end
  CacheFs.prefix = "platinum/"

  check(CacheFs.beginPack(), "beginPack under a root")
  check(CacheFs.packActive(), "a pack is being written")
  local savedMax = CachePack.MAX_ENTRIES
  CachePack.MAX_ENTRIES = 2
  check(CacheFs.write("data/generated/a.lua", "A"), "write a -> pack")
  check(CacheFs.write("assets/generated/x/b.png", "B"), "write b -> pack")
  check(CacheFs.write("data/generated/c.lua", "C"), "write c -> loose (pack full)")
  check(CacheFs.write("notes.txt", "N"), "a file outside the generated trees")
  CachePack.MAX_ENTRIES = savedMax

  eq(CacheFs.read("data/generated/a.lua"), "A", "read back from the pack mid-import")
  check(CacheFs.exists("assets/generated/x/b.png"), "exists from the pack mid-import")
  local function real(rel) return root .. SEP .. ("platinum/" .. rel):gsub("/", SEP) end
  check(readAll(real("data/generated/a.lua")) == nil, "a packed file is not on disk loose")
  eq(readAll(real("data/generated/c.lua")), "C", "the overflow file is on disk loose")
  eq(readAll(real("notes.txt")), "N", "non-generated files stay loose")
  check(readAll(real("rom-cache.zip")) == nil, "no final pack before finish")
  check(readAll(real("rom-cache.zip.part")) ~= nil, "a .part while writing")

  local ok, stats = CacheFs.finishPack()
  check(ok, "finishPack: " .. tostring(stats))
  eq(stats and stats.entries, 2, "two entries packed")
  eq(stats and stats.overflow, 1, "one left loose")
  check(not CacheFs.packActive(), "no pack being written after finish")
  check(readAll(real("rom-cache.zip.part")) == nil, "the .part was renamed away")
  check(CacheFs.packExists("platinum/"), "the pack exists under its final name")

  CacheFs.forgetPacks()
  eq(CacheFs.read("data/generated/a.lua"), "A", "read through the finished pack")
  eq(CacheFs.read("assets/generated/x/b.png"), "B", "and an asset")
  eq(CacheFs.read("data/generated/c.lua"), "C", "and the overflow, loose")
  check(not CacheFs.exists("data/generated/nope.lua"), "a missing file is missing")

  -- a loose file of the same name wins over the pack (mods, Data.lua's copies)
  local f = io.open(real("data/generated/a.lua"), "wb"); f:write("LOOSE"); f:close()
  eq(CacheFs.read("data/generated/a.lua"), "LOOSE", "loose beats the pack")
  os.remove(real("data/generated/a.lua"))

  -- the marker is never packed
  check(CacheFs.write("rom-cache.complete", "M"), "marker write")
  eq(readAll(real("rom-cache.complete")), "M", "the marker is a loose file")

  -- an aborted import leaves nothing that looks like a cache
  check(CacheFs.beginPack(), "a second import begins")
  check(CacheFs.write("data/generated/a.lua", "A2"), "writes into the new .part")
  CacheFs.abortPack()
  check(readAll(real("rom-cache.zip.part")) == nil, "abort removed the .part")
  check(CacheFs.packExists("platinum/"), "and left the finished pack alone")

  -- clearing removes the pack and any .part
  local part = io.open(real("rom-cache.zip.part"), "wb"); part:write("junk"); part:close()
  check(CacheFs.clearPack("platinum/"), "clearPack")
  check(readAll(real("rom-cache.zip")) == nil, "the pack is gone")
  check(readAll(real("rom-cache.zip.part")) == nil, "and the stale .part")
  CacheFs.forgetPacks()
  check(not CacheFs.exists("data/generated/a.lua"), "nothing answers from a cleared pack")

  -- Red is never packed
  CacheFs.prefix = ""
  local redOk = CacheFs.beginPack()
  check(not redOk, "Red's cache is never packed")

  for _, rel in ipairs({ "data/generated/c.lua", "notes.txt", "rom-cache.complete" }) do
    os.remove(real(rel))
  end
  for _, d in ipairs({ "platinum/data/generated", "platinum/assets/generated/x",
                       "platinum/assets/generated", "platinum/data",
                       "platinum/assets", "platinum" }) do
    CacheFs.rmdirReal(root .. SEP .. d:gsub("/", SEP))
  end
  CacheFs.rmdirReal(root)
  CacheFs.root = realRoot
  CacheFs.prefix = ""
end

-- ---------------------------------------------------------------- mode
do
  -- POKEPORT_PACKED_CACHE is read from the environment; without it, only the
  -- PS5 packs.  This run is not a PS5.
  local env = os.getenv("POKEPORT_PACKED_CACHE")
  if env == nil then
    check(not CacheFs.packedMode(), "loose by default off the PS5")
  elseif env == "1" then
    check(CacheFs.packedMode(), "POKEPORT_PACKED_CACHE=1 forces packing")
  end
end

for _, p in ipairs(made) do os.remove(p) end
CacheFs.rmdirReal(TMP)

T.finish("cache pack")
