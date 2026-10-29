package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Cache = require("src.import.CacheFs")
local Files = require("src.import.VersionFiles")
local originalLove, originalVersion = love, Version.get()
local oldRoot, oldDatasetRoot = Cache.root, Cache.datasetRoot
local root = os.tmpname()
os.remove(root)
local written, dirs = {}, {}
local function mkdir(path)
  local windows = package.config:sub(1, 1) == "\\"
  local quoted = windows and ('"' .. path .. '"') or ("'" .. path:gsub("'", "'\\''") .. "'")
  os.execute((windows and "mkdir " or "mkdir -p ") .. quoted)
  dirs[#dirs + 1] = path
end
local function write(path, body)
  local f = assert(io.open(path, "wb"))
  f:write(body)
  f:close()
  written[#written + 1] = path
end
mkdir(root)
for _, base in ipairs({ "cache", "save", "source" }) do
  mkdir(root .. "/" .. base)
  mkdir(root .. "/" .. base .. "/data")
  mkdir(root .. "/" .. base .. "/data/generated")
  mkdir(root .. "/" .. base .. "/gold")
  mkdir(root .. "/" .. base .. "/gold/data")
  mkdir(root .. "/" .. base .. "/gold/data/generated")
end
write(root .. "/cache/data/generated/probe.lua", "RED")
write(root .. "/cache/gold/data/generated/probe.lua", "GOLD")
write(root .. "/save/data/generated/probe.lua", "SAVE_RED")
write(root .. "/source/data/generated/probe.lua", "SOURCE_RED")
local chosen, ready = root .. "/cache", true
local virtualReads = 0
local fs = {
  getSaveDirectory = function()
    return root .. "/save"
  end,
  getSource = function()
    return root .. "/source"
  end,
  getRealDirectory = function()
    return root .. "/source"
  end,
  read = function()
    virtualReads = virtualReads + 1
    return "ACTIVE_OVERLAY"
  end,
  getInfo = function()
    return { type = "file", size = 14 }
  end,
}
love = { filesystem = fs }
Cache.root = function()
  error("observational reads must not resolve or mount roots")
end
Cache.datasetRoot = function()
  return chosen, ready
end
Version.set("gold")
local files = Files.new(fs)
T.eq(files.read("red", "data/generated/probe.lua", 100), "RED", "inactive Red bypasses active Gold overlay")
T.eq(files.read("gold", "data/generated/probe.lua", 100), "GOLD", "version-qualified native cache")
T.eq(files.info("red", "data/generated/probe.lua").size, 3, "native info uses exact file")
T.eq(
  files.read("gold", "data/generated/probe.lua", 3),
  nil,
  "native reader refuses oversized file before loading bytes"
)
T.eq(virtualReads, 0, "resolved cache never consults virtual overlay")
T.eq(files.path("red", "assets/generated/x.png"), nil, "ambiguous unprefixed asset path refused")
T.eq(
  files.path("gold", "assets/generated/x.png"),
  "gold/assets/generated/x.png",
  "prefixed asset path retained"
)
local identity = files.identity()
chosen = nil
T.check(files.identity() ~= identity, "cache-root changes have distinct identity")
T.eq(
  files.read("red", "data/generated/probe.lua", 100),
  "SAVE_RED",
  "resolved default save root takes precedence"
)
ready = false
T.eq(
  files.read("red", "data/generated/probe.lua", 100),
  "SOURCE_RED",
  "unresolved roots read verified source instead of guessing a save cache"
)
T.eq(virtualReads, 0, "physical source read bypasses overlay")
T.eq(Version.get(), "gold", "native dataset reads leave active version untouched")
-- A source archive is readable only when its exact provenance is verified.
fs.getRealDirectory = function()
  return "/another/overlay"
end
T.eq(
  Cache.datasetSourceFile("data/generated/probe.lua", 100),
  nil,
  "foreign overlay cannot impersonate developer source"
)
fs.getRealDirectory = function()
  return fs.getSource()
end
T.eq(
  Cache.datasetSourceFile("data/generated/probe.lua", 100),
  "ACTIVE_OVERLAY",
  "verified virtual source can be read"
)
T.eq(
  Cache.datasetSourceFile("data/generated/probe.lua", 3),
  nil,
  "source reader respects advertised size limit"
)
Cache.root, Cache.datasetRoot = oldRoot, oldDatasetRoot
love = originalLove
Version.set(originalVersion)
for i = #written, 1, -1 do
  os.remove(written[i])
end
for i = #dirs, 1, -1 do
  os.remove(dirs[i])
end
T.finish()
