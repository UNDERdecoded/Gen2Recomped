-- Opt-in GB Color/GBA companion. The public predicate selects whether it
-- exists; the native NPC update/draw lists own movement and rendering.
local NPC = require("src.world.NPC")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local F = {}
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Keep the predicate on the native module table so ModSeams can restore it
-- when a legacy mod fails to load or is disabled. A closure-only setter would
-- leave the unloaded mod's callback alive in subsequent game sessions.
F._shouldSpawn = function()
  return false
end
function F.setShouldSpawn(fn)
  local previous = F._shouldSpawn
  if fn then
    assert(type(fn) == "function", "follower predicate must be a function")
    F._shouldSpawn = fn
  end
  return previous
end
local function nativeDefault(game, world)
  if Version.generation() == 2 then return F._shouldSpawn(game, world) end
  return false
end
local function current(world)
  for i, npc in ipairs(world.npcs or {}) do
    if npc.optionalFollower then
      return npc, i
    end
  end
end
function F.current(world)
  return (current(world))
end
local function remove(world)
  local npc, at = current(world)
  if not npc then
    return
  end
  table.remove(world.npcs, at)
  for i, entity in ipairs(world.entities or {}) do
    if entity == npc then
      table.remove(world.entities, i)
      break
    end
  end
  world.follower, world.cast = nil, nil
end
local function spawn(game, world, opts, viaMapLoad)
  local keep = opts and (opts.keepFollower or opts.keepPikachu)
  if keep then
    table.insert(world.npcs, keep)
    table.insert(world.entities, keep)
    world.follower, world.cast = keep, nil
    return
  end
  local p, map = world.player, world.map
  local x, y = p.cellX, p.cellY
  if not viaMapLoad and Version.generation() == 2 then
    local d = DELTA[p.facing] or DELTA.down
    if map:inBounds(x - d[1], y - d[2]) and map:isWalkableCell(x - d[1], y - d[2]) then
      x, y = x - d[1], y - d[2]
    end
  end
  -- A missing optional sheet must not mutate the content registry. Give the
  -- NPC its own renderer over the player definition (then NPC's placeholder
  -- fallback if neither sheet exists), rather than sharing a renderer.
  local data = game.data
  if not (data.sprites and data.sprites.SPRITE_PIKACHU) then
    local def = p.spriteDef or (p.sprite and p.sprite.def)
    if def then
      data = setmetatable({
        sprites = setmetatable({ SPRITE_PIKACHU = def }, { __index = data.sprites }),
      }, { __index = data })
    end
  end
  local npc = NPC.new(data, map.id, {
    index = 250,
    name = "FOLLOWER",
    sprite = "SPRITE_PIKACHU",
    movement = "STAY",
    range = "NONE",
    x = x,
    y = y,
  })
  npc.optionalFollower, npc.follower, npc.pikachuFollower, npc.passable = true, true, true, true
  npc.facing, npc.elevation = p.facing or "down", p.elevation
  table.insert(world.npcs, npc)
  table.insert(world.entities, npc)
  world.follower, world.cast = npc, nil
  world.followerTrail = { x = p.cellX, y = p.cellY }
  world.pikachuTrail = world.followerTrail
end

function F._checkpointCreate(game, world)
  spawn(game, world, nil, true)
  return world.follower
end

function F.onMapEntered(game, world, opts, viaMapLoad)
  if not (world and world.map and world.player) then
    return
  end
  remove(world)
  if Runtime.call("world.follower.spawn", nativeDefault, game, world) then
    spawn(game, world, opts, viaMapLoad)
  end
end

function F.update(game, world)
  if not (world and world.map and world.player) then
    return
  end
  -- Lua truthiness is the Gen1 predicate contract, including 0 and "".
  if not Runtime.call("world.follower.spawn", nativeDefault, game, world) then
    remove(world)
    return
  end
  local npc, p = current(world), world.player
  if not npc then
    spawn(game, world)
    return
  end
  local trail = world.followerTrail
  if not trail then
    trail = { x = p.cellX, y = p.cellY }
    world.followerTrail, world.pikachuTrail = trail, trail
  end
  if Version.generation() == 3 and math.abs(p.cellX - trail.x) + math.abs(p.cellY - trail.y) > 6 then
    remove(world)
    spawn(game, world)
    return
  end
  local x, y = p.targetX or p.cellX, p.targetY or p.cellY
  if x ~= trail.x or y ~= trail.y then
    npc.goalX, npc.goalY = trail.x, trail.y
    trail.x, trail.y = x, y
  end
  npc.elevation = p.elevation
  if npc.moving or not npc.goalX then
    return
  end
  local dx, dy = npc.goalX - npc.cellX, npc.goalY - npc.cellY
  local distance = math.abs(dx) + math.abs(dy)
  if distance == 0 then
    npc.goalX, npc.goalY = nil, nil
    return
  end
  if distance > 6 then
    npc.cellX, npc.cellY = npc.goalX, npc.goalY
    npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
    npc.goalX, npc.goalY = nil, nil
    return
  end
  npc.facing = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
  local d = DELTA[npc.facing]
  npc.stepDir, npc.targetX, npc.targetY = npc.facing, npc.cellX + d[1], npc.cellY + d[2]
  local frames = p.stepFramesCur or p.stepFrames or 16
  npc.stepFrames = distance > 1 and math.max(1, math.floor(frames / 2)) or frames
  npc.progress, npc.moving = 0, true
  -- The world's normal NPC loop precedes this controller, so advance frame 1.
  npc:update(world.map, world.entities)
end
return F
