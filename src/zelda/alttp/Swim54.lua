-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SWIMMING INDOORS (round 54). Swim.lua (round 26) swims outdoors only; in
-- the dungeons deep water (attribute 0x08) was solid. Traced on the GBA
-- (Link's block at 0x03002230; zelda3 names):
--
--   * the swim handler, player state 4 (+0x1718), is 0x08097F64
--     (PlayerHandler_04_Swimming: +0x1702 aux -> recoil, the flippers byte
--     0x0200233A) -- the same as outdoors (Swim.lua's swimFrame runs it).
--   * TileDetection indoors (table 0x0816832C): 0x08 -> deep water (+0x17D0,
--     0x080A07DC), 0x0A -> "normal tile" (+0x17D2, 0x080A07FC; the short
--     water ladder, the only one indoors: the plain floor 0x00 sets nothing,
--     0x080A0678), 0x01 / 0x02 / 0x03 / 0x04 walls (0x080A067C).
--   * The Y collision (0x08095358): all three probes (y + 8 / y + 24 at x,
--     x + 8, x + 15) on deep water while not in it (+0x17D4 = 0): dash
--     cancelled (0x08093078); TS (+0x9B5) == 0 -> Dungeon_HandleLayerChange
--     (0x0808B1A8: the lower level) and the hop, else +0x17D4 = 1 and the
--     hop (0x0809A24C). In deep water the middle probe on 0x0A (0x080953F8,
--     +0x17D2 & 2): +0x17D4 = 0, AncillaAdd_Splash (0x080AD1EC; indoors and
--     not in deep water it clears link_is_on_lower_level +0xA10) and the hop
--     out. Only the middle probe on deep water (zelda3 4420): from shallow
--     water with the flippers Link swims at once, else he is put back where
--     the frame started and hops in.
--   * The X collision (zelda3 Link_HandleCardinalCollision_X): the same with
--     Link first put back on his spot; out of the water only with all three
--     probes on 0x0A; the partial test is the third probe (y + 23).
--   * The hop (0x0809A24C Y / 0x0809A670 X): index = TS (0 after a layer
--     change); speed tab[i], z speed tab[3 + i], timer tab[6 + i] (Y table
--     0x08167ED0, X table 0x08167F99); state 6 has no tile collision.
--   * The landing (0x08099E9C..0x08099F06, Link_HandleRecoilAndTimer):
--     Link_SplashUponLanding -> state 4 when in deep water; then indoors,
--     not from state 2, with the flippers: link_is_on_lower_level = 1 (the
--     water is the second table); TileDetect under (x + 8, y + 20) on deep
--     water also starts the swim.
--   * TS = kSpiralTab1 [dung_hdr_bg2_properties] (GBA 0x0814CAD4; negative
--     -> 0, property 2 -> 3), as Dungeon_ResetTorchBackgroundAndPlayer.
--
-- OURS: no splash / ripple ancilla drawn, no sounds; without the flippers
-- Link is put back on the room's entry spot at once (the splash ancilla's
-- CheckAbilityToSwim -> Module07_14, RecoverPositionAfterDrowning); the
-- layer change's room + 16 (kind 0) is not ported (as Game.lua's ledges).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Link = require("src.zelda.alttp.Link")

local M = { NAME = "swim54" }

M.OFF = {
  vLit = 0x0809A288,     -- ldr r0, =0x08167ED0 (vertical hop: speed, z speed, timer by index)
  hLit = 0x0809A6AC,     -- ldr r0, =0x08167F99 (horizontal hop)
  tsLit = 0x0806D48E,    -- ldr r1, =0x0814CAD4 (kSpiralTab1)
}
M.DEEP, M.SHALLOW, M.LADDER = 0x08, 0x09, 0x0A

local function lit(rom, code)
  local h = rom:u16(code - 0x08000000)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  local la = band(code + 4, 0xFFFFFFFC) + band(h, 0xFF) * 4
  return rom:u32(la - 0x08000000)
end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = {}
  local v, h, ts = lit(rom, O.vLit), lit(rom, O.hLit), lit(rom, O.tsLit)
  if v and h and ts then
    t.v = rom:bytesU8(v - 0x08000000, 9)
    t.h = rom:bytesU8(h - 0x08000000, 9)
    t.ts = rom:bytesU8(ts - 0x08000000, 8)
  end
  local ok = t.v and t.h and t.ts and t.v[1] > 0 and t.v[1] < 0x80 and t.h[2] > 0 and t.h[2] < 0x80
             and t.v[5] > 0 and t.h[8] > 0
  if ok then
    for i = 1, 8 do if t.ts[i] ~= 0 and t.ts[i] ~= 1 and t.ts[i] ~= 0xFF then ok = false end end
  end
  check(ok, "indoor water hop tables, kSpiralTab1")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.swim54 end
M.tab = T
local function SW() return require("src.zelda.alttp.Swim") end
local function flippers(game) return require("src.zelda.alttp.DarkWorld").hasFlippers(game) end
local function bunny(game) return game.isBunny and game:isBunny() or false end

-- TS_copy for the room (Dungeon_ResetTorchBackgroundAndPlayer)
function M.ts(game, inside)
  local t = T(game)
  local prop = rshift(band((inside.hdr or {})[1] or 0, 0xE0), 5)
  local v = t and t.ts and t.ts[prop + 1] or 0
  if v >= 0x80 then v = 0 end
  if prop == 2 then v = 3 end
  return v
end

-- the attribute bits on three points (bit 1, 2, 4) equal to `want`
local function bits3(inside, pts, want)
  local b = 0
  for i, p in ipairs(pts) do
    if inside:attrAt(p[1], p[2]) == want then b = b + 2 ^ (i - 1) end
  end
  return b
end
local function probesY(lk, up)
  local y = lk.y + (up and 8 or 24)
  return { { lk.x, y }, { lk.x + 8, y }, { lk.x + 15, y } }
end
local function probesX(lk, left)
  local x = lk.x + (left and 0 or 15)
  return { { x, lk.y + 8 }, { x, lk.y + 16 }, { x, lk.y + 23 } }
end
M.probesY, M.probesX = probesY, probesX

-- Link_HopInOrOutOfWater_Y / _X: the hop record (Hop50.frame's shape)
function M.newHop(game, axis, sign, idx, into)
  local t = T(game)
  local h50 = game.data.t.hop50
  local tab = axis == "y" and t.v or t.h
  local i = math.max(0, math.min(2, idx))
  local h = { gba50 = true, dx = axis == "x" and sign or 0, dy = axis == "y" and sign or 0,
              v = tab[i + 1], zv = tab[i + 4], timer = tab[i + 7], grav = (h50 and h50.grav) or 2,
              ax = 0, ay = 0, az = 0, zf = 0, t = 0, into = into }
  return h
end

local function startHop(game, axis, sign, idx, into)
  local lk = game.link
  lk.wHop54 = M.newHop(game, axis, sign, idx, into)
  lk.waterHop = { into = into, indoor = true }   -- Swim.lua's pose 5
  lk.swimGame = nil
  lk.z = 0
  lk.steps = 0
  if into then game.waterHops = (game.waterHops or 0) + 1 end
  game.waterHops54 = (game.waterHops54 or 0) + 1
end

local function enterSwim(game)
  local lk = game.link
  SW().enter(game)
  lk.swimGame = nil          -- indoors: not through Link:update
  lk.swimInside = true
  lk.inDeep = true
  lk.swimMove = M.move
  game.swims54 = (game.swims54 or 0) + 1
end
M.enterSwim = enterSwim

local function leaveSwim(game)
  local lk = game.link
  SW().leave(game)
  lk.swimInside, lk.swimMove = nil, nil
end

-- AncillaAdd_Splash's level rule (0x080AD22C..0x080AD24A)
local function splash(game)
  if not game.link.inDeep then game.interior.lower = false end
end

-- Dungeon_HandleLayerChange (Game.lua's ledge landing rule)
local function layerChange(game)
  local inside = game.interior
  if inside.stairKind ~= 2 then inside.lower = true end
end

-- the walk's water checks after the move (StartMovementCollisionChecks_Y /
-- _X): x0, y0 = link_x / y_coord_safe_return (the frame's start)
function M.walkCheck(game, x0, y0, ripple)
  local lk, inside = game.link, game.interior
  if lk.inDeep or lk.wHop54 then return false end
  local ts = M.ts(game, inside)
  local function hopIn(axis, sign)
    require("src.zelda.alttp.Dash").cancel(game)
    if ts == 0 then layerChange(game) else lk.inDeep = true end
    game.swing = nil
    startHop(game, axis, sign, ts, true)
    return true
  end
  local function partial(axis, sign)
    -- zelda3 4420 / 5059: the middle (Y) / third (X) probe on deep water
    require("src.zelda.alttp.Dash").cancel(game)
    game.swing = nil
    if ripple and flippers(game) and not bunny(game) then enterSwim(game) return true end
    lk.x, lk.y = x0, y0
    lk.inDeep = true
    startHop(game, axis, sign, ts, true)
    return true
  end
  local yv, xv = lk.velY or 0, lk.velX or 0
  if yv ~= 0 then
    local up = yv < 0
    local d = bits3(inside, probesY(lk, up), M.DEEP)
    if d == 7 then return hopIn("y", up and -1 or 1) end
    if band(d, 2) ~= 0 then return partial("y", up and -1 or 1) end
  end
  if xv ~= 0 then
    local left = xv < 0
    local d = bits3(inside, probesX(lk, left), M.DEEP)
    if d == 7 then lk.x, lk.y = x0, y0; return hopIn("x", left and -1 or 1) end
    if band(d, 4) ~= 0 then return partial("x", left and -1 or 1) end
  end
  return false
end

-- the swim's move indoors (Player_SomethingWithVelocity_TiredOrSwim, then
-- Link_HandleCardinalCollision on the room's table): S = { y, x } speeds in
-- 1/256 px a frame, j the joypad bits
function M.move(game, lk, S, j)
  local D = require("src.zelda.alttp.Doors")
  local inside = game.interior
  local x0, y0 = lk.x, lk.y
  local function step(c, sub, v)
    local tmp = (sub or 0) + v + c * 256
    return math.floor(tmp / 256), tmp % 256
  end
  if S[2] ~= 0 then lk.x, lk.subX = step(lk.x, lk.subX, S[2]) end
  if S[1] ~= 0 then lk.y, lk.subY = step(lk.y, lk.subY, S[1]) end
  local xv, yv = lk.x - x0, lk.y - y0
  lk.velX, lk.velY = xv, yv
  lk.dirLast = (yv < 0 and 8 or 0) + (yv > 0 and 4 or 0) + (xv < 0 and 2 or 0) + (xv > 0 and 1 or 0)
  lk.doorway = lk.doorway or 0
  local ts = M.ts(game, inside)
  inside.linkProbe54 = true
  if yv ~= 0 then
    -- the water tests read the probes at the moved spot, before the walls
    -- push Link back (StartMovementCollisionChecks_Y's order)
    local up = yv < 0
    local lb = bits3(inside, probesY(lk, up), M.LADDER)
    D._checkY(game, lk, yv, 0, false)
    if band(lb, 2) ~= 0 then
      -- 0x080953F8: out of the water up / down the ladder
      inside.linkProbe54 = nil
      lk.inDeep = false
      leaveSwim(game)
      splash(game)
      game.swimExits = (game.swimExits or 0) + 1
      startHop(game, "y", up and -1 or 1, ts, false)
      return
    end
  end
  if xv ~= 0 then
    local left = xv < 0
    local lb = bits3(inside, probesX(lk, left), M.LADDER)
    D._checkX(game, lk, xv, 0, false)
    if lb == 7 then
      inside.linkProbe54 = nil
      lk.inDeep = false
      leaveSwim(game)
      splash(game)
      game.swimExits = (game.swimExits or 0) + 1
      startHop(game, "x", left and -1 or 1, ts, false)
      return
    end
  end
  inside.linkProbe54 = nil
  lk.tileBelow = inside:attrAt(lk.x + 8, lk.y + 20)
  lk.moving = (lk.swim.v7[1] ~= 0 or lk.swim.v7[2] ~= 0)
end

-- one frame of the water hop (state 6) and its landing
function M.hopFrame(game)
  local lk = game.link
  local h = lk.wHop54
  if not require("src.zelda.alttp.Hop50").frame(lk, h) then return end
  lk.wHop54, lk.waterHop, lk.z = nil, nil, 0
  lk.subX, lk.subY = 0, 0
  M.landing(game)
end

-- Link_HandleRecoilAndTimer's landing indoors
function M.landing(game)
  local lk, inside = game.link, game.interior
  game.waterLandings54 = (game.waterLandings54 or 0) + 1
  local swim = lk.inDeep == true
  if swim and not bunny(game) and flippers(game) then
    inside.lower = true
  end
  if not swim and inside:attrAt(lk.x + 8, lk.y + 20) == M.DEEP then swim = true; lk.inDeep = true end
  if not swim then return end
  if flippers(game) and not bunny(game) then return enterSwim(game) end
  -- CheckAbilityToSwim -> Module07_14 (RecoverPositionAfterDrowning)
  lk.inDeep = false
  local c = game.entryCache
  if c and c.room == inside.room then
    lk.x, lk.y = c.x, c.y
    inside.lower = c.lower
  end
  game.blink = 0x90
  game.drownings = (game.drownings or 0) + 1
end

function M.active(game)
  return game.state == "room" and game.interior ~= nil and T(game) ~= nil
end

function M.install(G)
  if G.swim54Installed then return end
  G.swim54Installed = true
  local I = require("src.zelda.alttp.Interior")
  -- 0x0A, the short water ladder, is a normal tile indoors (0x080A07FC)
  I.WALKABLE[M.LADDER] = true
  -- the stair numbers 0x30-0x37 (handler 0x080A06F8 for 0x22 / 0x30-0x37:
  -- only tiledetect_stair_tile +0x1713, no wall bit): Link walks onto the
  -- number row of a spiral stair behind a key door (Swamp Palace 0x28,
  -- object 0x139: 0x5E row, number row, the door) and the stairs start
  -- (Interior:staircase); the port had them solid
  for v = 0x30, 0x37 do I.WALKABLE[v] = true end
  -- deep water is no wall to Link's own probes (TileDetect sets only
  -- +0x17D0); sprites keep the grid
  local blocked0 = I.blocked
  function I:blocked(x, y)
    if self.linkProbe54 and self:attrAt(x, y) == M.DEEP then return false end
    return blocked0(self, x, y)
  end

  local D = require("src.zelda.alttp.Doors")
  local move0 = D.move
  function D.move(g, inp)
    if not M.active(g) then return move0(g, inp) end
    local lk, inside = g.link, g.interior
    if lk.swimInside and lk.swim then
      inp.stroke = g.swimStroke54
      return SW().swimFrame(g, lk, inp)
    end
    local x0, y0 = lk.x, lk.y
    local a0 = inside:attrAt(x0 + 8, y0 + 20)
    local ripple = (a0 == M.SHALLOW or a0 == M.DEEP)
    inside.linkProbe54 = true
    local ok, err = pcall(move0, g, inp)
    inside.linkProbe54 = nil
    if not ok then error(err, 0) end
    M.walkCheck(g, x0, y0, ripple)
  end

  local led0 = G.indoorLedge
  function G:indoorLedge(inp)
    local lk = self.link
    if lk.swimInside or lk.wHop54 then self.ledgeTimer = nil return end
    return led0(self, inp)
  end

  local esc0 = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    local lk = self.link
    if M.active(self) and (lk.swimInside or lk.wHop54) then
      -- no sword, items or actions in the water (button masks cleared)
      self.swimStroke54 = inp.a or inp.b or inp.y
      inp.a, inp.b, inp.y = false, false, false
      self.swing = nil
    end
    local r = esc0(self, inp)
    if r then return r end
    if lk.wHop54 and M.active(self) then
      M.hopFrame(self)
      return true
    end
    return r
  end

  -- leaving the rooms ends it
  local leave0 = G.leaveRoom
  function G:leaveRoom()
    local lk = self.link
    if lk.swimInside then leaveSwim(self) end
    lk.wHop54, lk.inDeep = nil, nil
    if lk.waterHop and lk.waterHop.indoor then lk.waterHop = nil end
    return leave0(self)
  end
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    local lk = self.link
    lk.swimInside, lk.swimMove, lk.wHop54, lk.inDeep = nil, nil, nil, nil
    if lk.waterHop and lk.waterHop.indoor then lk.waterHop = nil end
    return enter0(self, e)
  end
end

return M
