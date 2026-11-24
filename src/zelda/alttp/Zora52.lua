-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 52: King Zora (sprite 0x52, Zora's waterfall) and the flippers he
-- throws (sprite 0xC0 with sprite_E = the item).
--
-- Traced on the GBA (active / prep tables 0x174138 / 0x17451C):
--   SpritePrep 0x080E9998: with the flippers (0x0200233A) the sprite is
--     gone at once (+0xFA2 = 0); else 0x080C3758.
--   Main 0x080E99CC: the draw 0x080E9718, Sprite_ReturnIfInactive
--     0x080C3438, then the state (+0xF52) table 0x08177AB4:
--   0 0x080E9268 wait: Link within (link_x - x + 16) < 32 and
--     (link_y - y + 48) < 80 (unsigned 16 bit) -> the dash cancelled
--     (0x08093078), timer (+0xFC2) 0x7F, sound 0x2D, state 1, and every
--     other sprite without +0xE75 bit 7 is killed (0x080CB1E0).
--   1 0x080E937C rumble: while the timer runs the screen shakes by
--     0x08177AC8[timer & 1] (BG +0xA28) and Link is held (+0x1770 = 1);
--     then state 2, timer 0x7F, graphics 4.
--   2 0x080E93F4 rising: at timer 0x1C the splash (0x080E95CC: sound 0xE,
--     eight splash sprites, the ring timer +0xFE2 = 15); graphics =
--     0x08177ACC[timer >> 3]; then state 3, timer 0x7F.
--   3 0x080E945C the talk (graphics 0x08177ADC[timer >> 4]): timer 0x50
--     message 0x145; 0x4F: the choice (+0x1AE2) "no" -> 0x149 and the
--     timer 0x30, else 0x146; 0x4E: "no" -> 0x148, else the rupees
--     (0x080AA868) above 0x1F3 -> -500 (0x080AA83C), 0x147 and the gift
--     flag (+0x1062), else 0x148; 0x4D with the flag: the flippers
--     (0x080E9900); then state 4, timer 0x24.
--   4 0x080E9568 diving: at timer 0x1D the splash; graphics
--     0x08177AE4[timer >> 1]; then the sprite is killed and Link let go.
--   Draw 0x080E9718: from state 2 on, four 16 x 16 OBJs at
--     (graphics << 2) + i of the x / y / char / flags tables 0x08177B29 /
--     0x08177B5D / 0x08177B91 / 0x08177BC5 (flags without a palette get
--     the sprite's own); while the ring timer runs four more from
--     0x08177BF9 / 0x08177C01 / 0x08177C09 / 0x08177C11 at
--     ((timer >> 1) & 4) + i.
--   The gift 0x080E9900: sprite 0xC0 at King Zora's spot, z speed 0x20,
--     y speed 0x10, sprite_E 0x1E (the flippers' receipt). Sprite 0xC0's
--     main 0x080F7558 with sprite_E set: on the ground (z 0) Link touching
--     it (0x080C500C) gets sprite_E (Link_ReceiveItem 0x080A1588); it
--     moves (0x080C99DC), z speed - 2, and on landing halves its x / y
--     speeds and bounces with 0x08179C3C[n] (n = 1..3), the fourth landing
--     stops it.
--
-- From the ROM at import: the draw tables, the graphics-by-timer tables,
-- the bounce speeds, the message numbers (their call sites) and the price
-- (the literals at 0x080E94F0 / 0x080E9508).
-- OURS: no sounds, no screen shake, the splash sprites and the water
-- ripple (0x080C6350) are not made; the thrown flippers are drawn with the
-- item's menu icon (as the port's receipts) and their shadow.

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = { TYPE = 0x52, ITEM_TYPE = 0xC0, FLIPPERS = 0x1E }

M.OFF = {
  dX = 0x177B29, dY = 0x177B5D, dChar = 0x177B91, dFlags = 0x177BC5,      -- 13 frames x 4
  rX = 0x177BF9, rY = 0x177C01, rChar = 0x177C09, rFlags = 0x177C11,      -- 2 x 4
  g2 = 0x177ACC, g3 = 0x177ADC, g4 = 0x177AE4, bounce = 0x179C3C,
}
M.SITES = {
  msg = { hello = 0x080E948A, bye = 0x080E94B4, offer = 0x080E94C8, refuse = 0x080E94E0,
          poor = 0x080E94FA, thanks = 0x080E9510 },
  minus = 0x080E9508,     -- ldr r0, =-price
  most = 0x080E94F0,      -- ldr r1, =price - 1 (bgt)
}

local function s8(t) for i, v in ipairs(t) do if v >= 128 then t[i] = v - 256 end end return t end
local function lit(rom, at)
  local op = rom:u16(at - 0x08000000)
  if band(op, 0xF800) ~= 0x4800 then return nil end
  local la = band(at + 4, 0xFFFFFFFC) + band(op, 0xFF) * 4
  return rom:u32(la - 0x08000000)
end

function M.extract(rom, R, check)
  local O, S = M.OFF, M.SITES
  local RT = require("src.zelda.alttp.RomTables")
  local t = {
    dX = s8(rom:bytesU8(O.dX, 52)), dY = s8(rom:bytesU8(O.dY, 52)),
    dChar = rom:bytesU8(O.dChar, 52), dFlags = rom:bytesU8(O.dFlags, 52),
    rX = s8(rom:bytesU8(O.rX, 8)), rY = s8(rom:bytesU8(O.rY, 8)),
    rChar = rom:bytesU8(O.rChar, 8), rFlags = rom:bytesU8(O.rFlags, 8),
    g2 = rom:bytesU8(O.g2, 16), g3 = rom:bytesU8(O.g3, 8), g4 = rom:bytesU8(O.g4, 21),
    bounce = rom:bytesU8(O.bounce, 4), msg = {},
  }
  local ok = true
  for k, at in pairs(S.msg) do
    t.msg[k] = RT.msgAt(rom, at)
    ok = ok and t.msg[k] ~= nil
  end
  local minus, most = lit(rom, S.minus), lit(rom, S.most)
  ok = ok and minus ~= nil and most ~= nil
  if ok then t.price = 0x100000000 - minus; t.most = most end
  check(ok and t.price == t.most + 1, "King Zora's messages and price")
  check(t.dX[1] == -8 and t.dChar[17] == t.dChar[18] and t.g4[1] == t.g4[6] and t.bounce[4] == 0
        and t.bounce[1] > t.bounce[2], "King Zora's tables")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.zora52 end
M.tabs = T
local function OE() return require("src.zelda.alttp.OwEnemies") end
local function hasFlippers(game) return require("src.zelda.alttp.DarkWorld").hasFlippers(game) end

-- ------------------------------------------------------------ King Zora
function M.prep(game, a)
  a.kz = true
  a.untouchable = true
  a.ai, a.delay, a.ring, a.gfx = 0, 0, 0, 0
  if hasFlippers(game) then a.dead, a.gone = true, true end
end

local function spawnFlippers(self, a)
  local item = { type = M.ITEM_TYPE, x = a.x, y = a.y, lower = false, t = 0, index = -1, dir = 1,
                 state = "idle", owe = true, kzItem = M.FLIPPERS, untouchable = true,
                 vx = 0, vy = 0x10, vz = 0x20, z = 0, fx = 0, fy = 0, fz = 0, n = 0 }
  self.list[#self.list + 1] = item
  self.game.kzGifts = (self.game.kzGifts or 0) + 1
  return item
end

local function wait(self, a, lk)
  local dx = band(lk.x - a.x + 16, 0xFFFF)
  local dy = band(lk.y - a.y + 48, 0xFFFF)
  if dx >= 32 or dy >= 80 then return end
  local game = self.game
  if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
  a.delay, a.ai = 0x7F, 1
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  for _, b in ipairs(self.list) do
    if b ~= a and not b.dead and band(cb and cb.deflBits and cb.deflBits[b.type + 1] or 0, 0x80) == 0 then
      b.dead, b.gone = true, true
    end
  end
  game.kzMet = (game.kzMet or 0) + 1
end

local function talk(self, a, tb)
  local game = self.game
  local d = a.delay
  if d == 0x50 then
    game:showMessage(tb.msg.hello)
  elseif d == 0x4F then
    if (game.lastChoice or 0) ~= 0 then game:showMessage(tb.msg.bye); a.delay = 0x30
    else game:showMessage(tb.msg.offer) end
  elseif d == 0x4E then
    if (game.lastChoice or 0) ~= 0 then game:showMessage(tb.msg.refuse); a.delay = 0x30
    elseif (game.stats.rupees or 0) > tb.most then
      game.stats.rupees = game.stats.rupees - tb.price
      game:showMessage(tb.msg.thanks)
      a.gift = true
      game.kzPaid = (game.kzPaid or 0) + 1
    else
      game:showMessage(tb.msg.poor); a.delay = 0x30
    end
  elseif d == 0x4D and a.gift then
    a.gift = nil
    spawnFlippers(self, a)
  end
end

function M.update(self, a, lk)
  local game = self.game
  local tb = T(game)
  if not tb or a.dead or game.textBox then return end
  -- the timers count first (Sprite_ExecuteSingle)
  if a.delay > 0 then a.delay = a.delay - 1 end
  if (a.ring or 0) > 0 then a.ring = a.ring - 1 end
  local ai = a.ai
  if ai == 0 then
    wait(self, a, lk)
  elseif ai == 1 then
    game.kzHold = true
    if a.delay == 0 then a.ai, a.delay, a.gfx = 2, 0x7F, 4 end
  elseif ai == 2 then
    if a.delay ~= 0 then
      if a.delay == 0x1C then a.ring = 0x0F end
      a.gfx = tb.g2[rshift(a.delay, 3) + 1] or a.gfx
    else
      a.ai, a.delay = 3, 0x7F
    end
  elseif ai == 3 then
    if a.delay ~= 0 then
      a.gfx = tb.g3[rshift(a.delay, 4) + 1] or a.gfx
      talk(self, a, tb)
    else
      a.ai, a.delay = 4, 0x24
    end
  elseif ai == 4 then
    if a.delay ~= 0 then
      if a.delay == 0x1D then a.ring = 0x0F end
      a.gfx = tb.g4[rshift(a.delay, 1) + 1] or a.gfx
    else
      a.dead, a.gone = true, true
      game.kzHold = nil
    end
  end
end

-- ------------------------------------------------------------ the thrown flippers
local function itemFrame(self, a, lk)
  local game = self.game
  local tb = T(game)
  if not tb or a.dead or game.textBox then return end
  if (a.z or 0) == 0 then
    local cb = game.data.roomIdx and game.data.roomIdx.combat
    local Act = require("src.zelda.alttp.Actors")
    local hx, hy, hw, hh = a.x, a.y, 16, 16
    if cb and cb.flags4 then hx, hy, hw, hh = Act.hitbox(cb, a) end
    local lx, ly, lw, lh = Act.linkBox(lk)
    if Act.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh) and not game.holdItem then
      a.dead, a.gone = true, true
      game.kzGot = (game.kzGot or 0) + 1
      require("src.zelda.alttp.Sprites31").give(game, a.kzItem)
      return
    end
  end
  local H = OE().H
  H.moveXY(a); H.moveZ(a)
  a.vz = a.vz - 2
  if (a.z or 0) < 0 then
    a.z, a.fz = 0, 0
    -- (v & 0x80) + (v >> 1) on the speed bytes: halved, rounded down
    a.vx, a.vy = math.floor(a.vx / 2), math.floor(a.vy / 2)
    if a.n ~= 4 then
      a.n = a.n + 1
      a.vz = tb.bounce[a.n] or 0
    else
      a.vx, a.vy, a.vz = 0, 0, 0
    end
  end
end

-- ------------------------------------------------------------ drawing
local function oamFlags(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
function M.draw(spr, a, x, y, game)
  local tb = spr.data.t and spr.data.t.zora52
  if not tb then return false end
  if a.kzItem then
    spr:drawShadow(x, y, M.ITEM_TYPE)
    if game and game.drawItemIcon and game.cam then
      -- (Sprites draws in screen space: x, y are already camera-relative)
      game:drawItemIcon(a.kzItem, x, y - (a.z or 0))
    end
    return true
  end
  local f = oamFlags(spr, M.TYPE)
  if (a.ai or 0) >= 2 then
    local base = (a.gfx or 0) * 4
    for i = 3, 0, -1 do
      local j = base + i + 1
      local fl = tb.dFlags[j] or 0
      if band(fl, 0x0F) == 0 then fl = bor(fl, f) end
      spr:oam(x + (tb.dX[j] or 0), y + (tb.dY[j] or 0), tb.dChar[j] or 0, fl, 2)
    end
  end
  if (a.ring or 0) > 0 then
    local base = band(rshift(a.ring, 1), 4)
    for i = 3, 0, -1 do
      local j = base + i + 1
      spr:oam(x + tb.rX[j], y + tb.rY[j], tb.rChar[j], bor(tb.rFlags[j], 0x04), 2)
    end
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  local E = OE()
  E.TYPES[M.TYPE] = true
  local prep0 = E.prep
  function E.prep(game, a)
    prep0(game, a)
    if a.type == M.TYPE and T(game) then M.prep(game, a) end
    return a
  end
  local up0 = E.update
  function E.update(self, a, lk)
    if a.kz and T(self.game) then return M.update(self, a, lk) end
    if a.kzItem and T(self.game) then return itemFrame(self, a, lk) end
    return up0(self, a, lk)
  end
  local dr0 = E.draw
  function E.draw(spr, a, x, y, frame)
    if (a.kz or a.kzItem) and a.owe then return M.draw(spr, a, x, y, M.game) end
    return dr0(spr, a, x, y, frame)
  end
  -- Link held from the rumble until King Zora is gone (+0x1770)
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    M.game = self
    if self.kzHold and T(self) then
      local alive = false
      for _, a in ipairs(self.owActors and self.owActors.list or {}) do if a.kz and not a.dead then alive = true end end
      if alive then self.link.moving = false return true end
      self.kzHold = nil
    end
    return owFrame(self, inp)
  end
end

return M
