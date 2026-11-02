-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LIFTS' RIDE AND THEIR "CURRENT FLOOR" WINDOW -- Platinum and HGSS.
--
--   Platinum  PlayElevatorAnimation <dir> <loops>   (0x23C, "ww")
--             ShowCurrentFloor <left> <top> <var> <unused>   (0x11D, "bbww")
--   HGSS      ElevatorAnim <dir> <length>           (0x1E8, "ww")
--             ElevatorCurFloorBox <x> <y> <var> <floor>      (0x0F2, "bbww")
--
-- THE RIDE (pokeplatinum src/overlay006/elevator_animation.c,
-- FieldSystem_PlayElevatorAnimation; pokeheartgold ScrCmd_ElevatorAnim ->
-- ov02_0224BDE8 / ov02_0224BE24, asm/overlay_02_02248728.s -- the same task
-- instruction for instruction).  The map must hold the elevator-lights prop
-- (Platinum `elevator_lights.nsbmd`, build_model 498; HGSS room model 0xD0 =
-- 208, both named `ev_o01` inside), else the cartridge asserts and starts no
-- task -- the script runs straight on.  Then a field task, one state a frame:
--
--   LOAD    MapPropOneShotAnimationManager_LoadPropAnimations(tag 1, the prop,
--           2 animations, loopCount): the prop's anim-list record's first two
--           ids, each MapPropAnimation_Init'ed paused on frame 0 with
--           `loopCount` loops (a 0 is made 1) -- not yet on the render object
--   PLAY    PlayAnimation(tag 1, direction): animation `direction` (0 up,
--           1 down) is switched onto the prop and unpaused; SEQ_SE_DP_ELEBETA2
--   WAIT    until IsAnimationLoopFinished: MapPropAnimationManager_Advance-
--           Animations steps it a frame a field frame, wrapping at numFrames,
--           and stops it on its last frame once `currentLoop + 1 >= loops` --
--           so it runs loops * numFrames - 1 frames.  Then StopSE ELEBETA2,
--           PlaySE SEQ_SE_DP_PINPON, UnloadAnimation (the prop is back at
--           rest: the animation leaves the render object)
--   PINPON  until the chime has stopped
--   done    the script resumes
--
-- WHICH ANIMATIONS AND HOW LONG: the anim-list record (Platinum
-- /arc/bm_anime_list.narc #498 = flags 3, ids { 35, 36 }; HGSS /a/1/0/8 #208 =
-- flags 3, ids { 224, 225 }), whose members are `ev_o01_up` / `ev_o01_down`,
-- BTA0 texture scrolls of 31 frames (Platinum) and 30 (HGSS).  The cache
-- already carries every one of those: the records are in `gen4_models`'
-- field sets (Platinum `field`, claimed by 498 as `props`; HGSS
-- `interiorField`, claimed by 208 as `scriptProps`), each with its frame count
-- and SRT tracks -- so the ride reads them from the ground, in list order
-- (ascending member, which is the record's order on both cartridges), and
-- needs no import of its own.  Flags 3 is DEFERRED LOAD: nothing plays them on
-- the frame clock (Gen4PropAnim.INTERACTION_ANIMATIONS lists 35/36 for
-- Platinum; HGSS's own `scripted` set already holds 224/225).
--
-- The picture is a Gen4PropControl hold the task moves a frame at a time, so
-- the scroll and the task agree on the frame by construction.
--
-- Installed by Gen4ScriptVM (`install` with the lowering table), after the
-- rows it replaces.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}
M.TICKS_PER_FRAME = 2
M.TAG = 1                         -- ELEVATOR_ANIMATION_TAG
M.PLATINUM_PROP = "elevator_lights.nsbmd"
M.PLATINUM_PROP_INDEX = 498       -- build_model.narc member, the fallback
M.HGSS_PROP = 0xD0                -- ov02_0224BDE8's literal (room model 208)
M.SE_RIDE = "SEQ_SE_DP_ELEBETA2"
M.SE_ARRIVE = "SEQ_SE_DP_PINPON"
M.CHIME_LIMIT = 60 * 6            -- engine ticks the chime may hold the script

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function hgss()
  local okV, GV = pcall(require, "src.core.GameVersion")
  return okV and GV.family and GV.family() == "hgss" or false
end
local function groundOf(ctx)
  local ow = ctx and ctx.overworld
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground or nil
end
local function Control() return require("src.render.Gen4PropControl") end
local function gameData(ctx)
  return (ctx.game and ctx.game.data) or (package.loaded["src.core.Game"] or {}).data
end

-- the elevator-lights prop's model index on this cartridge
function M.propModel()
  if hgss() then return M.HGSS_PROP end
  local okA, A = pcall(require, "src.import.Gen4Archives")
  local id = okA and A.find and A.find("/fielddata/build_model/build_model.narc", M.PLATINUM_PROP) or nil
  return id or M.PLATINUM_PROP_INDEX
end

-- records(ground, model) -> { up, down } (the prop's anim-list order) | nil
function M.records(ground, model)
  local byMember = ground and ground.animsByMember
  if type(byMember) ~= "table" then return nil end
  -- Plain numeric loops, and the function kept off the JIT (below): written
  -- as pairs-over-ipairs-over-ipairs, the compiled trace answered "owned by
  -- nobody" on some visits and not others in the harness, run to run.
  local KEYS = { "props", "scriptProps", "heldProps" }
  local list = {}
  for member, record in pairs(byMember) do
    local owned = false
    if type(record) == "table" then
      for k = 1, #KEYS do
        local owners = record[KEYS[k]]
        if type(owners) == "table" then
          for i = 1, #owners do
            if owners[i] == model then owned = true end
          end
        end
      end
    end
    if owned then list[#list + 1] = { member = member, record = record } end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a.member < b.member end)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.record end
  return out
end

-- FieldSystem_FindLoadedMapPropByModelID: is the prop on this map?
function M.propPlaced(ground, model)
  local grid, chunks = ground and ground.grid, ground and ground.terrain and ground.terrain.chunks
  if not (grid and grid.land and chunks) then return false end
  for _, land in ipairs(grid.land) do
    local record = chunks[land]
    for _, object in ipairs((record and record.objects) or {}) do
      if object.archive ~= "fldeff" and object.model == model then return true end
    end
  end
  return false
end

-- run once per ride: interpreted, so the lookups above cannot be mis-traced
if jit and jit.off then
  pcall(jit.off, M.records, true)
  pcall(jit.off, M.propPlaced, true)
end

-- the frames an animation of `frames` frames runs with `loops` loops before
-- MapPropAnimationManager_AdvanceAnimations stops it on its last frame
function M.rideFrames(frames, loops)
  frames = math.max(1, math.floor(tonumber(frames) or 1))
  loops = math.max(1, math.floor(tonumber(loops) or 1))
  return loops * frames - 1
end

-- the frame shown `k` advances after PlayAnimation (wraps at numFrames)
function M.frameAt(k, frames, loops)
  frames = math.max(1, math.floor(tonumber(frames) or 1))
  k = math.min(math.max(0, k), M.rideFrames(frames, loops))
  return k % frames
end

local function se(ctx, name)
  local data = gameData(ctx)
  local ok, src = pcall(function() return require("src.core.Sound").playSe(data, name) end)
  return ok and src or nil
end
local function stopSe(ctx, name)
  local data = gameData(ctx)
  pcall(function() require("src.core.Sound").stopSe(data, name) end)
end
local function sePlaying(ctx, name)
  local data = gameData(ctx)
  local ok, yes = pcall(function() return require("src.core.Sound").isSePlaying(data, name) end)
  return ok and yes or false
end

-- block the script on `step`, called once per FIELD frame until it says done
local function waitFrames(ctx, step)
  local runner = ctx.runner
  if not runner then
    for _ = 1, 100000 do if step() then return end end
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

-- the last ride, for probes and checks
M.last = nil

function Commands.g4_elevator_anim(ctx, direction, loops)
  local dir = valueOf(ctx, direction)
  -- both cartridges keep the two operands as u8
  local count = valueOf(ctx, loops) % 256
  if count == 0 then count = 1 end   -- GF_ASSERT, then made 1
  local ground = groundOf(ctx)
  local model = M.propModel()
  local records = ground and M.records(ground, model)
  if not (ground and records and M.propPlaced(ground, model)) then
    -- GF_ASSERT(FALSE) and no task: the script runs straight on
    Logger.warn("gen4 lift: no elevator-lights prop (model %s) on %s -- the ride plays nothing",
      tostring(model), tostring(ctx.overworld and ctx.overworld.map and ctx.overworld.map.id))
    return
  end
  if dir ~= 0 and dir ~= 1 then
    Logger.warn("gen4 lift: elevator direction %d is neither up (0) nor down (1)", dir)
  end
  local record = records[dir + 1] or records[1]
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local ride = M.rideFrames(frames, count)
  local control
  local state, k, chime, chimeTicks = "load", 0, nil, 0
  local log = { direction = dir, loops = count, frames = frames, rideFrames = ride,
                member = record.member, model = model, map = ctx.overworld and ctx.overworld.map and ctx.overworld.map.id }
  M.last = log
  waitFrames(ctx, function()
    if state == "load" then
      state = "play"
    elseif state == "play" then
      control = { attach = true, hold = 0 }
      Control().set(ground, model, record.member, control)
      se(ctx, M.SE_RIDE)
      log.played = true
      state = "wait"
    elseif state == "wait" then
      k = k + 1
      control.hold = M.frameAt(k, frames, count)
      if k >= ride then
        stopSe(ctx, M.SE_RIDE)
        chime = se(ctx, M.SE_ARRIVE)
        Control().set(ground, model, record.member, nil)
        log.advanced = k
        state = "pinpon"
      end
    elseif state == "pinpon" then
      chimeTicks = chimeTicks + M.TICKS_PER_FRAME
      if not chime or not sePlaying(ctx, M.SE_ARRIVE) or chimeTicks >= M.CHIME_LIMIT then
        state = "done"
      end
    else
      log.done = true
      return true
    end
    return false
  end)
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_elevator_anim = { foreground = true, blocking = true }

-- ShowCurrentFloor / ElevatorCurFloorBox: the window (src/ui/Gen4FloorWindow).
-- `var` is a var POINTER the window watches and never writes; `floor` is
-- HGSS's floor number (ScriptGetVar) and Platinum's unused fourth operand.
function Commands.g4_floor_window(ctx, left, top, var, floor)
  local ow = ctx.overworld
  if not (ow and ctx.game) then return end
  local def = ow.map and ow.map.def
  local panel = require("src.ui.Gen4FloorWindow").panelFor(ctx.game, tonumber(left), tonumber(top),
    tonumber(var), valueOf(ctx, floor), def and def.header)
  if panel then panel.map = ow.map and ow.map.id end
  ow.gen4FloorWindow = panel
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  local function anim(ins, s) emit(s, { "g4_elevator_anim", ins.args[1], ins.args[2] }) end
  local function window(ins, s)
    emit(s, { "g4_floor_window", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
  end
  L.playelevatoranimation, L.elevatoranim = anim, anim
  L.showcurrentfloor, L.elevatorcurfloorbox = window, window
end

return M
