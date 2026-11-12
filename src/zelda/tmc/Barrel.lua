-- Round 6: Deepwood Shrine's rolling barrel (src/manager/rollingBarrelManager.c,
-- ROLLING_BARREL_MANAGER $0C in the barrel's inside, room $48/$20).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * OnEnterRoom: palette group $28 (bank 3 copied to 21), gfx group $16
--     (+ $4A once LV1TARU_OPEN, the web sucked away), mode 1, BG2 control
--     $BC82 (256 colours, 512 px, wrap, map at $0600E000).
--   * sub_08058BC8: BG2 is redrawn every frame with a per-scanline affine
--     (an HBlank DMA of BgAffineSet output): line L samples texture row
--     unk_20 + L, scaled by sx = $100 + 3/4 sin(L*128/160), sy = $100 -
--     sin(2 idx) / 16 about (120, 128): the inside of a turning cylinder.
--   * sub_08058CB0: the start angle from the quadrant Link came in by
--     (gUnk_08108300).
--   * sub_08058CFC: Link slides back to the barrel's bottom row (screen y
--     $4C..$54) at $C0.
--   * sub_080588F8: once both webs outside burnt (local flags $15, $16),
--     standing off the middle row turns the barrel, faster the further
--     off ((|y - $50| >> 3) * $3000 + $4000 a frame, 16.16), SFX_BARREL_ROLL
--     each 16 px; passing $48 / $A0 / $F0 it locks there 45 frames
--     (SFX_BARREL_ROLL_STOP, a 2 px judder for the first 3).
--   * sub_08058A04 / sub_08058B08 / sub_08058B5C: at the four doorways,
--     when the angle is within a door's range and Link stands in that
--     angle's box (gUnk_08108228..081082B8), he steps out to room 6 at
--     gUnk_081082E8's spot, facing up or down, and gSave.dws_barrel_state
--     takes that door's value (SFX_STAIRS).
-- All tables are read from the player's ROM (Layout.MENU_DATA barrelTables).
-- Not ported: the fall through the open bottom (LV1TARU_OPEN, angle
-- $118..$124) and the BLDCNT $3456 blend.

local bit = require("bit")
local band = bit.band

local Assets = require("src.zelda.tmc.Assets")
local Barrel = {}
Barrel.__index = Barrel

local T_BOXES, T_EXITS, T_START = 0x08108228, 0x081082E8, 0x08108300
local EXIT_RANGES = { { 0x88, 0xB0 }, { 0x38, 0x60 }, { 0xE0, 0x108 }, { 0x90, 0xB8 } }
local LV1TARU_OPEN = 0x17
Barrel.MANAGER = 0x0C

-- gSineTable (256 steps a turn, $100 = 1)
local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end

local function reader(A)
  local e = A.manifest.menuData and A.manifest.menuData.barrelTables
  if not e then return nil end
  A.menuBlob = A.menuBlob or A.store:read("menudata.bin") or ""
  local blob, base, off = A.menuBlob, e[1], e[2]
  local t = {}
  function t.u8(a) return blob:byte(off + (a - base) + 1) or 0 end
  function t.u16(a) return t.u8(a) + 256 * t.u8(a + 1) end
  return t
end

function Barrel.new(field)
  local self = setmetatable({ field = field, A = field.assets }, Barrel)
  self.t = reader(self.A)
  self.action = 1
  self.unk28, self.subtimer = 0x1234, 0
  self.rolls = field:flag("local", 0x15) and field:flag("local", 0x16)
  -- sub_08058CB0
  local p = field.player
  local q = p.x < 0x78 and (p.y < 0x50 and 0 or 1) or (p.y < 0x50 and 2 or 3)
  local start = self.t and self.t.u16(T_START + 2 * q) or 0xA4
  self.unk20, self.unk24 = start, start * 65536
  self.unk2c = self.unk24
  return self
end

-- the in-room part of the manager, once a frame
function Barrel:update()
  local f = self.field
  local p = f.player
  if self.action ~= 1 or f.transition then return end
  -- sub_08058CFC
  local sy = p.y - f.camY
  if p.state == "normal" or p.state == "gust" then
    if sy < 0x4C then p:moveBy(0, 0.75) end
    if sy > 0x54 then p:moveBy(0, -0.75) end
  end
  self:web()
  if self:fall() then return end
  if self:exits() then return end
  self:roll()
end

-- round 13: BARREL_SPIDERWEB ($36, barrelSpiderweb.c) on the barrel's
-- inside: at x $78, y $170 - the barrel's angle; on screen it is the
-- gust's target (contactFlags $93).  120 frames of suction set
-- LV1TARU_OPEN (gfx group $4A shows the hole while it is sucked, $49 the
-- web again when the suction stops); then it is pulled to Link at $300
-- and gone within $1C of him (SFX_SECRET), or blinks 30 frames and goes
-- when the suction stops.  Its affine size per screen band is
-- gUnk_0812144C / gUnk_08121474 (sub_0808BBE0).
local WEB_SCALE = { 192, 256, 208, 240, 224, 224, 240, 208, 256, 192, 256, 192, 240, 208, 224, 224, 208, 240, 192, 256 }
local WEB_OFFY = { 248, 250, 252, 254, 0, 0, 2, 4, 6, 8, 0, 0 }
function Barrel:web()
  local f = self.field
  if f:flag("global", LV1TARU_OPEN) and not (self.w and self.w.action == 2) then self.w = nil return end
  local w = self.w
  if not w then
    if f:flag("global", LV1TARU_OPEN) then return end
    w = { action = 1, timer = 120, subtimer = 0, x = 0x78 }
    self.w = w
  end
  local GJ = require("src.zelda.tmc.GustJar")
  if w.action == 1 then
    w.x, w.y = 0x78, 0x170 - self.unk20
    local sy = w.y - f.camY
    local on = sy >= 0 and sy < 0xA0 and GJ.touching(f, w.x, w.y, 8, 8)
    if on then
      w.timer = w.timer - 1
      w.draw = true
      if w.timer == 0 then
        f:setFlag("global", LV1TARU_OPEN, true)
        w.action, w.subtimer = 2, 128
      else
        if w.timer % 2 == 1 then w.x, w.y = w.x + love.math.random(0, 3) - 2, w.y + love.math.random(0, 3) - 1 end
        if w.subtimer ~= 1 then w.subtimer = 1; self:webGfx(0x4A) end
      end
    else
      w.timer, w.draw = 120, false
      if w.subtimer ~= 0 then w.subtimer = 0; self:webGfx(0x49) end
    end
  else
    if w.subtimer > 0 then w.subtimer = w.subtimer - 8 end
    w.scale = 256 / (0x200 - w.subtimer) -- SetAffineInfo: $100 = 1x, $200 = half
    local p = f.player
    if GJ.touching(f, w.x, w.y, 8, 8) and not w.blink then
      local dx, dy = p.x - w.x, (p.y - 6) - w.y
      local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      w.x, w.y = w.x + dx / d * 3, w.y + dy / d * 3
      if d < 0x1C then f:sound(0x72); self.w = nil; self:webGfx(0x4A) end -- SFX_SECRET
    else
      w.blink = w.blink or 30
      w.draw = w.blink % 2 == 0
      w.blink = w.blink - 1
      if w.blink <= 0 then f:sound(0x72); self.w = nil; self:webGfx(0x4A) end
    end
  end
end

function Barrel:webGfx(g)
  self.wantGfx = g
  self.p = nil
end

-- sub_08058A04's first test: the open bottom (angle $118..$124, the web
-- gone, Link on the middle 23 x 23 px, on the floor) is a pit: PLAYER_FALL
-- from (x $78, y $50); the room's HOLE_MANAGER (gHoleTransitions[0]:
-- room $14 of B1 at ($E8, $C8), layer 2) takes him down (Holes.lua)
function Barrel:fall()
  local f = self.field
  local p = f.player
  if p.falling or p.state ~= "normal" and p.state ~= "gust" then return p.falling end
  local a = self.unk20
  if a - 0x118 >= 0 and a - 0x118 < 0xD and f:flag("global", LV1TARU_OPEN)
     and p.x - 0x6D >= 0 and p.x - 0x6D < 0x17 and p.y - 0x45 >= 0 and p.y - 0x45 < 0x17 and (p.z or 0) == 0 then
    p.x, p.y = 0x78, 0x50
    local d = f:dungeon()
    require("src.zelda.tmc.PlayerFall").start(d, p, require("src.zelda.tmc.Holes").exitFor(d, p))
    return true
  end
  return false
end

-- sub_08058A04 + sub_08058B08 + sub_08058B5C
function Barrel:exits()
  local t = self.t
  if not t then return false end
  local p = self.field.player
  local x, y = p.x, p.y
  local q = x < 0x78 and (y < 0x50 and 0 or 1) or (y < 0x50 and 2 or 3)
  local r = EXIT_RANGES[q + 1]
  local a = self.unk20
  if a < r[1] or a > r[2] then return false end
  local box = T_BOXES + q * 0x30 + 8 * math.floor((a - r[1]) / 8) -- struct_08108228: 4 x u16
  local dx, dy = x - t.u16(box), y - t.u16(box + 2)
  if not (dx >= 0 and dx < t.u16(box + 4) and dy >= 0 and dy < t.u16(box + 6)) then return false end
  local ex = T_EXITS + q * 6
  local f = self.field
  f.save.dwsBarrelState = t.u16(ex + 4)
  f:sound(0x121) -- SFX_STAIRS
  self.action = 2
  f:enterRoom(f.room.area, 6, t.u16(ex), t.u16(ex + 2), (q % 2 == 1) and 4 or 0)
  return true
end

-- sub_080588F8
function Barrel:roll()
  local f = self.field
  local hi = math.floor(self.unk24 / 65536)
  if self.subtimer == 0 then
    if math.abs(self.unk28 - hi) > 8 then
      self.unk28 = 0x1234
      local h = band(hi, 0xFFFE)
      if h == 0x48 or h == 0xA0 or h == 0xF0 then
        self.unk28 = hi
        self.subtimer = 45
        f:sound(0x8C) -- SFX_BARREL_ROLL_STOP
      end
    end
  else
    self.subtimer = self.subtimer - 1
    local frac = self.unk24 % 65536
    if self.subtimer > 0x29 then self.unk24 = (self.unk28 - 2) * 65536 + frac
    else self.unk24 = self.unk28 * 65536 + frac end
  end
  if self.rolls and self.subtimer == 0 then
    local y = f.player.y
    local step = math.floor(math.abs(y - 0x50) / 8) * 0x3000 + 0x4000
    if y < 0x49 then self.unk24 = self.unk24 - step
    elseif y > 0x57 then self.unk24 = self.unk24 + step end
    if math.abs(self.unk2c - self.unk24) > 0x100000 then
      self.unk2c = self.unk24
      f:sound(0x8B) -- SFX_BARREL_ROLL
    end
  end
  hi = math.floor(self.unk24 / 65536)
  if hi < 0 then hi = 0x1FF; self.unk24 = 0x1FF * 65536
  elseif hi > 0x1FF then hi = 0; self.unk24 = 0 end
  self.unk20 = hi
end

-- RollingBarrelManager_OnEnterRoom (the picture part) on a Ppu
function Barrel:ppu()
  if self.p then return self.p end
  local Ppu = require("src.zelda.tmc.Ppu")
  local p = Ppu.new(self.A)
  p:loadPaletteGroup(0x28)
  for i = 0, 15 do p:setColor(21 * 16 + i, p.pal[3 * 16 + i]) end
  p:loadGfxGroup(0x16)
  if self.field:flag("global", LV1TARU_OPEN) then p:loadGfxGroup(0x4A) end
  if self.wantGfx then p:loadGfxGroup(self.wantGfx) end -- round 13: the web sucked / let go
  p.dispcnt = 0x0401 -- mode 1, BG2
  p.bg[2].control = 0xBC82
  p.transparent = true
  self.p = p
  return p
end

-- sub_08058BC8: one BgAffineSet a scanline
function Barrel:lines()
  local out = {}
  for l = 0, 159 do
    local idx = band(math.floor(l * 128 / 160), 0xFF)
    local sx = 0x100 + math.floor(SIN[idx] * 3 / 4)
    local sy = 0x100 - math.floor(SIN[band(idx * 2, 0xFF)] * 2 / 32)
    local texY = (self.unk20 + l) * 256
    -- alpha 0: pa = sx, pb = 0, pc = 0, pd = sy; the reference point
    out[l] = { sx, 0, 0, sy, 0x10000 - 0x78 * sx, texY - 0x80 * sy }
  end
  return out
end

function Barrel:draw()
  local ok, p = pcall(self.ppu, self)
  if not ok or not p then return end
  if self.drawnAt ~= self.unk20 then
    p.bg[2].affineLines = self:lines()
    p.dirty = true
    self.drawnAt = self.unk20
  end
  local img = p:render()
  if img then love.graphics.draw(img, 0, 0) end
  -- round 13: the web being sucked (frame 2 of its sprite, affine size by
  -- its screen band)
  local w = self.w
  if w and w.draw then
    local f = self.field
    local d = f:objects():def(0x36, 0)
    if d then
      local img2, ox, oy = self.A:spriteFrame(d.sprite, 2, self.A:objPalette(d.palette or 0), "barrelweb", Assets.gfxSource(d.gfxType, d.gfx))
      if img2 then
        local sy = w.y - f.camY
        local band16 = math.max(0, math.min(9, math.floor(sy / 16)))
        local sx2 = w.scale or 256 / WEB_SCALE[band16 * 2 + 1]
        local sy2 = w.scale or 256 / WEB_SCALE[band16 * 2 + 2]
        local offy = WEB_OFFY[band16 + 1]; if offy > 127 then offy = offy - 256 end
        local wdt, hgt = img2:getWidth(), img2:getHeight()
        love.graphics.draw(img2, math.floor(w.x - f.camX) + ox + wdt / 2, math.floor(sy + offy) + oy + hgt / 2, 0, sx2, sy2, wdt / 2, hgt / 2)
      end
    end
  end
end

-- BIG_BARREL ($25) outside, in room 6 (bigBarrel.c): Type0 shows the
-- frame gSave.dws_barrel_state (+1 once LV1TARU_OPEN); sub_08088BE0 adds
-- the two end rims (Type1, frames 4 / 5, 8 px further out once that side's
-- web is gone) and, while local flags $15 / $16 are clear, the two webs
-- (Type2, frames 6 / 10).  The webs' burning (Type3 / Type4, the Lantern)
-- is not ported.
function Barrel.spawnBig(dungeon, e)
  local f = dungeon.field
  local O = f:objects()
  if e.form ~= 0 then return nil end
  local d = O:def(0x25, 0)
  if not d then return nil end
  O:dress(e, d, 0)
  e.staticFrame = (f.save.dwsBarrelState or 0) + (f:flag("global", LV1TARU_OPEN) and 1 or 0)
  e.bigBarrel = true
  local function child(form, type2, dx, frame)
    local cd = O:def(0x25, form)
    if not cd then return end
    local c = { kind = 6, id = 0x25, form = form, type2 = type2, x = e.x + dx, y = e.y, z = 0, animationState = 0,
                field80 = 0, field82 = 0, interactType = 0, dungeon = true, layer = e.layer }
    O:dress(c, cd, 0)
    c.staticFrame = frame
    f.entities[#f.entities + 1] = c
  end
  e.kids = {}
  local function kid(form, side, dx, frame)
    child(form, side, dx, frame)
    local c = f.entities[#f.entities]
    e.kids[#e.kids + 1] = c
    c.side = side
    return c
  end
  for side = 0, 1 do
    local flagSet = f:flag("local", 0x15 + side)
    local dx = side == 0 and -120 or 120
    if not flagSet then kid(2, side, dx, side * 4 + 6) end
    kid(1, side, dx + (flagSet and (side == 0 and 8 or -8) or 0), side + 4)
  end
  -- round 11: bigBarrel.c Type4 / Type2 / Type1 while Link is in the room:
  -- when a side's flag ($15 west, $16 east: its button) gets set, Type4
  -- lays TILE_TYPE_118 on the top layer at (origin + $48 / $188, 200), the
  -- fuse burns to the web (30 frames, then the web's three frames 30
  -- frames apart), and 90 frames after the flame reaches it the log slides
  -- 8 px into the barrel (4 steps of 2 px, 8 frames apart).  SIMPLIFIED:
  -- the FLAME objects themselves are not drawn; the timings are kept.
  e.sides = { [0] = { set = f:flag("local", 0x15) }, [1] = { set = f:flag("local", 0x16) } }
  e.extUpdate = function(d, b)
    for side = 0, 1 do
      local s = b.sides[side]
      if not s.set and f:flag("local", 0x15 + side) then
        s.set = true
        s.t = 0
        local tx = math.floor((side == 0 and 0x48 or 0x188) / 16)
        f:objects():setTileType(2, tx, math.floor(200 / 16), 118)
      end
      if s.t then
        s.t = s.t + 1
        for _, c in ipairs(b.kids) do
          if c.side == side and c.form == 2 and not c.deleted and s.t >= 30 then
            local step = math.floor((s.t - 30) / 30)
            if step >= 3 then c.deleted = true else c.staticFrame = side * 4 + 6 + step end
          end
          if c.side == side and c.form == 1 and s.t >= 150 and s.t < 182 and (s.t - 150) % 8 == 0 then
            c.x = c.x + (side == 0 and 2 or -2)
          end
        end
        if s.t >= 182 then s.t = nil end
      end
    end
  end
  dungeon:track(e)
  return e
end

return Barrel
