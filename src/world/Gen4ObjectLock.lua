-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT HOLDS A GEN 4 / BLACK-WHITE FIELD STILL WHILE A SCRIPT TALKS.
--
-- The cartridge never stops the field for a message.  A script runs as a
-- field task, the map objects keep updating every frame, and the ONLY thing
-- that stands them still is the script's own lock:
--
--   ScrCmd_LockAll (pokeplatinum src/scrcmd.c; pokeheartgold scrcmd_c.c)
--     with no talked-to object (a coord trigger, a sign, a map script):
--       MapObjectMan_PauseAllMovement -- every object's
--       MAP_OBJ_STATUS_PAUSE_MOVEMENT on (HGSS: the walking Pokemon, if it
--       is mid-step, unpaused and waited for, _WaitFollowMonPaused)
--     with one: ScrCmd_LockLastTalked --
--       PauseAllMovement, then the PLAYER (if its step is unfinished), the
--       TALKED-TO object and the partner / walking Pokemon (if mid-step)
--       unpaused again, and the script held (ScriptContext_Pause /
--       SetupNativeScript _WaitMovementPauseBeforeMsg) until each has
--       finished its step and been paused in turn
--   ScrCmd_ReleaseAll: MapObjectMan_UnpauseAllMovement
--   ScrCmd_LockObject / ReleaseObject (HGSS Lock / Release): one object
--
-- and a paused object is stopped WHERE IT IS.  MapObject_Move skips the
-- movement type's own routine (sub_02062B14, which is what carries a
-- wanderer's walk action forward a frame at a time) while
-- MapObject_IsMovementPaused, so an object caught between tiles stays
-- between tiles until the release -- unless a script is moving it
-- (MAP_OBJ_STATUS_4, ApplyMovement), which runs regardless.
--
-- So "NPCs freeze mid-step during a text box" is the cartridge too -- for
-- the objects a lock holds, for the whole of the lock.  What this port did
-- differently, and what this module fixes:
--
--   * it froze the WHOLE FIELD whenever a message was up (the TextBox is a
--     state on top of the overworld, and only the top state updates), lock or
--     no lock: a sign (ShowLandmarkSign / ShowScrollingSign take no lock),
--     a hidden item, any unlocked script stopped every walker mid-step, and
--     an applymovement under a message stopped with it.  `fieldTick` keeps
--     the objects updating under a message, as the cartridge's field does;
--   * it let a locked walker's step land between messages and froze it again
--     at the next one.  `holds` keeps a locked walker where the lock caught it;
--   * it froze the talked-to object mid-step for the message.  LockAll with
--     a target lets it (and the partner) land first and holds the script
--     until it has.
--
-- The Gen 4 movement types (Gen4MovementTypes) read `ow.gen4Lock` for
-- whether the field is locked, instead of "a script is running".

local M = {}

local function isFollower(npc)
  return npc and (npc.gen4Follower or npc.hgssFollowMon) and true or false
end

function M.locked(ow)
  return ow ~= nil and ow.gen4Lock ~= nil
end

-- the objects a lock reaches: the map's own and the neighbours' walkers
local function each(ow, fn)
  for _, npc in ipairs(ow.npcs or {}) do fn(npc) end
  for _, g in ipairs(ow.ghosts or {}) do if g.npc then fn(g.npc) end end
end

-- LockAll: `target` is the talked-to object (ScriptManager's target), or nil
function M.lockAll(ow, target)
  if not ow then return nil end
  ow.gen4Lock = { target = target }
  local waiting = {}
  each(ow, function(npc)
    if isFollower(npc) then
      -- the partner / walking Pokemon: its own follow logic owns it here
      return
    end
    if npc == target and npc.moving then
      -- LockLastTalked: unpaused until its step is done
      npc.gen4Paused = "finish"
      waiting[#waiting + 1] = npc
    else
      npc.gen4Paused = true
    end
  end)
  return waiting
end

function M.releaseAll(ow)
  if not ow then return end
  ow.gen4Lock = nil
  each(ow, function(npc) npc.gen4Paused = nil end)
end

function M.lockOne(npc) if npc then npc.gen4Paused = true end end
function M.releaseOne(npc) if npc then npc.gen4Paused = nil end end

-- true while the script's lock must wait on a step still landing
function M.finishing(waiting)
  for _, npc in ipairs(waiting or {}) do
    if npc.gen4Paused == "finish" and npc.moving then return true end
  end
  return false
end

-- NPC:update's question, at the top of its step branch: is this walker held
-- where it stands?  A walker a script is moving (scriptMoves -- the
-- cartridge's ApplyMovement, MAP_OBJ_STATUS_4) never is.
function M.holds(npc)
  local p = npc and npc.gen4Paused
  if p ~= true then return false end
  local MT = package.loaded["src.world.Gen4MovementTypes"]
  local f = MT and MT.frameState and MT.frameState()
  if f and f.claimed and f.claimed[npc] then return false end
  return true
end

-- ...and when a step lands: a "finish" walker is paused from here on
function M.landed(npc)
  if npc and npc.gen4Paused == "finish" then npc.gen4Paused = true end
end

-- THE FIELD UNDER A MESSAGE (OverworldState:animate, which the state stack
-- calls for the visible states under its top): on a Gen 4 / BW map with a
-- message box on top, the map objects take their frame -- the movement types
-- (paused by a lock, not by the box) and every step under way, which a lock
-- holds where it is.  The player, the input and the script's own queue are
-- left to the overworld's update, as before.
function M.fieldTick(ow)
  if not (ow and ow.map and ow.npcs) then return end
  local okV, GV = pcall(require, "src.core.GameVersion")
  if not (okV and GV.generation and (GV.generation() or 0) >= 4) then return end
  local Game = package.loaded["src.core.Game"]
  local stack = Game and Game.stack
  local top = stack and stack.top and stack:top()
  if not top or top == ow then return end
  local TextBox = package.loaded["src.render.TextBox"]
  local mt = getmetatable(top)
  if not (TextBox and (mt == TextBox or (mt and mt.__index == TextBox))) then return end
  -- only straight on top of this field (a box over a battle or a menu is not)
  local states = stack.states or {}
  local below = states[#states - 1]
  -- (or over a script's fade overlay, which is the field under a palette)
  if below ~= ow and not (below and below.ow == ow and below.alpha ~= nil) then return end
  require("src.world.Gen4MovementTypes").beginFrame(ow)
  local cast = ow.cast or ow.entities
  for _, npc in ipairs(ow.npcs) do npc:update(ow.map, cast) end
end

return M
