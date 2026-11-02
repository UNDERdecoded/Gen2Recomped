-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE GREAT MARSH QUICK TRAM (pokeplatinum src/overlay006/great_marsh_tram.c).
--
-- The station script (scripts_safari_game.s SafariGame_QuickTramStationAreaN)
-- walks the player onto the track and makes them invisible, calls
-- `movegreatmarshtram <dest>, RIDE`, then walks them off three tiles the
-- other way.  There is no warp: the ride itself is what carries the player
-- from one area's platform to the other's.  With only the state half ported
-- (Gen4DynamicMapFeatures.moveTramToLocation) the player got off at the
-- platform they had boarded at.
--
-- What is transcribed here:
--   * the prop (GreatMarshTram_DynamicMapFeaturesInit): great_marsh_train at
--     x 1056, y 16 and the location's z, in matrix units.  The six marsh
--     windows share one matrix (layout 240), so the prop goes on all six
--     defs in each def's own coordinates and the window the player is in
--     draws it;
--   * CallTramToPlayer: the prop runs from where it is to the platform at
--     sCalledTramSpeeds[level] units a frame, the level stepping up
--     (slower) every sCalledTramFramesPerSpeedLevel[level] frames once past
--     the slow-down tile, TRAIN03 when it first brakes;
--   * RideTramToArea: the invisible player walks along the track one tile at
--     a time, the walk speed picked from sRidingTram*Movements[level] at the
--     start of each tile (WALK_SLOWER 32 frames .. WALK_FASTER 2), the level
--     rising before the slow-down tile and falling from it, TRAIN02 when it
--     first speeds up and TRAIN03 when it first brakes; the prop is held at
--     player z + 8 and the ride stops when that is the destination;
--   * MoveTram's frame states: TRAIN04 before a ride and the wait for it.
--
-- Not transcribed: the prop's one-shot animation (tag 16).

local Logger = require("src.core.Logger")

local M = {}

M.MODEL_NAME = "great_marsh_train.nsbmd"
M.MODEL_FALLBACK = 475
M.X = 1056
M.Y = 16
-- GREAT_MARSH_TRAM_LOCATION_* -> TRAM_POSITION_* (matrix units)
M.POSITION = { [0] = 16 * (32 * 1 + 8), [1] = 16 * (32 * 2 + 18), [2] = 16 * (32 * 3 + 12) }
M.SLOW_1_2 = 32 * 1 + 14
M.SLOW_3_4_NORTH = 32 * 2 + 10
M.SLOW_3_4_SOUTH = 32 * 2 + 24
M.SLOW_5_6 = 32 * 3 + 4
M.MOVEMENT_CALL = 3
-- sRidingTram*Movements as frames per tile (MovementAction_InitWalk's count:
-- SLOWER 32, SLOW 16, NORMAL 8, FAST 4, FASTER 2)
M.RIDE_FRAMES = { 32, 16, 8, 8, 4, 4, 2 }
M.CALL_FRAMES = { 2, 4, 4, 8, 8, 16, 32 }
M.CALL_SPEEDS = { 8, 4, 4, 2, 2, 1, 0.5 }
M.SE_START = "SEQ_SE_DP_TRAIN04"
M.SE_FASTER = "SEQ_SE_DP_TRAIN02"
M.SE_BRAKE = "SEQ_SE_DP_TRAIN03"
-- the port's logic runs two ticks to a field frame
M.TICKS_PER_FRAME = 2
M.MAPS = { "D06R0201", "D06R0202", "D06R0203", "D06R0204", "D06R0205", "D06R0206" }

-- what the last call/ride did, for probes
M.last = nil

local function gameData(ctx)
  return ctx and ctx.game and ctx.game.data or nil
end

local function se(ctx, name, log)
  if log then log.se = log.se or {}; log.se[#log.se + 1] = name end
  local data = gameData(ctx)
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end

local function sePlaying(ctx, name)
  local data = gameData(ctx)
  local ok, playing = pcall(function() return require("src.core.Sound").isSePlaying(data, name) end)
  return ok and playing and true or false
end

function M.modelId()
  local okA, A = pcall(require, "src.import.Gen4Archives")
  local id = okA and A.find and A.find("/fielddata/build_model/build_model.narc", M.MODEL_NAME) or nil
  return id or M.MODEL_FALLBACK
end

function M.isMarsh(def)
  if not def then return false end
  for _, id in ipairs(M.MAPS) do if def.id == id then return true end end
  return false
end

local function defs(data)
  local out = {}
  local maps = data and data.maps
  for _, id in ipairs(M.MAPS) do
    local d = maps and maps[id]
    if d then out[#out + 1] = d end
  end
  return out
end

-- the shared live record: every window's copy of the prop is offset by it
M.live = { dx = 0, dy = 0, dz = 0 }

-- GreatMarshTram_DynamicMapFeaturesInit: stand the prop at `location` on
-- every marsh window.  A fresh list each time so Gen4Ground re-splits it.
function M.place(data, location)
  local z = M.POSITION[tonumber(location) or -1]
  if not z then return false end
  local model = M.modelId()
  M.live.dx, M.live.dy, M.live.dz = 0, 0, 0
  M.baseZ = z
  for _, def in ipairs(defs(data)) do
    local keep = {}
    for _, p in ipairs(type(def.gen4RuntimeProps) == "table" and def.gen4RuntimeProps or {}) do
      if not p.marshTram then keep[#keep + 1] = p end
    end
    keep[#keep + 1] = { model = model, x = M.X - (def.originX or 0) * 16, y = M.Y,
                        z = z - (def.originY or 0) * 16, live = M.live, marshTram = true }
    def.gen4RuntimeProps = keep
  end
  return true
end

local function waitFrames(ctx, step)
  local runner = ctx.runner
  if not runner then
    for _ = 1, 200000 do if step() then return end end
    return
  end
  local tick = 0
  runner.waitingCheck = function()
    tick = tick + 1
    if tick % M.TICKS_PER_FRAME ~= 0 then return false end
    return step() and true or false
  end
  runner:yield()
end

-- The slow-down tile and direction for a move from `from` (the location
-- before GreatMarshTram_MoveToLocation wrote the new one) to `to`.
function M.route(from, to)
  if from == 0 then
    return true, (to == 1) and M.SLOW_3_4_NORTH or M.SLOW_5_6
  elseif from == 1 then
    if to == 0 then return false, M.SLOW_1_2 end
    return true, M.SLOW_5_6
  elseif from == 2 then
    if to == 0 then return false, M.SLOW_1_2 end
    return false, M.SLOW_3_4_SOUTH
  end
  return nil
end

-- CallTramToPlayer, one frame; returns the new z and whether it arrived
function M.callFrame(st, z)
  local level = st.level
  if not st.south then
    z = z - M.CALL_SPEEDS[level + 1]
    if level < #M.CALL_FRAMES - 1 and math.floor((z - 8) / 16) <= st.slow then
      st.elapsed = st.elapsed + 1
      if st.elapsed >= M.CALL_FRAMES[level + 1] then
        if level == 0 then st.brake = true end
        st.level, st.elapsed = level + 1, 0
      end
    end
  else
    z = z + M.CALL_SPEEDS[level + 1]
    if level < #M.CALL_FRAMES - 1 and math.floor((z - 8) / 16) >= st.slow then
      st.elapsed = st.elapsed + 1
      if st.elapsed >= M.CALL_FRAMES[level + 1] then
        if level == 0 then st.brake = true end
        st.level, st.elapsed = level + 1, 0
      end
    end
  end
  return z, z == st.dest
end

-- The player's matrix tile and position (decomp units: a tile's centre is
-- tile * 16 + 8) from the port's map-local cell and pixel.
local function playerMatrix(ow)
  local def, p = ow.map.def, ow.player
  local ox, oy = def.originX or 0, def.originY or 0
  return ox + p.cellX, oy + p.cellY, oy * 16 + (p.py or p.cellY * 16) + 8
end

-- Put the player at matrix tile column `gx`, matrix z `wz` (decomp units),
-- handing over to the marsh window that holds the tile.
local function putPlayer(ow, data, gx, wz)
  local p = ow.player
  local gy = math.floor((wz - 8) / 16)
  local def = ow.map.def
  local ox, oy = def.originX or 0, def.originY or 0
  local lx, ly = gx - ox, gy - oy
  if lx < 0 or ly < 0 or lx >= (def.width or 32) or ly >= (def.height or 32) then
    for _, d in ipairs(defs(data)) do
      local dx, dy = gx - (d.originX or 0), gy - (d.originY or 0)
      if dx >= 0 and dy >= 0 and dx < (d.width or 32) and dy < (d.height or 32) then
        local hidden = p.hidden
        ow:setMap(d.id, dx, dy, p.facing, { seamless = true, keepMusic = true })
        ow.pendingSeamMusic = d.id
        p = ow.player
        p.hidden = hidden
        def = d
        ox, oy, lx, ly = d.originX or 0, d.originY or 0, dx, dy
        break
      end
    end
  end
  p.moving = false
  p.cellX, p.cellY = lx, ly
  p.px = lx * 16
  p.py = wz - 8 - oy * 16
end

-- GreatMarshTram_MoveToLocation's task.  `from`/`to` are the locations
-- before and after the state half moved the tram; `movementType` the raw
-- halfword (3 = CALL, anything else RIDE).
function M.run(ctx, from, to, movementType)
  local ow = ctx and ctx.overworld
  local data = gameData(ctx)
  local south, slow = M.route(from, to)
  local dest = M.POSITION[to]
  local log = { from = from, to = to, movement = movementType, frames = 0 }
  M.last = log
  if south == nil or not dest then return log end
  local ride = tonumber(movementType) ~= M.MOVEMENT_CALL
  log.ride = ride
  if not (ow and ow.map and ow.player and M.isMarsh(ow.map.def)) then
    -- off the marsh there is nothing to move; the state half stands
    log.offMarsh = true
    M.place(data, to)
    return log
  end
  M.place(data, from)
  local base = M.baseZ
  local z = base
  -- MoveTram states 1-2: TRAIN04 before a ride, and the wait for it
  if ride then se(ctx, M.SE_START, log) end
  local waited = 0
  waitFrames(ctx, function()
    waited = waited + 1
    return waited > 1 and (not sePlaying(ctx, M.SE_START) or waited > 600)
  end)
  log.startWait = waited
  local st = { south = south, slow = slow, dest = dest, level = 0, elapsed = 0 }
  if not ride then
    waitFrames(ctx, function()
      local arrived
      z, arrived = M.callFrame(st, z)
      if st.brake then st.brake = nil; se(ctx, M.SE_BRAKE, log) end
      M.live.dz = z - base
      log.frames = log.frames + 1
      return arrived or log.frames > 20000
    end)
  else
    local gx, _, wz = playerMatrix(ow)
    log.startTile = math.floor((wz - 8) / 16)
    local stepLeft, stepSpeed, dir = 0, 0, south and 1 or -1
    local maxLevel = #M.RIDE_FRAMES - 1
    log.levels = {}
    waitFrames(ctx, function()
      z = wz + 8
      M.live.dz = z - base
      if z == dest then return true end
      log.frames = log.frames + 1
      if log.frames > 20000 then return true end
      if stepLeft == 0 then
        -- LocalMapObj_IsAnimationSet: the last tile's walk is over
        local tile = math.floor((wz - 8) / 16)
        local frames = M.RIDE_FRAMES[st.level + 1]
        stepLeft, stepSpeed = frames, 16 / frames
        log.levels[#log.levels + 1] = st.level
        local before = south and (tile < slow) or (not south and tile > slow)
        if st.level < maxLevel and before then
          if st.level == 0 then se(ctx, M.SE_FASTER, log) end
          st.level = st.level + 1
        elseif not before then
          if st.level ~= 0 then
            if st.level == maxLevel then se(ctx, M.SE_BRAKE, log) end
            st.level = st.level - 1
          end
        end
      end
      wz = wz + dir * stepSpeed
      stepLeft = stepLeft - 1
      putPlayer(ow, data, gx, wz)
      return false
    end)
    log.endMap = ow.map and ow.map.id
    log.endCell = { ow.player.cellX, ow.player.cellY }
  end
  -- the prop stays where it stopped
  M.place(data, to)
  log.z = z
  Logger.debug("great marsh tram: %s %d -> %d in %d frames", ride and "ride" or "call",
               from, to, log.frames)
  return log
end

return M
