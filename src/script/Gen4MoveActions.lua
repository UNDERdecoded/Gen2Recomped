-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE GEN 4 MOVEMENT ACTIONS THAT ARE NOT A WALK, A TURN OR A WAIT, played
-- for Commands.g4_move (src/script/Gen4Commands.lua). The table is
-- src/import/Gen4Movement.lua; what each kind does is read off the step
-- tables there cited (pokeplatinum src/unk_020655F4.c, pokeheartgold
-- asm/unk_02062108.s and asm/unk_020632B0.s).
--
--   bow          POKECENTER_NURSE_BOW: 8 frames, then MapObject_TryFace(SOUTH)
--   pauseAnim /  MAP_OBJ_STATUS_PAUSE_ANIMATION: the frame holds, the object
--   resumeAnim   glides (NPC:pose / Player:pose read `sliding`)
--   axis         Platinum's Distortion World wall walks: one cell along x / z
--                at `frames` frames, facing `face`; along y a beat in place
--   axisJump     the same with a hop and the landing sound
--   leaps        HGSS's beasts: straight-line leaps of (dx, dz) cells over
--                `frames` frames under a 16-unit sine arc
--
-- Every chain here advances from the overworld's update through
-- `scriptPause` / `scriptMove`, never by yielding (see g4_move's own note).

local M = {}

M.TICKS_PER_FRAME = 2
-- the arc of a beast's leap: GF_SinDegNoWrap(180 / frames * i), shifted
-- left 4 -- sixteen units at the top (MapObjectMovementCmd108_Step1)
M.LEAP_HEIGHT = 16

local FACE = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
M.FACE = FACE

local function family()
  local ok, f = pcall(function() return require("src.core.GameVersion").family() end)
  return ok and f or nil
end

local function visible(entity)
  return entity and not entity.hidden and not entity.gen4Invisible
end

local function playSe(ctx, key)
  pcall(function()
    local G = package.loaded["src.core.Game"]
    local data = (ctx and ctx.game and ctx.game.data) or (G and G.data)
    require("src.core.Sound").playSe(data, key)
  end)
end

-- InitJump's take-off sound, SEQ_SE_DP_DANSA, played when the object can be
-- seen (HGSS sub_02062958 tests MapObject_CheckVisible first)
function M.takeoff(ctx, entity, action)
  if action and action.silent then return end
  if visible(entity) then playSe(ctx, "SEQ_SE_DP_DANSA") end
end

-- ...and the landing's: Platinum's Jump_Step1 ends on SEQ_SE_PL_SUTYA2,
-- HGSS's MapObjectMovementCmd092_Step1 on SEQ_SE_DP_SUTYA2
function M.landing(ctx, entity)
  if not visible(entity) then return end
  playSe(ctx, family() == "hgss" and "SEQ_SE_DP_SUTYA2" or "SEQ_SE_PL_SUTYA2")
end

local function setLift(entity, y)
  local so = entity.spriteOffset
  if y == nil or y == 0 then
    if so and so.g4Leap then entity.spriteOffset = nil end
    return
  end
  if not (so and so.g4Leap) then
    if so then return end -- someone else's offset owns the sprite
    so = { g4Leap = true }
    entity.spriteOffset = so
  end
  so.lift = y
end

-- One field frame, the way Gen4WarpMove waits one: a pause queued from
-- inside updateScriptMoves's own pass is counted down once in that pass, so
-- TICKS_PER_FRAME + 1 stands still for two ticks.
local function nextFrame(ow, entity, fn)
  ow:scriptPause(entity, M.TICKS_PER_FRAME + 1, fn)
end

-- leaps(ctx, ow, entity, list, count, done)
function M.leaps(ctx, ow, entity, list, count, done)
  local li, rep = 0, 1
  count = math.max(1, tonumber(count) or 1)
  local leap
  local function nextLeap()
    li = li + 1
    if li > #list then
      rep = rep + 1
      if rep > count then return done() end
      li = 1
    end
    return leap(list[li])
  end
  leap = function(L)
    local dx, dz, dir, frames = L[1], L[3], L[4], math.max(1, L[5])
    if not entity.g4DirLocked and FACE[dir] then entity.facing = FACE[dir] end
    local cx, cy = entity.cellX or 0, entity.cellY or 0
    local sx, sy = cx * 16, cy * 16
    local tx, ty = (cx + dx) * 16, (cy + dz) * 16
    local step = math.floor(180 / frames)
    M.takeoff(ctx, entity, nil)
    local i = 0
    local function frame()
      if i >= frames - 1 then
        -- the last frame: the object lands on its new cell
        -- (MapObject_AddCurrentX / Z, then the landing position)
        setLift(entity, nil)
        entity.cellX, entity.cellY = cx + dx, cy + dz
        entity.px, entity.py = tx, ty
        entity.targetX, entity.targetY = nil, nil
        return nextFrame(ow, entity, nextLeap)
      end
      entity.px = sx + (tx - sx) * i / frames
      entity.py = sy + (ty - sy) * i / frames
      setLift(entity, M.LEAP_HEIGHT * math.sin(math.rad(step * i)))
      i = i + 1
      nextFrame(ow, entity, frame)
    end
    frame()
  end
  nextLeap()
end

-- run(ctx, ow, entity, action, count, nextStep) -> true when `action` is one
-- of this file's kinds (and has been started), false otherwise
function M.run(ctx, ow, entity, action, count, nextStep)
  local kind = action and action.kind
  if kind == "bow" then
    ow:scriptPause(entity, (action.frames or 8) * M.TICKS_PER_FRAME * count, function()
      if not entity.g4DirLocked and action.dir then entity.facing = action.dir end
      nextStep()
    end)
    return true
  elseif kind == "pauseAnim" then
    entity.g4AnimPaused = true
    entity.sliding = true
    nextStep()
    return true
  elseif kind == "resumeAnim" then
    if entity.g4AnimPaused then entity.sliding = nil end
    entity.g4AnimPaused = nil
    nextStep()
    return true
  elseif kind == "axis" or kind == "axisJump" then
    if not entity.g4DirLocked and action.face then entity.facing = action.face end
    local frames = (action.frames or 8)
    if kind == "axisJump" then
      entity.hopFrames = frames * M.TICKS_PER_FRAME * count
      entity.hopTotal = entity.hopFrames
    end
    local function landed()
      if kind == "axisJump" then M.landing(ctx, entity) end
      nextStep()
    end
    if action.dir then
      require("src.script.Gen4MoveExec").setStep(entity, ow, action.rate)
      ow:scriptMove(entity, action.dir, count, landed, true, action.rate)
    else
      ow:scriptPause(entity, frames * M.TICKS_PER_FRAME * count, landed)
    end
    return true
  elseif kind == "leaps" then
    M.leaps(ctx, ow, entity, action.leaps or {}, count, nextStep)
    return true
  end
  return false
end

-- the cells a `leaps` action carries its object, for g4_move's log line
function M.net(action, count)
  local dx, dz = 0, 0
  for _, L in ipairs(action and action.leaps or {}) do
    dx, dz = dx + L[1], dz + L[3]
  end
  local n = math.max(1, tonumber(count) or 1)
  return dx * n, dz * n
end

return M
