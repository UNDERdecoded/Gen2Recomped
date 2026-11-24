-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 53: the shopkeeper sprite 0xBB's "kind 2" -- the man who gives
-- Link a chest's worth of rupees once (the Hype Cave, the Mini Moldorm cave
-- and one more room of the shop list).
--
-- Traced on the GBA:
--   SpritePrep_Shopkeeper 0x0810E1AC: the room's low byte (+0x9DA) against
--     kShopKeeperWhere 0x17D020 (13 bytes) -> index i (i = 13 when none),
--     then the prep handler 0x17CFE8 [i]. Indices 6, 9 and 12 (rooms
--     0x1E / 0x23 / 0x27) share 0x0810F1C8: subtype2 (+0x1052) = 2.
--   The main 0x0810E4B4 (kind table 0x17D034 [2]): every 4th frame the
--     head turns to Link; draw 0x080E67E8; Sprite_ReturnIfInactive; the
--     barrier 0x080C5080; then the state (+0xF52) table 0x17D090:
--     0 0x0810F51C: Sprite_ShowSolicitedMessage(0x179) (0x0810F528) ->
--       state 1;
--     1 0x0810E540: the room's save bits (+0xAA8) & 0x4000 set -> state 0;
--       else set it, state 2 and 0x0810EF44(item 0x46 (0x0810E588)):
--       Link_ReceiveItem 0x080A1588 (300 rupees, Receipt52), no thanks
--       message for subtype2 < 7;
--     2 0x0810F554: state 0.
--   The draw 0x080E67E8: Sprite_DrawMultiple(0x17768C + graphics * 16, 2)
--     (graphics +0xF92 = 2 from the main's every-4th-frame step); unless
--     +0x10D2, the head (the first OAM) gets char 0x17774C [dir] and the
--     h-flip of 0x177750 [dir] bit 6, dir = Sprite_DirectionToFaceLink
--     (0x080C2FA8) with up (3) turned to down (2), kept at +0x1082.
--
-- From the ROM at import: the prep table's subtype2 per room index (the
-- handler's `movs r1, #n; strb r1, [r0]`), the message (its call site),
-- the item (the `movs r1, #imm` before the call), the draw tables.
-- OURS: no shadow; talking is R facing him like the clerk's wares
-- (Items27's solicited reach); the graphics are 2 from the first frame.

local bit = require("bit")
local band = bit.band

local M = { TYPE = 0xBB, KIND = 2, FLAG = 0x4000 }

M.OFF = { where = 0x17D020, prep = 0x17CFE8, count = 13, dmd = 0x17768C, headChar = 0x17774C, headFlags = 0x177750 }
M.SITES = { msg = 0x0810F528, item = 0x0810E588 }

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { where = rom:bytesU8(O.where, O.count), kind = {} }
  for i = 0, O.count - 1 do
    local fn = band(rom:u32(O.prep + i * 4), 0xFFFFFFFE) - 0x08000000
    local mv, st = rom:u16(fn + 0x0C), rom:u16(fn + 0x0E)
    if band(mv, 0xFF00) == 0x2100 and st == 0x7001 then t.kind[i + 1] = band(mv, 0xFF) end
  end
  t.msg = require("src.zelda.alttp.RomTables").msgAt(rom, M.SITES.msg)
  local op = rom:u16(M.SITES.item - 0x08000000)
  if band(op, 0xFF00) == 0x2100 then t.item = band(op, 0xFF) end
  t.dmd = {}
  for i = 0, 5 do
    local p = O.dmd + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t.dmd[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                     rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  t.headChar, t.headFlags = rom:bytesU8(O.headChar, 4), rom:bytesU8(O.headFlags, 4)
  local n = 0
  for i = 1, O.count do if t.kind[i] == M.KIND then n = n + 1 end end
  check(t.msg ~= nil and t.item == 0x46 and n == 3 and t.kind[7] == M.KIND, "the generous shopkeeper")
  return t
end

local function T(game) local t = game.data and game.data.t and game.data.t.gen53 return t and t.kind and t end
M.tabs = T

-- the kind of the room's shopkeeper (nil: not on the list / no import)
function M.kindOf(game, room)
  local t = T(game)
  if not t then return nil end
  local low = room % 256
  for i, r in ipairs(t.where) do if r == low then return t.kind[i] end end
end

local function facing(game, a)
  local Carry = require("src.zelda.alttp.Carry")
  local q = Carry.QUERY and Carry.QUERY[game.link.facing]
  local lk = game.link
  local px, py = lk.x + (q and q[1] or 8), lk.y + (q and q[2] or 16)
  return px >= a.x - 2 and px < a.x + 18 and py >= a.y - 2 and py < a.y + 26
end

-- the kind-2 states, one frame
function M.update(actors, a, lk)
  local game, inside = actors.game, actors.inside
  local t = T(game)
  local st = a.gen53 or 0
  a.gen53k = true
  -- every 4th frame: graphics 2, the head towards Link (up -> down)
  if band(game.frame or 0, 3) == 0 then
    local d = require("src.zelda.alttp.Npc").faceLink(a, lk)
    a.gen53d = (d == 3) and 2 or d
  end
  if game.textBox or game.holdItem then return end
  if st == 0 then
    if game.rNow and facing(game, a) then
      game.rNow = false
      game:showMessage(t.msg)
      game.lastNpcMsg = t.msg
      a.gen53 = 1
    end
  elseif st == 1 then
    local mem = inside.mem or {}
    inside.mem = mem
    if mem.flag4000 then a.gen53 = 0 return end
    mem.flag4000 = true
    a.gen53 = 2
    game:getItem(t.item)
    game.gen53Given = (game.gen53Given or 0) + 1
    local msg = game.receiptMessage and game:receiptMessage(t.item)
    game.holdItem = { item = t.item, t = 0 }
    if msg and game:showMessage(msg) then
      local prev = game.onTextDone
      game.onTextDone = function(g) g.holdItem = nil; if prev then prev(g) end end
    else
      game.holdItem = nil
    end
  else
    a.gen53 = 0
  end
end

-- the draw (0x080E67E8)
function M.draw(spr, a, x, y)
  local t = spr.data.t and spr.data.t.gen53
  if not (t and t.dmd) then return false end
  local f = band(spr.info.flags3[M.TYPE + 1] or 0, 0x0F)
  local d = a.gen53d or 2
  local head = t.dmd[5]
  local list = { { head[1], head[2], t.headChar[d + 1] or head[3],
                   bit.bor(band(head[4], 0xBF), band(t.headFlags[d + 1] or 0, 0x40)), head[5] }, t.dmd[6] }
  spr:drawDmd(a, list, 0, 2, x, y, f)
  return true
end

function M.install(G)
  local Spr = require("src.zelda.alttp.Sprites")
  local da0 = Spr.drawActor
  function Spr:drawActor(a, x, y, frame, room)
    if a.gen53k and a.type == M.TYPE and M.draw(self, a, x, y) then return true end
    return da0(self, a, x, y, frame, room)
  end
  local S = require("src.zelda.alttp.Shop")
  local up0 = S.update
  function S.update(actors, a, lk)
    if not a.shopItem and actors.inside and T(actors.game) and M.kindOf(actors.game, actors.inside.room) == M.KIND then
      a.shopPrep, a.clerk = true, false
      return M.update(actors, a, lk)
    end
    return up0(actors, a, lk)
  end
end

return M
