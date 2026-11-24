-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BOTTLE MERCHANT (round 67). Kakariko's sprite 0x75 (the overworld
-- lists of story phases 2 and 3) was not spawned, so Link could not get an
-- empty bottle, and the potion shop's cauldrons (Sprites31) never sold.
-- The GBA's Sprite_75_BottleVendor (sprite routine table 0x08174138 [0x75]
-- = 0x080D15C0 -> 0x080D10E4; zelda3 names):
--
--   BottleVendor_Draw 0x080D161C: two entries (8 bytes: x, y, char, flags,
--     -, size) per picture from the literal at 0x080D1640 (picture * 16),
--     the shadow (0x080C6230).
--   main: Sprite_BehaveAsBarrier; Link busy -> nothing; GetRandomNumber() ==
--     0 -> picture 1, delay 0x14 (0x080D1144); delay 0 -> picture 0; the
--     state table 0x08174A58:
--   0 0x080D1198: sold (byte +0x1662 & 2) -> the solicited "sold out"
--     (bl at 0x080D11CE); else the solicited offer (bl at 0x080D11EA,
--     a choice) -> state 1 (states 3 / 4: the fish, not ported).
--   1 0x080D1220: a choice other than the first, or rupees <= the cmp at
--     0x080D125C -> "no" (bl 0x080D123C / 0x080D1266), state 0; else
--     "thanks" (bl 0x080D127E), state 2.
--   2 0x080D15D0: Link_ReceiveItem(the movs at 0x080D15E2: the bottle),
--     +0x1662 |= the movs at 0x080D15EE, rupees - the movs at 0x080D15F4,
--     state 0.
--
-- Every number above that is game data (the draw entries, the messages, the
-- receipt, the price, the flag bit, the blink time) is read from the
-- player's ROM at import (data.t.bottle67); only addresses live here.
-- OURS: the fish (states 3 / 4) is not ported; talking is the port's "A
-- facing him" (Sprite_ShowSolicitedMessage); the rupees drop at once (the
-- cartridge counts the goal down); the sold flag is progress.bottleVendor.

local bit = require("bit")
local band, bxor = bit.band, bit.bxor

local M = {}
M.TYPE = 0x75
M.SPRITE_TABLE, M.MAIN = 0x08174138, 0x080D10E4
M.SITES = {
  dmdLit = 0x080D1640, blink = 0x080D1144,
  soldOut = 0x080D11CE, ask = 0x080D11EA, no = 0x080D123C, poor = 0x080D1266, yes = 0x080D127E,
  poorCmp = 0x080D125C, receipt = 0x080D15E2, flag = 0x080D15EE, price = 0x080D15F4,
  stateTab = 0x080D115C,
}

function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function imm(at, want) local v, form = RT.codeImm(rom, at); if form ~= want then return nil end return v end
  local t = { dmd = {} }
  local base = imm(S.dmdLit, "ldr")
  if base then
    for i = 0, 3 do
      local p = base - 0x08000000 + i * 8
      local x, y = rom:u16(p), rom:u16(p + 2)
      t.dmd[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                       rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
    end
  end
  for _, k in ipairs({ "soldOut", "ask", "no", "poor", "yes" }) do t[k] = RT.msgAt(rom, S[k]) end
  t.blink = imm(S.blink, "movs")
  t.receipt = imm(S.receipt, "movs")
  t.flag = imm(S.flag, "movs")
  t.price = imm(S.price, "movs")
  local cmpv = imm(S.poorCmp, "cmp")
  -- the type's routine reaches the main loop
  local entry = rom:u32(M.SPRITE_TABLE - 0x08000000 + M.TYPE * 4)
  local main = RT.blTarget(rom, entry - 1 + 6)
  check(#t.dmd == 4 and t.soldOut and t.ask and t.yes and t.no and t.price and cmpv and cmpv + 1 == t.price
        and t.receipt and t.flag and t.blink and main == M.MAIN,
        "the bottle merchant (Sprite_75_BottleVendor)")
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.bottle67 end
M.tab = tab

-- state 0 .. 2 as one talk: the offer, the answer, the bottle
function M.talk(game, a)
  local t = tab(game)
  if not t then return false end
  local p = game.progress
  if p.bottleVendor then game:showMessage(t.soldOut) return true end
  game:showMessage(t.ask)
  a.ai = 1
  game.onTextDone = function(g)
    local st = g.stats
    if (g.lastChoice or 0) ~= 0 or (st.rupees or 0) < t.price then
      a.ai = 0
      g:showMessage((g.lastChoice or 0) ~= 0 and t.no or t.poor)
      return
    end
    a.ai = 2
    g:showMessage(t.yes)
    g.onTextDone = function(g2)
      a.ai = 0
      g2.progress.bottleVendor = true
      g2.stats.rupees = (g2.stats.rupees or 0) - t.price
      g2.bottlesBought = (g2.bottlesBought or 0) + 1
      require("src.zelda.alttp.Sprites31").give(g2, t.receipt)
    end
  end
  return true
end

-- the blink: GetRandomNumber() == 0 -> picture 1 for the blink time
function M.tick(game, a)
  local t = tab(game)
  if not t then return end
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  local r = require("src.zelda.alttp.Drops").rng(game:dropRng())
  if r == 0 then a.gfx, a.delay = 1, t.blink end
  if (a.delay or 0) == 0 then a.gfx = 0 end
end

function M.draw(spr, a, x, y)
  local t = spr.data.t and spr.data.t.bottle67
  if not t then return false end
  local f = band(spr.info.flags3[M.TYPE + 1] or 0, 0x0F)
  spr:drawDmd(a, t.dmd, (a.gfx or 0) * 2, 2, x, y, f)
  if not spr:hasShadow(M.TYPE) then spr:drawShadow(x, y, M.TYPE) end
  return true
end

function M.install(G)
  local N = require("src.zelda.alttp.Npc")
  -- spawned with the area's people (Npc.spawnArea), a barrier (Npc.solidAt)
  N.TYPES[M.TYPE] = N.TYPES[M.TYPE] or { dmd = "bottle67", frame = function() return 0 end }
  local talk0 = N.talk
  function N.talk(game, a)
    if a.type == M.TYPE and a.npc then return M.talk(game, a) end
    return talk0(game, a)
  end
  local upd0 = N.update
  function N.update(game, list)
    for _, a in ipairs(list) do
      if a.type == M.TYPE and a.npc and not a.dead and not game.textBox then M.tick(game, a) end
    end
    return upd0(game, list)
  end
  -- A in front of him (Sprite_ShowSolicitedMessage: Link against his hit
  -- box, kSpriteHitbox by flags4; the point in front of Link within 4 px of
  -- it, as Townsfolk30 -- Npc.lua's 16 x 16 box missed by a pixel here)
  local owFrame0 = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if inp and inp.a and self.owActors and not self.textBox and tab(self) then
      local C = require("src.zelda.alttp.Carry")
      local A = require("src.zelda.alttp.Actors")
      local q = C.QUERY and C.QUERY[self.link.facing]
      local cb = self.data.roomIdx and self.data.roomIdx.combat
      if q then
        local px, py = self.link.x + q[1], self.link.y + q[2]
        for _, a in ipairs(self.owActors.list) do
          if a.type == M.TYPE and a.npc and not a.dead then
            local hx, hy, hw, hh = a.x, a.y, 16, 16
            if cb then hx, hy, hw, hh = A.hitbox(cb, a) end
            if px >= hx - 4 and px < hx + hw + 4 and py >= hy - 4 and py < hy + hh + 4 and M.talk(self, a) then
              self.npcTalks = (self.npcTalks or 0) + 1
              return true
            end
          end
        end
      end
    end
    return owFrame0(self, inp)
  end
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if a.type == M.TYPE and a.npc and M.draw(self, a, x, y) then return true end
    return da0(self, a, x, y, frame, room)
  end
end

return M
