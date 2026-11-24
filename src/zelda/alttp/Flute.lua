-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE FLUTE, THE WEATHERVANE AND THE BIRD (round 30; research 27A.3).
-- zelda3 names; the GBA's tables are read at import (file offsets in OFF).
--
--   The flute is GBA inventory byte 0x2E (receipt 0x14 -> 2, the bird's
--   0x4A -> 3); the shovel has its own byte (0x32) on the GBA.
--   Digging it up is Tools.lua's (area 0x2A, map16 spot 0x492; OURS there:
--   the flute is given at once, AncillaAdd_DugUpFlute's item and its
--   receipt message are not ported).
--   LinkItem_Flute: one play per 128 frames (flute_countdown); indoors, in
--   the Dark World or a special area only the tune. Flute 2 in Kakariko
--   (area 0x18, Link 0x1CF <= x < 0x230, 0x760 <= y < 0x7E0) blows up the
--   weathervane (AncillaAdd_ExplodingWeatherVane, Ancilla37: the tune runs
--   0x280 frames, then 128, then 10; Overworld_AlterWeathervane -- the GBA's
--   0x0808FD34 writes map16 0xE21 / 0xE22 / 0xE21 / 0xE23 / 0xE24 / 0xE25
--   at 0xC3E / 0xC40 / 0xC42 / 0xCBE / 0xCC0 / 0xCC2, its literals read at
--   import -- and save_ow_event_info[0x18] |= 0x20), the bird flies off
--   (Ancilla38_CutsceneDuck) and the flute is 3. Link is held meanwhile.
--   Flute 3 in the Light World: the bird (AncillaAdd_Duck_take_off) takes
--   Link to the flute menu (Module0E_0A_FluteMenu; the GBA's 0x080B2F18):
--   the Light World map zoomed out, spots kBirdTravel_x/y (GBA 0x16EED0:
--   x_lo, x_hi, y_lo, y_hi, 9 each), left / up -1, right / down +1 with
--   wrap; the GBA has a 9th spot (area 7, Turtle Rock) once
--   save_ow_event_info[0x47] & 0x20 (the GBA's 0x020022C7); B leaves (the
--   GBA's cancel), A / R chooses. The landing is the GBA's 20-byte entry
--   (0x150B18: screen, ..., Link y (+10), Link x (+12)) of the spot.
--   The flute boy's father (Townsfolk30, room 0x103) hears it next to him:
--   0xA2 (Sprite_FluteDad). The stump kid (sprite 0x2E subtype 1, Dark
--   World area 0x6A; FluteAardvark_Draw 0x174CEC, kFluteAardvark_Gfx /
--   _Delay 0x174C44 / 0x174C58): 0xE5 "find my flute" (choice) -> 0xE6 and
--   the shovel (receipt 0x13) / 0xE7; the shovel and no flute 0xE8; the
--   flute 0xE9, then the tune -> his animation -> sram_progress_indicator_3
--   |= 8 (here progress.stumpy), graphics 3.
--
-- (r34: the travel bird and Link's ride are drawn by Bird34.lua; r32: the
-- debris by Cutscenes32.lua)
-- OURS: no sound, no tune pose; the debris, the birds and Link's ride are
-- not drawn (the hold times are the cartridge's: 640 + 128 + 10 frames, then
-- 96 frames of the bird flying off; the ride is 48 frames, the landing
-- instant); spot markers are drawn as numbered boxes (the world map's
-- sprite numbers are not ported); the stump kid's byte rules use our
-- separate shovel / flute bytes (the GBA routine was not traced).

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = {}
-- r36: the flute boy's and his father's messages, read at import from the
-- cartridge's calls (RomTablesSpec "msg.flute")
local MSGF = require("src.zelda.alttp.RomTables").get("msg.flute")

M.OFF = {
  land = 0x150B18, markers = 0x16EED0,
  vane = { tile1 = 0x8FDA0, pos1 = 0x8FDA4, tile2 = 0x8FDA8, pos3 = 0x8FDAC, tile4 = 0x8FDB0, pos4 = 0x8FDB4,
           map8 = 0x8FDC0, tile6 = 0x8FDD0, pos6 = 0x8FDD4 },
  stumpy = 0x174CEC, stumpyGfx = 0x174C44, stumpyDelay = 0x174C58,
}
M.FLUTE_BYTE, M.SHOVEL_BYTE = 0x2E, 0x32
M.VANE_AREA, M.STUMP_AREA = 0x18, 0x6A
M.VANE = { x0 = 0x1CF, x1 = 0x230, y0 = 0x760, y1 = 0x7E0 }

function M.extract(rom, R, check)
  local O, V = M.OFF, M.OFF.vane
  local t = { land = {}, mk = {}, map16 = {} }
  for i = 0, 9 do t.land[i + 1] = rom:bytesU16(O.land + i * 20, 10) end
  local raw = rom:bytesU8(O.markers, 36)
  for i = 0, 8 do
    t.mk[i + 1] = { raw[1 + i] + raw[10 + i] * 256, raw[19 + i] + raw[28 + i] * 256 }
  end
  local function lit(o) return rom:u16(o) end
  local t1, t2, t4, t6 = lit(V.tile1) / 4, lit(V.tile2) / 4, lit(V.tile4) / 4, lit(V.tile6) / 4
  local p1, p3, p4, p6 = lit(V.pos1), lit(V.pos3), lit(V.pos4), lit(V.pos6)
  -- the GBA's order: (pos1, t1), (pos1 + 2, t2), (pos3, t1), (pos4, t4),
  -- the map8-only cell (pos4 + 2, map8 / 8), (pos6, t6)
  t.vane = { { p1, t1 }, { p1 + 2, t2 }, { p3, t1 }, { p4, t4 }, { p4 + 2, (lit(V.map8) - 4) / 8 }, { p6, t6 } }
  for _, e in ipairs(t.vane) do t.map16[e[2]] = rom:bytesU16(R.map16 + e[2] * 8, 4) end
  t.stumpy = {}
  for i = 0, 7 do
    local p = O.stumpy + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t.stumpy[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                        rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  t.stumpyGfx = rom:bytesU8(O.stumpyGfx, 20)
  for i, v in ipairs(t.stumpyGfx) do if v >= 128 then t.stumpyGfx[i] = v - 256 end end
  t.stumpyDelay = rom:bytesU8(O.stumpyDelay, 19)
  check(t.land[3][1] == 0x18 and t.mk[1][1] == 0x680 and t.mk[9][2] == 0x115 and t.vane[1][1] == 0xC3E
        and t.vane[6][1] == 0xCC2 and t.vane[1][2] == 0xE21 and t.stumpyGfx[20] == -1 and t.stumpy[1][5] == 2,
        "flute / weathervane / bird tables")
  return t
end
local function T(game) local t = game.data.t and game.data.t.flute return t and t.land and t or nil end
M.tabs = T

-- ------------------------------------------------------------ state
local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end
function M.level(game) return inv(game)[M.FLUTE_BYTE] or 0 end
local function setLevel(game, v)
  local p = game.progress
  p.inv = p.inv or {}
  p.inv[M.FLUTE_BYTE], p.inv[tostring(M.FLUTE_BYTE)] = v, nil
end
local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end
local function evDone(game, area) return band(events(game)[tostring(area)] or 0, 0x20) ~= 0 end

local function mergeMap16(game)
  local tb, idx = T(game), game.data.roomIdx
  if not (tb and idx and idx.map16) or game.fluteMap16 then return end
  game.fluteMap16 = true
  for k, v in pairs(tb.map16) do if not idx.map16[k] then idx.map16[k] = v end end
end
-- one 8 x 8 cell of a layer's map (data.mapPatch, as owSetMap16)
local function setCell(game, layer, x, y, w)
  local O = require("src.zelda.alttp.Overworld")
  local screen = O.screenAt("lw", x, y)
  if not screen then return end
  local n = game.data:mapNumber(layer, screen)
  if not n then return end
  game.data.mapPatch = game.data.mapPatch or {}
  local p = game.data.mapPatch[n] or {}
  game.data.mapPatch[n] = p
  p[O.cellIndex((x % 512) / 8, (y % 512) / 8)] = w
  if game.ow and game.ow.attrCache then game.ow.attrCache[screen] = nil end
  if game.view then game.view.screens[screen] = nil end
end
M.BG1_BLANK = 0x01E3   -- the GBA's 0x0808F5C0 writes it to the overlay (BG1) under a new map16
-- Overworld_AlterWeathervane (the GBA's 0x0808FD34): each map16 through
-- 0x0808F5C0 (BG2 cells, the BG1 cells blanked); the fifth is only BG2's
-- lower row and BG1's upper row of map16 0xE24
function M.alterVane(game)
  local tb = T(game)
  mergeMap16(game)
  local ax, ay = (M.VANE_AREA % 8) * 512, math.floor(M.VANE_AREA / 8) * 512
  local m16 = game.data.roomIdx and game.data.roomIdx.map16
  for i, e in ipairs(tb.vane) do
    local x, y = ax + (e[1] % 128) / 2 * 16, ay + math.floor(e[1] / 128) * 16
    if i == 5 then
      local w = tb.map16[e[2]]
      setCell(game, "bg2", x, y + 8, w[3]); setCell(game, "bg2", x + 8, y + 8, w[4])
      setCell(game, "bg1", x, y, w[1]); setCell(game, "bg1", x + 8, y, w[2])
    else
      game:owSetMap16(x, y, e[2])
      for _, c in ipairs({ { 0, 0 }, { 8, 0 }, { 0, 8 }, { 8, 8 } }) do setCell(game, "bg1", x + c[1], y + c[2], M.BG1_BLANK) end
    end
  end
  local ev = events(game)
  ev[tostring(M.VANE_AREA)] = bor(ev[tostring(M.VANE_AREA)] or 0, 0x20)
end

-- ------------------------------------------------------------ playing
-- the sprites run before the item code: a play counts on this frame and the next
function M.heard(game) return (game.flutePlayedAt or -9) >= (game.frame or 0) - 1 end
function M.play(game)
  local lk = game.link
  game.flutePlays = (game.flutePlays or 0) + 1
  game.flutePlayedAt = game.frame
  if game.state ~= "play" or lk.world ~= "lw" then return end
  if not game.area or game.area.parent >= 0x40 then return end
  local lv = M.level(game)
  if lv == 2 then
    if game.area.parent == M.VANE_AREA and lk.x >= M.VANE.x0 and lk.x < M.VANE.x1 and lk.y >= M.VANE.y0 and lk.y < M.VANE.y1 then
      game.vane = { t = 0, var2 = 0x280, G = 128, aux = 10, step = 0 }
    end
  elseif lv >= 3 then
    game.birdRide = { t = 0 }
  end
end

local function vaneFrame(game)
  local v = game.vane
  v.t = v.t + 1
  if v.var2 > 1 then v.var2 = v.var2 - 1 return end
  if v.G > 1 then v.G = v.G - 1 return end
  if v.step == 0 then
    v.aux = v.aux - 1
    if v.aux < 0 then
      v.step = 1
      M.alterVane(game)
      v.duck = 96
      game.vaneAltered = (game.vaneAltered or 0) + 1
    end
  elseif v.duck then
    v.duck = v.duck - 1
    if v.duck <= 0 then
      setLevel(game, 3)        -- Ancilla38: the bird leaves, link_item_flute = 3
      game.vane = nil
    end
  end
end

-- the flute menu (Module0E_0A_FluteMenu on the Light World map)
local Menu = {}
Menu.__index = Menu
function M.openMenu(game)
  local O = require("src.zelda.alttp.OwMap")
  local m = setmetatable({ game = game, sel = 0, frame = 0, wait = 0x10, done = false }, Menu)
  if O.available(game.data) then
    m.map = O.new(game)
    m.map:open()
    m.map.world = "lw"
    m.map:setZoom(0)
  end
  m.count = evDone(game, 0x47) and 9 or 8
  game.owmap = m
  game.fluteMenus = (game.fluteMenus or 0) + 1
  return m
end
function Menu:update(input)
  local function pressed(b) return input and input.wasPressed(b) end
  self.frame = self.frame + 1
  if self.map then self.map.frame = self.frame end
  if self.wait > 0 then self.wait = self.wait - 1
  else
    if pressed("b") then self.done = true; self.cancel = true; return end
    if pressed("a") or pressed("r") then self.done = true; M.land(self.game, self.sel) return end
  end
  if pressed("left") or pressed("up") then self.sel = self.sel - 1 end
  if pressed("right") or pressed("down") then self.sel = self.sel + 1 end
  if self.sel < 0 then self.sel = self.count - 1 elseif self.sel >= self.count then self.sel = 0 end
end
function Menu:draw()
  local lg = love.graphics
  if self.map then self.map:draw() else lg.clear(0, 0, 0, 1) end
  local tb = T(self.game)
  for i = self.count - 1, 0, -1 do
    local p = tb.mk[i + 1]
    local sx, sy
    if self.map then sx, sy = self.map:toScreen(p[1] / 16 + 128, p[2] / 16 + 128) end
    if not sx then sx, sy = p[1] / 4096 * 240, p[2] / 4096 * 160 end
    sx, sy = math.floor(sx), math.floor(sy)
    local on = i == self.sel
    if not on or band(self.frame, 6) < 4 then
      lg.setColor(0, 0, 0, 1)
      lg.rectangle("fill", sx - 5, sy - 5, 10, 10)
      lg.setColor(on and 1 or 0.95, on and 0.85 or 0.95, on and 0.2 or 0.95, 1)
      lg.rectangle("fill", sx - 4, sy - 4, 8, 8)
      lg.setColor(0, 0, 0, 1)
      lg.print(tostring(i + 1), sx - 3, sy - 7, 0, 0.75, 0.75)
    end
  end
  lg.setColor(1, 1, 1, 1)
end

-- FluteMenu_LoadTransport: the GBA's landing entry
function M.land(game, i)
  local tb = T(game)
  local e = tb.land[i + 1]
  if not e then return end
  local lk = game.link
  lk.world, lk.x, lk.y, lk.facing = "lw", e[7], e[6], 2
  lk.z, lk.moving = 0, false
  game.state = "play"
  game.area = game.ow:area(game:screen())
  game.cam = game:cameraFor(game.area)
  game.owActors, game.oweState = nil, nil
  game.birdLandings = (game.birdLandings or 0) + 1
  game.lastBirdSpot = i
end

-- ------------------------------------------------------------ the stump kid
function M.spawnStumpy(game, oa)
  local t = game.data.t and game.data.t.npc
  if not (T(game) and t and game.area and game.area.parent == M.STUMP_AREA) then return end
  local prg = game:storyProgress()
  local phase = (prg == 2 and 2) or (prg == 3 and 3) or 1
  local list = t.ow[phase] and t.ow[phase][M.STUMP_AREA + 1]
  local bx, by = (M.STUMP_AREA % 8) * 512, math.floor((M.STUMP_AREA % 64) / 8) * 512
  for _, e in ipairs(list or {}) do
    if e[3] == 0x2E then
      -- SpritePrep_FluteKid (Dark World): +8, -8; done -> graphics 3, state 5
      local a = { type = 0x2E, x = bx + e[2] * 16 + 8, y = by + e[1] * 16 - 8, lower = false, dir = 1, t = 0,
                  state = "idle", hp = 255, index = -1, stumpy = true, npc = true, ai = 0, gfx = 0, delay = 0, A = 0 }
      if game.progress.stumpy or M.level(game) > 2 then a.gfx, a.ai = 3, 5
      elseif M.level(game) == 2 then a.gfx = 1 end
      oa.list[#oa.list + 1] = a
    end
  end
end
local function hasShovel(game) return (inv(game)[M.SHOVEL_BYTE] or 0) ~= 0 end
function M.stumpyTalk(game, a)
  if a.ai ~= 0 then return false end
  local lv = M.level(game)
  if lv >= 3 or game.progress.stumpy then return false end
  if lv == 2 then
    a.gfx = 1
    game:showMessage(MSGF.kidDone)
    game.onTextDone = function() a.ai = 3 end
  elseif hasShovel(game) then
    game:showMessage(MSGF.kidShovel)
  else
    game:showMessage(MSGF.kidAsk)
    game.onTextDone = function(g)
      if (g.lastChoice or 0) == 0 then
        g:showMessage(MSGF.kidYes)
        g.onTextDone = function(g2) require("src.zelda.alttp.Townsfolk30").give(g2, 0x13) end
      else
        g:showMessage(MSGF.kidNo)
      end
    end
  end
  return true
end
function M.stumpyFrame(game, a)
  local tb = T(game)
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  if a.ai == 3 then
    if M.heard(game) then a.ai, a.A, a.delay = 4, 0, 0; game.fluteHold = true end
  elseif a.ai == 4 then
    if a.delay == 0 then
      local j = a.A
      a.A = j + 1
      local g = tb.stumpyGfx[j + 1]
      if g and g >= 0 then
        a.gfx, a.delay = g, tb.stumpyDelay[j + 1] or 0
      else
        a.ai = 5
        game.fluteHold = nil
      end
    end
  elseif a.ai == 5 then
    a.gfx = 3
    game.progress.stumpy = true
  end
end

-- ------------------------------------------------------------ install
function M.install(G)
  local Items = require("src.zelda.alttp.Items")
  if not Items.SLOT[15] then Items.SLOT[15] = "flute" end
  local itemFrame0 = G.itemFrame
  function G:itemFrame(inp)
    if T(self) then
      if (self.fluteCountdown or 0) > 0 then self.fluteCountdown = self.fluteCountdown - 1 end
      if inp.y and self:yItem() == "flute" and not self.carry then
        if (self.fluteCountdown or 0) == 0 and M.level(self) >= 2 then
          self.fluteCountdown = 128
          M.play(self)
        end
        return true
      end
    end
    return itemFrame0(self, inp)
  end
  -- the flute boy's father hears it (Sprite_FluteDad: touching him)
  local A = require("src.zelda.alttp.Actors")
  local up0 = A.update
  function A:update()
    local game = self.game
    if game and T(game) and M.heard(game) and self.inside and self.room ~= -1 then
      local TF = require("src.zelda.alttp.Townsfolk30")
      for _, a in ipairs(self.list) do
        if a.type == 0x29 and a.p30 and a.sub2 == 0 and a.ai == 0 and not a.dead and TF.touching(game, a) then
          a.ai = 1
          game:showMessage(MSGF.dad)
          game.dadHeard = (game.dadHeard or 0) + 1
        end
      end
    end
    if game and T(game) and self.room == -1 then
      for _, a in ipairs(self.list) do if a.stumpy and not a.dead then M.stumpyFrame(game, a) end end
    end
    return up0(self)
  end
  local N = require("src.zelda.alttp.Npc")
  local spawn0 = N.spawnArea
  function N.spawnArea(game, oa)
    spawn0(game, oa)
    M.spawnStumpy(game, oa)
  end
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    local tb = self.data.t and self.data.t.flute
    if a.stumpy and tb and tb.stumpy then
      self:drawDmd(a, tb.stumpy, (a.gfx or 0) * 2, 2, x, y, band(self.info.flags3[0x2E + 1] or 0, 0x0F))
      return true
    end
    return da0(self, a, x, y, frame, room)
  end
  -- frame hooks: the weathervane, the ride, the vane kept after a reload
  local upd0 = G.update
  function G:update(dt)
    if T(self) and self.state == "play" and not self.textBox and not self.owmap then
      if self.vane then vaneFrame(self) end
      if self.birdRide then
        local r = self.birdRide
        r.t = r.t + 1
        if r.t >= 48 then self.birdRide = nil; M.openMenu(self) end
      end
      if self.area and self.area.parent == M.VANE_AREA and self.link.world == "lw" and self.vaneApplied ~= self.data
         and evDone(self, M.VANE_AREA) then
        self.vaneApplied = self.data
        M.alterVane(self)
      end
    end
    return upd0(self, dt)
  end
  -- Link held during the weathervane / ride / stump kid's dance
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if (self.vane or self.birdRide or self.fluteHold) and inp then
      for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "y" }) do inp[k] = false end
    end
    if inp and inp.a and T(self) and self.owActors and not self.textBox then
      local C = require("src.zelda.alttp.Carry")
      local q = C.QUERY[self.link.facing]
      local px, py = self.link.x + q[1], self.link.y + q[2]
      for _, a in ipairs(self.owActors.list) do
        if a.stumpy and not a.dead and px >= a.x - 4 and px < a.x + 20 and py >= a.y - 20 and py < a.y + 20 then
          if M.stumpyTalk(self, a) then return true end
        end
      end
    end
    return owFrame(self, inp)
  end
end

return M
