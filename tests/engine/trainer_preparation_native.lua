package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/trainer_preparation/fixture.lua")
local Version = require("src.core.GameVersion")
local World = require("src.world.OverworldController")
local Runner = require("src.script.ScriptRunner")
local Preparation = require("src.battle.TrainerPreparation")
local originalVersion = Version.get()
local function bind(fn, name, value)
  for i = 1, 100 do
    local key, old = debug.getupvalue(fn, i)
    if not key then
      break
    end
    if key == name then
      debug.setupvalue(fn, i, value)
      return function()
        debug.setupvalue(fn, i, old)
      end
    end
  end
  error("missing native fixture binding " .. name)
end
local function setup(version, api, format)
  local f = Fixture.new(".", "gen2", version, api, format)
  local npc = { id = "TRAINER_1", def = { index = 1, trainerClass = "OPP_FIX_YOUNGSTER", trainerParty = 1 } }
  local world = setmetatable({
    game = f.game,
    npcs = { npc },
    map = { id = "FIX_ROUTE", def = { label = "FIX_ROUTE" } },
    player = { cellX = 4, cellY = 5 },
    engaging = false,
  }, { __index = World })
  f.game.world, f.game.overworld = world, world
  f.game.stack.states = { world }
  local restore = bind(World.enter, "Game", f.game)
  f.patch(f.game.data, "trainerHeader", function()
    return { event = "TRAINER_WON", battle = "CHALLENGE", won = "WON" }
  end)
  f.game.data.text.CHALLENGE, f.game.data.text.WON = "A trainer challenge!", "You won!"
  local battles, rewards, after = {}, 0, 0
  f.patch(world, "pushBattle", function(_, b)
    battles[#battles + 1] = b
  end)
  f.patch(world, "checkVictoryRewards", function()
    rewards = rewards + 1
  end)
  f.patch(world, "afterBattle", function()
    after = after + 1
  end)
  f.patch(world, "runGen2AfterBattle", function() end)
  f.world, f.npc, f.battles = world, npc, battles
  f.finish = function()
    restore()
    f.close()
  end
  f.outcomes = function()
    return rewards, after
  end
  return f
end
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    for _, cancel in ipairs({ false, true }) do
      local f = setup(version, mode[1], mode[2])
      local done = 0
      f.world:engageTrainer(f.npc, function()
        done = done + 1
      end)
      T.eq(f.exports.calls, 0, "pre-battle challenge precedes preparation")
      local box = f.game.stack:top()
      box.done = true
      box:advance()
      T.eq(f.exports.calls, 1, "native challenge completion dispatches once")
      T.eq(#f.battles, 0, "deferral constructs/pushes no battle")
      T.eq(f.world.engaging, true, "native field stays busy while deciding")
      T.eq(
        f.exports.continue(cancel and { cancel = true } or { playerPartyIndices = { 3, 2 } }),
        true,
        "native decision accepted"
      )
      T.eq(f.exports.continue(), false, "native decision one-shot")
      T.eq(f.world.engaging, false, "preparation releases its engagement guard")
      T.eq(#f.battles, cancel and 0 or 1, "native construction only on resume")
      if cancel then
        T.eq(done, 1, "cancel releases encounter caller")
        T.eq(f.game.save.flags.TRAINER_WON, nil, "cancel sets no defeat flag")
        T.eq(f.world.spotHush.cellX, 4, "cancel suppresses same-tile sight retrigger")
        T.eq(f.world.spotHush[f.npc], true, "sight scan suppresses this cancelled trainer")
      else
        local b = f.battles[1]
        T.eq(b.player.mon, f.game.save.party[3], "native lead uses scoped party")
        T.same(b.playerPartyIndices, { 3, 2 }, "native ordered scope")
        b.onFinish("win")
        T.eq(f.game.save.flags.TRAINER_WON, true, "native win sets its flag")
        T.eq(f.game.save.defeatedTrainers.TRAINER_1, true, "native win records trainer defeat")
        local rewards, after = f.outcomes()
        T.eq(rewards, 1, "native win keeps rewards")
        T.eq(after, 1, "native win keeps post-battle flow")
        T.eq(done, 1, "native win releases encounter caller")
      end
      T.eq(Preparation.active(f.game), false, "native pending request discarded")
      f.finish()
    end
    local f = setup(version, mode[1], mode[2])
    local runner = Runner.new(f.game, f.world)
    runner:run({ { "start_battle", "trainer", "OPP_FIX_YOUNGSTER", 1 }, { "set_flag", "AFTER_BATTLE" } })
    T.eq(f.exports.calls, 1, "actual script dispatches trainer gate")
    T.eq(runner:isRunning(), true, "native script parks while preparing")
    T.eq(#f.battles, 0, "script defers construction")
    T.eq(f.exports.continue({ playerPartyIndices = { 2, 3 } }), true, "script continuation accepted")
    T.eq(#f.battles, 1, "script constructs native battle once")
    T.eq(f.exports.calls, 1, "resumed script never reintercepts itself")
    T.eq(f.battles[1].player.mon, f.game.save.party[2], "script scope selects native lead")
    T.eq(f.game.save.flags.AFTER_BATTLE, nil, "script still awaits actual battle outcome")
    f.battles[1].onFinish("lose")
    T.eq(runner:isRunning(), false, "native finish resumes script once")
    T.eq(f.game.save.flags.AFTER_BATTLE, true, "native script continues after outcome")
    f.finish()
    for _, immediate in ipairs({ false, true }) do
      for _, strict in ipairs({ false, true }) do
        local cancelled = setup(version, mode[1], mode[2])
        local r = Runner.new(cancelled.game, cancelled.world)
        local completed = 0
        if immediate then
          cancelled.exports.mode, cancelled.exports.options = "immediate", { cancel = true }
        end
        r:run({ { "start_battle", "trainer", "OPP_FIX_YOUNGSTER", 1 }, { "set_flag", "UNSAFE_WIN" } }, {
          source = strict and { modId = "strict_cancel_probe", strict = true } or nil,
          onDone = function()
            completed = completed + 1
          end,
          afterScript = {
            function()
              cancelled.game.save.flags.UNSAFE_REWARD = true
            end,
          },
        })
        if not immediate then
          cancelled.exports.continue({ cancel = true })
        end
        T.eq(#cancelled.battles, 0, "cancelled script constructs no battle")
        T.eq(r:isRunning(), false, "cancelled script releases coroutine")
        T.eq(cancelled.game.save.flags.UNSAFE_WIN, nil, "cancel never runs win rows")
        T.eq(cancelled.game.save.flags.UNSAFE_REWARD, nil, "cancel never runs deferred rewards")
        T.eq(completed, 1, "cancel releases native caller once")
        T.eq(r.ctx.lastCheck, false, "cancel has no successful battle result")
        T.eq(#cancelled.result.errors, 0, "native cancellation is not a mod failure")
        cancelled.finish()
      end
    end
    for _, skip in ipairs({ "link", "firstBattle", "tutorialKind" }) do
      local direct = setup(version, mode[1], mode[2])
      local r = Runner.new(direct.game, direct.world)
      r:run({ { "start_battle", "trainer", "OPP_FIX_YOUNGSTER", 1, { [skip] = true } } })
      T.eq(direct.exports.calls, 0, skip .. " keeps native non-preparation route")
      T.eq(#direct.battles, 1, skip .. " constructs native battle directly")
      direct.finish()
    end
  end
end
-- Retained continuations cannot cross session or actor/script identities.
for _, change in ipairs({
  "save",
  "stack",
  "data",
  "party",
  "map",
  "npc",
  "npc id",
  "trainer",
  "team",
  "session",
  "owner",
  "provider",
}) do
  local f = setup("red", 3, "unified")
  local done = 0
  f.world:engageTrainer(f.npc, function()
    done = done + 1
  end)
  local box = f.game.stack:top()
  box.done = true
  box:advance()
  local resume = f.exports.continue
  if change == "save" then
    f.game.save = {}
  elseif change == "stack" then
    f.game.stack = {}
  elseif change == "data" then
    f.game.data = {}
  elseif change == "party" then
    f.game.save.party = {}
  elseif change == "map" then
    f.world.map = {}
  elseif change == "npc" then
    f.world.npcs = {}
  elseif change == "npc id" then
    f.npc.id = "OTHER"
  elseif change == "team" then
    f.npc.def.trainerTeam = {}
  elseif change == "trainer" then
    f.npc.def.trainerClass = "OTHER"
  elseif change == "session" then
    f.game.sessionStartedAt = 2
  elseif change == "owner" then
    f.result.loader.hooks:removeOwner("portable_trainer_preparation")
  elseif change == "provider" then
    require("src.mods.Runtime").hooks = require("src.mods.Hooks").new()
  end
  T.eq(resume(), false, change .. " invalidates native continuation")
  T.eq(#f.battles, 0, change .. " cannot construct battle")
  T.eq(resume(), false, change .. " stale continuation stays retired")
  T.eq(Preparation.active(f.game), false, change .. " releases pending request")
  if change == "npc" or change == "npc id" or change == "team" or change == "trainer" then
    T.eq(f.world.engaging, false, "retired actor releases its field guard")
  end
  f.finish()
end
local f = setup("red", 3, "unified")
f.world:engageTrainer(f.npc, function() end)
local box = f.game.stack:top()
box.done = true
box:advance()
f.result.loader.hooks:removeOwner("portable_trainer_preparation")
local peerCalls = 0
local peer = f.result.loader.hooks:wrap("core.update", function(next, ...)
  peerCalls = peerCalls + 1
  return next(...)
end, 10, "other_core_owner")
local value, extra = require("src.mods.Runtime").call("core.update", function()
  return "native", 7
end)
T.eq(value, "native", "watcher preserves native update result")
T.eq(extra, 7, "watcher preserves native update tuple")
T.eq(peerCalls, 1, "watcher preserves another mod's callback")
require("src.mods.Runtime").call("core.update", function() end)
T.eq(peerCalls, 2, "other callback survives watcher removal")
peer()
T.eq(Preparation.active(f.game), false, "native update retires removed owner without resume")
T.eq(f.world.engaging, false, "native update releases removed owner's field guard")
T.eq(f.exports.continue(), false, "removed owner's continuation remains retired")
f.finish()
Version.set(originalVersion)
T.finish("trainer.before_battle native dialogue, script and lifetime")
