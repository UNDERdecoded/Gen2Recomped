-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 44: HYRULE CASTLE AFTER THE ESCAPE -- THE FRONT GATE, AGAHNIM'S
-- BARRIER AND THE TOWER DOOR (zelda3 names; traced on the GBA).
--
-- THE AREA'S EVENT OVERLAY. Overworld_HandleOverlaysAndBombDoors is the
-- GBA's 0x08076F30: area < 0x80 with save_ow_event_info (0x02002280)
-- [area] & 0x20 -> 0x080925E4 = Overworld_LoadEventOverlay, which calls
-- the area's own routine from the pointer table 0x153C04 (one per area;
-- 0x1B / 0x1C / 0x23 / 0x24 share 0x0808FDD8). That routine writes map8
-- words of map16 tiles straight into the BG2 map at 0x02018000 (32 x 32
-- blocks: index bits 0-4 x, 5-9 y, 10 / 12 x bits 5 / 6, 11 / 13 y bits 5 /
-- 6, as 0x0809265C converts a map16 position). For 0x1B it is the castle's
-- front gate opened (zelda3's case 0x1B: map16 0xDC1.. at (30..33, 39..40)).
-- The routine is straight-line code: it is run at import by a small Thumb
-- evaluator (ldr literal / mov / add / sub / lsl / ldrh from the ROM / strh),
-- and the words it stores are the data (data.t.castle44.gate). The bit is
-- set by the priest (Escape.lua, r43) and by Agahnim's defeat.
--
-- AGAHNIM'S BARRIER, sprite 0x40 (area 0x1B's lists, cell (31, 6)):
--   SpritePrep_AgahnimsBarrier (GBA 0x080F81BC, prep table 0x17451C):
--     outdoors, save_ow_event_info[area] & 0x40 -> graphics 4 (broken);
--     x + 8, y + 8 (0x080C35C0), then y_lo - 12 (0x080F7B24).
--   Sprite_EvilBarrier (0x080F7F8C): draw (0x080F8108: cur_sprite_y + 8;
--     graphics 4 -> the broken frame 0x179EF8 (2 OAM), else 0x179F30 +
--     F * 8 (1), 0x179F40 + F2 * 16 (2), 0x179F60 + (graphics & 1) * 32
--     (4)); graphics 4 -> nothing else. Else graphics = frame >> 1 & 3,
--     F = frame >> 5 & 1, F2 = (frame + 16) >> 5 & 1; Sprite_ReturnIfInactive;
--     Sprite_CheckDamageFromLink with link_sword_type <= 1 -> 0x080F821C
--     (hit timer 0, Sprite_AttemptDamageToLinkPlusRecoil, electrocute 0x40);
--     Sprite_BehaveAsBarrier (0x080C5080: flags4 cleared -> hit box 0, the
--     push back); then Link with (link_y - cur_y + 8) < 24 and (link_x -
--     cur_x + 32) < 64 (cur_y = y + 8) and link_actual_vel_y - 1 negative
--     (not moving down) is zapped: electrocute 64, incapacitated 12, damage
--     2, x speed 0, y speed 48 (pushed down).
--   Its death (the GBA's 0x080C2382, Sprite death): save_ow_event_info
--     [area] |= 0x40; SpriteDeath_Func4: state 9, graphics 4 (it stays,
--     drawn broken).
--
-- THE TOWER DOOR is a big door of kind 0x169 (map8 0x169 / 0x569 at (31..32,
-- 6)): 0x0808BE18 opens it while the story byte (+0x165E) is 2 or less,
-- else it is looked up as an ordinary entrance. The port opened kind 0x169
-- only before the escape (Game.lua, fixed there).
--
-- OURS: the barrier's hit timer (the sword's damage is taken at once, the
-- timer only stops a second hit in the same swing); no zapped pose / palette
-- flash, no sounds, no death poof; the Byrna exception (0x080F825C) is not
-- ported. A save made before r43 (escaped, no castle event bit) gets the bit
-- when the castle area loads.

local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local M = { NAME = "castle44" }

M.OFF = {
  overlayFns = 0x153C04,     -- Overworld_LoadEventOverlay's per-area routines (u32 x 0x80)
  bg2 = 0x02018000,          -- the BG2 map those routines write
  broken = 0x179EF8, partA = 0x179F30, partB = 0x179F40, partC = 0x179F60,
}
M.AREA = 0x1B
M.TYPE = 0x40
M.EV_GATE, M.EV_BARRIER = 0x20, 0x40

-- ------------------------------------------------------------ the Thumb run
-- run a straight-line Thumb routine (file offset) and return its halfword
-- stores as { addr, value } (nil, reason on anything it cannot follow)
function M.runThumb(rom, off, maxOps)
  local r = {}
  for i = 0, 15 do r[i] = 0 end
  local stores = {}
  local pc = off
  local M32 = 4294967296
  local function w(v) return v % M32 end
  for _ = 1, maxOps or 512 do
    local op = rom:u16(pc)
    local nextPc = pc + 2
    local top5 = rshift(op, 11)
    if band(op, 0xFE00) == 0xB400 or band(op, 0xFF00) == 0xBC00 then
      -- push / pop without pc: the saved registers do not matter here
    elseif band(op, 0xFF00) == 0xBD00 or band(op, 0xFF80) == 0x4700 then
      return stores
    elseif band(op, 0xFF00) == 0x4600 then
      local rd = bor(lshift(band(rshift(op, 7), 1), 3), band(op, 7))
      r[rd] = r[band(rshift(op, 3), 0xF)]
    elseif band(op, 0xFF00) == 0x4400 then
      local rd = bor(lshift(band(rshift(op, 7), 1), 3), band(op, 7))
      r[rd] = w(r[rd] + r[band(rshift(op, 3), 0xF)])
    elseif top5 == 0x09 then                                  -- ldr rd, [pc, #imm]
      local la = band(pc + 4, bit.bnot(3)) + band(op, 0xFF) * 4
      r[band(rshift(op, 8), 7)] = rom:u32(la)
    elseif band(op, 0xFE00) == 0x1800 then                    -- adds rd, rn, rm
      r[band(op, 7)] = w(r[band(rshift(op, 3), 7)] + r[band(rshift(op, 6), 7)])
    elseif band(op, 0xFE00) == 0x1A00 then                    -- subs rd, rn, rm
      r[band(op, 7)] = w(r[band(rshift(op, 3), 7)] - r[band(rshift(op, 6), 7)])
    elseif band(op, 0xFE00) == 0x1C00 then                    -- adds rd, rn, #imm3
      r[band(op, 7)] = w(r[band(rshift(op, 3), 7)] + band(rshift(op, 6), 7))
    elseif band(op, 0xFE00) == 0x1E00 then                    -- subs rd, rn, #imm3
      r[band(op, 7)] = w(r[band(rshift(op, 3), 7)] - band(rshift(op, 6), 7))
    elseif top5 == 0x04 then                                  -- movs rd, #imm8
      r[band(rshift(op, 8), 7)] = band(op, 0xFF)
    elseif top5 == 0x06 then                                  -- adds rd, #imm8
      local d = band(rshift(op, 8), 7); r[d] = w(r[d] + band(op, 0xFF))
    elseif top5 == 0x07 then                                  -- subs rd, #imm8
      local d = band(rshift(op, 8), 7); r[d] = w(r[d] - band(op, 0xFF))
    elseif top5 == 0x00 then                                  -- lsls rd, rm, #imm5
      r[band(op, 7)] = w(r[band(rshift(op, 3), 7)] * 2 ^ band(rshift(op, 6), 31))
    elseif top5 == 0x01 then                                  -- lsrs rd, rm, #imm5
      local n = band(rshift(op, 6), 31); if n == 0 then n = 32 end
      r[band(op, 7)] = math.floor(r[band(rshift(op, 3), 7)] / 2 ^ n)
    elseif top5 == 0x11 then                                  -- ldrh rd, [rn, #imm5 * 2]
      local a = r[band(rshift(op, 3), 7)] + band(rshift(op, 6), 31) * 2
      if a < 0x08000000 or a >= 0x08000000 + rom.size then return nil, ("ldrh from %08X"):format(a) end
      r[band(op, 7)] = rom:u16(a - 0x08000000)
    elseif top5 == 0x10 then                                  -- strh rd, [rn, #imm5 * 2]
      local a = r[band(rshift(op, 3), 7)] + band(rshift(op, 6), 31) * 2
      stores[#stores + 1] = { a, band(r[band(op, 7)], 0xFFFF) }
    else
      return nil, ("opcode %04X at %06X"):format(op, pc)
    end
    pc = nextPc
  end
  return nil, "too long"
end

-- a BG2 map halfword index (the GBA's 32 x 32 blocks) -> area 8 px cell
function M.cellOf(i)
  local cx = band(i, 31) + band(rshift(i, 10), 1) * 32 + band(rshift(i, 12), 1) * 64
  local cy = band(rshift(i, 5), 31) + band(rshift(i, 11), 1) * 32 + band(rshift(i, 13), 1) * 64
  return cx, cy
end

local function dmd(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local p = o + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end

function M.extract(rom, R, check)
  local O = M.OFF
  local fn = rom:u32(O.overlayFns + M.AREA * 4)
  local t = { gate = {}, gateAreas = {} }
  local stores, why = M.runThumb(rom, band(fn, 0xFFFFFFFE) - 0x08000000)
  local ok = stores ~= nil
  for _, s in ipairs(stores or {}) do
    local off = s[1] - O.bg2
    if off < 0 or off >= 0x8000 or off % 2 ~= 0 then ok = false break end
    local cx, cy = M.cellOf(off / 2)
    t.gate[#t.gate + 1] = { cx, cy, s[2] }
  end
  -- the areas that share the routine (a large area's four screens)
  for a = 0, 0x7F do if rom:u32(O.overlayFns + a * 4) == fn then t.gateAreas[#t.gateAreas + 1] = a end end
  check(ok and #t.gate == 32, "castle event overlay (0x153C04[0x1B]) ran: " .. tostring(why or #t.gate))
  t.broken, t.partA = dmd(rom, O.broken, 2), dmd(rom, O.partA, 2)
  t.partB, t.partC = dmd(rom, O.partB, 4), dmd(rom, O.partC, 8)
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.castle44 end
M.tabs = T

local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end
function M.event(game, area) return events(game)[tostring(area)] or 0 end
local function setEvent(game, area, b)
  local e = events(game)
  e[tostring(area)] = bor(e[tostring(area)] or 0, b)
end

-- ------------------------------------------------------------ the overlay
local function setCell(game, x, y, word)
  local O = require("src.zelda.alttp.Overworld")
  local screen = O.screenAt("lw", x, y)
  if not screen then return end
  local n = game.data:mapNumber("bg2", screen)
  if not n then return end
  game.data.mapPatch = game.data.mapPatch or {}
  local p = game.data.mapPatch[n] or {}
  game.data.mapPatch[n] = p
  p[O.cellIndex((x % 512) / 8, (y % 512) / 8)] = word
  if game.ow and game.ow.attrCache then game.ow.attrCache[screen] = nil end
  if game.view and game.view.screens then game.view.screens[screen] = nil end
end

-- Overworld_HandleOverlaysAndBombDoors for the castle area (on its load)
function M.applyOverlay(game)
  local tb = T(game)
  if not (tb and game.area) or game.link.world ~= "lw" then return false end
  local parent = game.area.parent
  if parent ~= M.AREA then return false end
  -- OURS: a save from before r43 (the priest did not set the bit)
  if game:storyProgress() >= 2 and band(M.event(game, parent), M.EV_GATE) == 0 then setEvent(game, parent, M.EV_GATE) end
  if band(M.event(game, parent), M.EV_GATE) == 0 then return false end
  for _, c in ipairs(tb.gate) do setCell(game, game.area.x + c[1] * 8, game.area.y + c[2] * 8, c[3]) end
  game.castleOverlays = (game.castleOverlays or 0) + 1
  return true
end

-- ------------------------------------------------------------ the barrier
local function cbOf(game) return game.data.roomIdx and game.data.roomIdx.combat end
local function A() return require("src.zelda.alttp.Actors") end

function M.prep(game, a)
  a.x, a.y = a.x + 8, a.y + 8 - 12
  a.gfx, a.F, a.F2 = 0, 0, 0
  a.untouchable = true          -- the shared code leaves it alone (its sword rule is here)
  if band(M.event(game, game.area and game.area.parent or M.AREA), M.EV_BARRIER) ~= 0 then a.gfx = 4 end
  M.box(game, a)
end

-- Sprite_BehaveAsBarrier with flags4 cleared: hit box 0
function M.box(game, a)
  if a.gfx == 4 then a.box = nil return end
  local cb = cbOf(game)
  local save = cb.flags4[a.type + 1]
  cb.flags4[a.type + 1] = 0
  local hx, hy, hw, hh = A().hitbox(cb, { type = a.type, x = a.x, y = a.y })
  cb.flags4[a.type + 1] = save
  a.box = { hx - a.x, hy - a.y, hw, hh }
end

-- Link zapped and pushed down (the zone at the end of Sprite_EvilBarrier)
local function zap(game)
  local lk = game.link
  if (game.blink or 0) == 0 then
    game.stats.health = math.max(0, game.stats.health - 2)
    game.blink = 58
    if game.stats.health <= 0 then game.gameOver = { t = 0 }; game.deaths = (game.deaths or 0) + 1 end
  end
  game.recoil = { vx = 0, vy = 48, t = 12, sx = 0, sy = 0 }
  game.swing, game.swordHeld = nil, 0
  game.barrierZaps = (game.barrierZaps or 0) + 1
end

function M.update(self, a, lk)
  local game = self.game
  if a.gfx == 4 then a.box = nil return end
  local fc = game.frame or self.frame or 0
  a.gfx = band(rshift(fc, 1), 3)
  a.F = band(rshift(fc, 5), 1)
  a.F2 = band(rshift(fc + 16, 5), 1)
  if (a.inv or 0) > 0 then a.inv = a.inv - 1 end
  a.recoil = nil
  M.box(game, a)
  if game.textBox or game.recoil then return end
  local cy, cx = a.y + 8, a.x
  -- link_actual_vel_y > 0 only while Link walks down (OURS: read from the pad)
  local inp = game.input
  local down = inp and inp.isDown and inp.isDown("down") and not inp.isDown("up")
  if lk.y - cy + 8 >= 0 and lk.y - cy + 8 < 24 and lk.x - cx + 32 >= 0 and lk.x - cx + 32 < 64 and not down then
    zap(game)
  end
end

-- Sprite_CheckDamageFromLink on the barrier: true when the sword met it
function M.sword(self, a, x, y, w, h, how)
  local game = self.game
  local sword = how and (how.sword or (how.vel and not how.cls and not how.arrow and not how.bomb))
  if not sword or a.gfx == 4 or (a.inv or 0) > 0 then return false end
  local hx, hy, hw, hh = A().hitbox(cbOf(game), a)
  if not A().overlapCart(x, y, w, h, hx, hy, hw, hh) then return false end
  local level = (game.progress and game.progress.swordLevel) or 1
  if level <= 1 then
    -- 0x080F821C: the barrier hurts Link (electrocute 0x40 if not blinking)
    local cb = cbOf(game)
    local cls = band(cb.bump[a.type + 1] or 0, 0x0F)
    game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
    game.barrierZaps = (game.barrierZaps or 0) + 1
    return true
  end
  local dmg = self:swordDamage(a, how) or 0
  a.inv = 0x1D
  game.swde = 16
  if dmg <= 0 then return true end
  a.hp = (a.hp or 1) - dmg
  game.barrierHits = (game.barrierHits or 0) + 1
  if a.hp <= 0 then
    -- the death: the area's event bit 0x40, graphics 4 (state 9, kept)
    setEvent(game, game.area and game.area.parent or M.AREA, M.EV_BARRIER)
    a.gfx, a.box = 4, nil
    game.barrierBroken = (game.barrierBroken or 0) + 1
  end
  return true
end

function M.draw(spr, a, x, y)
  local tb = spr.data.t and spr.data.t.castle44
  if not tb then return false end
  local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
  y = y + 8
  if a.gfx == 4 then
    spr:drawDmd(a, tb.broken, 0, 2, x, y, f)
  else
    spr:drawDmd(a, tb.partA, a.F or 0, 1, x, y, f)
    spr:drawDmd(a, tb.partB, (a.F2 or 0) * 2, 2, x, y, f)
    spr:drawDmd(a, tb.partC, band(a.gfx or 0, 1) * 4, 4, x, y, f)
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  local OE = require("src.zelda.alttp.OwEnemies")
  OE.TYPES[M.TYPE] = true
  local prep0 = OE.prep
  function OE.prep(game, a)
    prep0(game, a)
    if a.type == M.TYPE and T(game) then M.prep(game, a) end
    return a
  end
  local up0 = OE.update
  function OE.update(self, a, lk)
    if a.type == M.TYPE and T(self.game) then return M.update(self, a, lk) end
    return up0(self, a, lk)
  end
  local dr0 = OE.draw
  function OE.draw(spr, a, x, y, frame)
    if a.type == M.TYPE and a.owe then return M.draw(spr, a, x, y) end
    return dr0(spr, a, x, y, frame)
  end
  local Actors = require("src.zelda.alttp.Actors")
  local sh0 = Actors.swordHit
  function Actors:swordHit(x, y, w, h, how)
    local n = 0
    if self.room == -1 and T(self.game) then
      for _, a in ipairs(self.list) do
        if a.owe and a.type == M.TYPE and not a.dead and M.sword(self, a, x, y, w, h, how) then n = n + 1 end
      end
    end
    return n + sh0(self, x, y, w, h, how)
  end
  -- the overlay when the area loads (and again after a room)
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if T(self) and self.area then
      local key = self.area.parent .. ":" .. self.link.world
      if self.castle44Key ~= key then
        self.castle44Key = key
        M.applyOverlay(self)
      end
    end
    return owFrame(self, inp)
  end
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    self.castle44Key = nil
    return enter0(self, e)
  end
end

return M
