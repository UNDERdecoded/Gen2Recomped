-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DISTORTION WORLD'S MOVING PLATFORMS: the lifts between floors and B2F's
-- rafts, which the story moves.  Reported from play (the third of three
-- Distortion World gaps): "the game moves some platforms from story events,
-- and those still only show in their starting position".
--
-- pret's pokeplatinum, overlay009/ov9_02249960.c, transcribed:
--
--   * A LIFT exists on a floor only while its `persistedFlag` is set (or it
--     has none, DIST_WORLD_PLATFORM_FLAG_INVALID == 11) --
--     InitMovingPlatformPropsForMapEx.  A fresh Distortion World starts with
--     B4F_1 and B5F_1 set (InitPersistedData; every lift flag when it starts
--     on B7F).  Riding a lift applies its LAST path's flagToSet/flagToClear at
--     the change of maps (DistWorldElevatorPlatform_ChangeMaps), and riding up
--     paths 13, 10 and 11 adjusts three more as it begins
--     (DistWorldElevatorPlatform_BeginMovement).  The ride itself vibrates the
--     platform, then carries it and the player by the path's `posDelta` each
--     frame until the change-of-maps offset, then the next floor loads with
--     the platform still travelling the rest of the way to `final`.
--   * A RAFT moves when a COORDINATE EVENT runs (HandleEventAt, on the tile
--     the player's step ended on, if its flag condition holds):
--     EVENT_CMD_MOVE_PLATFORM vibrates the platform, then slides it by
--     `posDelta` a frame to `finalTile*Offset`, carrying the player when
--     `movePlayer` says so; EVENT_CMD_SET_MAP_OBJECT_ANIMATION gives local id
--     255 -- the player -- a MOVEMENT_ACTION_JUMP_DISTORTION_WORLD_* (117..120:
--     the two-tile hop north, south, west, east).

local P = {}

P.FLAG_NONE = 11
P.FLAG_B4F_1, P.FLAG_B4F_2, P.FLAG_B5F_3, P.FLAG_B3F_2, P.FLAG_B5F_1 = 3, 4, 5, 6, 7
P.B7F = 581
-- every lift flag, which is how the overlay starts on B7F
P.ALL_B7F = { 0, 1, 2, 3, 4, 7, 9, 10 }

-- 117..120: JUMP_DISTORTION_WORLD_{NORTH,SOUTH,WEST,EAST}
P.HOP_DIR = { [117] = { 0, -1, "up" }, [118] = { 0, 1, "down" },
              [119] = { -1, 0, "left" }, [120] = { 1, 0, "right" } }

local band, bor, bnot, lshift
do
  local ok, bit = pcall(require, "bit")
  if ok and bit then
    band, bor, bnot, lshift = bit.band, bit.bor, bit.bnot, bit.lshift
  else
    band = function(a, b) local r, m = 0, 1
      while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + m end
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end
    lshift = function(a, n) return a * 2 ^ n end
    bor = function(a, b) return a + b - band(a, b) end
    bnot = function(a) return 0xFFFFFFFF - a end
  end
end

local function Game() return package.loaded["src.core.Game"] end
local function dwData()
  local G = Game()
  return G and G.data and G.data.gen4_distortion_world
end

-- The persisted lift flags (DistWorldPersistedData.movingPlatformFlags).
function P.flags(header)
  local G = Game()
  local save = G and G.save
  if not save then return 0 end
  if save.gen4DistPlatformFlags == nil then
    local f = 0
    if tonumber(header) == P.B7F then
      for _, i in ipairs(P.ALL_B7F) do f = bor(f, lshift(1, i)) end
    else
      f = bor(lshift(1, P.FLAG_B4F_1), lshift(1, P.FLAG_B5F_1))
    end
    save.gen4DistPlatformFlags = f
  end
  return save.gen4DistPlatformFlags
end

function P.flagSet(i, header)
  i = tonumber(i)
  if not i or i >= P.FLAG_NONE then return true end
  return band(P.flags(header), lshift(1, i)) ~= 0
end

local function setFlag(i, on)
  i = tonumber(i)
  local G = Game()
  if not (i and i < P.FLAG_NONE and G and G.save) then return end
  local f = P.flags()
  if on then f = bor(f, lshift(1, i)) else f = band(f, bnot(lshift(1, i))) end
  G.save.gen4DistPlatformFlags = f
end
P.setFlag = setFlag

-- Show only the lifts whose flag is set, and gate their warps the same way --
-- AND THE ONE THE PLAYER IS STANDING ON.  The cartridge's platform that
-- carried you down stays where it landed (DistWorldMovingPlatformPropAnimator_
-- ChangeMaps), whatever the flags say; a save that reached a floor before the
-- flags were kept (or by a script) otherwise stood in an empty lift pocket
-- (reported from play: "this area leads somewhere empty").
function P.refresh(def)
  if not (def and def.gen4DistLive) then return end
  for _, live in pairs(def.gen4DistLive) do
    local t = live.template
    if t and t.elevatorDir ~= 2 then
      live.hidden = not (live.present or P.flagSet(t.persistedFlag, def.header))
    end
  end
end

-- A lift whose 5x5 pocket the player is in is present for this visit.
local function markPresent(ow, def, m)
  local p = ow.player
  local wx, wz = p.cellX + (m.offsetX or 0), p.cellY + (m.offsetZ or 0)
  local changed = false
  for _, live in pairs(def.gen4DistLive or {}) do
    local t = live.template
    if t and t.elevatorDir ~= 2 and not live.present
       and math.abs(t.x - wx) <= 2 and math.abs(t.z - wz) <= 2 then
      live.present = true
      changed = true
    end
  end
  return changed
end

local function liveAt(def, info, wx, wz)
  for _, live in pairs(def.gen4DistLive or {}) do
    local t = live.template
    if t and t.x == wx and t.z == wz and t.elevatorDir ~= 2 then return live end
  end
end

local function floorInfo(def)
  local dw = dwData()
  local h = def and tonumber(def.header)
  local m = dw and dw.maps and h and (dw.maps[h] or dw.maps[tostring(h)])
  return m, dw
end

local function pathChain(dw, first)
  local chain, p = {}, dw.elevatorPaths and dw.elevatorPaths[first]
  while p do
    chain[#chain + 1] = p
    if (p.nextIndex or 22) >= 22 or #chain > 8 then break end
    p = dw.elevatorPaths[p.nextIndex]
  end
  return chain
end

-- Warp.onArrive hands every lift warp here.  Returns nil always: an inactive
-- lift is not there, and an active one is ridden before the warp is taken.
function P.arrive(map, w)
  local G = Game()
  local ow = G and G.overworld
  local def = map and map.def
  if not (ow and def) then return nil end
  if ow.dwRide then return nil end
  local m, dw = floorInfo(def)
  if not (m and dw) then return w end
  local wx, wz = w.def.x + (m.offsetX or 0), w.def.y + (m.offsetZ or 0)
  local live = liveAt(def, m, wx, wz)
  if not live then return w end
  P.refresh(def)
  if live.hidden then return nil end
  local t = live.template
  local chain = pathChain(dw, t.elevatorPath)
  if #chain == 0 then return w end
  local first, last = chain[1], chain[#chain]
  -- BeginMovement's three up-paths
  if t.elevatorDir == 0 then
    if t.elevatorPath == 13 then setFlag(P.FLAG_B4F_1, true); setFlag(P.FLAG_B4F_2, false)
    elseif t.elevatorPath == 10 then setFlag(P.FLAG_B5F_3, false)
    elseif t.elevatorPath == 11 then
      setFlag(P.FLAG_B3F_2, true); setFlag(P.FLAG_B4F_1, false); setFlag(P.FLAG_B5F_3, false)
    end
  end
  local dy = (first.deltaY or 0) / 4096
  if dy == 0 then dy = (first.changeMapsY or 0) < 0 and -4 or 4 end
  ow.dwRide = {
    -- Cynthia riding down with the player (BeginMovement's passenger)
    passenger = t.elevatorDir == 1 and P.passengerFor(ow, def, m, w.def.destHeader) or nil,
    phase = "vibrate", t = 0, live = live, warp = w.def,
    stopY = (first.changeMapsY or 0) * 16, dy = dy, y = 0,
    flagToSet = last.flagToSet, flagToClear = last.flagToClear,
    -- the second half, on the far floor: from (final - changeMaps) to rest
    arriveFrom = ((last.finalY or 0) - (last.changeMapsY or 0)) * 16
                 + (#chain > 1 and 0 or 0),
    destHeader = w.def.destHeader, wx = wx, wz = wz,
  }
  ow.player.inputLocked = true
  pcall(function() require("src.core.Sound").play(G.data, "Elevator") end)
  return nil
end

local function ground(ow)
  local r = ow.map and ow.map.renderer
  return r and r.gen4Ground
end

local function standY(ow)
  -- the height Gen4DistSurface keeps over unplated tiles (a lift's pocket)
  if ow.dwMapY then return ow.dwMapY end
  local g = ground(ow)
  local p = ow.player
  if g and g.groundY then
    local ok, h = pcall(g.groundY, g, p.cellX * 16 + 8, p.cellY * 16 + 8)
    if ok and tonumber(h) then return h end
  end
  return 0
end

local function poseAt(ow, y)
  ow.dwPose = { y = y, nx = 0, ny = 1, nz = 0 }
  -- held for the engine frames between the overlay's 30 a second
  ow.dwRidePose = ow.dwPose
  local g = ground(ow)
  if g then g.surfaceBaseY = y end
end

local function tickRide(ow, def)
  local r = ow.dwRide
  r.t = r.t + 1
  local live = r.live
  if r.phase == "vibrate" then
    -- the platform shudders, a few units either way, for half a second
    local v = (r.t % 2 == 0) and 2 or -2
    if r.t >= 24 then v = 0; r.phase = "move" end
    live.dy = v
    poseAt(ow, (r.base or standY(ow)) + v)
    r.base = r.base or standY(ow)
    if r.passenger then P.sprite(ow, r.passenger.fromId, { lift = v }) end
  elseif r.phase == "move" then
    r.y = r.y + r.dy
    local done = (r.dy < 0 and r.y <= r.stopY) or (r.dy > 0 and r.y >= r.stopY)
    if done then r.y = r.stopY end
    live.dy = r.y
    poseAt(ow, r.base + r.y)
    if r.passenger then P.sprite(ow, r.passenger.fromId, { lift = r.y }) end
    if done then
      -- DistWorldElevatorPlatform_ChangeMaps
      if r.flagToSet then setFlag(r.flagToSet, true) end
      if r.flagToClear then setFlag(r.flagToClear, false) end
      -- the passenger changes maps with the platform: off this floor, onto
      -- the next one as its own local id (P.spawnCast places it there)
      if r.passenger then
        P.castDelete(ow, r.passenger.fromId)
        if ow.dwSprites then ow.dwSprites[r.passenger.fromId] = nil end
        ow.dwPassenger = r.passenger
      end
      live.dy = nil
      ow.dwRide = nil
      ow.player.inputLocked = false
      ow.dwArrive = { from = r.arriveFrom, wx = r.wx, wz = r.wz, header = r.destHeader, t = 0,
                      dy = math.abs(r.dy), passengerId = r.passenger and r.passenger.localId }
      local okW, err = pcall(ow.takeWarp, ow, r.warp)
      if not okW then print("[dwplatforms] lift warp: " .. tostring(err)) end
    end
  end
end

-- The far half of a ride: the platform and the player come down (or up) from
-- where the near floor left them to the platform's own place.
local function tickArrive(ow, def, m)
  local a = ow.dwArrive
  if tonumber(def.header) ~= tonumber(a.header) then
    a.t = a.t + 1
    if a.t > 240 then ow.dwArrive = nil end
    return
  end
  local live = liveAt(def, m, a.wx, a.wz)
  if not live then ow.dwArrive = nil; return end
  if a.y == nil then
    a.y = a.from
    a.base = standY(ow)
    ow.player.inputLocked = true
  end
  local step = a.dy > 0 and a.dy or 4
  if a.y > 0 then a.y = math.max(0, a.y - step) elseif a.y < 0 then a.y = math.min(0, a.y + step) end
  live.dy = a.y ~= 0 and a.y or nil
  poseAt(ow, a.base + a.y)
  if a.passengerId then
    if a.y ~= 0 then P.sprite(ow, a.passengerId, { lift = a.y })
    elseif ow.dwSprites then ow.dwSprites[a.passengerId] = nil end
  end
  if a.y == 0 then
    ow.dwArrive = nil
    ow.player.inputLocked = false
    live.dy = nil
  end
end

-- ------------------------------------------------------------------ rafts

local function condHolds(e)
  local c = tonumber(e.flagCond) or 0
  if c == 0 then return true end
  -- the progress conditions read the story's own Distortion World progress
  -- VAR_DISTORTION_WORLD_PROGRESS is 0x4055 (the floors' frame tables read it)
  local G = Game()
  local G4 = require("src.script.Gen4Commands")
  local okV, progress = pcall(G4.getVar, G and G.save, 0x4055)
  progress = okV and tonumber(progress) or nil
  if not progress then return false end
  local v = tonumber(e.flagCondVal) or 0
  if c == 3 then return progress == v elseif c == 4 then return progress <= v
  elseif c == 5 then return progress >= v end
  return false
end

-- EVERY COMMAND KIND NOW RUNS (sEventCmdHandlers).  The ones that only drive
-- the cartridge's lighting -- the sky's darkness during Giratina's arrival --
-- are timed rather than tinted.
local function runnable(e)
  return e.commands ~= nil
end

-- THE OVERLAY'S EVENTS ARE FIELD TASKS, AND A FIELD TASK OWNS THE FIELD.
--
-- Reported from the Platinum playthrough: in the Giratina room the player
-- walked 23 -> 20 -> 17 -> 14 while the platforms event (z 23) was still
-- running, so z 17's shadow and z 14's arrival never fired and progress
-- stuck at 11 -- a room with no way on.  `player.inputLocked` was set, but
-- only Player:tryMove reads it: the room's stepping stones are LEDGE HOPS,
-- and checkLedgeHop (like the edge exits, warps and boulder pushes beside
-- it in handleInput) starts its own scripted move without asking.
--
-- On the cartridge nothing in handleInput can run then.  HandleEventAt,
-- the waterfall (RunEventCommands) and the lifts (CallElevatorPlatform-
-- Handler) all start with FieldSystem_CreateTask, and HandleFieldInput
-- (field_system.c) reads the pad at all only while
-- FieldSystem_IsRunningTask is FALSE -- no step, no hop, no A, no START,
-- and no Field_ProcessStep (so no HandleEventAt) until the task returns.
-- A startScript inside the event runs as the task's own sub-task
-- (ScriptManager_Start(task, ...)), so a script's ReleaseAll does not end
-- it either.  This names the running task; OverworldController adds it to
-- its `scripted` gate, which is that same skip.
function P.fieldTask(ow)
  if ow.dwEvent then return "a Distortion World event (HandleEventAt)" end
  if ow.dwRide or ow.dwArrive then return "a Distortion World lift ride" end
  if ow.dwCascade then return "a Distortion World waterfall ride" end
  return nil
end

-- HandleEventAt: the first event on the tile whose condition holds.  Asked
-- only when no task runs (Gen4DistSurface.stepEnded passes over a move that
-- ended under one without recording it), so this refusal is a guard only.
function P.onPosition(ow, m, dw, x, y, z)
  if ow.dwEvent or ow.dwRide then return false end
  local def = ow.map and ow.map.def
  local list = dw.events and (dw.events[tonumber(def.header)] or dw.events[tostring(def.header)])
  for _, e in ipairs(list or {}) do
    if e.x == x and e.y == y and e.z == z and P.condition(e.flagCond, e.flagCondVal) then
      if not runnable(e) then return false end
      ow.dwEvent = { e = e, i = 1, state = nil }
      ow.player.inputLocked = true
      if os.getenv and os.getenv("DWTRACE") then
        print(("[dwevent] %s at %d,%d,%d: %s"):format(tostring(def.id), x, y, z, table.concat(e.commands, ",")))
      end
      return true
    end
  end
  return false
end
local function tickEvent(ow, def, m, dw)
  local ev = ow.dwEvent
  local e = ev.e
  local kind = e.commands[ev.i]
  if not kind then
    ow.dwEvent = nil
    ow.player.inputLocked = false
    return
  end
  local a = (e.params and e.params[ev.i]) or {}
  local S = require("src.world.Gen4DistSurface")
  if kind == "movePlatform" then
    local live = def.gen4DistLive and def.gen4DistLive[a.platformIndex]
    if not live then ev.i = ev.i + 1; ev.state = nil; return end
    if not ev.state then
      ev.state = { phase = "vibrate", t = 0, base = live.dz or 0, bx = live.dx or 0, by = live.dy or 0,
                   cur = { 0, 0, 0 },
                   final = { (a.offsetX or 0) * 16, (a.offsetY or 0) * 16, (a.offsetZ or 0) * 16 },
                   delta = { a.deltaX or 0, a.deltaY or 0, a.deltaZ or 0 } }
      pcall(function() require("src.core.Sound").play(require("src.core.Game").data, "Elevator") end)
    end
    local st = ev.state
    st.t = st.t + 1
    local carry = a.movePlayer == 1
    if st.phase == "vibrate" then
      local v = (st.t % 2 == 0) and 1 or -1
      if st.t >= 8 then v = 0; st.phase = "move" end
      live.dy = st.by + v
      if carry then ow.dwCarry = { 0, v, 0 } end
    else
      local done = true
      for k = 1, 3 do
        if st.cur[k] ~= st.final[k] then
          local d = st.delta[k]
          if d == 0 then d = (st.final[k] > st.cur[k]) and 4 or -4 end
          st.cur[k] = st.cur[k] + d
          if (d > 0 and st.cur[k] > st.final[k]) or (d < 0 and st.cur[k] < st.final[k]) then st.cur[k] = st.final[k] end
          if st.cur[k] ~= st.final[k] then done = false end
        end
      end
      live.dx = st.bx + st.cur[1]
      live.dy = st.by + st.cur[2]
      live.dz = st.base + st.cur[3]
      if carry then ow.dwCarry = { st.cur[1], st.cur[2], st.cur[3] } end
      if done then
        -- EventCmdMovePlatform_EndMovement: the player's tile moves with it
        if live.dx == 0 then live.dx = nil end
        if live.dy == 0 then live.dy = nil end
        if live.dz == 0 then live.dz = nil end
        if carry then
          ow.dwCarry = nil
          S.relocate(ow, a.offsetX or 0, a.offsetY or 0, a.offsetZ or 0)
        end
        ev.i, ev.state = ev.i + 1, nil
      end
    end
  elseif kind == "setMapObjectAnimation" then
    if not ev.state then
      local hop = P.HOP_DIR[a.movementAction]
      ev.state = { started = S.hop(ow, hop[1] * 3, hop[2] * 3, hop[3]) }
      if not ev.state.started then ev.i, ev.state = ev.i + 1, nil end
    elseif not ow.dwAnim then
      -- an event's own hop is not a step the player made: its landing tile
      -- does not run HandleEventAt again
      local Sf = require("src.world.Gen4DistSurface")
      local x, y, z = Sf.position(ow, m)
      ow.dwLastTile = ("%d,%d,%d"):format(x, y, z)
      ev.i, ev.state = ev.i + 1, nil
    end
  else
    if P.runCommand(ow, def, m, dw, ev, kind, a or {}) then ev.i, ev.state = ev.i + 1, nil end
  end
end

-- ---------------------------------------------- the other command kinds

local function setVarG4(id, v)
  local G = Game()
  pcall(function() require("src.script.Gen4Commands").setVar(G.save, id, v) end)
end

local function setPuzzle(i, on)
  local f = P.puzzleFlags()
  local G = Game()
  if on then f = bor(f, lshift(1, i)) else f = band(f, bnot(lshift(1, i))) end
  G.save.gen4DistPuzzleFlags = f
end
P.setPuzzle = setPuzzle

local function playCry(species)
  local G = Game()
  pcall(function() require("src.core.Sound").playCry(G.data, species) end)
end
P.playCry = playCry

-- a map script by its number in this floor's own list (ScriptManager_Start)
function P.startScript(ow, def, id)
  local G = Game()
  local ms = G and G.data and G.data.map_scripts
  local entry = ms and ((ms.maps and ms.maps[def.id]) or ms[def.id])
  local label = entry and entry.entries and entry.entries[tonumber(id) or 0]
  local rows = label and require("src.script.Gen4ScriptVM").compile(G.data, label)
  if not rows then
    print(("[dwplatforms] %s: no map script %s (re-import Platinum)"):format(tostring(def.id), tostring(id)))
    return false
  end
  if ow.runner and not (ow.runner.isRunning and ow.runner:isRunning()) then
    ow.runner:run(rows, { mapId = def.id })
  elseif ow.queueScript then
    ow:queueScript(rows, { mapId = def.id })
  end
  return true
end

local function scriptBusy(ow)
  return (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
      or (ow.pendingScripts and #ow.pendingScripts > 0)
end
P.scriptBusy = scriptBusy

-- A TEMPORARY PROP on this floor (Giratina's shadow), drawn through the same
-- runtime-prop list the platforms use; returns its live record.
local function addProp(def, kind, ux, uy, uz, scale, rotY)
  def.gen4RuntimeProps = def.gen4RuntimeProps or {}
  local live = { temp = true }
  def.gen4RuntimeProps[#def.gen4RuntimeProps + 1] = { model = 124 + kind, archive = "fldeff",
    distWorld = true, live = live, x = ux, y = uy, z = uz, scale = scale, rotY = rotY }
  return live
end
local function dropProp(def, live)
  for i = #(def.gen4RuntimeProps or {}), 1, -1 do
    if def.gen4RuntimeProps[i].live == live then table.remove(def.gen4RuntimeProps, i) end
  end
end

-- sGiratinaShadowPropRotAngles' yaw (index 4 is a 90-degree pitch, drawn level)
P.SHADOW_YAW = { [0] = 0, 180, 90, 270, 0 }
-- the guardians' tutorials: their B5F local id, the TUTO_SEEN and IN_B6F
-- puzzle flags they set, and the cry
P.LAKE_TRIO = {
  showUxieBoulderTuto    = { b5f = 131, seen = 10, inB6F = 13, species = 480, rise = 17, uxie = true },
  showAzelfBoulderTuto   = { b5f = 132, seen = 11, inB6F = 14, species = 482, rise = 13, walk = "azelf" },
  showMespritBoulderTuto = { b5f = 133, seen = 12, inB6F = 15, species = 481, rise = 9, walk = "mesprit" },
}

-- one step of command `kind`; true when it has finished
function P.runCommand(ow, def, m, dw, ev, kind, a)
  local st = ev.state
  if kind == "startScript" then
    if not st then
      ev.state = { started = P.startScript(ow, def, a.scriptId) }
      return not ev.state.started
    end
    return not scriptBusy(ow)
  elseif kind == "setDistortionWorldProgress" then
    setVarG4(P.VAR_PROGRESS, tonumber(a.progress) or 0)
    return true
  elseif kind == "addMapObjectWithLocalId" then
    P.castAdd(ow, tonumber(a.localId) or 0)
    return true
  elseif kind == "deleteMapObjectWithLocalId" then
    P.castDelete(ow, tonumber(a.localId) or 0)
    return true
  elseif kind == "setGiratinaAnimationFlag" then
    local G = Game()
    G.save.flags = G.save.flags or {}
    G.save.flags[("FLAG_G4_%04X"):format(P.FLAG_SHADOW_1 + (tonumber(a.anim) or 0))] = true
    return true
  elseif kind == "setPuzzleFlag" or kind == "clearPuzzleFlag" then
    setPuzzle(tonumber(a.flag) or 0, kind == "setPuzzleFlag")
    return true
  elseif kind == "showGiratinaShadow" then
    -- DistWorldGiratinaShadowProp: from the template's tile, by posDelta a
    -- frame for movementAnimSteps frames, Giratina's cry or the flee sound first
    if not st then
      ev.state = P.shadowStart(def, m, a)
      return false
    end
    return P.shadowTick(def, st, a)
  elseif kind == "showGiratinaRoomPlatforms" or kind == "hideGiratinaRoomPlatforms" then
    -- groups 1..3, 36 then 48 frames apart (hide: 3..1, 16 then 48, then 8),
    -- the camera easing to (16, 0) over 20 frames as they appear
    local show = kind == "showGiratinaRoomPlatforms"
    if not st then
      ev.state = { delay = show and 36 or 16, group = show and 1 or 3 }
      if show then require("src.world.Gen4DistSurface").aimCamera({ angleX = 16, angleY = 0, steps = 20 }) end
      return false
    end
    st.delay = st.delay - 1
    if st.delay > 0 then return false end
    if (show and st.group > 3) or (not show and st.group < 1) then return true end
    local bitv = lshift(1, st.group)
    if show then ow.dwGhostHidden = band(ow.dwGhostHidden or 0, bnot(bitv))
    else ow.dwGhostHidden = bor(ow.dwGhostHidden or 0, bitv) end
    P.refreshGhosts(ow, def, m)
    st.group = st.group + (show and 1 or -1)
    st.delay = (not show and st.group < 1) and 8 or 48
    return false
  elseif kind == "playGiratinaArrival" then
    return P.giratinaArrival(ow, ev)
  elseif P.LAKE_TRIO[kind] then
    return P.trioTuto(ow, ev, P.LAKE_TRIO[kind])
  end
  return true
end


-- ----------------------------------------------------- the cast's flights

-- Reported from play: "The lake trio and Giratina appear in place for their
-- scenes' length; they don't fly in."  These are overlay 9's own state
-- machines, a step per cartridge frame (30 a second), moving the map object's
-- SPRITE OFFSET (MapObject_SetSpritePosOffset) -- the object itself stays on
-- its tile.  ow.dwSprites[localId] = { ox, oz, lift, dark, facing } is that
-- offset in world units (16 a tile), applied to the cast's entity by
-- P.tickSprites.

-- (fx >> 4) / FX32_ONE, for a value held in units: tiles, toward zero
local function tilesOf(v)
  local q = math.floor(v * 256)
  if q >= 0 then return math.floor(q / 4096) end
  return -math.floor(-q / 4096)
end
P.tilesOf = tilesOf

function P.sprite(ow, localId, init)
  ow.dwSprites = ow.dwSprites or {}
  if init then ow.dwSprites[localId] = init end
  return ow.dwSprites[localId]
end

local function playSe(key)
  local G = Game()
  local ok, src = pcall(function() return require("src.core.Sound").playSe(G.data, key) end)
  return ok and src
end

-- ShowUxieBoulderTuto_Hover's yOffsets, in units
P.HOVER = { [0] = 0, 0.5, 1, 2, 4, 6, 7, 8 }
-- MOVEMENT_ACTION_WALK_* frames a tile, and the four directions
local WALK_FRAMES = { slower = 32, slow = 16, normal = 8, fast = 4 }
local DIRS = { E = { 1, 0, "right" }, W = { -1, 0, "left" }, N = { 0, -1, "up" }, S = { 0, 1, "down" } }

-- the MapObjectAnimCmd lists, { action, direction or frames, count }
local FACE_ROUND = { { "face", "W" }, { "delay", 1, 3 }, { "face", "N" }, { "delay", 1, 3 },
                     { "face", "E" }, { "delay", 1, 3 }, { "face", "S" }, { "delay", 1, 3 } }
P.TRIO_WALKS = {
  -- sAzelfBoulderTutoAnimation
  azelf = { { "delay", 32 }, { "slower", "E" }, { "slower", "E" }, { "slow", "W" }, { "slower", "W" }, { "delay", 16 } },
  -- sMespritBoulderTutoAnimationPokemonTop / Bottom
  mespritTop = { { "delay", 32 }, { "normal", "E", 2 }, { "fast", "N", 2 }, { "fast", "E", 2 }, { "fast", "S", 2 },
                 { "fast", "W", 2 }, { "fast", "N", 2 }, { "fast", "E", 2 }, { "fast", "S", 2 }, { "fast", "W", 2 },
                 { "fast", "W", 2 }, { "normal", "W" }, { "slow", "W" }, { "delay", 32 }, { "slow", "E", 2 },
                 { "slower", "E" }, { "delay", 16 } },
  mespritBottom = { { "delay", 32 }, { "normal", "E", 2 }, { "fast", "N" }, { "fast", "E", 2 }, { "fast", "S", 2 },
                    { "fast", "W", 2 }, { "fast", "N", 2 }, { "fast", "E", 2 }, { "fast", "S", 2 }, { "fast", "W", 2 },
                    { "fast", "N" }, { "fast", "W", 2 }, { "normal", "W" }, { "slow", "W" }, { "delay", 32 },
                    { "slow", "E", 2 }, { "slower", "E" }, { "delay", 16 } },
  -- sMespritBoulderTutoAnimationPlayerTop and ...Bottom, which are the same:
  -- the player's head turning round twice after Mesprit
  playerMesprit = { { "delay", 32 }, { "delay", 8, 2 } },
}
for _ = 1, 2 do
  for _, c in ipairs(FACE_ROUND) do P.TRIO_WALKS.playerMesprit[#P.TRIO_WALKS.playerMesprit + 1] = c end
end
P.TRIO_WALKS.playerMesprit[#P.TRIO_WALKS.playerMesprit + 1] = { "face", "W" }

local function expand(list)
  local out = {}
  for _, c in ipairs(list) do
    for _ = 1, c[3] or 1 do
      if c[1] == "delay" then
        out[#out + 1] = { n = c[2] }
      elseif c[1] == "face" then
        out[#out + 1] = { n = 1, face = DIRS[c[2]][3] }
      else
        local d = DIRS[c[2]]
        out[#out + 1] = { n = WALK_FRAMES[c[1]], dx = d[1] * 16, dz = d[2] * 16, face = d[3] }
      end
    end
  end
  return { list = out, i = 1, t = 0 }
end
P.expandWalk = expand

-- one frame of a MapObject animation on `rec`; true once it has ended
local function animTick(an, rec)
  local cmd = an.list[an.i]
  if not cmd then return true end
  if an.t == 0 and cmd.face then rec.facing = cmd.face end
  an.t = an.t + 1
  if cmd.dx then
    rec.ox = (rec.ox or 0) + cmd.dx / cmd.n
    rec.oz = (rec.oz or 0) + cmd.dz / cmd.n
  end
  if an.t >= cmd.n then an.i, an.t = an.i + 1, 0 end
  return an.list[an.i] == nil
end

-- ShowUxie/Azelf/MespritBoulderTuto.  Uxie rises to 17 tiles, crosses two
-- tiles toward the boulder, bobs over it three times and goes back; Azelf
-- (13 tiles) and Mesprit (9) rise and run their walk, Mesprit with the player
-- turning to follow it.  Then each sinks, accelerating by 1/8 to 2 units a
-- frame, and is gone: TUTO_SEEN and IN_B6F set, waiting for the player on B6F.
function P.trioTuto(ow, ev, trio)
  local st = ev.state
  if not st then
    P.castAdd(ow, trio.b5f)
    playCry(trio.species)
    ev.state = { phase = "ascend", hoverStep = 0, hoverDelta = 1, hoverRepeat = 0, descend = 0 }
    P.sprite(ow, trio.b5f, { ox = 0, oz = 0, lift = 0 })
    return false
  end
  local r = P.sprite(ow, trio.b5f) or P.sprite(ow, trio.b5f, { ox = 0, oz = 0, lift = 0 })
  local ph = st.phase
  if ph == "ascend" then
    local d = 2
    if tilesOf(r.lift) < trio.rise - 1 then d = 4 end
    r.lift = r.lift + d
    if tilesOf(r.lift) >= trio.rise then
      if trio.uxie then
        st.phase = "toBoulder"
      else
        local key = trio.walk
        if key == "mesprit" then
          -- GetPlayerPos: the top route when the player stands at z 67
          local m = floorInfo(ow.map and ow.map.def)
          local pz = (ow.player and ow.player.cellY or 0) + ((m and m.offsetZ) or 0)
          key = (pz == 67) and "mespritTop" or "mespritBottom"
          st.player, st.playerRec = expand(P.TRIO_WALKS.playerMesprit), {}
        end
        st.anim = expand(P.TRIO_WALKS[key])
        st.phase = "walk"
      end
    end
    return false
  elseif ph == "toBoulder" then
    r.oz = r.oz - 1
    if tilesOf(r.oz) <= -2 then st.finalY, st.phase = r.lift, "hover" end
    return false
  elseif ph == "hover" then
    r.lift = st.finalY + P.HOVER[math.floor(st.hoverStep / 2)]
    st.hoverStep = st.hoverStep + st.hoverDelta
    if st.hoverStep >= 8 * 2 - 1 or st.hoverStep <= 0 then   -- HOVER_STEP_COUNT 8
      st.hoverDelta = -st.hoverDelta
      if st.hoverStep == 0 then
        st.hoverRepeat = st.hoverRepeat + 1
        if st.hoverRepeat >= 3 then
          r.lift = st.finalY + P.HOVER[0]
          st.phase = "away"
        end
      end
    end
    return false
  elseif ph == "away" then
    r.oz = r.oz + 1
    if tilesOf(r.oz) == 1 then st.phase = "descend" end
    return false
  elseif ph == "walk" then
    local done = animTick(st.anim, r)
    local pdone = true
    if st.player then
      pdone = animTick(st.player, st.playerRec)
      if st.playerRec.facing and ow.player then ow.player.facing = st.playerRec.facing end
    end
    if not (done and pdone) then return false end
    -- WaitForAnimation's RES_LOOP: the descent starts this frame
    st.phase = "descend"
  end
  if st.descend < 2 then st.descend = st.descend + 0.125 end
  r.lift = r.lift - st.descend
  if tilesOf(r.lift) <= 0 then
    P.castDelete(ow, trio.b5f)
    ow.dwSprites[trio.b5f] = nil
    setPuzzle(trio.seen, true)
    setPuzzle(trio.inB6F, true)
    return true
  end
  return false
end

-- PlayGiratinaArrival: Giratina added ten tiles up, black (sprite darkness
-- 16), the sky held and darkening by 8/90 a frame to 12 while it sinks 1 unit
-- a frame (half that in its last tile); then its colour returns by 16/90 a
-- frame, and half a second's wait.  The sky stays dark (SKY_GIRATINA_ROOM_DARK,
-- the darkness held at its maximum).
P.ARRIVAL = { startY = 160, skyDelta = 364 / 4096, darkDelta = 728 / 4096, wait = 30 }
function P.giratinaArrival(ow, ev)
  local Sky = require("src.render.Gen4DistSkyView")
  local st = ev.state
  if not st then
    P.castAdd(ow, 128)
    st = { phase = "init", y = P.ARRIVAL.startY, dark = 16, sky = 0, delay = 0 }
    ev.state = st
    P.sprite(ow, 128, { lift = st.y, dark = 1 })
    return false
  end
  local r = P.sprite(ow, 128) or P.sprite(ow, 128, { lift = st.y, dark = 1 })
  if st.phase == "init" then
    Sky.hold(0)
    Sky.setKind(Sky.GIRATINA_ROOM_DARK)
    if not playSe("SEQ_SE_PL_GIRA") then playCry(487) end
    st.phase = "descend"   -- RES_LOOP
  end
  if st.phase == "descend" then
    st.sky = math.min(12, st.sky + P.ARRIVAL.skyDelta)
    Sky.hold(st.sky)
    if st.y >= 16 then st.y = st.y - 1 else st.y = st.y - 0.5 end
    if st.y < 0 and st.sky >= 12 then st.y, st.phase = 0, "brighten" end
    r.lift = st.y
    return false
  elseif st.phase == "brighten" then
    st.dark = st.dark - P.ARRIVAL.darkDelta
    if st.dark < 0 then st.dark, st.phase = 0, "wait" end
    r.dark = math.floor(st.dark) / 16
    return false
  end
  st.delay = st.delay + 1
  if st.delay >= P.ARRIVAL.wait then
    ow.dwSprites[128] = nil
    return true
  end
  return false
end

-- Giratina's shadow crossing the scene, from a template (a floor event's own
-- params, or one of sGiratinaShadowExternal for the scripts)
function P.shadowStart(def, m, a)
  local ux = ((a.x or 0) - (m.offsetX or 0)) * 16 + ((a.rot == 4) and 8 or 0)
  local uy = ((a.y or 0) - (m.offsetAltitude or 0)) * 16
  local uz = ((a.z or 0) - (m.offsetZ or 0)) * 16
  local st = { t = 0, live = addProp(def, 20, ux, uy, uz, a.scaleX or 1, P.SHADOW_YAW[a.rot or 0] or 0) }
  -- SetPropPolygonID's translucent shadow pass, drawn as a dark tint
  st.live.tint = { 0.08, 0.04, 0.12, 0.7 }
  if a.sound == 1 then playCry(487) end
  return st
end

-- a frame of it; true once it has crossed (and gone)
function P.shadowTick(def, st, a)
  local hold = os.getenv and tonumber(os.getenv("DWSHADOWHOLD") or "")
  if not (hold and st.t >= hold) then st.t = st.t + 1 end
  st.live.dx, st.live.dy, st.live.dz = (a.deltaX or 0) * st.t, (a.deltaY or 0) * st.t, (a.deltaZ or 0) * st.t
  if st.t >= (tonumber(a.steps) or 32) then
    dropProp(def, st.live)
    return true
  end
  return false
end

-- DistWorld_StartGiratinaShadowEvent / _FinishGiratinaShadowEvent: the map
-- scripts' own shadow (startdistortionworldgiratinashadowevent)
function P.shadowExternal(ow, index)
  local def = ow and ow.map and ow.map.def
  local m, dw = floorInfo(def)
  local t = dw and dw.externalShadows and dw.externalShadows[(tonumber(index) or 0) + 1]
  if not (m and t) then return false end
  P.shadowFinish(ow)
  local st = P.shadowStart(def, m, t)
  st.a, st.def = t, def
  ow.dwExtShadow = st
  return true
end

function P.shadowFinish(ow)
  local ext = ow and ow.dwExtShadow
  if ext then
    dropProp(ext.def, ext.live)
    ow.dwExtShadow = nil
  end
end

-- Every frame: the offsets onto the cast's entities, and the scripts' shadow
-- on the cartridge's frames.
function P.tickSprites(ow, def, m)
  local sp = ow.dwSprites
  for _, n in ipairs(ow.npcs or {}) do
    local d = n.def
    if d and d.gen4DistCast then
      local r = sp and sp[d.localId]
      -- the object's own altitude: the lake trio wait in the pits, 16, 12
      -- and 8 tiles under B5F's floor, and rise out of them
      local c = d.gen4DistCast
      local o = n.spriteOffset or {}
      n.spriteOffset = o
      o.y = c.y and m and ((c.y - (m.offsetAltitude or 0)) * 16) or nil
      if r then
        o.ox, o.oz, o.lift, o.dark = r.ox, r.oz, r.lift, r.dark
        if r.facing then n.facing = r.facing end
      else
        o.ox, o.oz, o.lift, o.dark = nil, nil, nil, nil
      end
    end
  end
  local ext = ow.dwExtShadow
  if ext and ow.dwDsFrame then
    if ext.def ~= def then
      ow.dwExtShadow = nil
    elseif P.shadowTick(def, ext, ext.a) then
      ow.dwExtShadow = nil
    end
  end
end

-- ------------------------------------------------------------- ghost props

-- InitActiveGhostPropManager: a floor starts with its header's default groups
-- visible; HandleGhostPropTriggerAt shows or hides a group when the player
-- presses the trigger's direction inside its bounds.
local function groupHidden(mask, g)
  return band(mask, lshift(1, g)) ~= 0
end

function P.refreshGhosts(ow, def, m)
  -- SetPersistedHiddenGhostPropGroups: the floor's groups are kept in the
  -- save while the player stays on it, so a game loaded there comes back with
  -- the stepping stones it was saved with (InitActiveGhostPropManager reads
  -- them when the persisted data is this floor's); a floor change starts over
  -- from the header's defaults
  local G = Game()
  local save = G and G.save
  if ow.dwGhostFloor ~= def then
    local kept = save and save.gen4DwGhosts
    local fresh = ow.dwGhostFloor == nil
    ow.dwGhostFloor = def
    if fresh and kept and tonumber(kept.header) == tonumber(def.header) and kept.mask then
      ow.dwGhostHidden = tonumber(kept.mask)
    else
      ow.dwGhostHidden = bnot(tonumber(m.ghostDefaultVisible) or 0)
    end
  end
  local rec = save and save.gen4DwGhosts
  if save and not (rec and rec.header == tonumber(def.header) and rec.mask == ow.dwGhostHidden) then
    save.gen4DwGhosts = { header = tonumber(def.header), mask = ow.dwGhostHidden }
  end
  for _, live in ipairs(def.gen4DistGhosts or {}) do
    live.hidden = groupHidden(ow.dwGhostHidden, tonumber(live.group) or 0)
  end
end

local DIRN = { up = 0, down = 1, left = 2, right = 3 }

function P.ghostTrigger(ow, m, x, y, z, dir)
  local def = ow.map and ow.map.def
  if not (def and m.ghostTriggers) then return end
  if ow.dwGhostFloor ~= def then P.refreshGhosts(ow, def, m) end
  local changed = false
  for _, t in ipairs(m.ghostTriggers) do
    local b = t.bounds
    if t.playerDir == DIRN[dir] and x >= b.x and x <= b.x + b.sizeX and y >= b.y and y <= b.y + b.sizeY
       and z >= b.z and z <= b.z + b.sizeZ then
      local bitv = lshift(1, tonumber(t.group) or 0)
      if t.show then ow.dwGhostHidden = band(ow.dwGhostHidden, bnot(bitv))
      else ow.dwGhostHidden = bor(ow.dwGhostHidden, bitv) end
      changed = true
    end
  end
  if changed then P.refreshGhosts(ow, def, m) end
end

-- --------------------------------------------- B7F / Giratina room teleports

-- DistWorld_DynamicMapFeaturesCheckCollision and DistWorld_HandlePlayerMoved-
-- End: past the teleport tile the floor goes on to stepping stones that
-- belong to the NEXT room (the Giratina room's, at the same tiles), so the
-- overlay walls the tile after it off and runs the map's teleport script when
-- the player presses on.  Without this the player walked off into the void
-- (reported from play).  Tiles in world coordinates, as the overlay has them.
P.TELEPORTS = {
  [581] = { x = 89, y = 65, z = 57, blockZ = 56, dir = "up", script = 2, minProgress = 10 },
  [582] = { x = 15, y = 1, z = 25, blockZ = 26, dir = "down", script = 4 },
}

local function progress()
  local G = Game()
  local ok, v = pcall(function() return require("src.script.Gen4Commands").getVar(G and G.save, 0x4055) end)
  return ok and tonumber(v) or 0
end
P.progress = progress

-- true when the map cell is the overlay's teleport wall
function P.blocked(def, m, cx, cy)
  local t = P.TELEPORTS[tonumber(def and def.header)]
  if not t then return false end
  return cx + (m.offsetX or 0) == t.x and cy + (m.offsetZ or 0) == t.blockZ
end

-- the teleport itself: pressing its direction on its tile (or the walled tile
-- beside it) runs map script N, named by number in the map's script file
function P.teleport(ow, m, x, z, dir)
  local def = ow.map and ow.map.def
  local t = P.TELEPORTS[tonumber(def and def.header)]
  if not (t and dir == t.dir and x == t.x and (z == t.z or z == t.blockZ)) then return false end
  if t.minProgress and progress() < t.minProgress then return false end
  local G = Game()
  local ms = G and G.data and G.data.map_scripts
  local entry = ms and ((ms.maps and ms.maps[def.id]) or ms[def.id])
  local label = entry and entry.entries and entry.entries[t.script]
  if not label then
    print(("[dwplatforms] %s: script %d is not in this cache's map_scripts (re-import)"):format(tostring(def.id), t.script))
    return false
  end
  local rows = require("src.script.Gen4ScriptVM").compile(G.data, label)
  if not rows then return false end
  if ow.queueScript then ow:queueScript(rows, { mapId = def.id })
  elseif ow.runner then ow.runner:run(rows, { mapId = def.id }) end
  return true
end

-- ------------------------------------------------------------------ the cast

-- THE DISTORTION WORLD'S PEOPLE AND THINGS: Cynthia, Cyrus, the lake trio,
-- Giratina, the puzzle's boulders and the invisible talk triggers are not in
-- the map's event file (it is empty) but in overlay 9's `sMapObjectEvents`
-- (extracted as `gen4_distortion_world.cast`).  AddMapObjectsForMap places
-- every member whose condition holds when the floor loads; a FLAG_COND_MANUAL_
-- ADD_ONLY member appears only when a script's AddDistortionWorldMapObject asks
-- for its local id (CheckFlagConditionForObjectEvent).
P.VAR_PROGRESS, P.VAR_CYRUS = 0x4055, 0x405B
P.FLAG_PUZZLE_DONE, P.FLAG_SHADOW_1 = 0x9AD, 0x9AE
P.COND_MANUAL = 6

local function getVar(id)
  local G = Game()
  local ok, v = pcall(function() return require("src.script.Gen4Commands").getVar(G and G.save, id) end)
  return ok and tonumber(v) or 0
end
local function flagOn(id)
  local G = Game()
  local flags = G and G.save and G.save.flags
  return flags ~= nil and flags[("FLAG_G4_%04X"):format(id)] == true
end

-- DistWorldPersistedData.boulderPuzzleFlags, as InitPersistedData seeds them
function P.puzzleFlags()
  local G = Game()
  local save = G and G.save
  if not save then return 0 end
  if save.gen4DistPuzzleFlags == nil then
    local f = 0
    if not flagOn(P.FLAG_PUZZLE_DONE) then
      for _, i in ipairs({ 0, 1, 2 }) do f = bor(f, lshift(1, i)) end
    else
      for _, i in ipairs({ 10, 11, 12, 6, 7, 8 }) do f = bor(f, lshift(1, i)) end
    end
    save.gen4DistPuzzleFlags = f
  end
  return save.gen4DistPuzzleFlags
end

-- CheckFlagCondition, all eight kinds
function P.condition(cond, val)
  cond, val = tonumber(cond) or 0, tonumber(val) or 0
  if cond == 0 then return true end
  if cond == 1 then return band(P.puzzleFlags(), lshift(1, val)) == 0 end
  if cond == 2 then return band(P.puzzleFlags(), lshift(1, val)) ~= 0 end
  local progress = getVar(P.VAR_PROGRESS)
  if cond == 3 then return progress == val end
  if cond == 4 then return progress <= val end
  if cond == 5 then return progress >= val end
  if cond == 7 then return not flagOn(P.FLAG_SHADOW_1 + val) end
  if cond == 8 then return getVar(P.VAR_CYRUS) == val end
  return false
end

local function castLabel(def, script)
  local G = Game()
  local ms = G and G.data and G.data.map_scripts
  script = tonumber(script) or 0
  if script <= 0 then return nil end
  if script < 10000 then
    local entry = ms and ((ms.maps and ms.maps[def.id]) or ms[def.id])
    return entry and entry.entries and entry.entries[script]
  end
  -- a shared band (10002 is Strength's boulder script).  WHICH band is the
  -- dispatcher's arithmetic (Gen4ScriptBands.classify, the same the script
  -- VM uses): the bands carry no `threshold`, so the loop this replaced
  -- matched nothing and every B5F/B6F boulder had no script -- A on one
  -- said nothing, Strength was never offered, and the puzzle could not be
  -- started.
  local bands = ms and (ms.bands or ms.shared)
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  if okB and bands then
    local kind, name, index = Bands.classify(script)
    local band = kind == "band" and bands[name]
    local label = band and band.entries and band.entries[(index or 0) + 1]
    if label then return label end
  end
  for _, band in pairs(bands or {}) do
    if type(band) == "table" and band.threshold and band.entries
       and script >= band.threshold and script < band.threshold + 1000 then
      return band.entries[script - band.threshold + 1]
    end
  end
end

local function placeCast(ow, def, m, c)
  local G = Game()
  local maxIndex = 0
  for _, o in ipairs(def.objects or {}) do maxIndex = math.max(maxIndex, tonumber(o.index) or 0) end
  local OW = require("src.world.OverworldController")
  local key, name
  if tonumber(c.graphicsId) and c.graphicsId < 8192 and OW.gen4SpriteFor then
    key, name = OW.gen4SpriteFor(G.data, c.graphicsId)
  end
  local obj = {
    index = maxIndex + 1, localId = c.localId, graphicsId = c.graphicsId,
    sprite = key, spriteName = name, invisible = (key == nil) or nil,
    x = c.x - (m.offsetX or 0), y = c.z - (m.offsetZ or 0), elevation = 0,
    direction = 1, movementType = c.movementType or 0, movementRangeX = 0, movementRangeY = 0,
    script = c.script, trainerType = c.trainerType or 0,
    eventFlag = (tonumber(c.hiddenFlag) or 0) > 0 and ("FLAG_G4_%04X"):format(c.hiddenFlag) or nil,
    text = castLabel(def, c.script),
    gen4DistCast = c,
  }
  def.objects = def.objects or {}
  def.objects[#def.objects + 1] = obj
  if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(obj) end) end
  return obj
end

local function castList(def)
  local dw = dwData()
  local h = tonumber(def and def.header)
  return dw and dw.cast and h and (dw.cast[h] or dw.cast[tostring(h)]) or {}
end

-- AddMapObjectsForMap: on entering a floor
function P.spawnCast(ow, def, m)
  -- a previous visit's members go first (the def outlives the visit)
  local kept = {}
  for _, o in ipairs(def.objects or {}) do
    if o.gen4DistCast then
      o.hidden = true
      if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(o) end) end
    else kept[#kept + 1] = o end
  end
  def.objects = kept
  local placed = {}
  for _, c in ipairs(castList(def)) do
    if not placed[c.localId] and tonumber(c.flagCond) ~= P.COND_MANUAL
       and P.condition(c.flagCond, c.flagCondVal) then
      placed[c.localId] = true
      placeCast(ow, def, m, c)
    end
  end
  -- the lift's passenger arriving with the player (ElevatorPlatform_ChangeMaps)
  local pas = ow.dwPassenger
  if pas and tonumber(pas.destHeader) == tonumber(def.header) then
    ow.dwPassenger = nil
    local c = {}
    for k, v in pairs(pas.cast) do c[k] = v end
    c.localId, c.x, c.z, c.y = pas.localId, pas.wx, pas.wz, nil
    c.flagCond, c.flagCondVal = P.COND_MANUAL, 0
    if pas.script then c.script = pas.script end
    placeCast(ow, def, m, c)
  end
end

-- THE LIFT'S PASSENGER.  Two lifts carry Cynthia down with the player
-- (DistWorldElevatorPlatform_BeginMovement): 1F's while the progress is
-- JUMPED_ON_1F_ELEVATOR (2), her local id 129 there, and B6F's while it is
-- FINISHED_BOULDER_PUZZLE (7), local id 134.  She is not in the next floor's
-- object table for that moment -- B1F's has only Mesprit, and B7F's first
-- Cynthia wants ENTERED_B7F (8), which the first-entry script itself sets --
-- so ChangeMaps keeps the same map object, renumbered: B1F_CYNTHIA_ELEVATOR
-- (128), or B7F_CYNTHIA (128) with script 6.  Without her both floors'
-- first-entry scripts moved a local id that was not there ("no object with
-- localId 128"): the scene played to an empty platform.  Her tile stays the
-- one she stood on (the floors share world coordinates).
P.HEADER_1F, P.HEADER_B1F, P.HEADER_B6F = 573, 574, 580
function P.passengerFor(ow, def, m, destHeader)
  local h = tonumber(def and def.header)
  local progress = getVar(P.VAR_PROGRESS)
  local fromId
  if h == P.HEADER_1F and progress == 2 then fromId = 129
  elseif h == P.HEADER_B6F and progress == 7 then fromId = 134 end
  if not fromId then return nil end
  for _, n in ipairs(ow.npcs or {}) do
    local d = n.def
    if d and d.gen4DistCast and d.localId == fromId and not n.hidden then
      local dest = tonumber(destHeader)
      return { fromId = fromId, localId = 128, cast = d.gen4DistCast, destHeader = dest,
               script = dest ~= P.HEADER_B1F and 6 or nil,
               wx = (n.cellX or d.x or 0) + (m.offsetX or 0), wz = (n.cellY or d.y or 0) + (m.offsetZ or 0) }
    end
  end
end

-- THE FIELD COMING BACK FROM A BATTLE REBUILDS THE OVERLAY'S OBJECTS.  The
-- overlay adds its map objects from their conditions whenever the field is
-- built (AddMapObjectsForCurrentAndNextMap, from the Distortion World
-- system's init), and a battle's end builds it again -- after ON_LOAD, which
-- in the Giratina room is what sets VAR_DISTORTION_WORLD_PROGRESS to
-- BATTLED_GIRATINA (14).  Kept from the visit's start instead, the room went
-- on showing what progress 13 had (nothing at 15,13), and the portal
-- (local id 131, progress == 14) and Cynthia beside it were never there:
-- no way out of the room.  OverworldState:gen4FieldResumed calls this after
-- the map's resume scripts, before the battle's own script carries on.
function P.fieldResumed(ow)
  local def = ow and ow.map and ow.map.def
  local m = floorInfo(def)
  if not m then return end
  P.spawnCast(ow, def, m)
  P.refreshedFor = def
end

-- AddMapObjectWithLocalID / DeleteMapObject...: the scripts' two commands
function P.castAdd(ow, localId)
  local def = ow and ow.map and ow.map.def
  local m = floorInfo(def)
  if not m then return false end
  for _, o in ipairs(def.objects or {}) do
    if o.gen4DistCast and o.localId == localId and not o.hidden then return true end
  end
  for _, c in ipairs(castList(def)) do
    if c.localId == localId and (tonumber(c.flagCond) == P.COND_MANUAL or P.condition(c.flagCond, c.flagCondVal)) then
      placeCast(ow, def, m, c)
      return true
    end
  end
  return false
end

function P.castDelete(ow, localId)
  local def = ow and ow.map and ow.map.def
  for _, o in ipairs(def and def.objects or {}) do
    if o.gen4DistCast and o.localId == localId and not o.hidden then
      o.hidden = true
      if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(o) end) end
    end
  end
end

-- ---------------------------------------------------------- the boulder puzzle

-- sBoulderFallLocations (gen4_distortion_world.boulderFalls): the pits a
-- boulder may be pushed into on B5F and B6F.  Map cell in, record out.
function P.fallAt(def, cx, cy)
  local m, dw = floorInfo(def)
  if not (m and dw and dw.boulderFalls) then return nil end
  local wx, wz = cx + (m.offsetX or 0), cy + (m.offsetZ or 0)
  for _, r in ipairs(dw.boulderFalls) do
    if r.header == tonumber(def.header) and r.x == wx and r.z == wz then return r end
  end
end

-- Each boulder by its local id: the B5F flag, the B6F-outside flag and the
-- local id it takes once it sits in a pit (DIST_WORLD_MAP_OBJECT_B6F_*_IN_PIT)
P.BOULDERS = {
  [128] = { inB5F = 0, outside = 3, inPit = 144 },   -- Mesprit's
  [129] = { inB5F = 1, outside = 4, inPit = 145 },   -- Azelf's
  [130] = { inB5F = 2, outside = 5, inPit = 146 },   -- Uxie's
}
-- each B6F pit's flag: the guardian flag it clears and the script it starts
P.PITS = {
  [6] = { guardian = 15, script = 5 },   -- Mesprit's pit
  [7] = { guardian = 14, script = 7 },   -- Azelf's pit
  [8] = { guardian = 13, script = 6 },   -- Uxie's pit
}
P.FLAG_INVALID = 17

-- DistWorldFallingBoulder: the push landed the boulder on a pit.  Returns true
-- when it fell (the caller's after-push work is done).
function P.boulderFell(ow, npc)
  local def = ow.map and ow.map.def
  local id = npc and (npc.localId or (npc.def and npc.def.localId))
  local b = P.BOULDERS[tonumber(id) or -1]
  local r = def and P.fallAt(def, npc.cellX, npc.cellY)
  if not (b and r) then return false end
  local G = Game()
  pcall(function() require("src.core.Sound").play(G.data, "Fall") end)
  P.castDelete(ow, id)
  local flag = tonumber(r.flag) or -1
  if flag == P.FLAG_INVALID then
    -- DistWorldFallingBoulder_TickToB6F: on through the floor to B6F
    P.setPuzzle(b.outside, true)
    P.setPuzzle(b.inB5F, false)
    return true
  end
  local pit = P.PITS[flag]
  if pit and band(P.puzzleFlags(), lshift(1, flag)) == 0 then
    -- _TickToCorrectPit: it fills the pit, becomes the pit's boulder, and the
    -- guardian waiting there has its say
    P.setPuzzle(flag, true)
    P.setPuzzle(b.outside, false)
    P.castAdd(ow, b.inPit)
    P.setPuzzle(pit.guardian, false)
    P.startScript(ow, def, pit.script)
    local all = 0
    for f in pairs(P.PITS) do
      if band(P.puzzleFlags(), lshift(1, f)) ~= 0 then all = all + 1 end
    end
    if all >= 3 then
      G.save.flags = G.save.flags or {}
      G.save.flags[("FLAG_G4_%04X"):format(P.FLAG_PUZZLE_DONE)] = true
    end
    return true
  end
  -- _TickToWrongPit: through the floor and back up to B5F
  P.setPuzzle(b.inB5F, true)
  P.setPuzzle(b.outside, false)
  return true
end

-- Called by Gen4DistSurface.update every frame on a Distortion World floor.
function P.update(ow, m, dw)
  local def = ow.map and ow.map.def
  if not def then return end
  if ow.dwGhostFloor ~= def then P.refreshGhosts(ow, def, m) end
  if P.refreshedFor ~= def then
    -- a new visit: only what the flags say, until the player is found in a pocket
    for _, live in pairs(def.gen4DistLive or {}) do live.present = nil end
    ow.dwSprites = nil
    P.spawnCast(ow, def, m)
  end
  if markPresent(ow, def, m) then P.refreshedFlags = nil end
  if P.refreshedFor ~= def or P.refreshedFlags ~= P.flags(def.header) then
    P.refresh(def)
    P.refreshedFor, P.refreshedFlags = def, P.flags(def.header)
  end
  -- the overlay's per-frame motion, at its own 30 frames a second
  if ow.dwDsFrame then
    if ow.dwRide then tickRide(ow, def) end
    if ow.dwArrive and not ow.dwRide then tickArrive(ow, def, m) end
    if ow.dwEvent then tickEvent(ow, def, m, dw) end
  end
  P.tickSprites(ow, def, m)
end

return P
