-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 44: THE SHUTTERS ON A TRANSITION INSIDE A ROOM (zelda3 names).
--
-- Traced on the GBA: the intra-room transition's state table
-- (kDungeon_IntraRoomTrans, 0x14CB54) has DungeonTransition_Subtile_
-- ResetShutters at state 2 (0x0806CFC0: dung_flag_trapdoors_down (+0xB10)
-- = 0, door_animation_step_indicator (+0xC02) = 7, OperateShutterDoors
-- 0x080810AC -- every shutter of type 0x44 / 0x18 that is shut opens at
-- once) and DungeonTransition_Subtile_TriggerShutters at state 7, after the
-- landing (0x0806D264: if the flag is 0 it becomes 1 and submodule 5 runs
-- OperateShutterDoors again -- every open 0x44 / 0x18 shutter shuts).
-- So a two-way shutter between quadrants never blocks the way in: it opens
-- as Link crosses and shuts behind him (Agahnim's tower, room 0xE0: the
-- south-west quadrant's way north ends in the north-west quadrant's
-- shutter 0x18; the port kept it shut and Link could not get in). The room
-- tags (Actors.lua) open the shutters again when their rule holds.
--
-- OURS: the shutters open and shut at once (the cartridge animates the
-- closing over submodule 5's steps); no sounds. The shutting waits until
-- Link's body is off every shutter's cells: the cartridge shuts them right
-- after the landing (kStaircaseTab2 leaves Link at y & 0xFF = 0xD8 going
-- up, on the door's rows) -- its doorway collision there is not traced, the
-- port's would hold Link in the shut door.

local M = { NAME = "shut44" }

M.TYPES = { [0x18] = true, [0x44] = true }   -- kDoorType_ShuttersTwoWay, kDoorType_Shutter

function M.extract() return {} end

local function shutters(inside)
  local out = {}
  for _, l in ipairs(inside and inside.locks or {}) do
    if l.kind == "shutter" and M.TYPES[l.type] then out[#out + 1] = l end
  end
  return out
end

-- DungeonTransition_Subtile_ResetShutters
function M.reset(game)
  local inside = game.interior
  local n = 0
  for _, l in ipairs(shutters(inside)) do
    if not l.open then inside:openLock(l); n = n + 1 end
  end
  if n > 0 then game.roomImages = nil end
  game.shutterResets = (game.shutterResets or 0) + n
  return n
end

-- is Link's body (x .. x + 15, y + 8 .. y + 23) on an open shutter's cells?
function M.onShutter(game)
  local lk = game.link
  for _, l in ipairs(shutters(game.interior)) do
    if l.open then
      for _, c in ipairs(l.cells) do
        local cx, cy = (c % 64) * 8, math.floor(c / 64) * 8
        if cx + 8 > lk.x and cx < lk.x + 16 and cy + 8 > lk.y + 8 and cy < lk.y + 24 then return true end
      end
    end
  end
  return false
end

-- DungeonTransition_Subtile_TriggerShutters
function M.trigger(game)
  local inside = game.interior
  local n = 0
  for _, l in ipairs(shutters(inside)) do
    if l.open then
      inside:closeLock(l)
      if inside.mem and inside.mem.doors then inside.mem.doors[l.index] = nil end
      l.entry = nil
      n = n + 1
    end
  end
  if n > 0 then game.roomImages = nil end
  -- the trapdoors are down again: the room tags may open them again
  if game.actors then game.actors.cleared = false end
  game.shutterTriggers = (game.shutterTriggers or 0) + n
  return n
end

function M.install(G)
  local srs = G.startRoomScroll
  function G:startRoomScroll(dir, leavesRoom, stairRoom)
    local intra = self.interior ~= nil and dir ~= nil and not leavesRoom and not stairRoom
    if intra then M.reset(self) end
    local r = srs(self, dir, leavesRoom, stairRoom)
    if intra then
      if self.roomScroll then self.roomScroll.shut44 = true else M.trigger(self) end
    end
    return r
  end
  local urs = G.updateRoomScroll
  function G:updateRoomScroll()
    local sc = self.roomScroll
    local r = urs(self)
    if sc and sc.shut44 and self.roomScroll == nil and self.interior then
      self.shut44Pending = self.interior.room
      if not M.onShutter(self) then M.trigger(self); self.shut44Pending = nil end
    end
    return r
  end
  local erf = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.shut44Pending and not self.roomScroll then
      if not self.interior or self.interior.room ~= self.shut44Pending then self.shut44Pending = nil
      elseif not M.onShutter(self) then M.trigger(self); self.shut44Pending = nil end
    end
    return erf(self, inp)
  end
end

return M
