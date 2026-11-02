-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S `applymovement`, PLAYED.
--
-- Reported from play: "NPCs dont move properly in events in black and white".
-- BW's scripted walks had been played through Platinum's executor and
-- Platinum's action table (Gen4Movement), which is right for the first 0x4C
-- actions and wrong after them, and the executor itself dropped what BW's
-- scenes lean on:
--
--   * SPEED. Every NPC walked at one pace: the queue stamps a fast step's
--     length on `stepFramesCur`, which NPC:update never read. BW writes its
--     rushes (Bianca running in, the Plasma grunts) in 4- and 2-frame steps.
--     Now `scriptStepLen` carries the cartridge's own frames to the walker.
--   * THE PLAYER'S PACE. A BW player's free step is 8 engine ticks (the
--     install's own constant), an NPC's 16, so a scripted walk played at the
--     walker's "normal" sent the player ahead of whoever they were walking
--     with. On the cartridge both run the same action at the same frames, so
--     every scripted step here is the action's frames x 2 ticks, whoever
--     takes it.
--   * THE LOCKED FACING (0x47 / 0x48, 288 uses). `47 0C 48` is a step back
--     still looking the same way; it was played as a turn and a walk.
--   * JUMPS (0x2C-0x3B, 0x5C-0x5F, 0x75-0x78) had no arc; the hop now rises
--     on Gen4Jump's table for walker and player alike.
--   * MARKING TIME (0x18-0x2B, 2,000+ uses) stood still for the beat; the
--     sprite now walks on the spot, for the action's own frames.
--   * WAITS were counted in engine ticks rather than field frames (half
--     length), and the "?", the note and the "..." (0x9F / 0xA0 / 0xA1) were
--     skipped or drawn as "!".
--   * The player's raised-arm poses (0x66 / 0x68 / 0xA2) and the characters'
--     own animations (0x64, 0xB5-0xBB) are held for their beat instead of
--     being skipped, so what follows them keeps its timing.
--
-- Queued, never yielding: every link after the first runs from the
-- overworld's update (see Gen4Commands.g4_move for why), and the join
-- (`ctx.g4Moving` / `ctx.g4MoveJoin`) is Platinum's, so `waitmovement`
-- needs nothing new.

local Logger = require("src.core.Logger")
local Movement = require("src.import.Gen5Movement")

local X = {}

-- the scripted step length the walker uses this step (NPC:update reads it)
local function setStep(entity, ow, ticks)
  if entity == ow.player then
    entity.stepFramesCur = ticks
  else
    entity.scriptStepLen = ticks
  end
end

-- `rate` for OverworldState:scriptMove, against the walker's own baseline
local function rateFor(entity, ow, ticks)
  local base = (entity == ow.player and entity.stepFrames) or entity.stepFrames or Movement.NORMAL_TICKS
  return ticks / math.max(1, base)
end

local function armEmote(ctx, ow, entity, kind, onDone)
  local Gen4Emotes = require("src.import.Gen4Emotes")
  local def = ow.map and ow.map.def
  local frames = Gen4Emotes.FRAMES * Gen4Emotes.ticksFor(def)
  local bubble = { npc = entity, frames = frames, totalFrames = frames,
                   bubble = (kind == "exclamation") and 1 or kind, onDone = onDone }
  if ow.emote then
    ow.extraEmotes = ow.extraEmotes or {}
    ow.extraEmotes[#ow.extraEmotes + 1] = bubble
  else
    ow.emote = bubble
  end
  -- no sound: BW's emote effect (0x021BB528, its task list 0x021D9A7C)
  -- plays none -- the scripts play their own first (`A6 0559`, then the
  -- 0x4B list, then `A8`)
end

-- run(ctx, entity, id, steps): queue `steps` (the decoded list) on `entity`
function X.run(ctx, entity, id, steps)
  local ow = ctx.overworld
  require("src.script.Commands").claimMove(ctx, entity)
  local index, finished = 0, false
  local function finish()
    if finished then return end
    finished = true
    entity.scriptStepLen = nil
    ctx.g4Moving = math.max(0, (ctx.g4Moving or 1) - 1)
    if ctx.g4Moving == 0 and ctx.g4MoveJoin then
      local join = ctx.g4MoveJoin
      ctx.g4MoveJoin = nil
      join()
    end
  end
  local nextStep
  -- AN ACTION IS AT LEAST A FIELD FRAME. A turn's init and its "done" run in
  -- one frame (0x2197F91 returns 1 into 0x2197F5D), and the list hands out
  -- its next action on the frame after -- so `02 00 03 01`, the Striaton
  -- triplets' spin, is four frames of turning, not one instant
  local function beat()
    ow:scriptPause(entity, Movement.TICKS_PER_FRAME, nextStep)
  end
  -- n marks on the spot, one after another, each its own walk cycle
  local function march(n, ticks)
    if n <= 0 then return nextStep() end
    -- the PLAYER holds the beat standing: Player:update's in-place cycle can
    -- land on a stale step target (Nuvema, M0778 S02D9's `23` put the player
    -- on Bianca's cell and the scene never released)
    if entity == ow.player then
      return ow:scriptPause(entity, ticks * n, nextStep)
    end
    setStep(entity, ow, ticks)
    ow:marchInPlace(entity, function() march(n - 1, ticks) end)
  end
  local function advance()
    index = index + 1
    local step = steps[index]
    if not step then return finish() end
    local a = Movement.action(step.action)
    local count = math.max(tonumber(step.count) or 1, 1)
    if a == nil then
      return nextStep()
    end
    local kind = a.kind
    if kind == "walk" or kind == "jump" then
      local ticks = Movement.ticks(a)
      local tiles = (a.tiles or 1) * count
      setStep(entity, ow, ticks)
      -- TURN FIRST: the cartridge's walk sets the direction at the step's
      -- start, and scriptMove only turns an NPC once its first cell is done,
      -- so a seven-cell walk away began as a step backwards (Mom leaving the
      -- player on Route 2 after the Running Shoes, still facing them)
      if a.dir and not entity.g5DirLocked then entity.facing = a.dir end
      if kind == "jump" then
        -- one arc over the whole jump, Gen4Jump's sixteen-frame table
        entity.hopFrames = ticks * (a.tiles or 1) * count
        entity.hopTotal = entity.hopFrames
      end
      ow:scriptMove(entity, a.dir, tiles, nextStep,
                    entity.g5DirLocked or nil, rateFor(entity, ow, ticks))
    elseif kind == "face" then
      if not entity.g5DirLocked then entity.facing = a.dir end
      return beat()
    elseif kind == "spot" then
      if not entity.g5DirLocked then entity.facing = a.dir end
      return march(count, Movement.ticks(a))
    elseif kind == "hop" then
      if not entity.g5DirLocked then entity.facing = a.dir end
      local ticks = Movement.ticks(a)
      local left = count
      local function one()
        if left <= 0 then return nextStep() end
        left = left - 1
        entity.hopFrames, entity.hopTotal = ticks, ticks
        ow:scriptPause(entity, ticks, one)
      end
      return one()
    elseif kind == "wait" or kind == "anim" then
      if a.se then
        pcall(function() require("src.script.Commands").play_sound(ctx, a.se) end)
      end
      ow:scriptPause(entity, Movement.ticks(a) * count, nextStep)
    elseif kind == "animpause" then
      -- a held animation glides (NPC:pose draws the standing frame)
      if not entity.g5AnimHeld then
        entity.g5AnimHeld, entity.g5SlidingBefore = true, entity.sliding
      end
      entity.sliding = true
      return beat()
    elseif kind == "animresume" then
      if entity.g5AnimHeld then
        entity.sliding, entity.g5AnimHeld, entity.g5SlidingBefore = entity.g5SlidingBefore, nil, nil
      end
      return beat()
    elseif kind == "hide" then
      entity.hidden = true
      return beat()
    elseif kind == "show" then
      entity.hidden = nil
      return beat()
    elseif kind == "lock" then
      entity.g5DirLocked = true
      return beat()
    elseif kind == "unlock" then
      entity.g5DirLocked = nil
      return beat()
    elseif kind == "emote" then
      return armEmote(ctx, ow, entity, a.emote, nextStep)
    else
      return beat()
    end
  end
  nextStep = function()
    local ok, err = pcall(advance)
    if not ok then
      Logger.warn("g5 move: step %d for object %s failed (%s); releasing the "
                  .. "wait on it", index, tostring(id), tostring(err))
      finish()
    end
  end
  ctx.g4Moving = (ctx.g4Moving or 0) + 1
  nextStep()
end

-- Where the list leaves the walker, for the log line g4_move writes.
function X.net(steps)
  local dx, dy = 0, 0
  for _, step in ipairs(steps or {}) do
    local a = Movement.action(step.action)
    if a and (a.kind == "walk" or a.kind == "jump") and a.dir then
      local n = (a.tiles or 1) * math.max(tonumber(step.count) or 1, 1)
      if a.dir == "up" then dy = dy - n
      elseif a.dir == "down" then dy = dy + n
      elseif a.dir == "left" then dx = dx - n
      elseif a.dir == "right" then dx = dx + n end
    end
  end
  return dx, dy
end

return X
