-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE INDOOR LEDGE HOP (round 50). The port's indoor hop (round 11) flew Link
-- to "the first spot 8-64 px on where he fits", which in the Palace of
-- Darkness's arena (room 0x2A) is the pit 24 px past the ledge; the floor
-- arrows there point across the pits.
--
-- Traced on the GBA:
--   * The landing search r48 / r49 read (0x08093128 horizontal, 0x080932C8
--     vertical, 0x08093604, 0x0809A338 north) is the OUTDOOR hop only: the
--     X collision 0x080962E0 calls 0x08095AD4 (-> 0x08095D88) only when
--     +0x9B2 (player_is_indoors) is 0, the Y collision 0x08094DC0 calls
--     0x08094538 (-> 0x080948A0) likewise. Indoors the plain floor (0x00)
--     sets no TileDetect flag (0x0816832C[0] = 0x080A0678, `bx lr`), so
--     those searches could never end there.
--   * Indoors: X 0x0809675A ([+0x1800] & 7 == 7: all three probes on
--     0x2A / 0x2B) and Y 0x080952EE ([+0x17FF] & 7 == 7: on 0x28), then
--     RunLedgeHopTimer 0x0809A5BC, +0xB22 += 1, +0x1702 = 2, sound 4, and
--     0x0809A670 (horizontal) / 0x0809A24C (vertical): a FIXED hop, no
--     search. Index i = +0x9B5, but 0 while +0xB22 != 0 (it was just
--     raised): x / y speed = tab[i] (0x08167F99 / 0x08167ED0, 1/16 px a
--     frame, negative left / up), z speed = tab[3 + i] (stored at +0x16CF
--     and +0x174C), the incapacitated timer +0x16F8 = tab[6 + i], state 6.
--   * State 6 (0x08099C90, the recoil state) a frame: gravity 0x0809E624 /
--     0x0809A138 (z speed -= 2, the `movs r2, #2` at 0x0809E626; not while
--     falling with z = 0); the timer counts down and, once out, Link lands
--     when (z & 0xFE) - 1 > 0x7E with the z speed negative (0x08099DD4); the
--     move 0x080978AC (speed >> 4 plus the carry of (speed & 15) << 4 into
--     the sub-pixel byte); a z of 0 or below clamps to 0 (0x0809A08E).
--     On landing 0x0808B1A8 (Dungeon_HandleLayerChange, kept in Game.lua).
-- So both indoor hops fly about 52 px. OURS: the sub-pixel bytes start at 0;
-- the recoil state's wall bounce (0x0809A7C4) is not ported for hops.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.OFF = {
  hLit = 0x0809A6AC,    -- ldr r0, =tab (horizontal hop speeds)
  vLit = 0x0809A288,    -- ldr r0, =tab (vertical hop speeds)
  grav = 0x0809E626,    -- movs r2, #gravity
}

-- the pc-relative literal of the thumb `ldr rX, [pc, #imm]` at `code`
local function lit(rom, code)
  local h = rom:u16(code - 0x08000000)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  local la = band(code + 4, 0xFFFFFFFC) + band(h, 0xFF) * 4
  return rom:u32(la - 0x08000000)
end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = {}
  local h, v = lit(rom, O.hLit), lit(rom, O.vLit)
  local g = rom:u16(O.grav - 0x08000000)
  t.grav = (rshift(g, 11) == 4) and band(g, 0xFF) or nil
  if h and v then
    h, v = h - 0x08000000, v - 0x08000000
    t.h = { v = rom:u8(h), z = rom:u8(h + 3), timer = rom:u8(h + 6) }
    t.v = { v = rom:u8(v), z = rom:u8(v + 3), timer = rom:u8(v + 6) }
  end
  check(t.grav ~= nil and t.h ~= nil and t.h.v > 0 and t.h.v < 0x80 and t.h.z > 0 and t.h.z < 0x80
        and t.v.v > 0 and t.v.v < 0x80 and t.v.z > 0 and t.v.z < 0x80 and t.h.timer > 0,
        "indoor ledge hop tables (gravity %s)", tostring(t.grav))
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.hop50 end
M.tab = tab

-- the hop record for Link going (dx, dy); nil when the tables are missing
function M.newHop(game, dir, dx, dy)
  local t = tab(game)
  if not t then return nil end
  local s = (dx ~= 0) and t.h or t.v
  return { gba50 = true, dir = dir, dx = dx, dy = dy, v = s.v, zv = s.z, grav = t.grav,
           timer = s.timer, ax = 0, ay = 0, az = 0, zf = 0, t = 0 }
end

-- 0x080978AC on one axis: whole pixels moved for speed `vel` (1/16 px),
-- the sub-pixel byte carried
local function step(vel, acc)
  local vb = band(vel, 0xFF)
  local frac = band(vb, 0xF) * 16
  local ip = rshift(vb, 4)
  if ip > 7 then ip = ip - 16 end
  acc = acc + frac
  local carry = 0
  if acc >= 0x100 then carry, acc = 1, acc - 0x100 end
  return ip + carry, acc
end

-- one frame of state 6; true when Link has landed
function M.frame(lk, h)
  h.t = h.t + 1
  -- gravity (0x0809A138): not while falling at z = 0
  if h.zv >= 0 or h.zf > 0 then h.zv = h.zv - h.grav end
  h.timer = h.timer - 1
  if h.timer <= 0 then
    h.timer = 1
    local zb = band(h.zf, 0xFF)
    if band(band(zb, 0xFE) - 1, 0xFF) > 0x7E and h.zv < 0 then
      h.zf, lk.z = 0, 0   -- the landing clears z (0x08099F90)
      return true
    end
  end
  local d
  if h.dx ~= 0 then
    d, h.ax = step(h.dx * h.v, h.ax); lk.x = lk.x + d
  else
    d, h.ay = step(h.dy * h.v, h.ay); lk.y = lk.y + d
  end
  d, h.az = step(h.zv, h.az); h.zf = h.zf + d
  if h.zf <= 0 then h.zf = 0 end
  lk.z = h.zf
  return false
end

function M.install(G)
  if G.hop50Installed then return end
  G.hop50Installed = true
  local Link = require("src.zelda.alttp.Link")
  local upd0 = Link.updateHop
  function Link:updateHop(...)
    local h = self.hop
    if not (h and h.gba50) then return upd0(self, ...) end
    if M.frame(self, h) then
      self.hop, self.z = nil, 0
      self.subX, self.subY = 0, 0
    end
  end
  -- the trigger as before (round 11: all three probe points on the ledge,
  -- 0x28 for up / down, 0x2A / 0x2B for left / right, for 20 frames); the
  -- flight from the cartridge's tables, whatever lies past the ledge
  local led0 = G.indoorLedge
  function G:indoorLedge(inp)
    if not tab(self) then return led0(self, inp) end
    local inside, lk = self.interior, self.link
    local dx = (inp.right and 1 or 0) - (inp.left and 1 or 0)
    local dy = (inp.down and 1 or 0) - (inp.up and 1 or 0)
    local dir, want
    if dy ~= 0 and dx == 0 then dir, want = (dy < 0) and Link.UP or Link.DOWN, { [0x28] = true }
    elseif dx ~= 0 and dy == 0 then dir, want = (dx < 0) and Link.LEFT or Link.RIGHT, { [0x2A] = true, [0x2B] = true }
    end
    if not dir then self.ledgeTimer = nil return end
    for _, p in ipairs(Link.PROBES[dir]) do
      if not want[inside:attrAt(lk.x + dx + p[1], lk.y + dy + p[2]) or -1] then self.ledgeTimer = nil return end
    end
    self.ledgeTimer = (self.ledgeTimer or 0) + 1
    if self.ledgeTimer < 20 then return end
    self.ledgeTimer = nil
    lk.hop = M.newHop(self, dir, dx, dy)
    lk.steps = 0
    self.ledgeHop = true
    self.hops50 = (self.hops50 or 0) + 1
  end
end

return M
