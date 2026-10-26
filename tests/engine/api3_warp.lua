package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Contract = require("tests.api3_contract.warp")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Loader = require("src.mods.Loader")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
love = nil
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared warp contract: " .. tostring(why))
end
for _, lock in ipairs({
  "flyAnim",
  "teleportOut",
  "engaging",
  "emote",
  "pikaHop",
  "healAnim",
  "whirlSpin",
  "gen3Decorate",
  "gen3Locked",
  "frameScriptThisTick",
  "_modScriptLock",
  "parallelRunners",
  "parallelQueue",
  "pendingScripts",
  "scriptMoves",
  "stairExit",
  "spinning",
  "inputLocked",
  "fieldMove",
  "linkSession",
  "linkNet",
}) do
  local f = fixture()
  if lock == "linkSession" then
    f.game.linkSession = {}
  elseif lock == "linkNet" then
    f.game.linkNet = { closed = false }
  elseif lock == "stairExit" or lock == "spinning" or lock == "inputLocked" or lock == "fieldMove" then
    f.player[lock] = true
  elseif lock:find("Runners") or lock:find("Queue") or lock == "pendingScripts" or lock == "scriptMoves" then
    f.ow[lock] = { {} }
  else
    f.ow[lock] = true
  end
  local ok, why = f.exports.request(f.dest, 0, 0)
  T.eq(ok, nil, lock .. " declines admission")
  T.eq(why, "world is busy", lock .. " explains busy state")
  T.eq(#f.trace, 0, lock .. " never dispatches")
end
do
  local f = fixture()
  f.game.save = nil
  T.eq(f.exports.request(f.dest, 0, 0), nil, "missing save refuses")
  f.live = nil
  T.eq(f.exports.request(f.dest, 0, 0), nil, "missing game refuses")
  T.eq(#f.trace, 0, "missing context never dispatches")
end
for _, size in ipairs({ false, -1, 0, 0.5, math.huge, 0 / 0 }) do
  local f = fixture()
  f.game.data.maps[f.dest].width = size
  local ok, why = f.exports.request(f.dest, 0, 0)
  T.eq(ok, nil, "malformed map dimensions refuse")
  T.eq(why, "invalid map dimensions", "dimensions diagnosed before native work")
  T.eq(#f.trace, 0, "malformed maps never dispatch")
end
do
  local f = fixture()
  local opts = setmetatable({}, {
    __index = function()
      error("must not run")
    end,
  })
  local ok, why = f.exports.request(f.dest, 0, 0, "down", opts)
  T.eq(ok, nil, "metatable options rejected")
  T.eq(why, "invalid options", "plain options required")
  T.eq(#f.trace, 0, "metatable never reaches native warp")
end
for _, change in ipairs({ "data", "stack", "player", "version" }) do
  local f = fixture()
  T.check(f.exports.request(f.dest, 0, 0, "up", { onDone = f.exports.notify }), "start " .. change)
  f:arrive()
  local restore
  if change == "version" then
    Version.set("blue")
    restore = function()
      Version.set("red")
    end
  else
    local obj = change == "player" and f.ow or f.game
    local previous = obj[change]
    obj[change] = {}
    restore = function()
      obj[change] = previous
    end
  end
  f:update()
  restore()
  f:complete()
  T.eq(f.exports.results().calls, 0, change .. " cannot revive callback after observed change")
end
for _, failure in ipairs({ "refuse", "throw" }) do
  local f = fixture()
  f.failure, f.synchronous = failure, true
  f.ow.arriveWarp = "original"
  local ok, why = f.exports.request(f.dest, 0, 0, "up", { arrive = "fly", onDone = f.exports.notify })
  T.eq(ok, nil, "native " .. failure .. " is not admitted")
  T.check(type(why) == "string", "native failure explained")
  T.eq(f.exports.results().calls, 0, "synchronous callback waits for native acceptance")
  T.eq(f.ow.arriveWarp, "original", "failed dispatch restores borrowed arrival field")
  f:complete()
  T.eq(f.exports.results().calls, 0, "failed callback cannot replay")
end
do
  local f = fixture()
  f.synchronous = true
  local ok = f.exports.request(f.dest, 0, 0, "up", {
    onDone = function(...)
      T.eq(Runtime.currentMod, "warp", "callback attributed to owning mod")
      f.exports.notify(...)
      f.synchronous = false
      T.check(
        f.exports.request(f.home, 1, 1, "down", { onDone = f.exports.notify }),
        "callback may start next warp"
      )
    end,
  })
  T.check(ok, "synchronous native arrival admitted")
  T.eq(#f.trace, 2, "one reentrant request dispatches once")
  T.eq(Runtime.currentMod, nil, "callback restores previous runtime owner")
  f:arrive()
  f:complete()
  T.eq(f.exports.results().calls, 2, "old completion does not clear next request")
end
for _, operation in ipairs({ "rollback", "reload", "teardown" }) do
  local f = fixture()
  T.check(f.exports.request(f.dest, 0, 0, "up", { onDone = f.exports.notify }), "start before " .. operation)
  f:arrive()
  if operation == "rollback" then
    f.loader:_rollback("warp")
  elseif operation == "reload" then
    fixture() -- A new loader/session retires every previous facade.
  else
    Loader.teardown()
  end
  f:complete()
  T.eq(f.exports.results().calls, 0, operation .. " retires callback")
  local ok, why = f.exports.request(f.dest, 0, 0)
  T.eq(ok, nil, operation .. " retires facade")
  T.eq(why, "warp facade is retired", "stale facade diagnostic")
end
for _, direction in ipairs({ "up", "down", "left", "right" }) do
  local f = fixture()
  T.check(f.exports.request(f.home, 1, 1, direction, { onDone = f.exports.notify }), "same-map " .. direction)
  T.eq(f.trace[1].facing, direction, "direction reaches native warp unchanged")
  f:arrive()
  f:complete()
  T.eq(f.exports.results().calls, 1, "same-map arrival not mistaken for stale completion")
end
do
  local f = fixture()
  T.check(f.exports.request(f.dest, 0, 0, "up", { onDone = f.exports.notify }), "start before false arrival")
  f:complete()
  T.eq(f.exports.results().calls, 0, "completion on old map never invokes mod")
  f:arrive()
  f:complete()
  T.eq(f.exports.results().calls, 0, "false completion cannot be revived by later arrival")
end
-- Exercise the actual native transition; only map materialization is synthetic.
love = require("tests.love_stub")
local OW = require("src.world.OverworldController")
local Transition = require("src.render.Transition")
local StateStack = require("src.core.StateStack")
local function bind(game)
  for i = 1, 100 do
    local name, old = debug.getupvalue(OW.startWarpTo, i)
    if not name then
      break
    end
    if name == "Game" then
      debug.setupvalue(OW.startWarpTo, i, game)
      return function()
        debug.setupvalue(OW.startWarpTo, i, old)
      end
    end
  end
  error("native Game upvalue missing")
end
for _, version in ipairs({ "red", "gold", "firered", "emerald" }) do
  for _, fade in ipairs({ true, false }) do
    if fade or Version.generation(version) == 3 then
      local f = fixture(version)
      setmetatable(f.game.stack, { __index = StateStack })
      f.ow.startWarpTo = OW.startWarpTo
      local restore = bind(f.game)
      function f.ow:frlgBehaviours()
        return false
      end
      function f.ow:noteGen2Spawn(from)
        self.notedFrom = from
      end
      function f.ow:setMap(id, x, y, facing, opts)
        f.destination = { id, x, y, facing }
        T.eq(opts.via, "warp", "native transition retains warp reason")
        T.eq(opts.keepMusic, true, "native transition retains music request")
        f:arrive()
      end
      local opts = { onDone = f.exports.notify, keepMusic = true }
      if f.gen == 3 then
        opts.fade = fade
      end
      T.check(f.exports.request(f.dest, 1, 2, "right", opts), "actual native warp admitted")
      if fade then
        local state = f.game.stack:top()
        T.eq(getmetatable(state), Transition, "ordinary warp pushes native fade")
        T.eq(f.exports.results().calls, 0, "callback waits for native transition")
        for _ = 1, state.frames + state.framesIn + 2 do
          if f.game.stack:top() == state then
            state:update(1 / 60)
          end
        end
      else
        T.eq(#f.game.stack.states, 1, "no-fade warp creates no transition screen")
      end
      T.eq(f.ow.map.id, f.dest, "native transition arrives at destination")
      T.eq(f.ow.notedFrom, f.home, "native spawn bookkeeping retained")
      T.same(f.ow.warpEntryCell, { x = 1, y = 2 }, "native arrival tile guard retained")
      T.eq(f.ow.transitioning, false, "native transition releases lock")
      T.eq(f.exports.results().calls, 1, "actual native callback runs exactly once")
      restore()
    end
  end
end
-- Legacy public facade continues to ignore fade, rather than opting into API 3.
do
  local f = fixture("firered")
  local native = require("src.world.WorldAPI").new(f.game, "legacy")
  T.check(native:warpTo(f.dest, -1, 0, "north", { fade = false }), "legacy dispatch behavior unchanged")
  T.eq(f.trace[1].fade, nil, "legacy fade option remains ignored")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("API 3 portable warp")
