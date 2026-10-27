-- Semantic behavior IDs for compatibility views. Native behavior bytes stay
-- native; callers explicitly select the cartridge before translating a byte.
local data = require("src.compat.gen1.MetatileNames")
local Behavior = { RSE_BASE = 256 }
Behavior.RENAMES = { NO_RUNNING = "RUNNING_DISALLOWED", NO_SURFACING = "UNDERWATER_BLOCKED_ABOVE",
  NON_ANIMATED_DOOR = "CAVE_DOOR", ANIMATED_DOOR = "WARP_DOOR" }
for name, id in pairs(data.ids) do Behavior[name] = id end
local function nameKey(name)
  return type(name) == "string" and (name:gsub("^MB_", "")) or nil
end
function Behavior.id(name) return data.ids[nameKey(name)] end
function Behavior.require(name)
  local id = Behavior.id(name)
  if id == nil then error("mb: unknown metatile behavior '" .. tostring(name) .. "'", 2) end
  return id
end
function Behavior.nameOf(id) return data.names[tonumber(id) or -1] end
function Behavior.isRseOnly(id) id = tonumber(id); return id ~= nil and id >= Behavior.RSE_BASE end
function Behavior.all()
  local out = {}; for name, id in pairs(data.ids) do out[name] = id end; return out
end
local converters = {}
function Behavior.translator(game)
  local values = data.translations[game]
  if not values then return nil end
  if converters[game] then return converters[game] end
  local reverse = {}
  for raw = 0, 255 do
    local id = values[raw + 1]
    if reverse[id] == nil then reverse[id] = raw end
  end
  local t = { game = game }
  function t.canon(raw) return values[(tonumber(raw) or 0) % 256 + 1] end
  function t.raw(id) return reverse[tonumber(id) or -1] end
  function t.table()
    local out = {}; for raw = 0, 255 do out[raw] = values[raw + 1] end; return out
  end
  if data.sourceNames[game] then
    function t.sourceName(id)
      local raw = t.raw(id)
      return raw and data.sourceNames[game][raw] or nil
    end
  end
  converters[game] = t
  return t
end
function Behavior.fromRaw(game, raw)
  local converter = Behavior.translator(game)
  if converter then return converter.canon(raw) end
  return raw
end
return Behavior
