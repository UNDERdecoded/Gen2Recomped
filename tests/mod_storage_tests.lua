-- mod.storage: the bulk half of a mod's persistence, sandboxed per mod.
--
-- The behaviours worth pinning are the ones a caller gets wrong silently.
-- Chief among them: "not_found" and "storage_unavailable" must never blur
-- together.  A mod that reads a failed LOOKUP as "nothing is cached" rebuilds
-- its cache on every launch -- that exact confusion is what the Stadium 2
-- importer's cache layer guards against, and it can only guard against it if
-- this layer tells the two apart.
package.path = "./?.lua;./?/init.lua;" .. package.path

local Storage = require("src.mods.Storage")
local Loader = require("src.mods.Loader")

local S = require("tests.harness").suite("mod storage")
local check = S.check

-- A writable memfs: love.filesystem's shape, minus everything storage does
-- not touch.  Directories are implied by their children, exactly as the
-- read-only memfs in the catalog suite does it.
local function memfs()
  local files, dirs = {}, {}
  local fs
  fs = {
    files = files,
    read = function(path) return files[path] end,
    write = function(path, body)
      files[path] = body
      return true
    end,
    remove = function(path)
      if files[path] == nil then return false end
      files[path] = nil
      return true
    end,
    createDirectory = function(path)
      dirs[path] = true
      return true
    end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      if dirs[path] then return { type = "directory" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
  return fs
end

local function newStore(id, fs)
  return Storage.new(id or "TESTMOD", fs or memfs())
end

-- ---------------------------------------------------------------- bytes

local fs = memfs()
local store = newStore("TESTMOD", fs)
local GAME = {} -- an opaque handle: storage must not index it

-- A DSM-style payload: embedded NULs and high bytes have to survive verbatim,
-- so a future switch to a text encoding cannot pass this suite.
local payload = "\0\255\1DSM\0\0binary\255"
check(store:writeBytes(GAME, "cache/models/001", payload) == true,
  "writeBytes reports success")
check(store:readBytes(GAME, "cache/models/001") == payload,
  "opaque bytes round-trip byte for byte, NULs included")
check(fs.files["modstorage/TESTMOD/cache/models/001.bin"] == payload,
  "bytes land inside the mod's own namespace")

local missing, missingCode = store:readBytes(GAME, "cache/models/999")
check(missing == nil and missingCode == "not_found",
  "an absent key is not_found, not an error")

-- ---------------------------------------------------------------- records

check(store:write(GAME, "cache/marker", { count = 251, format = "S2IMP32" })
  == true, "write stores a data record")
local marker = store:read(GAME, "cache/marker")
check(type(marker) == "table" and marker.count == 251
  and marker.format == "S2IMP32", "records round-trip through SaveSerializer")

local wrongKind, wrongCode = store:read(GAME, "cache/models/001")
check(wrongKind == nil and wrongCode == "type_mismatch",
  "reading a byte key as a record is type_mismatch, not not_found")
local wrongBytes, wrongBytesCode = store:readBytes(GAME, "cache/marker")
check(wrongBytes == nil and wrongBytesCode == "type_mismatch",
  "reading a record key as bytes is type_mismatch, not not_found")

-- One key, one representation: a caller migrating a payload from a record to
-- opaque bytes must not leave the old copy behind to be found later.
check(store:writeBytes(GAME, "cache/marker", payload) == true,
  "a byte write may replace a record at the same key")
check(fs.files["modstorage/TESTMOD/cache/marker.rec"] == nil,
  "the replaced record is removed rather than shadowed")
check(store:readBytes(GAME, "cache/marker") == payload,
  "the surviving representation is the one just written")
store:write(GAME, "cache/marker", { count = 251, format = "S2IMP32" })

-- ---------------------------------------------------------------- listing

store:writeBytes(GAME, "cache/models/002", "b")
store:writeBytes(GAME, "other/thing", "c")
local keys = store:list(GAME, "cache")
check(type(keys) == "table" and #keys == 3,
  "list returns every key under the prefix and nothing above it")
check(keys[1] == "cache/marker" and keys[2] == "cache/models/001"
  and keys[3] == "cache/models/002",
  "listed keys are sorted, extension-free and namespace-free")

local empty = store:list(GAME, "never/written")
check(type(empty) == "table" and #empty == 0,
  "an unwritten prefix lists empty rather than failing -- 'nothing there' is "
    .. "an answer, and a caller that clears its cache must not see an error")

-- The memo behind list() is the reason a menu row can ask "is my cache still
-- complete?" every frame; it is also the thing most likely to go stale.
store:writeBytes(GAME, "cache/models/003", "d")
check(#store:list(GAME, "cache") == 4, "a write invalidates the list memo")
check(store:delete(GAME, "cache/models/003") == true, "delete reports success")
check(#store:list(GAME, "cache") == 3, "a delete invalidates the list memo")

local goneOk, goneCode = store:delete(GAME, "cache/models/003")
check(goneOk == false and goneCode == "not_found",
  "deleting what is already gone is not_found, not a failure")
local readGone, readGoneCode = store:readBytes(GAME, "cache/models/003")
check(readGone == nil and readGoneCode == "not_found",
  "a deleted key reads back as absent")

-- ---------------------------------------------------------------- keys

for _, bad in ipairs({ "../escape", "cache/../../escape", "/leading",
                       "trailing/", "cache//empty", "back\\slash",
                       "sp ace", "" }) do
  local ok, code = store:writeBytes(GAME, bad, "x")
  check(ok == false and code == "invalid_key",
    ("%q is rejected as a key"):format(bad))
end
check(store:writeBytes(GAME, "a-b_c.1/d", "x") == true,
  "letters, digits, - _ . and / are all legal in a key")

-- ---------------------------------------------------------------- sandbox

local shared = memfs()
local mine, yours = newStore("MINE", shared), newStore("YOURS", shared)
mine:writeBytes(GAME, "cache/x", "mine")
yours:writeBytes(GAME, "cache/x", "yours")
check(mine:readBytes(GAME, "cache/x") == "mine"
  and yours:readBytes(GAME, "cache/x") == "yours",
  "two mods using the same key do not collide")
check(#mine:list(GAME, "cache") == 1,
  "one mod's listing never includes another mod's keys")

-- ---------------------------------------------------------------- no fs

local blind = Storage.new("TESTMOD", { })
local blindOk, blindCode = blind:readBytes(GAME, "cache/x")
check(blindOk == nil and blindCode == "storage_unavailable",
  "an unusable filesystem is storage_unavailable -- distinct from not_found, "
    .. "so a caller never mistakes a broken backend for an empty cache")

local readOnly = memfs()
readOnly.write = nil
local frozen = Storage.new("TESTMOD", readOnly)
local frozenOk, frozenCode = frozen:writeBytes(GAME, "cache/x", "x")
check(frozenOk == false and frozenCode == "storage_unavailable",
  "a read-only filesystem refuses writes rather than reporting success")

-- ---------------------------------------------------------------- context

local ctx = store:context(GAME)
check(type(ctx) == "table" and ctx.modId == "TESTMOD"
  and type(ctx.gameVersion) == "string" and type(ctx.playthroughId) == "string",
  "context names the mod, the version and the playthrough")

-- ---------------------------------------------------------- loader facade

local loaderFs = memfs()
loaderFs.files["mods/EXAMPLE/manifest.json"] =
  '{"id":"EXAMPLE","name":"Example","version":"1.0.0","api":2,'
  .. '"entry":"main.lua","game_version":">=0.0.0-0 <2.0.0"}'
loaderFs.files["mods/EXAMPLE/main.lua"] = "return function(mod) end"
loaderFs.load = function(path)
  if not loaderFs.files[path] then return nil, "no file: " .. path end
  return load(loaderFs.files[path], path)
end

-- an injected game, because this suite is love-free and the real
-- src.core.Game cannot load here
local loader = Loader.new({ fs = loaderFs })
loader.game = { injected = true }
loader:_discover()
check(loader.mods.EXAMPLE ~= nil, "the fixture mod is discovered")
local api = loader:_api(loader.mods.EXAMPLE)
check(api.storage ~= nil, "mod.storage is reachable from the mod facade")
check(api.storage == api.storage, "mod.storage is the same object every touch")
check(api.game ~= nil and api.game.injected == true,
  "mod.game is reachable from the mod facade")
check(api.nonsense == nil, "the facade still answers nil for unknown keys")
api.storage:writeBytes(api.game, "probe", "p")
check(loaderFs.files["modstorage/EXAMPLE/probe.bin"] == "p",
  "the facade's store is namespaced by the mod's own id")

S.finish()
