-- Sandboxed bulk storage for mods (mod.storage).
--
-- mod.save is the right home for a handful of per-playthrough values: it lives
-- inside save.modData and rides every save/load.  This is the other half --
-- large opaque payloads a mod DERIVES rather than authors (an extracted model
-- cache, a decoded asset pack), which must never bloat a save file and must
-- survive New Game.  Each mod gets one namespace under the save directory and
-- can see nothing outside it.
--
-- The payloads here are derived from a source the mod already owns, so the
-- namespace is per MOD, not per playthrough or per game version: re-deriving
-- hundreds of megabytes for every save slot would be the wrong default.  A mod
-- that needs finer scoping puts the scope in its own key, and context() hands
-- it the version and slot to build one from.
--
-- Every method takes the live game as its first argument (mod.storage:read(
-- mod.game, key)) so a future revision can scope by it without a signature
-- break.  Errors come back as `nil/false, code, message`; "not_found" is a
-- normal answer, never an error.

local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local Storage = {}
Storage.__index = Storage

Storage.ROOT = "modstorage"
Storage.RECORD_EXT = ".rec"
Storage.BYTES_EXT = ".bin"
Storage.MAX_KEY = 180

local function fsOr(fs)
  return fs or (love and love.filesystem) or nil
end

-- id and key both land in a filesystem path, so both are validated rather
-- than escaped: a key may name segments under the namespace and nothing
-- above it.  "..", absolute paths, empty segments and backslashes are out.
local function sanitizeId(id)
  id = tostring(id or "")
  if id == "" then return nil end
  return (id:gsub("[^%w%-_%.]", "_"))
end

local function validKey(key)
  if type(key) ~= "string" or key == "" or #key > Storage.MAX_KEY then
    return nil, "key must be a short non-empty string"
  end
  if key:find("\\", 1, true) then return nil, "key may not contain backslashes" end
  if key:sub(1, 1) == "/" or key:sub(-1) == "/" then
    return nil, "key may not start or end with /"
  end
  for segment in key:gmatch("[^/]*") do
    if segment == ".." then return nil, "key may not traverse upward" end
  end
  if key:find("//", 1, true) then return nil, "key may not have empty segments" end
  if key:find("[^%w%-_%./]") then
    return nil, "key may only use letters, digits, - _ . and /"
  end
  return key
end

function Storage.new(modId, fs)
  local id = sanitizeId(modId)
  assert(id, "mod storage needs a mod id")
  return setmetatable({
    modId = modId,
    root = Storage.ROOT .. "/" .. id,
    fs = fsOr(fs),
  }, Storage)
end

-- Resolved once per call and cached back onto the instance, so the helpers
-- below (which reach for self.fs directly) can never see a different
-- filesystem than the method that admitted them.
function Storage:_fs()
  local fs = fsOr(self.fs)
  if not (fs and fs.read and fs.getInfo) then
    return nil, "storage_unavailable", "no filesystem is available"
  end
  self.fs = fs
  return fs
end

function Storage:_path(key, ext)
  return self.root .. "/" .. key .. ext
end

-- love.filesystem.createDirectory makes the intermediate levels too, but an
-- injected fs may not; walk the segments so both behave the same.
function Storage:_ensureDir(path)
  local fs = self.fs
  if not (fs and fs.createDirectory) then return end
  local dir = path:match("^(.*)/[^/]*$")
  if not dir then return end
  local built
  for segment in dir:gmatch("[^/]+") do
    built = built and (built .. "/" .. segment) or segment
    if not (fs.getInfo and fs.getInfo(built)) then fs.createDirectory(built) end
  end
end

-- The key index is walked once and then held: Cache-style callers ask
-- "is my payload still complete?" on a UI row, i.e. every frame, and a
-- getDirectoryItems walk over several hundred blobs per frame is not
-- something a menu can afford.  This process is the only writer, so every
-- mutation below drops the memo and the next list() rebuilds it.
function Storage:_invalidate()
  self._keys = nil
end

function Storage:_allKeys()
  if self._keys then return self._keys end
  local fs = self.fs
  local out = {}
  local function walk(dir)
    local info = fs.getInfo(dir)
    if not info or info.type == "file" then return end
    for _, name in ipairs(fs.getDirectoryItems(dir) or {}) do
      local path = dir .. "/" .. name
      local entry = fs.getInfo(path)
      if entry and entry.type == "directory" then
        walk(path)
      else
        local key = path:sub(#self.root + 2)
        local stem = key:match("^(.*)%" .. Storage.RECORD_EXT .. "$")
          or key:match("^(.*)%" .. Storage.BYTES_EXT .. "$")
        if stem then out[#out + 1] = stem end
      end
    end
  end
  walk(self.root)
  table.sort(out)
  self._keys = out
  return out
end

function Storage:_exists(path)
  local fs = self.fs
  local info = fs.getInfo and fs.getInfo(path)
  return info ~= nil and (info.type == nil or info.type == "file")
end

-- The playthrough this call happens inside.  Informational: a mod logs it, or
-- folds it into its own keys when it does want per-save scoping.
function Storage:context(_game)
  local fs, code, message = self:_fs()
  if not fs then return nil, code, message end
  local version = GameVersion.get and GameVersion.get() or nil
  local ok, slot = pcall(SaveData.activeSlot, version)
  return {
    modId = self.modId,
    root = self.root,
    gameVersion = version or "unknown",
    playthroughId = (ok and slot) or "default",
  }
end

function Storage:read(_game, key)
  local fs, code, message = self:_fs()
  if not fs then return nil, code, message end
  local valid, keyErr = validKey(key)
  if not valid then return nil, "invalid_key", keyErr end
  local path = self:_path(valid, Storage.RECORD_EXT)
  if not self:_exists(path) then
    -- A record key that exists as bytes is a caller mistake, not an absence.
    if self:_exists(self:_path(valid, Storage.BYTES_EXT)) then
      return nil, "type_mismatch", "record key holds opaque bytes"
    end
    return nil, "not_found", "no record at " .. valid
  end
  local body = fs.read(path)
  if type(body) ~= "string" then
    return nil, "read_failed", "could not read " .. valid
  end
  local decoded, value = pcall(SaveSerializer.decode, body)
  if not decoded or type(value) ~= "table" then
    return nil, "decode_failed", "record at " .. valid .. " is malformed"
  end
  return value
end

function Storage:write(_game, key, value)
  local fs, code, message = self:_fs()
  if not fs then return false, code, message end
  if not fs.write then
    return false, "storage_unavailable", "filesystem is read-only"
  end
  local valid, keyErr = validKey(key)
  if not valid then return false, "invalid_key", keyErr end
  if type(value) ~= "table" then
    return false, "invalid_value", "records must be tables"
  end
  local encoded, body = pcall(SaveSerializer.encode, value)
  if not encoded or type(body) ~= "string" then
    return false, "encode_failed", tostring(body)
  end
  local path = self:_path(valid, Storage.RECORD_EXT)
  self:_ensureDir(path)
  local wrote, writeErr = fs.write(path, body)
  if not wrote then return false, "write_failed", tostring(writeErr) end
  self:_invalidate()
  -- one key, one representation
  if fs.remove and self:_exists(self:_path(valid, Storage.BYTES_EXT)) then
    fs.remove(self:_path(valid, Storage.BYTES_EXT))
  end
  return true
end

function Storage:readBytes(_game, key)
  local fs, code, message = self:_fs()
  if not fs then return nil, code, message end
  local valid, keyErr = validKey(key)
  if not valid then return nil, "invalid_key", keyErr end
  local path = self:_path(valid, Storage.BYTES_EXT)
  if not self:_exists(path) then
    -- Told apart so a caller can migrate a payload it once stored as a record.
    if self:_exists(self:_path(valid, Storage.RECORD_EXT)) then
      return nil, "type_mismatch", "byte key holds a data record"
    end
    return nil, "not_found", "no bytes at " .. valid
  end
  local body = fs.read(path)
  if type(body) ~= "string" then
    return nil, "read_failed", "could not read " .. valid
  end
  return body
end

function Storage:writeBytes(_game, key, bytes)
  local fs, code, message = self:_fs()
  if not fs then return false, code, message end
  if not fs.write then
    return false, "storage_unavailable", "filesystem is read-only"
  end
  local valid, keyErr = validKey(key)
  if not valid then return false, "invalid_key", keyErr end
  if type(bytes) ~= "string" then
    return false, "invalid_value", "opaque storage takes a byte string"
  end
  local path = self:_path(valid, Storage.BYTES_EXT)
  self:_ensureDir(path)
  local wrote, writeErr = fs.write(path, bytes)
  if not wrote then return false, "write_failed", tostring(writeErr) end
  self:_invalidate()
  if fs.remove and self:_exists(self:_path(valid, Storage.RECORD_EXT)) then
    fs.remove(self:_path(valid, Storage.RECORD_EXT))
  end
  return true
end

function Storage:delete(_game, key)
  local fs, code, message = self:_fs()
  if not fs then return false, code, message end
  local valid, keyErr = validKey(key)
  if not valid then return false, "invalid_key", keyErr end
  local record, bytes = self:_path(valid, Storage.RECORD_EXT),
                        self:_path(valid, Storage.BYTES_EXT)
  local hadRecord, hadBytes = self:_exists(record), self:_exists(bytes)
  if not (hadRecord or hadBytes) then
    return false, "not_found", "nothing stored at " .. valid
  end
  if not fs.remove then
    return false, "storage_unavailable", "filesystem cannot remove"
  end
  if hadRecord and not fs.remove(record) then
    return false, "delete_failed", "could not remove " .. valid
  end
  if hadBytes and not fs.remove(bytes) then
    return false, "delete_failed", "could not remove " .. valid
  end
  self:_invalidate()
  return true
end

-- Every key at or below `prefix`, in the mod's own key space (no extension,
-- no namespace root).  A prefix that was never written is an empty list, not
-- an error: "nothing stored there" is an answer.
function Storage:list(_game, prefix)
  local fs, code, message = self:_fs()
  if not fs then return nil, code, message end
  if not fs.getDirectoryItems then
    return nil, "storage_unavailable", "filesystem cannot enumerate"
  end
  prefix = prefix == nil and "" or prefix
  if prefix ~= "" then
    local valid, keyErr = validKey(prefix)
    if not valid then return nil, "invalid_key", keyErr end
    prefix = valid
  end
  local all = self:_allKeys()
  if prefix == "" then return all end
  local out, under = {}, prefix .. "/"
  for _, key in ipairs(all) do
    if key == prefix or key:sub(1, #under) == under then
      out[#out + 1] = key
    end
  end
  return out
end

return Storage
