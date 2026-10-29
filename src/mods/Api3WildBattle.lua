-- API-3 encounter admission over native construction, transition and afterBattle.
-- Portable scripts may supply a private owned guard and native trainer plan.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Edits = require("src.mods.Api3WorldEdits")
local Ids = require("src.mods.UnifiedIds")
local Party = require("src.pokemon.Party")
local B = {}
local pending, observers = {}, setmetatable({}, { __mode = "k" })
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function text(value)
  local ok, result = pcall(tostring, value)
  return ok and result or "unprintable error"
end
local function retire(token)
  token.retired, token.callback = true, nil
  pending[token] = nil
end
function B.cancelAll(loader, owner)
  for token in pairs(pending) do
    if (not loader or loader == token.loader) and (not owner or owner == token.owner) then
      retire(token)
    end
  end
end
local function inspect(loader)
  for token in pairs(pending) do
    if token.loader == loader and not token.valid() then
      retire(token)
    end
  end
end
local function observe(loader)
  if observers[loader] == loader.hooks then
    return
  end
  observers[loader] = loader.hooks
  loader.hooks:wrap("input.step", function(nextFn, ...)
    inspect(loader)
    local result = pack(pcall(nextFn, ...))
    inspect(loader)
    if not result[1] then
      error(result[2], 0)
    end
    return unpack(result, 2, result.n)
  end, math.huge, "engine:api3_wild_battle")
end
function B.new(loader, owner, current, native, licensed, req, ownedReady, ownedNative)
  local ids = Ids.new(loader)
  observe(loader)
  return function(species, level, callback)
    if not licensed() then
      return nil, "world facade is retired"
    end
    local game = current()
    if not game then
      return nil, "no game"
    end
    local ow = native(game):overworld()
    if not ow then
      return nil, "no overworld"
    end
    local ok, reason = (ownedReady or Edits.ready)(game, ow)
    if not ok then
      return nil, reason
    end
    for token in pairs(pending) do
      if token.game == game then
        if token.valid() then
          return nil, "world is busy"
        end
        retire(token)
      end
    end
    local key, why
    if ownedNative then
      key, why = ownedNative.resolve(game, species, level)
      if not key then
        return nil, why
      end
      if callback ~= nil and type(callback) ~= "function" then
        return nil, "invalid callback"
      end
    else
      if type(species) ~= "string" or #species == 0 or #species > 256 or species:find("%c") then
        return nil, "invalid species id"
      end
      if type(level) ~= "number" or level ~= level or level < 1 or level > 100 or level % 1 ~= 0 then
        return nil, "level must be a whole number 1..100"
      end
      if callback ~= nil and type(callback) ~= "function" then
        return nil, "invalid callback"
      end
      local group, why = ids:resolve("pokemon", species)
      if not group then
        return nil, why:find("^ambiguous") and why or "unknown species: " .. species
      end
      key = group.key
      if not (game.data.pokemon and game.data.pokemon[key]) then
        return nil, "unknown species: " .. species
      end
    end
    if not Party.firstHealthy(game.save.party or {}) then
      return nil, "no healthy party"
    end
    if type(ow.pushBattle) ~= "function" or type(ow.afterBattle) ~= "function" then
      return nil, "battle runtime unavailable"
    end
    local save, data, stack, player, world = game.save, game.data, game.stack, ow.player, game.overworld
    local version, hooks, events = Version.get(), Runtime.hooks, Runtime.events
    local token = { loader = loader, owner = owner, game = game, callback = callback }
    local function live()
      return current() == game
        and game.save == save
        and game.data == data
        and game.stack == stack
        and game.overworld == world
        and ow.player == player
        and native(game):overworld() == ow
        and Version.get() == version
    end
    function token.valid()
      return not token.retired
        and licensed()
        and live()
        and Runtime.hooks == hooks
        and Runtime.events == events
    end
    local admitted, deferred, finished, battle
    local function finish(...)
      if finished then
        return
      end
      if admitted == nil then
        if not deferred then
          deferred = pack(...)
        end
        return
      end
      finished = true
      local valid, fn = token.valid(), token.callback
      retire(token)
      if not admitted or not live() then
        return
      end
      -- Native cleanup still runs after the originating mod has been unloaded.
      local outcome = (...)
      local called, err = pcall(function()
        if ownedNative and ownedNative.cleanup then
          ownedNative.cleanup(game, ow, key, outcome, battle)
        end
        ow:afterBattle(outcome, battle)
      end)
      if not called then
        Runtime.reportError(owner, "world battle cleanup failed: " .. text(err))
        if ownedReady and valid and fn then
          pcall(fn, nil, "native battle cleanup failed: " .. text(err))
        end
        return
      end
      if valid and licensed() and live() and fn then
        local previous = Runtime.currentMod
        Runtime.currentMod = owner
        called, err = pcall(fn, ...)
        Runtime.currentMod = previous
        if not called then
          Runtime.reportError(owner, "world battle callback failed: " .. text(err))
        end
      end
    end
    pending[token] = true
    local called, accepted, err = pcall(Edits.run, game, function()
      if ownedNative then
        battle = ownedNative.construct(game, key)
      else
        battle = req("src.battle.BattleState").newWild(game, key, level)
      end
      if not battle or battle.dead then
        return nil, "battle failed"
      end
      if not token.valid() or ownedReady and not ownedReady(game, ow) then
        return nil, "battle session changed"
      end
      battle.onFinish = finish
      local value, detail = ow:pushBattle(battle)
      if value == false or value == nil and detail ~= nil then
        return nil, detail or "battle failed"
      end
      return true
    end)
    admitted = called and accepted == true
    if not admitted then
      retire(token)
      return nil, called and (err or "battle failed") or "world operation failed: " .. text(accepted)
    end
    if deferred then
      finish(unpack(deferred, 1, deferred.n))
    end
    return true
  end
end
return B
