-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 57: a push block resting on a floor switch holds a "hold" shutter.
--
-- RoomTag_SwitchTrigger_HoldDoor (tag 0x16, kDungTagroutines GBA 0x152AC4
-- -> 0x08079CCC; Link's block 0x03002230):
--   for i < +0xB20 (the room's replacement-object count): if the state word
--   +0x195C[i] is 5, v = +0xB0E (0x08079CE0..0x08079CFA); only when no entry
--   is 5 (or +0xB0E is 0xFFFF) v = !(+0xBC4 somaria block on a switch) &&
--   !(+0xBC0 dung_flag_statechange_waterpuzzle) && !RoomTag_CheckForPressed
--   Switch (0x08079A10) -- the rule Palace.roomTags / Traps27 port. If v
--   differs from +0xB10 (dung_door_switch_triggered) it is stored there and
--   the shutters move (submodule +0x9AD = 5; v = 0 opens with sound 0x3B).
--   The push block's landing (0x0808373C, called for state 3 at 0x08083936):
--   the attribute under its new top-left cell (RAM 0x0200CBA0, the upper
--   table) is read; 0x20 drops it into the pit; else its four words are
--   drawn and, when the attribute was 0x23 (a floor switch), +0xB0E =
--   +0xB10 ^ 1 and the state becomes 4 (0x080837C8..0x080837E6); the push
--   code steps it to 5 (0x080AF96C). From then on the tag uses that latched
--   value: the shutters flip once and stay so while the room is loaded, no
--   matter who stands on what.
--
-- The port's push block (RoomObjects.stepBlock) calls M.landed with the
-- attribute under the landing cell before it becomes the block; M.roomTags
-- wraps Palace.roomTags at its call (Actors.lua) and, once a block holds a
-- switch, runs tag 0x16 with the latch and hides the slot from the inner
-- tags (Palace / Traps27 / Items27 wrappers).
-- OURS: the latch is kept on the block's record (the GBA's state table is
-- rebuilt on each room load, as our blocks are); tag routine 0x0807A088 (the
-- second table entry with the same test, 0x152BCC) is not wired.

local M = { NAME = "block57" }
M.SWITCH = 0x23
M.TAG = 0x16

-- RoomObjects.stepBlock's landing: attr = the cell's attribute before the
-- block is drawn there
function M.landed(inside, b, attr)
  if attr == M.SWITCH then b.onSwitch57 = true end
end

-- the latched shutter state (true = closed) of the room's blocks, or nil
local function latch(self, inside)
  for _, b in ipairs(inside.blocks or {}) do
    if b.onSwitch57 and not b.fell then
      if b.latch57 == nil then
        -- +0xB0E = +0xB10 ^ 1: the opposite of the shutters' state now
        b.latch57 = not (self.trapDown == true)
      end
      return b.latch57
    end
  end
  return nil
end
M.latch = latch

-- Palace.roomTags with the push-block latch for tag 0x16
function M.roomTags(Palace, self, lk)
  local game, inside = self.game, self.inside
  local hdr = inside and inside.hdr
  local slot = hdr and ((hdr[6] == M.TAG) and 6 or ((hdr[7] == M.TAG) and 7 or nil))
  local v = slot and latch(self, inside)
  if v == nil then return Palace.roomTags(self, lk) end
  local h2 = {}
  for k, x in pairs(hdr) do h2[k] = x end
  h2[slot] = 0
  inside.hdr = h2
  local ok, err = pcall(Palace.roomTags, self, lk)
  inside.hdr = hdr
  if not ok then error(err) end
  if v ~= (self.trapDown == true) then
    self.trapDown = v
    game.blockHolds57 = (game.blockHolds57 or 0) + 1
    if v then game:closeShutters() else game:openShutters() end
  end
end

return M
