-- Portable references mapped to the flag stores the host VM/save converter use.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local F = {}
local catalogs, writing = {}, setmetatable({}, { __mode = "k" })
local function integer(value, minimum, maximum)
  return type(value) == "number"
    and value == value
    and value % 1 == 0
    and value >= minimum
    and value <= maximum
end
local function identifier(value)
  return type(value) == "string" and #value > 0 and #value <= 256 and not value:find("%c")
end
local function catalog(version)
  local key = version == "blue" and "red" or version
  if catalogs[key] then
    return catalogs[key]
  end
  local data = require("src.mods.flag_names." .. key)
  local out = { names = {}, ids = {}, limit = data.limit }
  for id, row in pairs(data.records) do
    if row[1] then
      out.names[id] = row[1]
    end
    for _, name in ipairs(row) do
      if name then
        out.ids[name] = id
      end
    end
  end
  catalogs[key] = out
  return out
end
function F.resolve(generation, version, name)
  local supported = ({
    red = 1,
    blue = 1,
    yellow = 1,
    gold = 2,
    silver = 2,
    crystal = 2,
    firered = 3,
    emerald = 3,
  })[version]
  if supported ~= generation then
    return nil, "native flag mapping unavailable for selected version"
  end
  if generation == 1 then
    local t = catalog(version)
    local id = integer(name, 0, 65535) and name or identifier(name) and t.ids[name]
    if id ~= nil and t.names[id] then
      return t.names[id], t.names[id], id
    end
  elseif generation == 2 then
    local native = require("src.script.Gen2Flags")
    local id = name
    if identifier(name) then
      if version == "crystal" then
        return nil, "symbolic event flags unavailable for Crystal; use native ids"
      end
      id = native.EVENT_FLAG_INDEX[name]
    end
    if integer(id, 0, 2047) then
      return native.eventFlag(id), id, id
    end
  elseif generation == 3 then
    local t = catalog(version)
    local id
    if type(name) == "number" then
      if integer(name, 1, t.limit - 1) and t.names[name] then
        id = name
      end
    elseif identifier(name) then
      id = t.ids[name]
    end
    if id and integer(id, 1, t.limit - 1) then
      return ("FLAG_G3_%04X"):format(id), t.names[id] or id, id
    end
  end
  return nil, "invalid or unknown flag"
end
-- Resolve without a Game/save for whole-program script preflight.
function F.address(owner, gen, version, name)
  local key
  if type(name) == "string" then
    if name:sub(1, 4) == "mod:" then
      key = name:sub(5)
    elseif name:sub(1, 4) == "mod." then
      local prefix = "mod." .. owner .. "."
      if name:sub(1, #prefix) ~= prefix then
        return nil, "foreign mod flag"
      end
      key = name:sub(#prefix + 1)
    end
  end
  if key then
    if not identifier(key) then
      return nil, "invalid mod flag"
    end
    return { kind = "mod", key = key }
  end
  local storage, public, number = F.resolve(gen, version, name)
  if not storage then
    return nil, public
  end
  return { kind = "native", key = storage, public = public, number = number }
end
function F.call(game, owner, gen, name, value, write, licensed, overworld)
  if write and not licensed() then
    return nil, "world facade is retired"
  end
  if write and type(value) ~= "boolean" then
    return nil, "flag value must be boolean"
  end
  local save = game.save
  if not save then
    return nil, "no save"
  end
  local address, reason = F.address(owner, gen, Version.get(), name)
  if not address then
    return nil, reason
  end
  if address.kind == "mod" then
    local key = address.key
    local store = save.modData
    if store ~= nil and type(store) ~= "table" then
      return nil, "invalid mod save store"
    end
    local bucket = store and store[owner]
    if bucket ~= nil and type(bucket) ~= "table" then
      return nil, "invalid mod save store"
    end
    local flags = bucket and bucket.worldFlags
    if flags ~= nil and type(flags) ~= "table" then
      return nil, "invalid mod flag store"
    end
    if not write then
      return flags ~= nil and flags[key] == true
    end
    if writing[save] then
      return nil, "world is busy"
    end
    local before = flags ~= nil and flags[key] == true
    save.modData = store or {}
    bucket = bucket or {}
    save.modData[owner] = bucket
    bucket.worldFlags = flags or {}
    bucket.worldFlags[key] = value or nil
    if before ~= value then
      writing[save] = true
      local ok, err =
        pcall(Runtime.emit, "flag.changed", { name = "mod." .. owner .. "." .. key, value = value })
      writing[save] = nil
      if not ok then
        error(err, 0)
      end
    end
    return true
  end
  local storage, public, number = address.key, address.public, address.number
  if type(save.flags) ~= "table" then
    return nil, "invalid flag store"
  end
  if not write then
    return save.flags[storage] == true
  end
  if writing[save] then
    return nil, "world is busy"
  end
  writing[save] = true
  local ok, err = pcall(function()
    local before = save.flags[storage] == true
    -- Native clear keeps false: visibility distinguishes cleared from untouched.
    save.flags[storage] = value
    if gen == 3 then
      local ow = overworld(game)
      if ow and ow.syncObjectVisibility then
        for _, object in ipairs(ow.map and ow.map.def and ow.map.def.objects or {}) do
          if object.eventFlag == storage then
            ow:syncObjectVisibility(object)
          end
        end
      end
    end
    if before ~= value then
      local event = { name = public, value = value }
      if gen == 3 then
        event.id = number
      end
      Runtime.emit("flag.changed", event)
    end
  end)
  writing[save] = nil
  if not ok then
    error(err, 0)
  end
  return true
end
return F
