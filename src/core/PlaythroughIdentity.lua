-- Opaque storage identity. Never consumes gameplay RNG or rewrites progress
-- merely because a mod requests a namespace. Slot routing is engine-owned.
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local copy = require("src.mods.Merge").deepCopy
local M = {}
local fresh = setmetatable({}, { __mode = "k" })
local sequence = 0
local function saves()
  return require("src.core.SaveData")
end
local function valid(id)
  return type(id) == "string" and id:match("^[%w_-]+$") ~= nil
end
function M.markFresh(save)
  if type(save) == "table" then
    fresh[save] = true
  end
end
function M.newId()
  sequence = sequence + 1
  local address = tostring({}):match("0x(%x+)") or "0"
  local function word(n)
    return math.floor(tonumber(n) or 0) % 4294967296
  end
  return ("%08x%08x%08x%08x"):format(
    word(os.time()),
    word(os.clock() * 1000000),
    word(tonumber(address:sub(-8), 16)),
    word(sequence)
  )
end
local function routing(version, fs)
  local opts = saves().loadOptions(fs)
  local reg = opts.saveSlots and opts.saveSlots[version]
  local slot = saves()._storageSlot(version, fs)
    or (reg and (reg.active or (reg.list and reg.list[1])))
    or "legacy"
  if not valid(slot) then
    slot = "legacy"
  end
  local ids = opts.playthroughIds and opts.playthroughIds[version]
  return opts, slot, ids and ids[slot]
end
local function normalSave(version, slot, fs)
  local main = slot == "legacy" and ("save" .. Version.saveSuffix(version) .. ".lua")
    or ("saves/" .. version .. "/" .. slot .. ".lua")
  for _, path in ipairs({ main, main .. ".tmp", main .. ".bak" }) do
    local body = fs.read(path)
    local data = type(body) == "string" and Serializer.decode(body)
    if type(data) == "table" and data.version == version then
      return data
    end
  end
end
local function bind(opts, version, slot, id, fs)
  opts.playthroughIds = opts.playthroughIds or {}
  opts.playthroughIds[version] = opts.playthroughIds[version] or {}
  if opts.playthroughIds[version][slot] == id then
    return true
  end
  opts.playthroughIds[version][slot] = id
  return saves().saveOptions(opts, fs) ~= nil
end
function M.ensure(save, fs)
  if type(save) ~= "table" or not Version.info(save.version) then
    return nil
  end
  save.meta = type(save.meta) == "table" and save.meta or {}
  if valid(save.meta.playthroughId) then
    return save.meta.playthroughId
  end
  local opts, slot, mapped = routing(save.version, fs)
  local id = not fresh[save] and valid(mapped) and mapped or M.newId()
  -- Boot/New Game skeletons must not strand an already-bound real save.
  if not (fresh[save] and valid(mapped)) and not bind(opts, save.version, slot, id, fs) then
    return nil
  end
  save.meta.playthroughId = id
  return id
end
function M.inherit(save, fs)
  if type(save) ~= "table" or fresh[save] or not Version.info(save.version) then
    return
  end
  if save.meta and valid(save.meta.playthroughId) then
    return
  end
  local _, _, id = routing(save.version, fs)
  if valid(id) then
    save.meta = type(save.meta) == "table" and save.meta or {}
    save.meta.playthroughId = id
  end
end
function M.selected(save, fs)
  if type(save) ~= "table" then
    return nil, "not_in_playthrough", "No selected playthrough is available."
  end
  if not Version.info(save.version) then
    return nil, "unknown_game", "The selected game version is unavailable."
  end
  local id = save.meta and save.meta.playthroughId
  if not fresh[save] and valid(id) then
    return id
  end
  local _, slot, mapped = routing(save.version, fs)
  -- A committed normal save is authoritative even if its options update
  -- failed, or the registry was recovered from an older backup.
  local normal = normalSave(save.version, slot, fs)
  local stamped = normal and normal.meta and normal.meta.playthroughId
  if valid(stamped) then
    return stamped
  end
  if valid(mapped) then
    return mapped
  end
  return nil, "no_selected_playthrough", "The selected playthrough has no durable tool state."
end
function M.remember(save, fs, slot, version)
  local id = save.meta and save.meta.playthroughId
  if not valid(id) then
    fresh[save] = nil
    return true
  end
  version = version or save.version
  local opts, active = routing(version, fs)
  local ok = bind(opts, version, slot or active, id, fs)
  if ok then
    fresh[save] = nil
    if save.options then
      save.options.playthroughIds = copy(opts.playthroughIds)
    end
  end
  return ok
end
function M.preserveOptions(opts, fs)
  local stored = saves().loadOptions(fs)
  -- A live options snapshot can predate lazy legacy-to-slot promotion.
  opts.playthroughIds = copy(stored.playthroughIds)
  opts.saveSlots = copy(stored.saveSlots)
end
function M.prepareSlot(save, version, slot, fs)
  local id = save.meta and save.meta.playthroughId
  if not valid(id) then
    return save
  end
  local opts = saves().loadOptions(fs)
  local ids = opts.playthroughIds and opts.playthroughIds[version]
  local collision = false
  for other, used in pairs(ids or {}) do
    if other ~= slot and used == id then
      collision = true
    end
  end
  local reg = opts.saveSlots and opts.saveSlots[version]
  for _, other in ipairs(reg and reg.list or {}) do
    if other ~= slot then
      local base = "saves/" .. version .. "/" .. other .. ".lua"
      for _, path in ipairs({ base, base .. ".tmp", base .. ".bak" }) do
        local bytes = fs.read(path)
        local data = type(bytes) == "string" and Serializer.decode(bytes)
        if type(data) == "table" and data.meta and data.meta.playthroughId == id then
          collision = true
        end
      end
    end
  end
  if collision then
    save = copy(save)
    save.meta.playthroughId = M.newId()
  end
  return save
end
function M.normalInfo(save, fs)
  local id, code, message = M.selected(save, fs)
  if not id then
    return nil, code, message
  end
  local _, slot = routing(save.version, fs)
  local normal = normalSave(save.version, slot, fs)
  if
    not normal
    or normal.version ~= save.version
    or (normal.meta and normal.meta.playthroughId and normal.meta.playthroughId ~= id)
  then
    return { exists = false }
  end
  local at = normal.meta and normal.meta.savedAt
  if type(at) ~= "number" or at < 0 or at ~= at or at == math.huge then
    at = nil
  end
  return { exists = true, savedAt = at }
end
return M
