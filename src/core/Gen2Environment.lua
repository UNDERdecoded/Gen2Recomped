-- Public GSC environment names and their native header bytes. Keep both:
-- renderers consume names; scripts, items and movement consume ROM values.
local Environment = {}
local names = { "TOWN", "ROUTE", "INDOOR", "CAVE", "ENVIRONMENT_5", "GATE", "DUNGEON" }
local ids = {}
for id, name in ipairs(names) do ids[name] = id end

local function valid(value)
  return type(value) == "number" and value % 1 == 0 and names[value] and value or nil
end

function Environment.id(def)
  if type(def) ~= "table" then return nil end
  local value = def.environment
  if value == nil then return valid(def.environmentId) end
  -- An authored name is authoritative even if an older environmentId remains.
  -- Unknown names must not inherit that stale native classification.
  if type(value) == "string" then return ids[value] or valid(tonumber(value)) end
  return valid(value)
end

function Environment.publish(data)
  if not require("src.core.GameVersion").isGen2()
     or type(data and data.maps) ~= "table" then return false end
  for _, def in pairs(data.maps) do
    local id = Environment.id(def)
    if id then
      if def.environmentId == nil then def.environmentId = id end
      def.environment = names[id]
      if def.outdoor == nil then def.outdoor = id == 1 or id == 2 end
    end
  end
  return true
end

return Environment
