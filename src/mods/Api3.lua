-- API-3 entry over the existing native adapters. Unsupported operations have
-- callable handles but never delegate to a native method with a different contract.
local Records = require("src.mods.Api3Records")
local Runtime = require("src.mods.Runtime")
local Warp = require("src.mods.Api3Warp")
local Edits = require("src.mods.Api3WorldEdits")
local NPC = require("src.mods.Api3NPC")
local Wild = require("src.mods.Api3WildBattle")
local Flags = require("src.mods.Api3Flags")
local copy = require("src.mods.Merge").deepCopy
local A = {}
local WORLD = [[overworld current activeBlockAt party canReorderParty reorderParty
 availableFieldActions useFieldAction canFly flyTo mapOverview warpTo toggleObject
 setFlag getFlag effectiveEncounters replaceBlock spawnNpc liveMaps removeNpc npc
 queueScript startWildBattle invalidateMap]]
local SUPPORTED = {}
for name in
  ([[overworld current activeBlockAt party canReorderParty reorderParty
 availableFieldActions useFieldAction canFly flyTo mapOverview effectiveEncounters
 setFlag getFlag liveMaps queueScript warpTo toggleObject replaceBlock spawnNpc removeNpc npc startWildBattle invalidateMap]]):gmatch(
    "%S+"
  )
do
  SUPPORTED[name] = true
end
local function pack(...)
  return { n = select("#", ...), ... }
end
local unpack = table.unpack or unpack
local function block(gen)
  return {
    tileSize = gen == 3 and 16 or 32,
    cellSize = 16,
    coordinateBase = 0,
    kind = gen == 3 and "metatile" or "block",
  }
end
function A.install(api, loader, readContext, overviewContext, engineRequire, engineCall)
  local gen = api.generation
  local supportedGeneration = gen >= 1 and gen <= 3
  -- Passthrough registries keep native shapes but expose the same handle metadata.
  for name, entry in pairs(api.content) do
    local handle = entry
    if type(handle) == "table" and handle.supports == nil then
      local available, reason = api:supports("content", name)
      handle.available = available
      local get, each = handle.get, handle.each
      if get then
        handle.get = function(self, id)
          local value, why = get(self, id)
          return copy(value), why
        end
      end
      if each then
        handle.each = function(self)
          local iter, state, key = each(self)
          return function()
            local id, value = iter(state, key)
            key = id
            return id, copy(value)
          end
        end
      end
      handle.supports = function()
        return available, reason
      end
    end
    if type(handle) == "table" and handle.has == nil and handle.get then
      handle.has = function(_, id)
        return handle:get(id) ~= nil
      end
    end
  end
  local scripts = api.world -- PortableScripts owns the per-loader/session queue.
  local world = {}
  local nativeGame, nativeWorld
  local function current()
    return loader:_game(true) -- Never bootstrap Game for an observational early call.
  end
  local function native(game)
    if game ~= nativeGame then
      nativeWorld = engineRequire("src.world.WorldAPI").new(game, api.id, readContext)
      nativeWorld.overviewContext = overviewContext
      nativeGame = game
    end
    return nativeWorld
  end
  local warp, licensed, npc, wild
  if supportedGeneration then
    warp, licensed = Warp.new(loader, api.id, gen, current, native)
    npc = NPC.new(loader, api.id, gen, current, native, licensed, engineRequire)
    wild = Wild.new(loader, api.id, current, native, licensed, engineRequire)
  end
  local function dispatch(name, ...)
    if not supportedGeneration or not SUPPORTED[name] then
      return nil, "unsupported: API 3 world method " .. name
    end
    if name == "spawnNpc" or name == "removeNpc" or name == "npc" then
      return npc(name, ...)
    end
    if name == "startWildBattle" then
      return wild(...)
    end
    if name == "warpTo" then
      return warp(...)
    end
    local edit = name == "toggleObject" or name == "replaceBlock" or name == "invalidateMap"
    if edit and not licensed() then
      return nil, "world facade is retired"
    end
    local game = current()
    if not game then
      return nil, "no game"
    end
    if edit then
      return Edits.call(game, native(game), gen, engineRequire, name, ...)
    end
    if name == "setFlag" or name == "getFlag" then
      local key, value = ...
      return Flags.call(game, api.id, gen, key, value, name == "setFlag", licensed, function(live)
        return native(live):overworld()
      end)
    end
    if name == "queueScript" then
      return scripts:queueScript(...)
    end
    local raw = native(game)
    local result = pack(raw[name](raw, ...))
    if name == "party" and type(result[1]) == "table" then
      for _, mon in ipairs(result[1]) do
        Records.mon(mon, game.data, gen)
      end
    elseif (name == "current" or name == "mapOverview") and type(result[1]) == "table" then
      result[1].block = block(gen)
    end
    return unpack(result, 1, result.n)
  end
  for name in WORLD:gmatch("%S+") do
    local method = name
    world[method] = function(_, ...)
      local owner = Runtime.currentMod
      Runtime.currentMod = nil
      local values = pack(pcall(dispatch, method, ...))
      Runtime.currentMod = owner
      if not values[1] then
        return nil, "world operation failed: " .. tostring(values[2])
      end
      return unpack(values, 2, values.n)
    end
  end
  api.world = world
  local battle = api.battle
  api.battle = {
    snapshot = function()
      local snapshot, why = battle:snapshot()
      if not snapshot then
        return nil, why
      end
      local game = current()
      local data = game and game.data
      Records.mon(snapshot.player, data, gen)
      Records.mon(snapshot.enemy, data, gen)
      for _, name in ipairs({ "party", "battlers" }) do
        for _, mon in ipairs(snapshot[name] or {}) do
          Records.mon(mon, data, gen)
        end
      end
      return snapshot
    end,
    submit = function(_, ...)
      return battle:submit(...)
    end,
  }
  api.datasets = {
    open = function(_, version)
      if not loader.datasetViews then
        local Views = engineRequire("src.mods.DatasetViews")
        loader.datasetViews = Views.new(loader.fs, engineRequire, engineCall)
      end
      return loader.datasetViews:open(version)
    end,
  }
  local supports = api.supports
  function api:supports(surface, name)
    if surface == "world" then
      if supportedGeneration and SUPPORTED[name] then
        return true
      end
      return false, "unsupported: API 3 world method " .. tostring(name)
    end
    return supports(self, surface, name)
  end
end
return A
