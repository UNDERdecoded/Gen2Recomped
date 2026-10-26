package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_travel")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(v)
  return Contract.fixture("tests/api3_contract", "gen2", v or "red")
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared travel: " .. tostring(why))
end
for _, rows in ipairs({
  { { "face_player_dir", "up" }, { "warp", "UNKNOWN", 0, 0 } },
  { { "warp", "DEST", 0.5, 0 } },
  { { "warp", "DEST", -1, 0 } },
  { { "warp", "DEST", 16, 0 } },
  { { "warp", "DEST", 0, 0, "north" } },
  { { "warp", "DEST", 0, 0, "down", {} } },
  { { "warp", "DEST", 0, 0 }, { "move_npc", 99, "down" } },
  { { "warp", "DEST", 0, 0 }, { "replace_block", 999, 0, 1 } },
  { { "warp", "DEST", 0, 0 }, { "face", "down" } },
}) do
  local f = fixture()
  T.eq(f.exports.queue(rows), nil, "invalid destination/later row preflight")
  T.eq(#f.trace, 0, "invalid suffix prevents native warp")
  T.eq(f.player.facing, "left", "invalid list has no prefix effect")
  f.restoreRenderer()
end
for _, v in ipairs({ "red", "gold", "firered", "emerald" }) do
  local f = fixture(v)
  T.check(f.exports.queue({ { "remember_outdoor", f.home, 1, 2 } }), "outdoor memory admitted")
  T.same(f.game.save.lastOutdoor, { id = f.home, x = 1, y = 2 }, "canonical remembered destination")
  if f.gen == 3 then
    T.same(f.game.save.escapeWarp, { map = f.home, warpId = 255, x = 1, y = 2 }, "native Gen3 escape memory")
  end
  f.restoreRenderer()
end
for _, change in ipairs({ "cancel", "rollback", "save", "data", "stack", "player", "version" }) do
  local f = fixture()
  local original = f.ow.runner
  T.check(
    f.exports.queue({ { "warp", f.dest, 2, 2 }, { "set_flag", "mod:after" } }),
    "cancellable warp admitted"
  )
  local callback = f.callback
  if change == "cancel" then
    require("src.mods.PortableScripts").cancelAll(f.loader, "script_travel")
  elseif change == "rollback" then
    f.loader:_rollback("script_travel")
  elseif change == "version" then
    Version.set("blue")
  elseif change == "player" then
    f.ow.player = { cellX = 2, cellY = 2 }
  else
    f.game[change] = {}
  end
  local ok = pcall(function()
    f:tick()
  end)
  T.check(ok, "changed context checked without crashing")
  T.eq(f.exports.result().done, 1, "changed context completes once")
  T.eq(f.exports.result().success, false, "changed warp fails script")
  callback()
  callback()
  T.eq(f.exports.result().done, 1, "stale warp callback cannot replay")
  T.eq(f.ow.runner, original, "source idle runner restored")
  f.restoreRenderer()
end
do
  local f = fixture()
  T.check(f.exports.queue({ { "warp", f.dest, 2, 2 }, { "set_flag", "mod:after" } }), "warp before overlay")
  local old = f.callback
  f:arrive()
  f:completeWarp()
  local replacement = f.ow.runner
  local overlay = {}
  f.game.stack.states[2] = overlay
  old()
  old()
  for _ = 1, 4 do
    f:tick()
  end
  T.eq(f.exports.get("mod:after"), false, "arrival callback cannot run beneath foreign UI")
  f.game.stack.states[2] = nil
  f:drain()
  T.eq(f.exports.result().success, true, "arrival resumes in foreground")
  T.check(f.ow.runner ~= replacement and not f.ow.runner:isRunning(), "new destination idle runner restored")
  f.restoreRenderer()
end
for _, failure in ipairs({ "throw", "refuse", "false_arrival", "wrong_map" }) do
  local f = fixture()
  if failure == "throw" or failure == "refuse" then
    f.failure = failure
  end
  T.check(
    f.exports.queue({ { "warp", f.dest, 2, 2 }, { "set_flag", "mod:after" } }),
    "native warp admitted before result"
  )
  if failure == "false_arrival" then
    f:completeWarp()
  elseif failure == "wrong_map" then
    f:arrive(f.home)
    f:completeWarp()
  end
  f:tick()
  T.eq(f.exports.result().success, false, "native failure cannot complete script")
  T.eq(f.exports.get("mod:after"), false, "native failure cannot burn later flag")
  f.restoreRenderer()
end
do
  local f = fixture()
  f.synchronous = true
  T.check(
    f.exports.queue({ { "warp", f.dest, 2, 2 }, { "set_flag", "mod:after" } }),
    "synchronous arrival admitted"
  )
  T.eq(f.exports.result().success, true, "synchronous warp continuation does not hang")
  f.restoreRenderer()
end
for _, v in ipairs({ "red", "gold", "firered", "emerald" }) do
  local f = fixture(v)
  function f.ow:startWarpTo(id, x, y, facing, callback)
    self.player.cellX, self.player.cellY, self.player.facing = x, y, facing
    callback()
  end
  T.check(
    f.exports.queue({ { "warp", f.home, 1, 1 }, { "set_flag", "mod:after" } }),
    "same-map reused runtime admitted"
  )
  T.eq(f.exports.result().success, true, "same-map warp can retain native map identity")
  T.eq(f.exports.get("mod:after"), true, "same-map native callback resumes once")
  f.restoreRenderer()
end
do
  local f = fixture()
  T.check(f.exports.queue({ { "warp", f.dest, 2, 2 } }), "stalled warp admitted")
  for _ = 1, 3601 do
    f:tick()
  end
  T.eq(f.exports.result().success, false, "warp deadline expires")
  f:arrive()
  f:completeWarp()
  T.eq(f.ow.transitioning, false, "engine can still finish timed-out warp")
  T.eq(f.exports.result().done, 1, "timed-out script cannot resume")
  f.restoreRenderer()
end
for _, v in ipairs({ "red", "gold", "firered", "emerald" }) do
  local f = fixture(v)
  f.tiles.blocks[8] = {}
  local arrive = f.arrive
  function f:arrive(id)
    arrive(self, id)
    self.ow.map.renderer = { rebuild = function() end }
  end
  function f.ow:replaceBlock(x, y, block)
    self.map:setBlock(x, y, block)
    self.map.renderer:rebuild()
  end
  T.check(
    f.exports.queue({ { "warp", f.dest, 2, 2 }, { "replace_block", 0, 0, 7 }, { "set_flag", "mod:after" } }),
    "future destination block preflight"
  )
  f:drain()
  T.eq(f.exports.result().success, true, "block edit executes on arrived map")
  T.eq(f.ow.map:blockAt(0, 0), 7, "native block patch is on destination")
  f.restoreRenderer()
end
-- Exercise the actual native transition; only destination materialization is a fixture.
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
for _, v in ipairs({ "red", "gold", "firered", "emerald" }) do
  for _, cancel in ipairs({ false, true }) do
    local f = fixture(v)
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
      f:arrive()
    end
    T.check(
      f.exports.queue({ { "warp", f.dest, 2, 2, "right" }, { "set_flag", "mod:after" } }),
      "actual transition admitted"
    )
    local state = f.game.stack:top()
    T.eq(getmetatable(state), Transition, "native warp transition retained")
    if cancel then
      f.loader:_rollback("script_travel")
      T.eq(f.game.stack:top(), state, "unload retains engine-owned warp transition")
    end
    for _ = 1, state.frames + state.framesIn + 3 do
      if f.game.stack:top() == state then
        state:update(1 / 60)
      end
      f:tick()
    end
    T.eq(f.ow.map.id, f.dest, "actual transition arrives")
    T.eq(f.ow.transitioning, false, "native warp releases its lock even after unload")
    T.eq(f.exports.result().success, not cancel, "only live script continues")
    T.eq(f.exports.get("mod:after"), not cancel, "no late effects after unload")
    restore()
    f.restoreRenderer()
  end
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script travel")
