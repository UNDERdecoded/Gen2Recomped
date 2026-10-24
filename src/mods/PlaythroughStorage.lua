-- Data-only and opaque-byte per-mod persistence, scoped by game version and
-- opaque playthrough.
-- API-3 contract adapted from Gen1Recomp Storage at 79ea62f45fb2ea8f65d081a109431e4eb1bbdb36.
-- Engine-private; the public handle contains only bound facade methods.

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local Version = require("src.core.Version")

local Storage = {}
Storage.__index = Storage
Storage.MAX_BYTES = 512 * 1024 * 1024

local ROOT = "mod_storage"

local function failure(code, message)
  return nil, code, message
end

local function validSegment(value)
  return type(value) == "string" and value ~= "" and value:match("^[%w_-]+$") ~= nil
end

local function validKey(key, allowEmpty)
  if type(key) ~= "string" or (key == "" and not allowEmpty) then
    return false
  end
  if key == "" then
    return true
  end
  if key:sub(1, 1) == "/" or key:sub(-1) == "/" or key:find("//", 1, true) then
    return false
  end
  for segment in key:gmatch("[^/]+") do
    if not validSegment(segment) then
      return false
    end
  end
  return true
end

local function ensureParent(fs, path)
  local dir = path:match("^(.*)/[^/]+$")
  if dir and fs.createDirectory then
    fs.createDirectory(dir)
  end
end

local function remove(fs, path)
  if fs.remove then
    fs.remove(path)
  end
end

local function decodeAt(fs, path)
  if not (fs.getInfo and fs.getInfo(path)) then
    return nil
  end
  local body = fs.read and fs.read(path)
  if type(body) ~= "string" then
    return nil
  end
  local data = SaveSerializer.decode(body)
  if not data then
    return nil
  end
  return data, body
end

local function readOpaqueAt(fs, path)
  if not (fs.getInfo and fs.getInfo(path)) then
    return nil
  end
  local body = fs.read and fs.read(path)
  if type(body) ~= "string" then
    return nil
  end
  return body
end

local function hasAny(fs, paths)
  for _, path in ipairs(paths) do
    if fs.getInfo(path) then
      return true
    end
  end
  return false
end

function Storage.new(modId, fs)
  assert(validSegment(modId), "Storage.new needs a safe mod id")
  return setmetatable({ modId = modId, injectedFs = fs }, Storage)
end

function Storage:_scope(game)
  local save = game and game.save
  local meta = save and save.meta
  local version = save and save.version
  if not (save and validSegment(version)) then
    return failure("not_in_playthrough", "Storage is available only inside an identified playthrough.")
  end
  local fs = SaveData.persistenceFs(self.injectedFs)
  if not (fs and fs.read and fs.write and fs.getInfo) then
    return failure("storage_unavailable", "The persistence backend is unavailable.")
  end
  local playthroughId = meta and meta.playthroughId
  if not validSegment(playthroughId) then
    playthroughId = SaveData.ensurePlaythroughId(save, self.injectedFs)
  end
  if not validSegment(playthroughId) then
    return failure("not_in_playthrough", "Storage could not identify the active playthrough.")
  end
  local base = table.concat({ ROOT, version, playthroughId, self.modId }, "/")
  return { gameVersion = version, playthroughId = playthroughId, base = base, fs = fs }
end

local function isTitleSession(game)
  local states = game and game.stack and game.stack.states
  if type(states) ~= "table" then
    return false
  end
  for _, state in ipairs(states) do
    if type(state) == "table" and state.screenId == "TitleState" then
      return true
    end
  end
  return false
end

-- Bind this mod only to the engine-selected existing playthrough while the
-- title session is active. Unlike _scope this must never allocate an identity:
-- browsing history before the first normal SAVE is a read of durable state,
-- not the start of a New Game. The returned facade closes over its private
-- proxy game, so callers cannot substitute another playthrough id or path.
function Storage:selected(game)
  if not isTitleSession(game) then
    return failure("not_at_title", "Selected playthrough storage is available only from the title session.")
  end
  local save = game and game.save
  local version = save and save.version
  if not validSegment(version) then
    return failure("not_in_playthrough", "The title session has no selected game version.")
  end
  local playthroughId, code, message = SaveData.selectedPlaythroughId(save, self.injectedFs)
  if not validSegment(playthroughId) then
    return failure(code, message)
  end

  local selectedGame = {
    save = { version = version, meta = { playthroughId = playthroughId } },
  }
  local context = {
    engineVersion = Version.engine,
    gameVersion = version,
    playthroughId = playthroughId,
  }
  local normal = SaveData.selectedNormalSaveInfo(save, self.injectedFs)
  if type(normal) == "table" and normal.savedAt ~= nil then
    context.normalSavedAt = normal.savedAt
  end
  return {
    context = function()
      local copy = {
        engineVersion = context.engineVersion,
        gameVersion = context.gameVersion,
        playthroughId = context.playthroughId,
      }
      if context.normalSavedAt ~= nil then
        copy.normalSavedAt = context.normalSavedAt
      end
      return copy
    end,
    read = function(_, key)
      return self:read(selectedGame, key)
    end,
    write = function(_, key, value)
      return self:write(selectedGame, key, value)
    end,
    readBytes = function(_, key)
      return self:readBytes(selectedGame, key)
    end,
    writeBytes = function(_, key, bytes)
      return self:writeBytes(selectedGame, key, bytes)
    end,
    list = function(_, prefix)
      return self:list(selectedGame, prefix)
    end,
    delete = function(_, key)
      return self:delete(selectedGame, key)
    end,
  }
end

function Storage:context(game)
  local scope, code, message = self:_scope(game)
  if not scope then
    return nil, code, message
  end
  return {
    engineVersion = Version.engine,
    gameVersion = scope.gameVersion,
    playthroughId = scope.playthroughId,
  }
end

function Storage:_names(game, key, allowEmpty, extension)
  if not validKey(key, allowEmpty) then
    return failure(
      "invalid_key",
      "Storage keys use nonempty letters, numbers, underscore, dash and slash segments."
    )
  end
  local scope, code, message = self:_scope(game)
  if not scope then
    return nil, code, message
  end
  local path = scope.base .. (key ~= "" and ("/" .. key) or "")
  extension = extension or ".lua"
  return scope, path .. extension, path .. extension .. ".bak", path .. extension .. ".tmp", path
end

function Storage:write(game, key, value)
  local scope, main, bak, tmp, path = self:_names(game, key, false)
  if not scope then
    return false, main, bak
  end
  local fs = scope.fs
  if hasAny(fs, { path .. ".bin", path .. ".bin.bak", path .. ".bin.tmp" }) then
    return false, "type_conflict", "A byte value already exists for this storage key; delete it first."
  end
  if type(value) ~= "table" then
    return false, "encode_failed", "Storage values must be data-only tables."
  end
  local encodedOk, encoded = pcall(SaveSerializer.encode, value)
  if not encodedOk then
    return false, "encode_failed", "Storage value is not serializable data: " .. tostring(encoded)
  end

  ensureParent(fs, main)
  local _, previous = decodeAt(fs, main)
  if not previous then
    _, previous = decodeAt(fs, bak)
  end

  local ok, err = fs.write(tmp, encoded)
  if not ok then
    return false, "write_failed", "Could not stage storage data: " .. tostring(err)
  end
  local staged = decodeAt(fs, tmp)
  if not staged then
    remove(fs, tmp)
    return false, "verify_failed", "Staged storage data could not be verified."
  end

  if previous then
    fs.write(bak, previous)
  end
  ok, err = fs.write(main, encoded)
  if not ok then
    remove(fs, tmp)
    return false, "write_failed", "Could not replace storage data: " .. tostring(err)
  end
  local verified = decodeAt(fs, main)
  if not verified then
    remove(fs, main)
    remove(fs, tmp)
    return false, "verify_failed", "Replacement storage data could not be verified."
  end

  -- At rest both main and backup hold the newest verified record. If a later
  -- write dies after rolling this copy aside, one verified generation remains.
  fs.write(bak, encoded)
  remove(fs, tmp)
  return true
end

function Storage:read(game, key)
  local scope, main, bak, tmp, path = self:_names(game, key, false)
  if not scope then
    return nil, main, bak
  end
  local fs = scope.fs
  if hasAny(fs, { path .. ".bin", path .. ".bin.bak", path .. ".bin.tmp" }) then
    return failure("type_mismatch", "This storage key contains opaque bytes; use readBytes instead.")
  end
  local data, body = decodeAt(fs, main)
  if data then
    return data
  end

  data, body = decodeAt(fs, tmp)
  if not data then
    data, body = decodeAt(fs, bak)
  end
  if not data then
    return nil, "not_found", "No valid stored value exists for this key."
  end

  -- Best-effort healing. The recovered copy remains in tmp/bak if promotion
  -- cannot land, so returning it is still safe and the next read can retry.
  ensureParent(fs, main)
  if fs.write(main, body) then
    fs.write(bak, body)
  end
  remove(fs, tmp)
  return data
end

function Storage:writeBytes(game, key, bytes)
  local scope, main, bak, tmp, path = self:_names(game, key, false, ".bin")
  if not scope then
    return false, main, bak
  end
  if type(bytes) ~= "string" then
    return false, "invalid_bytes", "Opaque storage values must be strings."
  end
  if #bytes > Storage.MAX_BYTES then
    return false, "size_limit", ("Opaque storage values cannot exceed %d bytes."):format(Storage.MAX_BYTES)
  end

  local fs = scope.fs
  if hasAny(fs, { path .. ".lua", path .. ".lua.bak", path .. ".lua.tmp" }) then
    return false, "type_conflict", "A table value already exists for this storage key; delete it first."
  end

  ensureParent(fs, main)
  local previous = readOpaqueAt(fs, main)
  if previous == nil then
    previous = readOpaqueAt(fs, bak)
  end

  local ok, err = fs.write(tmp, bytes)
  if not ok then
    return false, "write_failed", "Could not stage opaque storage data: " .. tostring(err)
  end
  local staged = readOpaqueAt(fs, tmp)
  if staged == nil or staged ~= bytes then
    remove(fs, tmp)
    return false, "verify_failed", "Staged opaque storage data could not be verified."
  end

  if previous ~= nil then
    fs.write(bak, previous)
  end
  ok, err = fs.write(main, bytes)
  if not ok then
    remove(fs, tmp)
    return false, "write_failed", "Could not replace opaque storage data: " .. tostring(err)
  end
  local verified = readOpaqueAt(fs, main)
  if verified == nil or verified ~= bytes then
    remove(fs, main)
    remove(fs, tmp)
    return false, "verify_failed", "Replacement opaque storage data could not be verified."
  end

  fs.write(bak, bytes)
  remove(fs, tmp)
  return true
end

function Storage:readBytes(game, key)
  local scope, main, bak, tmp, path = self:_names(game, key, false, ".bin")
  if not scope then
    return nil, main, bak
  end
  local fs = scope.fs
  if hasAny(fs, { path .. ".lua", path .. ".lua.bak", path .. ".lua.tmp" }) then
    return failure("type_mismatch", "This storage key contains table data; use read instead.")
  end

  local bytes = readOpaqueAt(fs, main)
  if bytes ~= nil then
    return bytes
  end
  bytes = readOpaqueAt(fs, tmp)
  if bytes == nil then
    bytes = readOpaqueAt(fs, bak)
  end
  if bytes == nil then
    return nil, "not_found", "No valid opaque value exists for this key."
  end

  ensureParent(fs, main)
  if fs.write(main, bytes) then
    fs.write(bak, bytes)
  end
  remove(fs, tmp)
  return bytes
end

function Storage:list(game, prefix)
  prefix = prefix or ""
  local scope, main, codeOrBak = self:_names(game, prefix, true)
  if not scope then
    return nil, main, codeOrBak
  end
  local fs = scope.fs
  if not fs.getDirectoryItems then
    return nil, "storage_unavailable", "The persistence backend cannot enumerate keys."
  end

  local base = scope.base
  local start = prefix == "" and base or (base .. "/" .. prefix)
  local out, seen = {}, {}

  local function add(logical)
    if not seen[logical] then
      seen[logical] = true
      out[#out + 1] = logical
    end
  end

  local function walk(path, logical)
    local info = fs.getInfo(path)
    if not info then
      return
    end
    if info.type == "file" then
      local suffix = path:sub(-4)
      if suffix == ".lua" or suffix == ".bin" then
        add(logical:sub(1, -5))
      end
      return
    end
    for _, child in ipairs(fs.getDirectoryItems(path) or {}) do
      local childLogical = logical == "" and child or (logical .. "/" .. child)
      walk(path .. "/" .. child, childLogical)
    end
  end

  -- A prefix may identify one exact key or a directory of keys.
  if fs.getInfo(start .. ".lua") then
    add(prefix)
  elseif fs.getInfo(start .. ".bin") then
    add(prefix)
  else
    walk(start, prefix)
  end
  table.sort(out)
  return out
end

function Storage:delete(game, key)
  local scope, main, bak, tmp, path = self:_names(game, key, false)
  if not scope then
    return false, main, bak
  end
  local fs = scope.fs
  local byteMain, byteBak, byteTmp = path .. ".bin", path .. ".bin.bak", path .. ".bin.tmp"
  if
    not (
      fs.getInfo(main)
      or fs.getInfo(bak)
      or fs.getInfo(tmp)
      or fs.getInfo(byteMain)
      or fs.getInfo(byteBak)
      or fs.getInfo(byteTmp)
    )
  then
    return false, "not_found", "No stored value exists for this key."
  end
  remove(fs, main)
  remove(fs, bak)
  remove(fs, tmp)
  remove(fs, byteMain)
  remove(fs, byteBak)
  remove(fs, byteTmp)
  return true
end

return Storage
