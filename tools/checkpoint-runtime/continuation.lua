-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Actual native RNG, NPC/follower producers and battle turns over owned data.
return function(check)
  local F = require("tests.checkpoint_fixture")
  local GV = require("src.core.GameVersion")
  local NPC = require("src.world.NPC")
  local Serializer = require("src.core.SaveSerializer")
  local Maps = require("src.world.MapLoader")
  local Battle = require("src.battle.BattleState")
  local M = require("src.world.Gen4MovementTypes")
  local cases = {}
  local function copy(v)
    return assert(Serializer.decode(Serializer.encode(v)))
  end
  for _, edition in ipairs({ "red", "yellow", "gold", "firered", "emerald", "platinum", "heartgold", "black" }) do
    for api = 1, 3 do
      local f = F.boot(edition, api)
      local game, world, stack = f.game, f.world, f.stack
      world.noWildEncounters = true
      local npc = world.npcs[1]
      npc.wanders, npc.timer = true, 1
      local off
      if GV.generation() <= 3 then
        off = f.loaded.loader.exports.checkpoint_fixture.api.hooks:wrap("world.follower.spawn", function()
          return true
        end)
      else
        game.data.constants.gen3MovementTypes = nil
        local def = copy(npc.def)
        def.index = 92
        def.direction = 1
        def.movementType = 3
        def.movementRangeX, def.movementRangeZ = 2, 2
        local extra = NPC.new(game.data, "FIX_TOWN", def)
        world.npcs[#world.npcs + 1] = extra
        world.entities[#world.entities + 1] = extra
        local follower = NPC.new(
          game.data,
          "FIX_TOWN",
          { index = 93, sprite = "SPRITE_FIX_NPC", movement = "STAY", range = "NONE", x = 2, y = 4 }
        )
        world.npcs[#world.npcs + 1] = follower
        world.entities[#world.entities + 1] = follower
        require("src.world.Gen4Follower").adopt(game.save, world, follower)
      end
      love.math.setRandomSeed(27981, api)
      local function step(i)
        local p = world.player
        if i % 32 == 0 then
          p.cellX = 2 + (math.floor(i / 32) % 2)
          p.px = p.cellX * 16
        end
        world:update(1 / 60)
        return Serializer.encode(assert(f.checkpoints:capture(game))), love.math.getRandomState()
      end
      for i = 1, 45 do
        step(i)
      end
      local cp, why, detail = f.checkpoints:capture(game)
      assert(cp, edition .. "/" .. api .. ": " .. tostring(why) .. " " .. tostring(detail))
      local future = {}
      for i = 1, 192 do
        future[i] = { step(i) }
      end
      check(f.checkpoints:restore(game, cp), edition .. " actor continuation reconstructs")
      for i = 1, 192 do
        local state, rng = step(i)
        check(state == future[i][1], edition .. " native actor/follower continuation " .. i)
        check(rng == future[i][2], edition .. " native actor/follower RNG " .. i)
      end
      if off then
        off()
      end
      -- Current native constructors and command queue, including actual damage,
      -- PP, volatile state, events and the next player decision.
      local battleTurns = 0
      for _, kind in ipairs({ "wild", "trainer" }) do
        stack.states = { world }
        local battle = kind == "wild" and Battle.newWild(game, "FIXMON_B", 15)
          or Battle.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
        battle.phase, battle.queue, battle.introSlide = "menu", {}, 0
        battle.player.mon.hp, battle.player.mon.stats.hp, battle.player.shownHP = 400, 400, 400
        battle.enemy.mon.hp, battle.enemy.mon.stats.hp, battle.enemy.shownHP = 400, 400, 400
        battle.player.stages.attack = 2
        stack.states = { world, battle }
        local decision, why, detail = f.checkpoints:capture(game)
        assert(decision, edition .. "/" .. kind .. ": " .. tostring(why) .. " " .. tostring(detail))
        local function turn()
          local b = stack:top()
          game.input.wasPressed = function(_, key)
            return key == "a"
          end
          game.input.pressed = game.input.wasPressed
          game.save.options.battleAnimations = false
          b:chooseMenu("fight")
          b:chooseMove(1)
          local ticks = 0
          repeat
            b:update(1 / 60)
            ticks = ticks + 1
          until (b.phase == "menu" and not b.current and #b.queue == 0) or ticks >= 4000
          check(ticks < 4000 and b.phase == "menu", "native turn reaches its next decision")
          return Serializer.encode(assert(f.checkpoints:capture(game)))
        end
        local expected = turn()
        check(f.checkpoints:restore(game, decision), "native turn rewinds to the same choice")
        check(turn() == expected, "actual RNG and native turn continuation match")
        battleTurns = battleTurns + 1
      end
      cases[#cases + 1] = {
        edition = edition,
        api = api,
        actorUpdates = 192,
        actorRng = true,
        nativeFollower = true,
        laterGenerationMovement = GV.generation() >= 4,
        battleTurns = battleTurns,
      }
      f.close()
    end
  end
  return cases
end
