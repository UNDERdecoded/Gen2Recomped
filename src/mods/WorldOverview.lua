-- Read-only world summaries. Do not call timeOfDay(), rollTable(), map loading,
-- or object visibility refreshes here: each can change the live simulation.
local Ids = require("src.mods.UnifiedIds")
local GameVersion = require("src.core.GameVersion")
local Overview = {}

function Overview.context(loader)
  Ids.new(loader):entries("pokemon")
  return function()
    return Ids.new(loader)
  end
end

function Overview.install(api, loader)
  local context = Overview.context(loader)
  if api.supports then
    local supports = api.supports
    function api:supports(surface, name)
      if surface == "world" and (name == "mapOverview" or name == "effectiveEncounters") then
        return true
      end
      return supports(self, surface, name)
    end
  end
  return context
end

local function dataIds(data)
  local rows = data.pokemon or {}
  return Ids.new({
    content = {
      pokemon = {
        base = function()
          return rows
        end,
        each = function()
          return pairs(rows)
        end,
      },
    },
  })
end

local periods = { MORN = "MORNING", MORNING = "MORNING", DAY = "DAY", NITE = "NITE", NIGHT = "NITE" }
local hours = { MORNING = 6, DAY = 12, NITE = 22 }

function Overview.encounters(game, ow, context, mapId, terrain, opts)
  if terrain ~= "grass" and terrain ~= "water" and terrain ~= "indoor" then
    return nil, "invalid terrain: " .. tostring(terrain)
  end
  if opts ~= nil and type(opts) ~= "table" then
    return nil, "opts must be a table"
  end
  local daytime = opts and opts.daytime
  if daytime ~= nil then
    daytime = type(daytime) == "string" and periods[daytime:upper()]
    if not daytime then
      return nil, "invalid daytime"
    end
  end
  local data = game and game.data
  if not (data and type(data.encounters) == "table") then
    return nil, "encounters data not loaded"
  end
  local def = data.maps and data.maps[mapId]
  if not def then
    return nil, "unknown map: " .. tostring(mapId)
  end
  -- HGSS's Safari table depends on the player's position in a six-area matrix.
  -- Encounter.forMap resolves it through the Game singleton and seeds Safari
  -- save state. Refuse this exceptional table instead of querying another game.
  if def.cameraFamily == "hgss" and require("src.world.HgssSafariZone").isSafariMap(def) then
    return nil, "position-dependent Safari encounters unavailable"
  end
  if GameVersion.get() == "emerald" then
    if
      require("src.script.Gen3BattlePike").inWildRoom(mapId)
      or require("src.script.Gen3BattlePyramid").onFloor(mapId)
    then
      return nil, "facility encounters unavailable"
    end
  end
  local Encounter = require("src.world.Encounter")
  local hour = daytime and hours[daytime]
  local enc = Encounter.forMap(data, def, mapId, hour, game.save)
  if not daytime then
    -- A world.tod hook's most recent effective period is already on the world.
    -- Calling it again would execute mod code and can emit/change world state.
    local Runtime = require("src.mods.Runtime")
    if Runtime.wantsHook("world.tod") and ow then
      daytime = ow.tod
    end
    if GameVersion.isGen2() then
      if not daytime then
        hour = require("src.core.Gen2Clock").hour(game.save)
        daytime = hour < 4 and "NITE" or hour < 10 and "MORNING" or hour < 18 and "DAY" or "NITE"
      end
    else
      daytime = daytime or (ow and ow.tod) or "DAY"
    end
  end
  local slots = enc and enc[terrain == "indoor" and "grass" or terrain]
  if terrain ~= "water" then
    slots = Encounter.atTime(slots, daytime)
  end
  if not slots then
    return { chance = 0, dist = {} }
  end
  local maximum = tonumber(slots.rateMax) or 256
  local rate = tonumber(slots.rate) or 0
  local span = tonumber(slots.bucketSpan) or 256
  if
    maximum <= 0
    or maximum ~= math.floor(maximum)
    or maximum == math.huge
    or rate ~= rate
    or rate == math.huge
    or rate == -math.huge
    or span <= 0
    or span ~= math.floor(span)
    or span == math.huge
  then
    return nil, "invalid encounter rate/span"
  end
  local dist, prev = {}, 0
  local weights = slots.buckets or require("src.world.FieldDefaults").constant(data, "encounterBuckets")
  if type(weights) ~= "table" or (slots.slots ~= nil and type(slots.slots) ~= "table") then
    return nil, "invalid encounter buckets/slots"
  end
  local ids = context and context() or dataIds(data)
  for i, threshold in ipairs(weights or {}) do
    if
      type(threshold) ~= "number"
      or threshold ~= math.floor(threshold)
      or threshold < prev
      or threshold > span
    then
      return nil, "invalid encounter buckets"
    end
    local slot = slots.slots and slots.slots[i]
    if rate > 0 and slot and slot.species and threshold > prev then
      local id = ids:read("pokemon", slot.species)
      if id then
        dist[id] = (dist[id] or 0) + threshold - prev
      end
    end
    prev = threshold
  end
  -- Same independent integer rate gate as rollTable, without drawing a slot.
  return { chance = math.max(0, math.min(maximum, math.ceil(rate))) / maximum, dist = dist }
end

return Overview
