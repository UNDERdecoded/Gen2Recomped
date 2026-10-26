-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local T = require("tests.harness")
love = require("tests.love_stub")
local state = "owned-actor-rng"
love.math.getRandomState = function()
  return state
end
love.math.setRandomState = function(v)
  state = v
end
local F = require("tests.checkpoint_fixture")
local NPC = require("src.world.NPC")
local Serializer = require("src.core.SaveSerializer")
local Maps = require("src.world.MapLoader")
local function copy(v)
  return assert(Serializer.decode(Serializer.encode(v)))
end
for _, edition in ipairs(require("src.core.GameVersion").ORDER) do
  local f = F.boot(edition)
  local world, game = f.world, f.game
  local npc = world.npcs[1]
  npc.wanders, npc.timer = true, 2
  npc.cellX, npc.cellY, npc.px, npc.py = 7, 6, 112, 96
  npc.facing, npc.stepFlip = "left", true
  npc.moving, npc.targetX, npc.targetY, npc.progress = true, 6, 6, 3
  npc.px = 109
  world.strengthActive, world.noWildEncounters = true, true
  world.npcPlacement = { FIX_TOWN = { [1] = { x = 7, y = 6 } } }
  local extra = NPC.new(
    game.data,
    "FIX_TOWN",
    { index = 91, sprite = "SPRITE_FIX_NPC", movement = "STAY", range = "NONE", x = 9, y = 7 }
  )
  extra.hidden, extra.passable = true, true
  world.npcs[#world.npcs + 1] = extra
  world.entities[#world.entities + 1] = extra
  if edition == "yellow" then
    local p = require("src.world.PikachuFollower")._checkpointCreate(game, world, 2, 4, "up")
    world.npcs[#world.npcs + 1] = p
    world.entities[#world.entities + 1] = p
    p.idle, p.idleClock = { kind = "shuffle", frames = 12, tick = 2, phase = 1 }, 1
    world.pikachuTrail = { x = 2, y = 3 }
  elseif edition == "gold" or edition == "firered" or edition == "emerald" then
    require("src.world.OptionalFollower")._checkpointCreate(game, world)
    world.follower.goalX, world.follower.goalY = 2, 4
  end
  game.save.flashLit = true
  game.save.gen3ThinIce = { FIX_TOWN = { owned = true } }
  game.save.gen3ObjectHomes = { FIX_TOWN = { [1] = { x = 7, y = 6 } } }
  world.cutBlocks = { FIX_TOWN = { { bx = 1, by = 1, block = 1 } } }
  world.map:setBlock(1, 1, 1, true)
  local cp, why, detail = f.checkpoints:capture(game)
  T.check(cp ~= nil, edition .. " captures native actor state: " .. tostring(why) .. " " .. tostring(detail))
  if cp then
    local original = Serializer.encode(cp)
    local old = world.npcs[1]
    old.timer, old.cellX = 90, 11
    T.check(f.checkpoints:restore(game, cp), edition .. " restores native actor state")
    T.eq(Serializer.encode(assert(f.checkpoints:capture(game))), original, "complete native actor state recaptures")
    T.check(world.npcs[1] ~= old, "fresh native actor identity")
    T.eq(world.npcs[1].cellX, 7, "scripted placement restored")
    T.eq(world.npcs[1].progress, 3, "in-flight native NPC movement restored")
    T.eq(world.npcs[2].hidden, true, "extra native actor retained")
    T.eq(world.strengthActive, true, "strength state restored")
    T.eq(world.noWildEncounters, true, "encounter override restored")
    T.eq(game.save.flashLit, true, "checkpoint reconstruction retains canonical map flags")
    T.eq(game.save.gen3ThinIce.FIX_TOWN.owned, true, "checkpoint reconstruction retains transient saved progress")
    T.eq(game.save.gen3ObjectHomes.FIX_TOWN[1].x, 7, "native map entry cannot erase stored placements")
    T.eq(world.map.collisionPatch[12], 1, "native collision patch restored")
    T.eq(world.cutBlocks.FIX_TOWN[1].bx, 1, "native cut-block continuation restored")
    T.eq(Serializer.encode(cp), original, "caller data remains detached")
    local invalid = copy(cp)
    invalid.runtime.actors.records[npc.id].state.timer = "invalid"
    local saved, pool, map = game.save, world.npcPool, world.map
    local ok, code = f.checkpoints:restore(game, invalid)
    T.eq(ok, false, "malformed native actor field refused")
    T.eq(code, "invalid_actor_state", "native actor field refusal named")
    T.eq(game.save, saved, "preflight preserves live progress")
    T.eq(world.npcPool, pool, "preflight preserves native owners")
    local actors = require("src.core.CheckpointActors")
    local apply = actors.apply
    actors.apply = function(...)
      apply(...)
      error("intentional failure after native actor apply")
    end
    ok, code = f.checkpoints:restore(game, cp)
    actors.apply = apply
    T.eq(ok, false, "partial actor apply fails closed")
    T.eq(code, "restore_failed", "partial apply uses rollback")
    T.eq(game.save, saved, "partial apply preserves original progress")
    T.eq(world.npcPool, pool, "partial apply preserves original actors")
    T.eq(Maps.load(game.data, "FIX_TOWN"), map, "partial apply preserves original cache owner")
  end
  f.close()
end
T.finish("Native checkpoint actor continuation")
