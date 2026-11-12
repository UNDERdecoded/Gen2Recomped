-- The title screen (src/title.c HandleTitlescreen, USA path; the
-- TITLE_SCREEN_OBJECT pieces from src/object/titleScreenObject.c), drawn
-- through Ppu.lua.
--
--   state 0: LoadGfxGroup(2), palette group 4, mode 1: BG0 (screen 29,
--            priority 2) blended over BG1 (screen 30, priority 3) at 9/9,
--            BG2 the affine 256-colour sword (screen 28, char 2, wrap),
--            a white fade in at speed 8, then LoadGfxGroup(3) (the
--            language's letters, PRESS START).
--   state 1: (HandleTitlescreenAnimationIntro) BG2 on, SFX_EVAPORATE; the
--            sword's scale ratio grows $10 a frame from $10 to $100
--            (BgAffineSet about (120, 72)); a white flash; 40 frames on,
--            the logo objects appear with another flash and SFX_F8;
--            A / START (or 300 frames) moves on.
--   state 2: 60 frames, then state 3 with a 3600-frame timer.
--   state 3: A / START: SFX_TEXTBOX_SELECT and the file select.
-- Every frame: UpdateLightRays (palette group 5 + n every 8 frames, the
-- alpha from sLightRaysAlphaBlends every 32); in states 2-3 the PRESS
-- START icon (DrawDirect(511, 1) at (120, 152), _8 $E020) and, while
-- timer & $20 is clear, DrawDirect($1FF, 0) at y $84.

local bit = require("bit")
local band, bor, lshift = bit.band, bit.bor, bit.lshift
local Ppu = require("src.zelda.tmc.Ppu")

local Title = {}
Title.__index = Title

local SPRITE = 0x1FF
local OBJ_TITLE = 0xBD                 -- TITLE_SCREEN_OBJECT
Title.ALPHA_TABLE = 0x08107C30         -- sLightRaysAlphaBlends (8 x u16)
Title.OBJ_TABLE = 0x08125014           -- gUnk_08125014 {x, y, frame, prio, pad}
local SFX_EVAPORATE, SFX_F8, SFX_TEXTBOX_SELECT = 0xF6, 0xF8, 0x6A

function Title.new(game)
  local self = setmetatable({ game = game, A = game.assets }, Title)
  local p = Ppu.new(self.A)
  self.ppu = p
  self.state, self.sub, self.counter = 0, 0, 0
  self.timer = 30
  self.objs = {}
  self.rays, self.raysAlpha = 0, 0
  self.fade = nil
  self:enter()
  return self
end

function Title:sound(id)
  local au = self.game.audio
  if au and au.playSfx then pcall(au.playSfx, au, id) end
end

-- SetFade(FADE_BLACK_WHITE | FADE_INSTANT, speed): from white to clear
function Title:fadeIn(speed) self.fade = { level = 256, speed = speed, out = false } end

-- BgAffineSet with texture centre ($8000, $8000), screen (120, 72), no
-- rotation: pa = pd = ratio, origin = tex - ratio * scr
function Title:swordAffine()
  local r = self.ratio
  self.ppu.bg[2].affine = { r, 0, 0, r, 0x8000 - r * 120, 0x8000 - r * 72 }
end

function Title:enter()
  local p = self.ppu
  p:loadGfxGroup(2)
  p:loadPaletteGroup(4)
  p.blend = { t1 = 0x01, eva = 9, evb = 9 }       -- BG0 over BG1
  p.bg[0].control = bor(lshift(29, 8), 2)
  p.bg[1].control = bor(lshift(30, 8), 3)
  p.bg[2].control = bor(lshift(28, 8), 1, lshift(2, 2), 0x80, 0x2000, 0x4000)
  for n = 0, 2 do p.bg[n].updated = false end
  p.dispcnt = bor(1, 0x100, 0x200, 0x1000)         -- mode 1, BG0 BG1 OBJ
  self.ratio = 0x10
  self:swordAffine()
  p:loadGfxGroup(3)
  self:fadeIn(8)
  local au = self.game.audio
  if au then pcall(au.playBgm, au, 0x03) end
end

local function readTable(self)
  if self.tbl ~= nil then return self.tbl end
  self.tbl = Ppu.table({ A = self.A }, "titleObjs") or false
  return self.tbl
end

-- the TITLE_SCREEN_OBJECT pieces: their fixed gfx blocks into OBJ VRAM
-- (from tile $100), their object palettes into OBJ banks 4-6
function Title:createObjects()
  local A, p = self.A, self.ppu
  local def = A.manifest.objectDefs and A.manifest.objectDefs[OBJ_TITLE]
  local t = readTable(self)
  local tile, banks = 0x100, {}
  local nextBank = 4
  A.objPalRaw = A.objPalRaw or A.store:read("objpal.bin") or ""
  -- type 0 creates 1, 2 (USA: language 1) and 4
  for _, ty in ipairs({ 0, 1, 2, 4 }) do
    local form = def and def.forms and def.forms[ty]
    if form and t then
      local gfx = A:fixedGfx(form.gfx)
      local base = tile
      if gfx then
        p:write(0x06010000 + tile * 32, gfx)
        tile = tile + math.ceil(#gfx / 32)
      end
      local bank = banks[form.palette]
      if not bank then
        bank = nextBank; nextBank = nextBank + 1
        banks[form.palette] = bank
        local e = A.manifest.objPalettes and A.manifest.objPalettes[form.palette]
        if e then p:write(0x05000200 + bank * 32, A.objPalRaw, e[1], 32) end
      end
      local a = Title.OBJ_TABLE + 8 * ty
      self.objs[#self.objs + 1] = {
        type = ty, x = t.u16(a), y = t.u16(a + 2), frame = t.u16(a + 4), base = base, bank = bank,
        timer = 8, sub = 0, first = t.u16(a + 4), speed = 0x1E + 16 * math.random(0, 3), action = 1,
      }
    end
  end
end

-- TitleScreenObject_Type4: the sparkle -- wait `speed` frames, then four
-- 8-frame steps through frames first..first+3
local function sparkle(o)
  if o.action == 1 then
    o.speed = o.speed - 1
    if o.speed > 0 then return end
    o.speed = 0x1E + 16 * math.random(0, 7)
    o.action = 2
  else
    o.timer = o.timer - 1
    if o.timer > 0 then return end
    o.timer = 8
    o.sub = (o.sub + 1) % 4
    o.frame = o.first + o.sub
    if o.sub == 0 then o.action = 1 end
  end
end

function Title:updateFade()
  local f = self.fade
  if not f then return false end
  f.level = f.level - f.speed
  if f.level <= 0 then self.fade = nil end
  return true
end

-- returns "files" when the player moves on
function Title:update(input)
  self.counter = self.counter + 1
  local fading = self.fade ~= nil
  self:updateFade()
  local pressed = input.pressed("a") or input.pressed("start")
  local function advance()
    if fading then return nil end
    self.timer = self.timer - 1
    if self.timer == 0 then return "timer" end
    if pressed then return "key" end
    return nil
  end
  if self.state == 0 then
    self.state, self.sub = 1, 0
  elseif self.state == 1 then
    if self.sub == 0 then
      if not fading then
        self.sub = 1
        self.ppu.dispcnt = bor(self.ppu.dispcnt, 0x400)
        self:sound(SFX_EVAPORATE)
      end
    elseif self.sub == 1 then
      self.ratio = self.ratio + 0x10
      if self.ratio > 0x100 then
        self.ratio = 0x100
        self.timer = 40
        self.sub = 2
        self:fadeIn(16)
      end
      self:swordAffine()
    elseif self.sub == 2 then
      self.timer = self.timer - 1
      if self.timer == 0 then
        self.timer = 300
        self.sub = 3
        self:createObjects()
        self:fadeIn(16)
        self:sound(SFX_F8)
      end
    else
      if not fading and advance() then self.state = 2; self.timer = 60 end
    end
  elseif self.state == 2 then
    self.timer = self.timer - 1
    if self.timer == 0 then self.timer = 3600; self.state = 3 end
  else
    local a = advance()
    if a == "key" then
      self:sound(SFX_TEXTBOX_SELECT)
      return "files"
    elseif a == "timer" then
      self.timer = 3600 -- the attract demo is not ported: stay on the title
    end
  end
  -- UpdateLightRays
  local p = self.ppu
  if band(self.counter, 7) == 0 then
    self.rays = band(self.rays + 1, 3)
    p:loadPaletteGroup(5 + self.rays)
  end
  if band(self.counter, 0x1F) == 0 then
    self.raysAlpha = band(self.raysAlpha + 1, 7)
    local t = Ppu.table({ A = self.A }, "titleAlpha")
    if t then
      local v = t.u16(Title.ALPHA_TABLE + 2 * self.raysAlpha)
      p.blend = { t1 = 0x01, eva = band(v, 0x1F), evb = band(bit.rshift(v, 8), 0x1F) }
    end
  end
  for _, o in ipairs(self.objs) do if o.type == 4 then sparkle(o) end end
  return nil
end

function Title:draw()
  local p = self.ppu
  p:flush()
  if self.state >= 2 then
    p:drawDirect(SPRITE, 1, { x = 120, y = 152, _4 = 0, _6 = 0, _8 = 0xE020 })
    if self.state == 3 and band(self.timer, 0x20) == 0 then
      p:drawDirect(SPRITE, 0, { x = 120, y = 0x84, _4 = 0, _6 = 0, _8 = 0xE000 })
    end
  end
  -- entities: spriteRendering.b3 = 1 (OAM priority 1)
  for _, o in ipairs(self.objs) do
    p:drawDirect(SPRITE, o.frame, { x = o.x, y = o.y, _4 = 0, _6 = 0, _8 = bor(lshift(o.bank, 12), 0x400, o.base) })
  end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  g.draw(p:render(), 0, 0)
  if self.fade then
    g.setColor(1, 1, 1, math.min(1, self.fade.level / 256))
    g.rectangle("fill", 0, 0, 240, 160)
    g.setColor(1, 1, 1, 1)
  end
end

return Title
