-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local T = require("tests.harness")
love = require("tests.love_stub")
love.math.getRandomState = function()
  return "owned-native-trainer"
end
love.math.setRandomState = function() end
local F = require("tests.checkpoint_fixture")
local C = require("src.core.CheckpointCallbacks")
local B = require("src.core.CheckpointBattle")
local retired = setmetatable({}, { __mode = "v" })
local function abandonBattle()
  local battle = {}
  local callback = function() return battle end
  battle.onFinish = callback
  B.bind(battle, { kind = "script", ctx = { game = { stack = { battle } } } })
  T.eq(battle.onFinish, callback, "native completion callback identity is unchanged")
  retired[1] = battle
end
abandonBattle()
collectgarbage("collect")
collectgarbage("collect")
T.eq(retired[1], nil, "checkpoint provenance cannot retain retired native battle graphs")
for _, edition in ipairs(require("src.core.GameVersion").ORDER) do
  local f = F.boot(edition)
  local game, world, stack = f.game, f.world, f.stack
  local npc = world.npcs[1]
  npc.def.trainerClass, npc.def.trainerParty = "OPP_FIX_YOUNGSTER", 1
  npc.frozen = true
  world.engaging = true
  local done = C.bind(function()
    npc.frozen = false
    world.engaging = false
  end, { npc = npc.id, clearEngaging = true })
  local push = world.pushBattle
  world.pushBattle = function(_, battle)
    stack.states[#stack.states + 1] = battle
  end
  world:engageTrainer(npc, done)
  local text = stack:top()
  stack.states = { world }
  text.onDone()
  world.pushBattle = push
  local battle = stack:top()
  battle.phase, battle.queue, battle.introSlide = "menu", {}, 0
  collectgarbage("collect")
  local cp, code, detail = f.checkpoints:capture(game)
  T.check(
    cp ~= nil,
    edition .. " detaches actual native trainer producer: " .. tostring(code) .. " " .. tostring(detail)
  )
  if cp then
    T.check(f.checkpoints:restore(game, cp), "native trainer controller reconstructs")
    local fresh = stack:top()
    stack.states = { world }
    fresh.onFinish("win")
    T.eq(game.save.defeatedTrainers[npc.id], true, "native trainer defeat flag continues")
    T.eq(world.npcs[1].frozen, false, "native trainer completion resolves reconstructed NPC")
    T.eq(world.engaging, false, "native trainer completion releases field input")
  end
  f.close()
end
for _, edition in ipairs(require("src.core.GameVersion").ORDER) do
  local f = F.boot(edition)
  local game, world, stack = f.game, f.world, f.stack
  local npc = world.npcs[1]
  npc.def.pokemon, npc.def.level = "FIXMON_B", 15
  local push = world.pushBattle
  world.pushBattle = function(_, battle) stack.states[#stack.states + 1] = battle end
  world:talkTo(npc)
  local text = stack:top()
  stack.states = { world }
  text.onDone()
  world.pushBattle = push
  local battle = stack:top()
  battle.phase, battle.queue, battle.introSlide = "menu", {}, 0
  collectgarbage("collect")
  local cp, code, detail = f.checkpoints:capture(game)
  T.check(cp ~= nil, edition .. " detaches actual static encounter: " .. tostring(code) .. " " .. tostring(detail))
  if cp then
    local Serializer = require("src.core.SaveSerializer")
    local bad = assert(Serializer.decode(Serializer.encode(cp)))
    bad.runtime.battle.continuation.onDone = nil
    local saved = game.save
    local ok, reason = f.checkpoints:restore(game, bad)
    T.eq(ok, false, "static completion cannot be omitted")
    T.eq(reason, "invalid_battle_state", "missing completion is rejected before mutation")
    T.eq(game.save, saved, "static preflight preserves progress ownership")
    T.check(f.checkpoints:restore(game, cp), "static native decision reconstructs")
    local fresh, actor = stack:top(), world.npcs[1]
    stack.states = { world }
    fresh.onFinish("win")
    T.eq(game.save.defeatedTrainers[npc.id], true, "static encounter defeat flag continues")
    T.eq(actor.frozen, false, "static native completion resolves fresh actor")
    local found = false
    for _, n in ipairs(world.npcs) do if n == actor then found = true end end
    T.eq(found, false, "defeated static encounter leaves native cast")
  end
  f.close()
end
T.finish("Native trainer checkpoint producer")
