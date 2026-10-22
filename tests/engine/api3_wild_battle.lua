package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.wild_battle")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Loader = require("src.mods.Loader")
local Battle = require("src.battle.BattleState")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared battle contract: " .. tostring(why))
end
for _, level in ipairs({ -1, 0, 1.5, 101, math.huge, 0 / 0, "5", false, {} }) do
  local f = fixture()
  T.eq(f.exports.request("MEW", level), nil, "invalid level refused")
  T.eq(f.constructed, 0, "invalid level never constructs/marks seen")
  f.restore()
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
  T.eq(f.exports.request("MEW", 5), nil, lock .. " blocks battle")
  T.eq(f.constructed, 0, lock .. " leaves dex/RNG untouched")
  f.restore()
end
for _, change in ipairs({ "game", "save", "data", "stack", "world", "player", "version", "bus" }) do
  local f = fixture()
  T.check(f.exports.request("MEW", 5, f.exports.notify), "start before " .. change)
  local restore
  if change == "game" then
    f.live = {}
    restore = function()
      f.live = f.game
    end
  elseif change == "world" then
    f.game.overworld = {}
    restore = function()
      f.game.overworld = f.ow
    end
  elseif change == "version" then
    Version.set("blue")
    restore = function()
      Version.set("red")
    end
  elseif change == "bus" then
    local old = Runtime.events
    Runtime.events = {}
    restore = function()
      Runtime.events = old
    end
  else
    local object = change == "player" and f.ow or f.game
    local old = object[change]
    object[change] = {}
    restore = function()
      object[change] = old
    end
  end
  f.loader.hooks:call("input.step", function() end)
  restore()
  f:complete("win")
  T.eq(f.exports.result().calls, 0, "observed replacement permanently retires callback")
  T.eq(f.after, 1, "restored native session still completes cleanup")
  f.restore()
end
for _, action in ipairs({ "rollback", "reload", "teardown" }) do
  local f = fixture()
  T.check(f.exports.request("MEW", 5, f.exports.notify), "start before " .. action)
  if action == "rollback" then
    f.loader:_rollback("wild_battle")
  elseif action == "reload" then
    local nextFixture = fixture()
    nextFixture.restore()
  else
    Loader.teardown()
  end
  f:complete("caught")
  T.eq(f.after, 1, "unloading mod preserves native cleanup")
  T.eq(f.exports.result().calls, 0, "unloading retires callback")
  T.eq(f.exports.request("MEW", 5), nil, "unloaded facade retired")
  f.restore()
end
do
  local f = fixture()
  T.check(f.exports.request("MEW", 5, f.exports.notify), "start before foreign save")
  f.game.save = {}
  f:complete("lose")
  T.eq(f.after, 0, "late result cannot run cleanup against replaced save")
  T.eq(f.exports.result().calls, 0, "late result cannot call mod on replaced save")
  f.restore()
end
for _, mode in ipairs({ "constructError", "pushFailure", "cleanupError", "callbackError", "syncRefusal" }) do
  local f = fixture()
  local callback = f.exports.notify
  if mode == "callbackError" then
    callback = function()
      error("authored callback probe")
    end
  elseif mode == "syncRefusal" then
    f.synchronous, f.pushFailure = true, true
  else
    f[mode] = true
  end
  local value = f.exports.request("MEW", 5, callback)
  if mode == "constructError" or mode == "pushFailure" or mode == "syncRefusal" then
    T.eq(value, nil, "failed admission returns nil")
    T.eq(f.after, 0, "failed admission never invokes native completion")
    T.eq(f.exports.result().calls, 0, "failed admission never calls mod")
  else
    T.check(value, "completion-error battle admitted")
    T.check(pcall(f.complete, f, "win"), "completion errors contained")
    T.eq(#f.loader.errors, 1, "completion error attributed once")
    f:complete("win")
    T.eq(#f.loader.errors, 1, "replay cannot repeat error")
  end
  f.restore()
end
do
  local f = fixture()
  f.synchronous = true
  T.check(
    f.exports.request("MEW", 5, function(...)
      T.eq(Runtime.currentMod, "wild_battle", "completion owner restored")
      f.exports.notify(...)
      f.synchronous = false
      T.check(f.exports.request("MEW", 6), "synchronous completion releases admission guard")
    end),
    "synchronous battle admitted"
  )
  T.eq(f.pushed, 2, "callback can start next battle")
  f:complete("run")
  f.restore()
end
-- Real native BattleState/Pokemon construction with fixture data. The entry
-- transition and cleanup seams are independent from the public adapter.
for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local f = fixture(version)
  f.restore()
  local data = T.fixtures.fresh()
  data.pokemon.MEW = require("src.mods.Merge").deepCopy(data.pokemon.FIXMON_A)
  data.pokemon.MEW.id, data.pokemon.MEW.name = "MEW", "MEW"
  data.constants.gen = Version.generation(version)
  f.game.data = data
  f.game.save = require("src.core.SaveData").newGame()
  f.game.session = f.game.save
  f.game.save.party = { require("src.pokemon.Pokemon").new(data, "FIXMON_A", 15) }
  require("src.render.Font").load(data)
  T.check(f.exports.request("MEW", 5, f.exports.notify), version .. " native constructor admitted")
  T.eq(f.battle.kind, "wild", "native battle kind")
  T.eq(f.battle.enemy.mon.species, "MEW", "native enemy species")
  T.eq(f.battle.enemy.mon.level, 5, "native level")
  T.eq(f.game.save.pokedex.seen.MEW, true, "native constructor marks seen")
  f:complete("caught")
  T.eq(f.after, 1, "native battle retains cleanup")
  T.eq(f.exports.result().calls, 1, "native battle completes public callback")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("API 3 public wild battle")
