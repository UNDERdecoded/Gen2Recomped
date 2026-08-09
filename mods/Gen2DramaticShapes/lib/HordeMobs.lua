-- HORDE MODE: the crowd.
--
-- Waves of people who want to touch you, walking the same grid the game
-- walks, wearing the overworld's own character sheets. Every mob IS a
-- real engine NPC (OverworldState:addRuntimeObject), which is what buys
-- the whole feature for nothing: the engine interpolates their steps,
-- the collision system lets them jostle, the voxel pass billboards them
-- with the right frame for the angle you see them from, and the flat 2D
-- path draws them too. Nothing here draws a character.
--
-- THEY ARE DRIVEN, NOT SCRIPTED. OverworldState:scriptMove would be the
-- obvious way to walk one, and it is a trap: a queued script move sets
-- `scripted` on the state, which blocks the PLAYER's input for as long as
-- it runs. So mobs are spawned with movement = "STAY" (which leaves
-- NPC:update's wander branch inert) and this file writes facing / target /
-- moving / progress directly, once per step. NPC:update then does the
-- pixel interpolation and the cell commit exactly as it does for a
-- wandering shopkeeper.
--
-- PATHING IS A FLOW FIELD, not A* per mob. One breadth-first sweep out
-- from the player's cell, over the map's walkable cells, gives EVERY mob
-- its next step at once -- and gives it correctly through doorways and
-- around buildings, which is what "gang up on the player" actually
-- requires. Rebuilt a few times a second rather than per frame; between
-- rebuilds a mob just walks downhill on the numbers. It also answers two
-- other questions for free: how far a cell is from the player (so a spawn
-- point can be picked at a fair distance and be guaranteed REACHABLE),
-- and whether a mob is adjacent enough to swing.
--
-- The sweep ignores entity occupancy on purpose. Mobs are solid to each
-- other, so a pack funnelling down a corridor will jam -- and the fix for
-- that is not a cleverer path, it is that a mob whose downhill step is
-- occupied tries its second choice and otherwise waits. That is what
-- makes them pool around the player instead of forming a queue.
--
-- FOLLOWING THROUGH DOORS. A warp tears down every NPC on the old map, so
-- the roster cannot survive one. What survives is the COUNT: the number
-- still alive when the player ran, re-spawned on the far side over the
-- next few seconds, from the cells nearest the door they came in by. From
-- the player's chair that is the horde coming through the door after them.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Horde = V.require("Horde")
local HordeSfx = V.require("HordeSfx")

local HordeMobs = {}

-- ------- tuning

-- Wave n throws this many at you, and no more than CAP stand at once.
local function waveSize(n) return 4 + 3 * n end
local CAP = 14
local SPAWN_INTERVAL = 0.75      -- seconds between arrivals inside a wave
local WAVE_GAP = 4.0             -- the breather, and the banner's window
local FOLLOW_INTERVAL = 0.55     -- how fast they pour through a door

-- Frames per cell. The engine's own walk is 16; the horde is quicker than
-- a shopkeeper and gets quicker as the waves stack, floored so it never
-- outruns the player's own free walk.
local function stepFrames(n)
  return math.max(9, 15 - math.floor(n / 2))
end

local function mobHp(n) return math.min(4, 1 + math.floor(n / 3)) end
local function killScore(n) return 100 + 25 * (n - 1) end
local function waveBonus(n) return 250 * n end

-- How close a mob comes before it stops walking and starts swinging, in
-- CELLS, and how close it has to be to land the hit, in world pixels.
--
-- The standoff is the difference between a horde and a wall. Nothing
-- stops a mob taking the cell next to the player -- and when it does, a
-- sixteen-pixel figure a cell away fills a sixty-five-degree lens edge to
-- edge, so being surrounded looks like a texture rather than like people.
-- Two cells back they read as figures closing in, the ring holds a dozen
-- of them, and the player can still see what they are shooting at.
local STANDOFF = 2
local REACH = 40

-- The cast. Overworld sprite sheets that read as a threat coming out of
-- the dark; anything missing from the loaded game is dropped at spawn.
local CAST = {
  "SPRITE_ROCKET", "SPRITE_CHANNELER", "SPRITE_SCIENTIST", "SPRITE_BIKER",
  "SPRITE_GUARD", "SPRITE_SUPER_NERD", "SPRITE_HIKER", "SPRITE_SWIMMER",
  "SPRITE_GYM_GUIDE", "SPRITE_BLACK_HAIR_BOY_1", "SPRITE_GIRL",
  "SPRITE_MIDDLE_AGED_MAN", "SPRITE_FISHER", "SPRITE_GAMBLER",
}

local OWNER = "DRAMATIC_SHAPE"

-- ------- the flow field
--
-- dist[cy * w + cx] = steps from the player, over walkable cells only.
-- Nil where the sweep never reached, which is the same answer as "no way
-- there from here" -- an island across water, a room behind a locked door.

local field = { mapId = nil, w = 0, h = 0, dist = nil, at = nil, age = 0 }

local REBUILD_EVERY = 0.28

local function passable(map, cx, cy)
  if not map:inBounds(cx, cy) then return false end
  if not map:isWalkableCell(cx, cy) then return false end
  -- a warp cell is walkable but standing on one takes the warp; mobs may
  -- cross them (that IS the door they follow you through) so they stay in
  return true
end

-- fixed order, so a tie between two equally good steps always breaks the
-- same way -- a mob that dithers between two cells reads as broken, and a
-- pairs() walk over a hash would give a different answer every run
local DIRS = { "right", "left", "down", "up" }
local DX = { right = 1, left = -1, down = 0, up = 0 }
local DY = { right = 0, left = 0, down = 1, up = -1 }

local function rebuildField(map, px, py)
  local w, h = map.widthCells, map.heightCells
  local dist = {}
  -- a plain array queue: BFS on a grid never revisits a cell, so no heap
  -- and no priority is needed and the whole sweep is one pass
  local qx, qy = { px }, { py }
  local head = 1
  dist[py * w + px] = 0
  while head <= #qx do
    local cx, cy = qx[head], qy[head]
    head = head + 1
    local d = dist[cy * w + cx] + 1
    for i = 1, 4 do
      local dir = DIRS[i]
      local nx, ny = cx + DX[dir], cy + DY[dir]
      local key = ny * w + nx
      if dist[key] == nil and passable(map, nx, ny) then
        dist[key] = d
        qx[#qx + 1], qy[#qy + 1] = nx, ny
      end
    end
  end
  field.mapId, field.w, field.h, field.dist = map.id, w, h, dist
  field.at = { px, py }
  field.age = 0
end

local function distAt(cx, cy)
  if not field.dist then return nil end
  if cx < 0 or cy < 0 or cx >= field.w or cy >= field.h then return nil end
  return field.dist[cy * field.w + cx]
end

-- named for the suite: the sweep, and the distance it wrote to a cell
HordeMobs._dist = distAt
HordeMobs._rebuild = rebuildField

-- ------- spawning

local function liveSprites(G)
  local out = {}
  local sprites = G and G.data and G.data.sprites
  for _, key in ipairs(CAST) do
    if sprites and sprites[key] then out[#out + 1] = key end
  end
  if #out == 0 and sprites then
    -- a total conversion with none of the vanilla sheets: take whatever
    -- walker it does have rather than spawning nothing at all
    local keys = {}
    for key, def in pairs(sprites) do
      if def and def.walker then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for i = 1, math.min(6, #keys) do out[i] = keys[i] end
  end
  return out
end

-- Cells at a fair distance from the player that the flow field says are
-- actually reachable, preferring the far end of the band so the horde
-- arrives from off in the dark rather than on top of you.
local function spawnCells(map, near, far, want)
  local out = {}
  if not field.dist then return out end
  for key, d in pairs(field.dist) do
    if d >= near and d <= far then
      local cy = math.floor(key / field.w)
      local cx = key - cy * field.w
      out[#out + 1] = { cx, cy, d }
    end
  end
  -- shuffle, then bias toward distance: sorting outright would file every
  -- mob in from the same corner
  for i = #out, 2, -1 do
    local j = love.math.random(i)
    out[i], out[j] = out[j], out[i]
  end
  table.sort(out, function(a, b) return a[3] > b[3] end)
  while #out > (want or 16) do table.remove(out) end
  return out
end

local function occupiedCell(state, cx, cy)
  local Collision = require("src.world.Collision")
  return Collision.occupied(state.entities, cx, cy, nil) ~= nil
end

-- One mob, on a cell, on the live map. Returns the roster entry or nil.
local function spawnAt(G, state, cx, cy, wave)
  local s = Horde.session
  if not s then return nil end
  local sprites = liveSprites(G)
  if #sprites == 0 then return nil end
  local def = {
    x = cx, y = cy,
    sprite = sprites[love.math.random(#sprites)],
    movement = "STAY",
    range = "DOWN",
    name = "HORDE",
    hordeMob = true,
  }
  local mapId = state.map.id
  local okAdd, npcId = pcall(state.addRuntimeObject, state, mapId, def, OWNER)
  if not (okAdd and npcId) then return nil end
  s.spawned[mapId] = s.spawned[mapId] or {}
  s.spawned[mapId][def.index] = true

  local npc = nil
  for _, e in ipairs(state.npcs) do
    if e.id == npcId then npc = e break end
  end
  if not npc then return nil end
  npc.wanders = false
  npc.stepFrames = stepFrames(wave)
  local entry = {
    npc = npc, id = npcId, mapId = mapId,
    hp = mobHp(wave), attackT = 0,
  }
  s.mobs[#s.mobs + 1] = entry
  return entry
end

-- ------- removal
--
-- Targeted, because the engine's own removeRuntimeObject walks every map
-- in the game to find one object and a firefight calls this several times
-- a second.

local function dropNpc(state, npcId)
  for _, list in ipairs({ state.npcs or {}, state.entities or {} }) do
    for i = #list, 1, -1 do
      if list[i].id == npcId then table.remove(list, i) end
    end
  end
  if state.npcPool then state.npcPool[npcId] = nil end
end

-- Take this mode's objects back out of a map record. Runtime objects live
-- in Game.data.maps[id].objects until removed, and setMap respawns from
-- that list -- so a def left behind is a mob waiting on the far side of a
-- door long after the mode ended.
local function scrubMap(G, mapId, indices)
  local def = G and G.data and G.data.maps and G.data.maps[mapId]
  if not def or not def.objects then return end
  for i = #def.objects, 1, -1 do
    local obj = def.objects[i]
    if obj and obj.hordeMob and (not indices or indices[obj.index]) then
      table.remove(def.objects, i)
    end
  end
end

-- ------- the roster's own step

local function faceToward(npc, cx, cy)
  local dx, dy = cx - npc.cellX, cy - npc.cellY
  if math.abs(dx) > math.abs(dy) then
    return dx > 0 and "right" or "left"
  end
  return dy > 0 and "down" or "up"
end

-- Walk one mob downhill on the flow field. The best neighbour is the one
-- with the lowest distance; when it is taken, the second best is tried,
-- and when both are taken the mob waits a beat -- which is what makes a
-- pack pool around the player instead of queueing behind one another.
local function stepMob(state, entry)
  local npc = entry.npc
  if npc.moving then return end
  local here = distAt(npc.cellX, npc.cellY)
  -- close enough: stand and swing rather than crowding into the lens
  if here and here <= STANDOFF then
    local p = state.player
    npc.facing = faceToward(npc, p.cellX, p.cellY)
    return
  end
  local best, bestD, second, secondD = nil, nil, nil, nil
  for i = 1, 4 do
    local dir = DIRS[i]
    local tx, ty = npc.cellX + DX[dir], npc.cellY + DY[dir]
    local d = distAt(tx, ty)
    -- the standoff is enforced on the cell being ENTERED, not the one
    -- being stood on: a mob that checked only where it was would still
    -- finish the step it was already taking and end up in the lens
    if d and d < STANDOFF then d = nil end
    if d and (not here or d < here) then
      if not bestD or d < bestD then
        second, secondD = best, bestD
        best, bestD = { dir, tx, ty }, d
      elseif not secondD or d < secondD then
        second, secondD = { dir, tx, ty }, d
      end
    end
  end
  for _, pick in ipairs({ best, second }) do
    if pick then
      local dir, tx, ty = pick[1], pick[2], pick[3]
      if not occupiedCell(state, tx, ty) then
        npc.facing = dir
        npc.targetX, npc.targetY = tx, ty
        npc.moving = true
        npc.progress = 0
        return
      end
    end
  end
  -- boxed in: keep facing the player so the pack still reads as a threat
  local p = state.player
  npc.facing = faceToward(npc, p.cellX, p.cellY)
end

-- ------- the public surface

function HordeMobs.begin(G)
  local s = Horde.session
  if not s then return end
  local state = G and G.overworld
  if not (state and state.map) then return end
  field.mapId = nil
  s.wave, s.waveRemaining, s.waveGap, s.spawnGap = 0, 0, 0, 0
  HordeMobs.convertLocals(state)
end

-- Everyone already standing on the map joins in. Their sprite, their
-- position, their business -- now walking at the player. Nothing is
-- stored to undo it, because the restore warps through setMap, which
-- rebuilds every one of them from the map record (see Horde.finish).
function HordeMobs.convertLocals(state)
  local s = Horde.session
  if not (s and state and state.npcs) then return end
  local known = {}
  for _, e in ipairs(s.mobs) do known[e.npc] = true end
  for _, npc in ipairs(state.npcs) do
    if not known[npc] and not npc.passable then
      npc.wanders = false
      npc.frozen = false
      npc.stepFrames = stepFrames(math.max(1, s.wave))
      s.mobs[#s.mobs + 1] = {
        npc = npc, id = npc.id, mapId = state.map.id,
        hp = mobHp(math.max(1, s.wave)), attackT = 0, local_ = true,
      }
    end
  end
end

function HordeMobs.nextWave(G)
  local s = Horde.session
  if not s then return end
  s.wave = s.wave + 1
  s.waveRemaining = waveSize(s.wave)
  s.spawnGap = 0
  Horde.banner(("WAVE %d"):format(s.wave), 1.6)
  HordeSfx.play(HordeSfx.WAVE)
  for _, e in ipairs(s.mobs) do
    e.npc.stepFrames = stepFrames(s.wave)
  end
end

-- A mob took a bullet. Returns "kill", "hit", or nil.
function HordeMobs.hit(entry, damage)
  local s = Horde.session
  if not (s and entry) then return nil end
  entry.hp = entry.hp - (damage or 1)
  if entry.hp > 0 then
    HordeSfx.play(HordeSfx.HIT)
    return "hit"
  end
  entry.dead = true
  s.kills = s.kills + 1
  Horde.addScore(killScore(math.max(1, s.wave)))
  HordeSfx.randomCry()
  return "kill"
end

-- Every live mob, for the gun's ray to test against.
function HordeMobs.list()
  local s = Horde.session
  return s and s.mobs or {}
end

function HordeMobs.update(dt, G)
  local s = Horde.session
  if not s then return end
  local state = G and G.overworld
  if not (state and state.map and state.player) then return end
  local p = state.player

  -- the flow field, rebuilt on a clock and whenever the player changes
  -- cell far enough that the old numbers point at where they used to be
  field.age = field.age + dt
  local moved = field.at
    and (math.abs(field.at[1] - p.cellX) + math.abs(field.at[2] - p.cellY)) or 99
  if field.mapId ~= state.map.id or field.age >= REBUILD_EVERY or moved >= 2 then
    rebuildField(state.map, p.cellX, p.cellY)
  end

  -- the dead, collected before anything walks
  for i = #s.mobs, 1, -1 do
    local e = s.mobs[i]
    if e.dead or not e.npc then
      if e.npc then dropNpc(state, e.id) end
      table.remove(s.mobs, i)
    end
  end

  -- the living
  local pcx, pcy = p.px + 8, p.py + 8
  for _, e in ipairs(s.mobs) do
    local npc = e.npc
    e.attackT = math.max(0, e.attackT - dt)
    stepMob(state, e)
    local dx, dz = (npc.px + 8) - pcx, (npc.py + 8) - pcy
    if dx * dx + dz * dz <= REACH * REACH then
      if e.attackT <= 0 then
        e.attackT = 0.8
        npc.facing = faceToward(npc, p.cellX, p.cellY)
        Horde.damage()
      end
    end
  end

  if not Horde.playing() then return end

  -- the crowd that followed the player through a door, arriving
  if s.followQueue > 0 then
    s.spawnGap = s.spawnGap - dt
    if s.spawnGap <= 0 and #s.mobs < CAP then
      s.spawnGap = FOLLOW_INTERVAL
      local cells = spawnCells(state.map, 2, 9, 8)
      local cell = cells[1]
      if cell and spawnAt(G, state, cell[1], cell[2], s.wave) then
        s.followQueue = s.followQueue - 1
      else
        s.followQueue = s.followQueue - 1   -- nowhere to put them; let it go
      end
    end
    return
  end

  -- the wave itself
  if s.waveRemaining > 0 then
    s.spawnGap = s.spawnGap - dt
    if s.spawnGap <= 0 and #s.mobs < CAP then
      s.spawnGap = SPAWN_INTERVAL
      local cells = spawnCells(state.map, 7, 18, 10)
      if #cells == 0 then cells = spawnCells(state.map, 3, 30, 10) end
      local cell = cells[1]
      if cell and spawnAt(G, state, cell[1], cell[2], s.wave) then
        s.waveRemaining = s.waveRemaining - 1
      else
        s.spawnGap = 1.5     -- no room right now; try again shortly
      end
    end
  elseif #s.mobs == 0 then
    s.waveGap = s.waveGap + dt
    if s.waveGap == dt then
      Horde.addScore(waveBonus(s.wave))
      Horde.banner(("WAVE %d CLEAR"):format(s.wave), 1.8)
    end
    if s.waveGap >= WAVE_GAP then
      s.waveGap = 0
      HordeMobs.nextWave(G)
    end
  end
end

-- ------- the door
--
-- map.entered fires after setMap has rebuilt the world, which means every
-- mob instance from the old map is already gone. What is left to do is
-- take our defs off the old map (or they respawn if the player ever comes
-- back), remember how many were chasing, and let update() walk them in.

function HordeMobs.onMapEntered(payload)
  local s = Horde.session
  if not s then return end
  local G = require("src.core.Game")
  local state = G.overworld
  if not (state and state.map) then return end
  local newId = state.map.id

  local following = 0
  for _, e in ipairs(s.mobs) do
    if e.mapId ~= newId and not e.local_ then following = following + 1 end
  end
  -- the old map's records, and any instance the pool kept
  for mapId, indices in pairs(s.spawned) do
    if mapId ~= newId then
      scrubMap(G, mapId, indices)
      s.spawned[mapId] = nil
    end
  end
  for i = #s.mobs, 1, -1 do
    if s.mobs[i].mapId ~= newId then table.remove(s.mobs, i) end
  end

  field.mapId = nil
  s.followQueue = math.max(s.followQueue, following)
  s.spawnGap = math.min(s.spawnGap, 0.4)
  HordeMobs.convertLocals(state)
end

-- ------- the end
--
-- Every def this mode wrote, off every map it wrote one to. The live
-- instances go too, though the restore's own warp would have taken them:
-- cleanup has to leave a consistent world even when it is called from a
-- path that never warps.

function HordeMobs.cleanup(G)
  G = G or require("src.core.Game")
  local s = Horde.session
  local state = G.overworld
  if s then
    for _, e in ipairs(s.mobs) do
      if state and not e.local_ then dropNpc(state, e.id) end
    end
    for mapId, indices in pairs(s.spawned) do
      scrubMap(G, mapId, indices)
    end
    s.mobs, s.spawned = {}, {}
    s.followQueue, s.waveRemaining = 0, 0
  else
    -- a session that vanished under us (a reload mid-mode): sweep every
    -- map for this mode's marker rather than leaving actors behind
    for mapId in pairs((G.data and G.data.maps) or {}) do
      scrubMap(G, mapId, nil)
    end
  end
  field.mapId, field.dist, field.at = nil, nil, nil
end

-- named for the suite, down here because the walk is defined above it
HordeMobs._stepMob = stepMob

return HordeMobs
