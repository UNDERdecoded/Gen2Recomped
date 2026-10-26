package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local previous = Version.get(); Version.set("crystal")
local files, reads, omitSize = {}, 0, false
local fs = {}
function fs.read(path) reads = reads + 1; return files[path] end
function fs.write(path, body) files[path] = body; return true end
function fs.remove(path) files[path] = nil; return true end
function fs.createDirectory() return true end
function fs.getInfo(path)
  if files[path] then return {type = "file", size = not omitSize and #files[path] or nil, modtime = 123} end
  for name in pairs(files) do if name:sub(1, #path + 1) == path .. "/" then return {type = "directory"} end end
end
function fs.getDirectoryItems(path)
  local seen, out = {}, {}
  for name in pairs(files) do
    if name:sub(1, #path + 1) == path .. "/" then
      local child = name:sub(#path + 2):match("^[^/]+")
      if not seen[child] then seen[child] = true; out[#out + 1] = child end
    end
  end
  table.sort(out); return out
end
for _, id in ipairs({"CACHE_A", "CACHE_B"}) do
  files["mods/" .. id .. "/manifest.json"] =
    ('{"id":"%s","name":"Cache probe","version":"1.0.0","api":2,"entry":"main.lua"}'):format(id)
  files["mods/" .. id .. "/main.lua"] = "return function() end"
end
local loader = Loader.new({fs = fs}); loader:_discover()
local a, b = loader:_api(assert(loader.mods.CACHE_A)), loader:_api(assert(loader.mods.CACHE_B))
local key, bytes = "hd-content/blobs/digest", "\0\255\r\nbinary PNG bytes"
T.eq(a.cache:write(key, bytes), true, "real public cache facade stores binary download data")
local before = reads
local info = a.cache:info(key)
T.eq(info.type, "file", "public cache metadata identifies persisted file")
T.eq(info.size, #bytes, "public metadata reports actual byte size")
T.eq(info.modtime, 123, "public metadata retains filesystem time")
T.eq(info.kind, "bytes", "existing native kind field retained")
T.eq(info.key, key, "existing native key field retained")
T.eq(reads, before, "metadata query does not read a potentially large payload")
local function verifiedRead(cache)
  local row = cache:info(key)
  if not row or row.type ~= "file" or row.size ~= #bytes then return nil end
  local value = cache:read(key)
  return value == bytes and value or nil
end
T.eq(verifiedRead(a.cache), bytes, "file-shaped package consumer accepts real cached bytes")
T.eq(verifiedRead(b.cache), nil, "same public key cannot expose another mod's download")
info.type, info.size = "changed", -1
T.eq(a.cache:info(key).type, "file", "metadata is detached")
local native = a.cache.storage:stat(nil, key)
T.eq(native.type, nil, "mod.storage retains its distinct native stat contract")
T.eq(native.kind, "bytes", "native storage kind unchanged")
files["modstorage/CACHE_A/preexisting.bin"] = bytes
T.eq(a.cache:info("preexisting").type, "file", "old cache is recognized without migration")
T.eq(a.cache:read("preexisting"), bytes, "old physical namespace and bytes unchanged")
omitSize = true; before = reads
T.eq(a.cache:info(key).type, "file", "backends without size still identify actual files")
T.eq(reads, before, "missing size does not trigger a payload read")
local missing, code = a.cache:info("not-present")
T.eq(missing, nil, "missing cache metadata stays absent"); T.eq(code, "not_found", "missing reason preserved")
missing, code = a.cache:info("../escape")
T.eq(missing, nil, "metadata cannot escape namespace"); T.eq(code, "invalid_key", "invalid-key reason preserved")
T.eq(a.cache:delete(key), true, "delete uses existing native owner")
T.eq(a.cache:info(key), nil, "deleted download is no longer advertised")
Version.set(previous)
T.finish("native cache file metadata and package-consumer roundtrip")
