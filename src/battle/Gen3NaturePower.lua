-- Native terrain caller. Nature Power announces before its child, while the
-- child's PP command owns the original selected slot and child target rules.
local N = {}
local V = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
N.MOVES = { [0] = 78, 75, 89, 56, 57, 61, 157, 247, 129, 129 }
local TERRAIN = {
  GRASS = 0,
  LONG_GRASS = 1,
  SAND = 2,
  UNDERWATER = 3,
  WATER = 4,
  POND = 5,
  MOUNTAIN = 6,
  CAVE = 7,
  BUILDING = 8,
  PLAIN = 9,
}
function N.terrain(battle)
  if battle.terrain ~= nil then
    return tonumber(battle.terrain) or 8
  end
  local terrain = battle.gen3Terrain or require("src.battle.Gen3Battle").terrainFor(battle.game)
  return TERRAIN[terrain] or tonumber(terrain) or 8
end
function N.pick(ctx)
  if not V.isGen3() then
    return nil
  end
  local number = N.MOVES[N.terrain(ctx.battle)] or 129
  local id, move = require("src.battle.EnemyMoveChoice").resolveMove(ctx.data, number)
  if not id then
    ctx.say(Strings("But, it failed!"))
    return nil
  end
  ctx.say(Strings("NATURE POWER turned into\n%s!", move.name))
  return id
end
function N.call(ctx, pick)
  local frame = ctx.battle._gbaMoveFrame
  return require("src.battle.Gen3CalledMove").call(ctx, pick, frame and frame.ppIndex)
end
function N.record()
  return { kind = "full", announceAnim = false, gbaNaturePower = true, callsMove = N.pick }
end
return N
