-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 43: ZELDA'S TELEPATHY AFTER THE MASTER SWORD (zelda3 names).
--
-- Traced on the GBA:
--   * Ancilla22_ItemReceipt (0x081183F0..): for item 1 (the Master Sword,
--     +0xE29 == 1) while step != 2 and the receipt timer (+0xE33) is 0x11:
--     word_7E02CD (+0x1752) = 0xDF3 and follower_indicator (+0x1663) =
--     `movs r0, #0x0E` (0x08118438) -- the "telepathy" follower: nothing
--     follows Link, the follower slot only arms a trigger.
--   * Follower_Main: follower 0x0E runs Follower_HandleTrigger only.
--   * Follower_HandleTrigger (0x08115D30; the trigger rows are OldMan.lua's
--     tables, kTagalong_OutdoorInfos 0x17ECD4): outdoors, area 0 (the Lost
--     Woods) has the row {y 0xE8, x 0x90, bit 0, message 0x2B, follower
--     0x0E}: Link + 12 within 24 x 28 of (x + 8, y + 8) shows the message;
--     on the message the code compares with `cmp r2, #0x2B` (0x08115DE2) it
--     clears follower_indicator (0x08115E0A) -- the telepathy plays once.
-- The two code immediates (0x0E, 0x2B) are read at import.
-- OURS: the follower is set when the receipt starts (the cartridge: at
-- receipt timer 0x11, a few frames in, before its message); the GBA's
-- word_7E02CD countdown is not used by follower 0x0E (Follower_Main returns
-- before it) and is not kept.

local bit = require("bit")
local band, bor = bit.band, bit.bor

local M = { NAME = "tele43" }

M.OFF = { follower = 0x118438, clearMsg = 0x115DE2 }

function M.extract(rom, R, check)
  local t = { follower = rom:u8(M.OFF.follower), clearMsg = rom:u8(M.OFF.clearMsg) }
  -- the instructions' own opcodes (movs r0, #imm = 0x20; cmp r2, #imm = 0x2A)
  check(rom:u8(M.OFF.follower + 1) == 0x20 and rom:u8(M.OFF.clearMsg + 1) == 0x2A and t.follower ~= 0,
        "telepathy follower / message immediates")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.tele43 end
M.tabs = T
local function OMt(game) return require("src.zelda.alttp.OldMan").tabs(game) end
local function bmg(n) return require("src.zelda.alttp.Text").bmgIndex(n) end

-- Follower_HandleTrigger for the telepathy follower (outdoors and indoors)
function M.trigger(game)
  local tb, om = T(game), OMt(game)
  if not (tb and om) then return end
  if (game.progress.follower or 0) ~= tb.follower or game.textBox then return end
  local list, offs, rooms, key
  if game.state == "room" and game.interior then
    list, offs, rooms, key = om.inInfos, om.inOffs, om.inRooms, game.interior.room
  elseif game.state == "play" then
    list, offs, rooms = om.outInfos, om.outOffs, om.outRooms
    key = game.area and game.area.parent
    if key and game.link.world == "dw" then key = key + 0x40 end
  else
    return
  end
  local ix
  for j, r in ipairs(rooms) do if r == key then ix = j - 1 break end end
  if not ix then return end
  local lk = game.link
  local lx, ly = lk.x, lk.y
  if game.state == "room" then
    local r = game.interior.room
    lx, ly = (r % 16) * 512 + lk.x, math.floor(r / 16) * 512 + lk.y
  end
  for i = offs[ix + 1] + 1, offs[ix + 2] do
    local e = list[i]
    if e.follower == tb.follower then
      local dx, dy = math.abs(lx + 12 - (e.x + 8)), math.abs(ly + 12 - (e.y + 8))
      if dx < 24 and dy < 28 then
        local fl = game.omFlags or 0
        if band(e.bit, fl) ~= 0 then return end
        game.omFlags = bor(fl, e.bit)
        if e.msg == tb.clearMsg then game.progress.follower = 0 end
        game:showMessage(bmg(e.msg))
        game.telepathy43 = (game.telepathy43 or 0) + 1
        return
      end
    end
  end
end

function M.install(G)
  local Gv = require("src.zelda.alttp.Grove")
  local recv = Gv.receive
  function Gv.receive(game)
    local r = recv(game)
    local tb = T(game)
    if tb then game.progress.follower = tb.follower end
    return r
  end
  local upd0 = G.update
  function G:update(dt)
    local r = upd0(self, dt)
    if (self.state == "play" or self.state == "room") and not self.roomScroll and not self.scroll then
      M.trigger(self)
    end
    return r
  end
end

return M
