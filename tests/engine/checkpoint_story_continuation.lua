-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local T = require("tests.harness")
love = require("tests.love_stub")
local state = "owned-story-rng"
love.math.getRandomState = function()
  return state
end
love.math.setRandomState = function(v)
  state = v
end
local Fixture = require("tests.checkpoint_fixture")
local Serializer = require("src.core.SaveSerializer")
for _, edition in ipairs(require("src.core.GameVersion").ORDER) do
  for _, api in ipairs({ 1, 2, 3 }) do
    local f = Fixture.boot(edition, api)
    local game, world, stack = f.game, f.world, f.stack
    local originalPush = world.pushBattle
    world.pushBattle = function(_, battle)
      stack.states[#stack.states + 1] = battle
    end
    local rows = {
      { "set_flag", "OWNED_BEFORE" },
      { "start_battle", "wild", "FIXMON_B", 10 },
      { "set_flag", "OWNED_AFTER" },
    }
    local npc = world.npcs[1]
    world.runner:run(rows, { npc = npc, mapId = "FIX_TOWN" })
    local battle = stack:top()
    world.pushBattle = originalPush
    battle.phase, battle.queue, battle.introSlide = "menu", {}, 0
    T.check(world.runner:isRunning(), "actual native story is suspended at its battle command")
    T.eq(game.save.flags.OWNED_BEFORE, true, "prefix executed once")
    T.eq(game.save.flags.OWNED_AFTER, nil, "suffix is still suspended")
    local cp, code, detail = f.checkpoints:capture(game)
    T.check(
      cp ~= nil,
      edition .. "/API-" .. api .. " detaches native story: " .. tostring(code) .. " " .. tostring(detail)
    )
    if not cp then
      local ok, why = pcall(require("src.core.CheckpointBattle").capture, game, battle, function(v)
        return assert(Serializer.decode(Serializer.encode(v)))
      end)
      print("STORY_DIAG", ok, why)
    else
      local bytes = Serializer.encode(cp)
      local oldRunner = world.runner
      local ok, why, detail = f.checkpoints:restore(game, cp)
      T.check(ok, "restores story battle: " .. tostring(why) .. " " .. tostring(detail))
      if ok then
        T.check(world.runner ~= oldRunner, "native coroutine owner is reconstructed")
        T.eq(world.runner.ctx.npc, world.npcs[1], "native context resolves actor by stable identity")
        T.eq(game.save.flags.OWNED_AFTER, nil, "restore runs no suffix commands")
        T.check(Serializer.encode(assert(f.checkpoints:capture(game))) == bytes, "story decision fully recaptures")
        local fresh = stack:top()
        stack.states = { world }
        fresh.onFinish("run")
        T.eq(game.save.flags.OWNED_AFTER, true, "battle completion resumes the native suffix")
        T.eq(world.runner:isRunning(), false, "restored runner reaches its normal termination")
        T.eq(Serializer.encode(cp), bytes, "story payload remains detached")
        stack.states = { { screenId = "TitleState" } }
        T.check(f.checkpoints:resume(game, cp), "title resumes pending native story battle")
        fresh = stack:top()
        stack.states = { world }
        fresh.onFinish("run")
        T.eq(game.save.flags.OWNED_AFTER, true, "title-restored native story continues")
      end
    end
    f.close()
  end
end
T.finish("Native checkpoint story continuation")
