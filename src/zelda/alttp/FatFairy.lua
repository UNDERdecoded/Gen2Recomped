-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PYRAMID'S FAT FAIRY (round 29) -- and the Waterfall of Wishing, which
-- runs the same routine.
--
-- Sprite 0x72 (routine 0x080DF44C): in room 0x115 (low byte 0x15, the
-- Lake Hylia pond) it runs table 0x1765CC (not ported here); in the other
-- pond rooms -- 0x114 (the Waterfall of Wishing, entrances 92 / 98) and
-- 0x116 (the pyramid, entrance 99 from area 0x5B) -- table 0x176608:
--   0 (0x080DFD54): delay 0, Link not busy, the message on contact (0x14D:
--     "Mysterious Pond ... Throw an item / Don't try it") -> state 1, Link
--     faces up;
--   1: the choice: "Don't" -> 0x14E, state 0, delay 0xFF; "Throw" -> 0x8D
--     ("Select an item ... and throw it") and the item menu, state 2;
--   2 (0x080DFE48): the chosen item (inventory offset sel from 0x02002320)
--     leaves the inventory (0 written), its receipt id = kPondItems
--     (0x17653C [sel]) [value - 1] (value 1 for sel 3 / 0x20), delay 0xFF;
--   3: at delay 0 -> the fairy appears (sprite 0x72 70 px above the pond),
--     music 0x14, the palette filter starts, delay 0xFF;
--   4: one filter step every 8 frames; at level 0 -> 0x8E ("Did you drop
--     this? Yes / No");
--   5: "Yes" -> 6, "No" -> 11;
--   6 (0x080E004C): the swap: in the Dark World (+0x165C) the bow (0x3A) ->
--     0x3B (the Silver Arrows, kind 4, message 0x152), the Tempered Sword
--     (2) -> the Golden Sword (3, kind 5), a bottle (0x16) -> 0x2C (kind 3);
--     in the Light World the boomerang (0x0C) -> 0x2A (kind 1), the shield
--     (4) -> 5 (kind 2), a bottle -> 0x2C (kind 3); a swap shows 0x8F ("I
--     like an honest person..."), anything else 0x150 ("I will give this
--     back"); state 7;
--   7: (sel 3: the old value is written back) the filter starts; 8: a step
--     every 8 frames, the fairy goes at level 0x1E, at 0 state 9;
--   9: the receipt of the (new or same) item; 10: the kind's message
--     (0x17669C: 0x92 0x93 0x95 0x94 0x96), state 0, delay 0xFF;
--   11: 0x90 ("Are you sure this is not yours?"); 12: "Really" -> 13, "To
--     tell the truth" -> 6; 13: 0x91 ("don't tell lies"), state 7.
-- Message numbers above are the cartridge's (GBA = SNES + 3); M.MSG holds the
-- SNES numbers read at import, kindMsgs the GBA's (Text.bmgIndex).
--
-- OURS / NOT PORTED: the item menu of state 1 is our item menu (Menu.lua):
-- A / SELECT throws the chosen item, B throws the sword, R the shield (the
-- GBA's own throw menu is not traced); the thrown item's flight (ancilla
-- 0x28), the fairy's picture and its dust, the palette filter (counted:
-- 31 steps of 8 frames from 0x1F, not drawn) and the music are not drawn
-- or played; Link is held from the throw to the last message.

local bit = require("bit")
local band = bit.band

local M = {}

M.TYPE = 0x72
M.ROOMS = { [0x114] = true, [0x116] = true }
-- r37: all nine read at import from the cartridge's calls (RomTablesSpec
-- "msg.fairy", SNES numbering: shown with game:showMessage); r36 had read
-- four of them from calls of other states
M.MSG = require("src.zelda.alttp.RomTables").get("msg.fairy")

M.OFF = { items = 0x17653C, kindMsgs = 0x17669C }

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { items = {}, kindMsgs = rom:bytesU16(O.kindMsgs, 5) }
  for sel = 0, 0x1F do
    local p = rom:u32(O.items + sel * 4) - 0x08000000
    t.items[sel + 1] = rom:bytesU8(p, 4)
  end
  check(t.items[0x00 + 1][1] == 0x3A and t.items[0x00 + 1][3] == 0x3B and t.items[0x1D + 1][3] == 0x02
        and t.items[0x1E + 1][1] == 0x04 and t.items[0x01 + 1][1] == 0x0C, "pond item lists")
  check(t.kindMsgs[1] == 0x92 and t.kindMsgs[5] == 0x96, "pond messages")
  return t
end

local function T(game) local t = game.data.t and game.data.t.fairy return t and t.items and t end
M.tabs = T

local function msg(game, n)
  return game:showMessage(require("src.zelda.alttp.Text").bmgIndex(n))
end

local function busy(game)
  return game.textBox or game.carry or game.swing or game.dash or game.recoil or game.holdItem or game.receipt
end

local function dark(game)
  local w = game.enteredFrom and game.enteredFrom.world
  return w == "dw"
end
M.dark = dark

-- the inventory byte at 0x02002320 + sel (Menu.inventory's addresses)
local function invGet(game, sel)
  return require("src.zelda.alttp.Menu").inventory(game)[0x20 + sel] or 0
end
local function invSet(game, sel, v)
  local p = game.progress
  p.inv = p.inv or {}
  p.inv[0x20 + sel] = v
  p.inv[tostring(0x20 + sel)] = nil
end

-- the swap of state 6: new receipt id, kind, message
function M.swap(isDark, gfx)
  local m = M.MSG
  if isDark then
    if gfx == 0x3A then return 0x3B, 4, m.silver end
    if gfx == 0x02 then return 0x03, 5, m.honest end
    if gfx == 0x16 then return 0x2C, 3, m.honest end
  else
    if gfx == 0x0C then return 0x2A, 1, m.honest end
    if gfx == 0x04 then return 0x05, 2, m.honest end
    if gfx == 0x16 then return 0x2C, 3, m.honest end
  end
  return gfx, 0, m.back
end

local function step(game, a)
  -- one palette-filter step every 8 frames (frame_counter & 7)
  if band(game.frame or 0, 7) ~= 0 then return false end
  a.filter = math.max(0, (a.filter or 0) - 1)
  return true
end

function M.update(actors, a, lk)
  local game = actors.game
  local tb = T(game)
  a.delay = a.delay or 0
  if a.delay > 0 then a.delay = a.delay - 1 end
  local ai = a.ai or 0
  local m = M.MSG
  if ai == 0 then
    if a.delay > 0 or busy(game) then return end
    if not require("src.zelda.alttp.Desert").touching(actors, a, lk) then return end
    game:showMessage(m.intro)
    a.ai, a.kind = 1, 0
    lk.facing = 0
  elseif ai == 1 then
    if (game.lastChoice or 0) ~= 0 then
      game:showMessage(m.dont)
      a.ai, a.delay = 0, 0xFF
    else
      game:showMessage(m.select)
      a.ai = 2
      game.pondHold, game.pondSel = true, nil
    end
  elseif ai == 2 then
    if game.pondSel == nil then
      if not game.menu then game.pondPick = true; game:openMenu() end
      return
    end
    local sel = game.pondSel
    game.pondSel, game.pondPick = nil, nil
    local v = invGet(game, sel)
    if v == 0 then
      -- OURS: nothing owned there (the GBA's menu offers owned items only)
      a.ai, a.delay, game.pondHold = 0, 0xFF, nil
      return
    end
    local r2 = (sel == 0x20 or sel == 3) and 1 or v
    local list = tb.items[sel + 1]
    a.sel, a.old, a.gfx = sel, v, list and list[r2] or 0
    invSet(game, sel, 0)
    a.ai, a.delay = 3, 0xFF
    game.pondThrows = (game.pondThrows or 0) + 1
  elseif ai == 3 then
    if a.delay > 0 then return end
    a.fairy, a.filter = true, 0x1F
    a.ai, a.delay = 4, 0xFF
  elseif ai == 4 then
    if step(game, a) and a.filter == 0 then
      a.ai = 5
      game:showMessage(m.drop)
    end
  elseif ai == 5 then
    a.ai = ((game.lastChoice or 0) ~= 0) and 11 or 6
  elseif ai == 6 then
    a.ai = 7
    local g2, kind, mm = M.swap(dark(game), a.gfx)
    a.gfx, a.kind = g2, kind
    game:showMessage(mm)
  elseif ai == 7 then
    if a.sel == 3 then invSet(game, 3, a.old) end
    a.ai, a.filter = 8, 0x1F
  elseif ai == 8 then
    if step(game, a) then
      if a.filter == 0x1E then a.fairy = false end
      if a.filter == 0 then a.ai = 9 end
    end
  elseif ai == 9 then
    a.ai = 10
    game:getItem(a.gfx)
    game.holdItem = { item = a.gfx, t = 0 }
    game.pondGifts = (game.pondGifts or 0) + 1
  elseif ai == 10 then
    a.ai, a.delay = 0, 0xFF
    local function done(g) g.holdItem, g.pondHold = nil, nil end
    if (a.kind or 0) ~= 0 and msg(game, tb.kindMsgs[a.kind]) then
      game.onTextDone = done
    else
      done(game)
    end
  elseif ai == 11 then
    a.ai = 12
    game:showMessage(m.sure)
  elseif ai == 12 then
    a.ai = ((game.lastChoice or 0) ~= 0) and 6 or 13
  elseif ai == 13 then
    a.ai = 7
    game:showMessage(m.lies)
  end
end

function M.install(G)
  local Actors = require("src.zelda.alttp.Actors")
  local up0 = Actors.update
  function Actors:update()
    local game = self.game
    local inside = self.inside
    if game and inside and inside.room and M.ROOMS[inside.room] and T(game) then
      for _, a in ipairs(self.list) do
        if a.type == M.TYPE and not a.dead then
          a.untouchable, a.noTouch = true, true
          M.update(self, a, game.link)
        end
      end
    end
    return up0(self)
  end
  -- Link is held while the pond's scene runs
  local roomFrame = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    -- (the room's sprites run inside escapeRoomFrame: only Link's input goes)
    if self.pondHold and inp then
      for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "y" }) do inp[k] = false end
    end
    return roomFrame(self, inp)
  end
  -- the throw menu (OURS: our item menu; B = the sword, R = the shield)
  local updMenu = G.updateMenu
  function G:updateMenu()
    local mn = self.menu
    if self.pondPick and mn and (mn.state == 4 or mn.state == 5) and self.input then
      local sel
      if self.input.isDown("b") then sel = 0x1D elseif self.input.isDown("r") then sel = 0x1E end
      if sel then
        self.pondSel = sel
        mn.state = 6
      end
    end
    local r = updMenu(self)
    if self.pondPick and not self.menu and self.pondSel == nil then
      self.pondSel = (self.progress.curItem or 1) - 1
    end
    return r
  end
end

return M
