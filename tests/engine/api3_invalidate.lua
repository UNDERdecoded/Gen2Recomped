package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.invalidate")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local OW = require("src.world.OverworldController")
local MapLoader = require("src.world.MapLoader")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared invalidation contract: " .. tostring(why))
end
for _, lock in ipairs({ "overlay", "moving", "script", "parallel", "link", "transition", "no_save" }) do
  local f = fixture()
  if lock == "overlay" then
    f.game.stack.states[2] = {}
  elseif lock == "moving" then
    f.player.moving = true
  elseif lock == "script" then
    f.ow.runner.isRunning = function()
      return true
    end
  elseif lock == "parallel" then
    f.ow.parallelQueue = { {} }
  elseif lock == "link" then
    f.game.linkSession = {}
  elseif lock == "transition" then
    f.ow.transitioning = true
  else
    f.game.save = nil
  end
  T.eq(f.exports.request(f.home), nil, lock .. " refuses reload")
  T.eq(f.reloads, 0, lock .. " has no native effects")
end
for _, bad in ipairs({ {}, 1, 0 / 0, math.huge, false, string.rep("x", 257), "bad\0id" }) do
  local f = fixture()
  T.eq(f.exports.request(bad), nil, "malformed ID refused")
  T.eq(f.reloads, 0, "malformed ID not dispatched")
end
do
  local f = fixture()
  f.reloadError = true
  T.eq(f.exports.request(f.home), nil, "native failure returns refusal")
  T.eq(#f.exports.events(), 0, "failed reload emits no success event")
  f.reloadError = false
  T.check(f.exports.request(f.home), "native exception releases guard")
  local native = f.ow.reloadMap
  function f.ow:reloadMap(...)
    local value, why = f.exports.request(f.home)
    T.eq(value, nil, "native callback cannot reenter")
    T.eq(why, "world is busy", "reload reentry diagnosed")
    return native(self, ...)
  end
  T.check(f.exports.request(f.home), "outer reload accepted")
end
for _, action in ipairs({ "rollback", "reload", "teardown" }) do
  local f = fixture()
  if action == "rollback" then
    f.loader:_rollback("invalidate")
  elseif action == "reload" then
    fixture()
  else
    Loader.teardown()
  end
  T.eq(f.exports.request(f.home), nil, "retired facade refuses after " .. action)
  T.eq(f.reloads, 0, "retired facade makes no native calls")
end
local function upvalue(fn, wanted)
  for i = 1, 100 do
    local name, value = debug.getupvalue(fn, i)
    if name == wanted then
      return value, i
    end
    if not name then
      break
    end
  end
  error("native upvalue missing: " .. wanted)
end
for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  for _, outside in ipairs({ false, true }) do
    local f = fixture(version)
    local old, index = upvalue(OW.reloadMap, "Game")
    debug.setupvalue(OW.reloadMap, index, f.game)
    f.ow.reloadMap = OW.reloadMap
    f.ow.neighbors = { { map = { id = f.dest } } }
    local cache = upvalue(MapLoader.invalidate, "cache")
    cache[f.home], cache[f.dest] = {}, {}
    local loads = {}
    function f.ow:setMap(id, x, y, facing, opts)
      loads[#loads + 1] = { id = id, x = x, y = y, facing = facing, opts = opts }
      self.map = {
        id = id,
        def = f.game.data.maps[id],
        inBounds = function()
          return not outside
        end,
      }
    end
    function f.ow:healPoint()
      return { map = f.dest, x = 1, y = 2 }
    end
    T.check(f.exports.request(f.home), "native reload accepted")
    T.eq(cache[f.home], nil, "native target cache evicted")
    T.eq(cache[f.dest], nil, "native neighbor cache evicted")
    T.eq(loads[1].x, 0, "native reload preserves x")
    T.eq(loads[1].facing, "left", "native reload preserves facing")
    T.eq(loads[1].opts.keepMusic, true, "native seamless reload keeps music")
    T.eq(loads[1].opts.seamless, true, "native seamless reload selected")
    T.eq(#loads, outside and 2 or 1, "native out-of-bounds fallback count")
    if outside then
      T.eq(loads[2].id, f.dest, "invalidated geometry uses heal map")
      T.eq(loads[2].facing, "down", "heal fallback orientation")
    end
    T.eq(#f.exports.events(), 1, "one native reload notification")
    debug.setupvalue(OW.reloadMap, index, old)
  end
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("API 3 map invalidation")
