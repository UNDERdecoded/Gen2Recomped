-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 95: the Goriyas (Ganon's Tower 2F). The Eyegore types 0x83 / 0x84
-- are Goriyas in four rooms. SpritePrep_Eyegore (GBA 0x080EE074, from the
-- prep table entries of 0x83 / 0x84): the room (+0xB36) compared with four
-- `cmp r0, #imm` (0x080EE084..0x080EE0A0) -> sprite_B (+0xF72) + 1 and, for
-- 0x83, the deflection bits (+0xE75) = 0. Sprite_83_GreenEyegore (0x080EDB68)
-- runs Eyegore_Main only while sprite_B is 0; otherwise the Goriya:
--   Goriya_Draw (0x080EDFA4), inactive / recoil returns, delay_aux1 (+0xFD2)
--   == 8 -> Sprite_SpawnFirePhlegm (0x080EC688, the Zazak's: Enemies27A);
--   no d-pad (+0x545 & 0xF) or a drag state (+0x16F9) -> A = 0, touch, tiles;
--   else j = pad | (type 0x84) * 16: D / x speed / y speed from the tables
--   whose literals sit at 0x080EDBF8 / 0x080EDC06 / 0x080EDC14, MoveXY when
--   no wall, touch, tiles, gfx = Gfx[(++subtype2 & 12) | D] (literal
--   0x080EDC4C); a red one (0x84) facing Link within 8 px on an axis
--   (Sprite_DirectionToFaceLink 0x080C2FA8) sets delay_aux1 = 0x10 when
--   (A & 0x1F) == 0 and counts A; otherwise A = 0.
-- So a green Goriya walks with Link's d-pad across x and against it on y
-- (16), a red one against it on both (24), and the red one breathes fire.
-- The port ran every 0x83 / 0x84 as an Eyegore (asleep, eye, chase):
-- room 0x6B's Goriyas slept, then chased Link, and the green one tinked.
-- All tables, the rooms and the immediates are read from the ROM at import.
-- Sprite_SpawnFirePhlegm (shared with the Zazak) also writes flags5 = 0x20 when
-- link_shield_type > 2 (0x080EC79E..0x080EC7AE): the Mirror Shield blocks the
-- fire. The port's phlegm (Enemies27A) had no flags5: the shield never stopped
-- it. Now every phlegm gets the flag (Shield84's per-sprite flags5_84).
-- OURS: the drag state (+0x16F9) is taken as 0 (Link is never dragged in
-- these rooms in the port); the d-pad is the game's held keys this frame.

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = { NAME = "goriya95" }

M.SITES = { prep = 0x080EE074, prepRooms0 = 0x080EE084, prepRooms1 = 0x080EE0A2,
            main = 0x080EDB68, fireCmp = 0x080EDBBC, dirLit = 0x080EDBF8, xvLit = 0x080EDC06,
            yvLit = 0x080EDC14, gfxLit = 0x080EDC4C, maskImm = 0x080EDC9A, fireImm = 0x080EDCA2,
            draw = 0x080EDFA4, dmd2Lit = 0x080EDFC8, offsLit = 0x080EDFD4, dmdLit = 0x080EDFE6,
            cntLit = 0x080EDFEA, phlegm = 0x080EC688,
            phShieldLit = 0x080EC79E, phShieldCmp = 0x080EC7A2, phFlagMovs = 0x080EC7AC }

local function off(a) return a - 0x08000000 end
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end
-- `cmp rX, #imm` / `movs rX, #imm`: the immediate (op 0x28 / 0x20)
local function imm(rom, a, op)
  local h = rom:u16(off(a))
  if rshift(h, 11) ~= rshift(op, 3) then return nil end
  return band(h, 0xFF)
end
local function s8(v) v = band(v, 0xFF) return v >= 128 and v - 256 or v end
local function s16(v) v = band(v, 0xFFFF) return v >= 0x8000 and v - 0x10000 or v end
local function dmd(rom, p, n)
  local t = {}
  for i = 0, n - 1 do
    local o = off(p) + i * 8
    t[i + 1] = { s16(rom:u16(o)), s16(rom:u16(o + 2)), rom:u8(o + 4), rom:u8(o + 5), rom:u8(o + 7) }
  end
  return t
end

function M.extract(rom, R, check)
  local S = M.SITES
  -- the prep's room compares: every `cmp r0, #imm` between the two sites
  local rooms = {}
  for a = S.prepRooms0, S.prepRooms1, 2 do
    local h = rom:u16(off(a))
    if band(h, 0xFF00) == 0x2800 then rooms[band(h, 0xFF)] = true end
  end
  local n = 0
  for _ in pairs(rooms) do n = n + 1 end
  local p = { dir = lit(rom, S.dirLit), xv = lit(rom, S.xvLit), yv = lit(rom, S.yvLit), gfx = lit(rom, S.gfxLit),
              dmd2 = lit(rom, S.dmd2Lit), offs = lit(rom, S.offsLit), dmd = lit(rom, S.dmdLit), cnt = lit(rom, S.cntLit) }
  local ok = n == 4
  for _, v in pairs(p) do ok = ok and v ~= nil and v >= 0x08000000 and v < 0x0A000000 end
  local fire, mask, aux = imm(rom, S.fireCmp, 0x28), imm(rom, S.maskImm, 0x20), imm(rom, S.fireImm, 0x20)
  ok = ok and fire ~= nil and mask ~= nil and aux ~= nil
  -- Sprite_SpawnFirePhlegm's shield flag: link_shield_type (literal) > imm -> flags5 = the movs immediate
  local shLit, shCmp, shFlag = lit(rom, S.phShieldLit), imm(rom, S.phShieldCmp, 0x28), imm(rom, S.phFlagMovs, 0x20)
  ok = ok and shLit ~= nil and band(shLit, 0xFF000000) == 0x02000000 and shCmp ~= nil and shFlag ~= nil
  check(ok, "goriya95: prep rooms / table literals / immediates")
  if not ok then return {} end
  local t = { rooms = rooms, fire = fire, mask = mask, aux = aux, phShield = shCmp, phFlag = shFlag, xv = {}, yv = {}, dir = {}, gfx = {}, cnt = {}, offs = {} }
  for i = 0, 31 do
    t.xv[i + 1] = s8(rom:u8(off(p.xv) + i))
    t.yv[i + 1] = s8(rom:u8(off(p.yv) + i))
    t.dir[i + 1] = rom:u8(off(p.dir) + i)
  end
  for i = 0, 15 do t.gfx[i + 1] = rom:u8(off(p.gfx) + i) end
  for i = 0, 9 do t.cnt[i + 1] = rom:u8(off(p.cnt) + i); t.offs[i + 1] = rom:u8(off(p.offs) + i) end
  t.dmd = dmd(rom, p.dmd, 32)
  t.dmd2 = dmd(rom, p.dmd2, 3)
  -- shapes: right / left mirrored, the red half faster and reversed, counts fit the list
  check(t.xv[2] == -t.xv[3] and t.yv[5] == -t.yv[9] and t.xv[18] == -t.xv[19] and t.dir[3] == 1
        and t.offs[10] + t.cnt[10] <= 32 and t.dmd[1][5] == 2, "goriya95: table shapes")
  return t
end

local function tabs(game) return game and game.data and game.data.t and game.data.t.goriya95 end
M.tabs = tabs

-- SNES pad nibble (8 up, 4 down, 2 left, 1 right) from the game's held keys
function M.pad(game)
  local inp = game and game.input
  if not (inp and inp.isDown) then return 0 end
  local p = 0
  if inp.isDown("up") then p = p + 8 end
  if inp.isDown("down") then p = p + 4 end
  if inp.isDown("left") then p = p + 2 end
  if inp.isDown("right") then p = p + 1 end
  return p
end

function M.phlegmFlag(T, shieldType) return T ~= nil and T.phShield ~= nil and (shieldType or 0) > T.phShield end

function M.isGoriyaRoom(T, room) return T ~= nil and T.rooms ~= nil and room ~= nil and T.rooms[band(room, 0xFF)] == true end

-- SpritePrep_Eyegore's Goriya part
function M.prep(actors, a, T)
  local inside = actors.inside or (actors.game and actors.game.interior)
  if not M.isGoriyaRoom(T, inside and inside.room) then return false end
  a.goriya = (a.goriya or 0) + 1
  if a.type == 0x83 then a.closed, a.defl0 = false, true end
  a.A = 0
  return true
end

local OUR = { [0] = 3, 2, 1, 0 }
local function moveXY(a)
  local px = a.x * 16 + (a.fx or 0) + (a.vx or 0)
  local py = a.y * 16 + (a.fy or 0) + (a.vy or 0)
  a.x, a.fx = math.floor(px / 16), px % 16
  a.y, a.fy = math.floor(py / 16), py % 16
end
local function wrap8(v) v = v % 256 return v >= 128 and v - 256 or v end

M.OFFSCREEN, M.SPAN = 0x40, 0x170
function M.paused(a, cx, cy)
  local sx = band(a.x - cx + M.OFFSCREEN, 0xFFFF)
  local sy = band(a.y - (a.z or 0) - cy + M.OFFSCREEN, 0xFFFF)
  return sx >= M.SPAN or sy >= M.SPAN
end

-- one frame (after the timers); h = Palace._h, E = Enemies27A, D = Dungeons26
function M.step(actors, a, lk, T, pad, h, spawnPhlegm)
  local game = actors.game
  if a.type == 0x83 then a.closed = false end
  -- Goriya_Draw first: Sprite_PrepOamCoordOrDoubleRet (0x080C5ACC) pauses a
  -- sprite whose x / y - z is more than 0x40 px off the camera ((v + 0x40) >
  -- 0x16F, as the SNES), and Sprite_ReturnIfInactive then returns
  local inside = actors.inside
  if inside and inside.camera then
    local cx, cy = inside:camera(lk.x, lk.y, 240, 160)
    if M.paused(a, cx, cy) then a.paused95 = true; return "paused" end
  end
  a.paused95 = nil
  if a.recoil and actors:recoilStep(a) then return "recoil" end
  if (a.aux1 or 0) == T.fire and spawnPhlegm then spawnPhlegm(actors, a) end
  pad = band(pad or 0, 0x0F)
  if pad == 0 then
    a.A = 0
    h.tileCollision(actors, a)
    return "still"
  end
  local j = pad + (a.type == 0x84 and 16 or 0)
  a.D = T.dir[j + 1]
  a.dir = OUR[a.D]
  a.vx, a.vy = T.xv[j + 1], T.yv[j + 1]
  if (a.wall or 0) == 0 then moveXY(a) end
  h.tileCollision(actors, a)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  a.gfx = T.gfx[bor(band(a.sub2, 12), a.D) + 1]
  if a.type == 0x84 then
    local dx = wrap8(lk.x - a.x)
    local dy = wrap8(lk.y + 8 + (a.z or 0) - a.y)
    local face
    if math.abs(dx) >= math.abs(dy) then face = (lk.x - a.x) < 0 and 1 or 0 else face = ((lk.y + 8 + (a.z or 0) - a.y) < 0 and 1 or 0) + 2 end   -- r98: 16-bit side (0x080C2FA8)
    if (band(dx + 8, 0xFF) < 16 or band(dy + 8, 0xFF) < 16) and a.D == face then
      if band(a.A or 0, T.mask) == 0 then a.aux1 = T.aux end
      a.A = band((a.A or 0) + 1, 0xFF)
      return "aim"
    end
  end
  a.A = 0
  return "walk"
end

-- Goriya_Draw: the fire in the mouth (delay_aux1, not facing up) in front, then the body
function M.drawList(a, T)
  local list = {}
  if (a.aux1 or 0) ~= 0 and (a.D or 0) ~= 3 then list[#list + 1] = T.dmd2[(a.D or 0) + 1] end
  local g = a.gfx or 0
  local o, n = T.offs[g + 1] or 0, T.cnt[g + 1] or 0
  for i = 0, n - 1 do list[#list + 1] = T.dmd[o + i + 1] end
  return list
end

function M.install(G)
  if G.goriya95Installed then return end
  G.goriya95Installed = true
  local P = require("src.zelda.alttp.Palace")
  local prep0 = P.prep
  function P.prep(self, a, k)
    local r = prep0(self, a, k)
    if (a.type == 0x83 or a.type == 0x84) and self.game then M.prep(self, a, tabs(self.game)) end
    return r
  end
  -- every fire phlegm (the Goriya's and the Zazak's: the one spawn routine) gets the
  -- shield flag in flags5 when Link's shield is above the compare (the Mirror Shield)
  local E = require("src.zelda.alttp.Enemies27A")
  local eprep0 = E.prep
  function E.prep(self, a)
    local r = eprep0(self, a)
    local T = self.game and tabs(self.game)
    if a.phlegm and T and T.phShield then
      local st = require("src.zelda.alttp.Gear").shieldType(self.game) or 0
      if M.phlegmFlag(T, st) then a.flags5_84 = T.phFlag end
    end
    return r
  end
  local function spawnPhlegm(self, a)
    local E = require("src.zelda.alttp.Enemies27A")
    local tb = E.tabs(self.game)
    if not tb then return end
    local D = require("src.zelda.alttp.Dungeons26")
    local i = a.D or 0
    E._phlegm = a
    local ok, f = pcall(D.spawn, self, 0xA5, a.x + tb.phX[i + 1], a.y + tb.phY[i + 1], a.lower)
    E._phlegm = nil
    if ok and f then
      f.vx, f.vy = tb.phXv[i + 1], tb.phYv[i + 1]
      self.game.phlegms = (self.game.phlegms or 0) + 1
      self.game.lastPhlegm = f
    end
  end
  local upd0 = P.update
  function P.update(self, a, lk)
    local T = self.game and tabs(self.game)
    if a.goriya and T and (a.type == 0x83 or a.type == 0x84) and P.ready(self.game) then
      for _, key in ipairs({ "delay", "aux1", "aux2", "aux3", "aux4" }) do
        if (a[key] or 0) > 0 then a[key] = a[key] - 1 end
      end
      return M.step(self, a, lk, T, M.pad(self.game), P._h, spawnPhlegm)
    end
    return upd0(self, a, lk)
  end
  local draw0 = P.draw
  function P.draw(spr, a, x, y, frame, game)
    local d = (game and game.data) or spr.data
    local T = d and d.t and d.t.goriya95
    if a.goriya and T and (a.type == 0x83 or a.type == 0x84) then
      local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
      local list = M.drawList(a, T)
      spr:drawDmd(a, list, 0, #list, x, y, f)
      return true
    end
    return draw0(spr, a, x, y, frame, game)
  end
end

return M
