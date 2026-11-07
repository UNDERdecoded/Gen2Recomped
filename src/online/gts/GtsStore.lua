-- Crash-safe storage for the GTS host (docs/online-design.md 2.7a, WS7).
--
-- One document per pool (`gts_<pool>`), JSON, written ATOMICALLY:
--
--   1. write  <name>.part   (header: magic, sequence, length, checksum)
--   2. read it back and check it
--   3. <name> -> <name>.bak (the old .bak removed first: Windows' rename
--      cannot replace a file)
--   4. <name>.part -> <name>
--
-- A crash anywhere leaves at least one whole copy: before 3 the old main
-- file; between 3 and 4 the .bak and the complete .part.  load() reads every
-- candidate (main, .part, .bak), keeps those whose length and checksum
-- match, and takes the HIGHEST sequence number.  A .part that is whole but
-- was never renamed is a state the host never acknowledged to anyone; taking
-- it is safe because every GTS request is idempotent (a client resends the
-- same token and gets the same answer), and taking the older copy is safe
-- for the same reason.  load() then rewrites the winner as the main file.
--
-- The file system is a small interface, so the same code runs over real
-- files (the Link Hub, a world host on desktop/Android) and over memory
-- (tests, with crash injection):
--
--   fs.read(name) -> string | nil       fs.write(name, s) -> ok, err
--   fs.remove(name)                     fs.rename(from, to) -> ok, err
--   fs.exists(name) -> bool
--
--   GtsStore.new(fs, { crashHook = fn(stage, name) }) -> store
--   store:load(name[, { readOnly = true }]) -> doc | nil, { source = "main"|"part"|"bak"|"none", seq }
--   store:commit(name, doc) -> ok, err        (stamps doc.seq)
--   GtsStore.dirFs(dir) / GtsStore.memoryFs() / GtsStore.loveFs(subdir)

local Json = require("src.link.Json")

local GtsStore = {}
GtsStore.__index = GtsStore

GtsStore.MAGIC = "GTSDB1"

-- Adler-32 (pure arithmetic: no bit library needed)
function GtsStore.checksum(s)
  local a, b = 1, 0
  local MOD = 65521
  local byte = string.byte
  local n = #s
  local i = 1
  while i <= n do
    local stop = math.min(n, i + 3800)
    for j = i, stop do
      a = a + byte(s, j)
      b = b + a
    end
    a = a % MOD
    b = b % MOD
    i = stop + 1
  end
  return b * 65536 + a
end

function GtsStore.encode(doc, seq)
  local body = Json.encode(doc)
  return ("%s %d %d %d\n"):format(GtsStore.MAGIC, seq, #body, GtsStore.checksum(body)) .. body
end

-- doc, seq | nil, why
function GtsStore.decode(bytes)
  if type(bytes) ~= "string" then return nil, "missing" end
  local nl = bytes:find("\n", 1, true)
  if not nl then return nil, "no header" end
  local magic, seq, len, sum = bytes:sub(1, nl - 1):match("^(%S+) (%d+) (%d+) (%d+)$")
  if magic ~= GtsStore.MAGIC then return nil, "bad header" end
  local body = bytes:sub(nl + 1)
  if #body ~= tonumber(len) then return nil, "truncated" end
  if GtsStore.checksum(body) ~= tonumber(sum) then return nil, "checksum" end
  local ok, doc = pcall(Json.decode, body)
  if not ok or type(doc) ~= "table" then return nil, "bad json" end
  return doc, tonumber(seq)
end

function GtsStore.new(fs, opts)
  opts = opts or {}
  return setmetatable({ fs = assert(fs, "GtsStore needs a file system"),
                        crashHook = opts.crashHook, seqs = {} }, GtsStore)
end

function GtsStore:_crash(stage, name)
  if self.crashHook then self.crashHook(stage, name) end
end

-- opts.readOnly: report what a load would pick, change nothing on disk
function GtsStore:load(name, opts)
  local fs = self.fs
  local best, bestSeq, bestSource = nil, -1, "none"
  for _, cand in ipairs({ { name, "main" }, { name .. ".part", "part" }, { name .. ".bak", "bak" } }) do
    local doc, seq = GtsStore.decode(fs.read(cand[1]))
    if doc and seq > bestSeq then best, bestSeq, bestSource = doc, seq, cand[2] end
  end
  if not best then
    self.seqs[name] = 0
    return nil, { source = "none", seq = 0 }
  end
  self.seqs[name] = bestSeq
  if opts and opts.readOnly then
    -- inspection only
  elseif bestSource ~= "main" then
    -- recovered: make the winner the main file again
    best.seq = bestSeq
    self.seqs[name] = bestSeq - 1
    self:commit(name, best)
  elseif fs.exists(name .. ".part") then
    fs.remove(name .. ".part") -- an older or broken leftover
  end
  return best, { source = bestSource, seq = bestSeq }
end

function GtsStore:commit(name, doc)
  local fs = self.fs
  local seq = (self.seqs[name] or 0) + 1
  doc.seq = seq
  local bytes = GtsStore.encode(doc, seq)
  local part = name .. ".part"
  local ok, err = fs.write(part, bytes)
  if not ok then return false, "write failed: " .. tostring(err) end
  if fs.read(part) ~= bytes then
    fs.remove(part)
    return false, "write did not read back"
  end
  self:_crash("part_written", name)
  if fs.exists(name) then
    fs.remove(name .. ".bak")
    ok, err = fs.rename(name, name .. ".bak")
    if not ok then return false, "rename to .bak failed: " .. tostring(err) end
  end
  self:_crash("main_moved", name)
  ok, err = fs.rename(part, name)
  if not ok then
    -- the caller will report "nothing happened", so the new copy must not
    -- be adopted by a later load: drop it and put the old one back
    fs.remove(part)
    if not fs.exists(name) and fs.exists(name .. ".bak") then fs.rename(name .. ".bak", name) end
    return false, "rename failed: " .. tostring(err)
  end
  self:_crash("committed", name)
  self.seqs[name] = seq
  return true
end

-- ------------------------------------------------------------ file systems

-- real files in `dir` (created if missing)
function GtsStore.dirFs(dir)
  dir = tostring(dir):gsub("\\", "/"):gsub("/+$", "")
  local function path(name) return dir .. "/" .. name end
  local function mkdirs()
    local f = io.open(path(".gts_probe"), "wb")
    if f then f:close(); os.remove(path(".gts_probe")); return end
    local isWin = package.config:sub(1, 1) == "\\"
    if isWin then
      os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
    else
      os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
    end
  end
  mkdirs()
  return {
    dir = dir,
    read = function(name)
      local f = io.open(path(name), "rb")
      if not f then return nil end
      local s = f:read("*a")
      f:close()
      return s
    end,
    write = function(name, s)
      local f, err = io.open(path(name), "wb")
      if not f then return false, err end
      local ok, werr = f:write(s)
      f:flush()
      f:close()
      if not ok then return false, werr end
      return true
    end,
    remove = function(name) os.remove(path(name)) end,
    rename = function(from, to)
      local ok, err = os.rename(path(from), path(to))
      if not ok then return false, err end
      return true
    end,
    exists = function(name)
      local f = io.open(path(name), "rb")
      if f then f:close() return true end
      return false
    end,
  }
end

-- in memory.  rename refuses an existing target (as Windows does), so the
-- commit order is exercised exactly as on disk.  `fs.files` is the table.
function GtsStore.memoryFs(files)
  local fs = { files = files or {} }
  fs.read = function(name) return fs.files[name] end
  fs.write = function(name, s)
    if fs.failWrite then return false, "disk full" end
    fs.files[name] = s
    return true
  end
  fs.remove = function(name) fs.files[name] = nil end
  fs.rename = function(from, to)
    if fs.files[from] == nil then return false, "no such file" end
    if fs.files[to] ~= nil then return false, "target exists" end
    fs.files[to] = fs.files[from]
    fs.files[from] = nil
    return true
  end
  fs.exists = function(name) return fs.files[name] ~= nil end
  return fs
end

-- under the game's save directory (portable folder when that is on):
-- online/<subdir>.  Falls back to memory when no real path is known.
function GtsStore.loveFs(subdir)
  subdir = subdir or "online/gts"
  local base
  local okS, SaveData = pcall(require, "src.core.SaveData")
  if okS and SaveData.portableBaseDir then
    local okP, p = pcall(SaveData.portableBaseDir)
    if okP and p then base = p end
  end
  if not base and love and love.filesystem and love.filesystem.getSaveDirectory then
    pcall(love.filesystem.createDirectory, subdir)
    base = love.filesystem.getSaveDirectory()
  end
  if not base then return GtsStore.memoryFs() end
  return GtsStore.dirFs(tostring(base):gsub("\\", "/"):gsub("/+$", "") .. "/" .. subdir)
end

return GtsStore
