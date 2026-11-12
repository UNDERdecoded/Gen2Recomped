-- Round 28: the credits roll (src/staffroll.c StaffrollTask) through Ppu.lua.
--
-- State0: saw_staffroll, GAMECLEAR, the English entry list gUnk_08127644
--   (StaffrollEntry, 12 bytes: menuType, font, -, transitionTimer, gfxEntry,
--   bg2XOffset, unk_14 -- read from the ROM, Ending.ROM_RANGES.staffEN),
--   menuType 0 with 180 frames, palette groups $B / $C, colour 0 black,
--   DISPCNT $640, BLDCNT $2442 (BG1 over BG2 + backdrop), BLDALPHA $1000,
--   BG1 $1E4D, BG2 $1DC3 (256 colours), the sound off, faded out at once.
-- State1, by the entry's menuType (sub_080A3954 reads the next entry):
--   0 wait the timer; 1 (fade done) the picture gUnk_08127CEC[gfxEntry]
--   (palette group, gfx group), BG1 cleared, BG2 x offset, BLDALPHA $1000,
--   BGM_CREDITS the first time, fade in (speed 8), then menuType 0;
--   2 ShowTextBox(gfxEntry, gStaffrollFonts[font]) into BG1, its alpha up
--   by 1 every 2 frames to 16, the timer, down again, the next entry once
--   the fade is done; 3 the timer, the next entry, fade out (8); 4 fade out
--   (4) to progress `timer` with BG palette 15 kept (mask $FFFF7FFF);
--   5 fade in (4) from `timer`; 6 (fade done) BG1 / BG2 cleared, fade in;
--   7 (fade done) fade out to white, State2.
-- State2: the popup (the same setup as the game-over popup: GameOver.lua's
--   Ppu), SetPopupState(0, choice) -- message $10 Save / Don't Save -- after
--   30 frames: up / down choose (SFX_TEXTBOX_CHOICE), A (SFX_TEXTBOX_SELECT):
--   save -> HandleSave (the host's save), then case 4: fade out to white,
--   State3: DoSoftReset (back to the title).
-- Fades: gFadeControl's progress $100 down by `speed` a frame to `sustain`;
--   the palettes in the mask mixed toward black ($F8 = white) by
--   256 - progress (fading out) or progress (fading in).
--
-- SIMPLIFIED: CreateDialogBox(8 / 9) (the "saving" / error box) is not
--   drawn -- the host's save is immediate and cannot fail here; the fade of
--   the popup screens is an overlay instead of the palettes.
local ffi = require("ffi")
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local Ppu = require("src.zelda.tmc.Ppu")

local St = {}
St.__index = St

local BGM_CREDITS = 9
local SFX_TEXTBOX_CHOICE, SFX_TEXTBOX_SELECT = 0x69, 0x6A
local GAMECLEAR = 0x55
local FADE_IN_OUT, FADE_BLACK_WHITE = 1, 2
local BG1BUF = 0x02021F30
St.BGM_CREDITS = BGM_CREDITS

-- gStaffrollFonts (staffroll.c gUnk_08127280..C8): dest = &gBG1Buffer[n],
-- BG_TILE_ADDR($188), gfx_src $F020, width 240, right_align, fill 5,
-- charColor 0, _16 1, stylized 0
St.FONTS = { [0] = { 0x21, false }, { 0x30, false }, { 0x8F, true }, { 0x1CF, true } }
local function font(n)
  local d = St.FONTS[n] or St.FONTS[0]
  return { dest = BG1BUF + 2 * d[1], gfx_dest = 0x0600C400, gfx_src = 0xF020, width = 240, centre = d[2],
           sm_border = false, draw_border = false, border_type = 0, fill = 5, charColor = 0, spacing = 1, stylized = 0 }
end
St.font = font

-- the ROM's entry list (nil before the cache has it; a scene may set R26_DEV_ROM)
local function tables(f, name)
  local ok, X = pcall(require, "src.zelda.tmc.ExtractR26")
  if ok and X.tables then return X.tables(f, name) end
end
function St.readEntry(T, i)
  local a = 0x08127644 + 12 * i
  return { menuType = T.u8(a), font = T.u8(a + 1), timer = T.u16(a + 4), gfxEntry = T.u16(a + 6),
           bg2x = T.u16(a + 8), unk14 = T.u16(a + 10) }
end

function St.new(field, opts)
  local self = setmetatable({ field = field, state = 0, frame = 0, opts = opts or {} }, St)
  self.T = (self.opts.tables or tables)(field, "staffEN")
  self.G = (self.opts.tables or tables)(field, "staffGfx")
  self.fade = { active = false, progress = 0x100, sustain = 0, speed = 0, type = 0, mask = 0xFFFFFFFF }
  self:state0()
  return self
end

-- ---------------------------------------------------------------- fades
function St:setFade(type, speed)
  local d = self.fade
  d.speed, d.type, d.active, d.progress, d.sustain = speed, type, true, 0x100, 0
  d.white = band(type, FADE_BLACK_WHITE) ~= 0
end
function St:setFadeProgress(v)
  local d = self.fade
  if band(d.type, FADE_IN_OUT) ~= 0 then d.sustain = v else d.progress = v end
end
-- FadeMain
function St:fadeStep()
  local d = self.fade
  if not d.active then return end
  d.progress = d.progress - d.speed
  if d.progress <= d.sustain then d.progress = d.sustain end
  d.active = d.progress ~= d.sustain
end
-- how far toward the fade colour (0..256)
function St:fadeLevel()
  local d = self.fade
  if band(d.type, FADE_IN_OUT) ~= 0 then return 256 - d.progress end
  return d.progress
end

-- ---------------------------------------------------------------- ppu
function St:newPpu()
  local f = self.field
  if not (f and f.assets and f.assets.manifest and f.assets.manifest.gfxGroups) then return nil end
  local p = Ppu.new(f.assets)
  self.base = ffi.new("uint16_t[512]")
  return p
end
function St:snap() if self.ppu then ffi.copy(self.base, self.ppu.pal, 1024) end end
-- LoadPaletteGroup onto the unfaded palettes (the fade is applied at draw)
function St:palGroup(g)
  local p = self.ppu
  if not p then return end
  ffi.copy(p.pal, self.base, 1024)
  p:loadPaletteGroup(g)
  self:snap()
  self.fadeKey = nil
end
function St:applyFade()
  local p = self.ppu
  if not p then return end
  local lv = self:fadeLevel()
  local d = self.fade
  local key = lv .. (d.white and "w" or "b") .. d.mask
  if key == self.fadeKey then return end
  self.fadeKey = key
  local tgt = d.white and 31 or 0
  for i = 0, 511 do
    local c = self.base[i]
    if band(rshift(d.mask, rshift(i, 4)), 1) ~= 0 and lv > 0 then
      local r, g, b = band(c, 31), band(rshift(c, 5), 31), band(rshift(c, 10), 31)
      local function mix(v) return v + math.floor((tgt - v) * lv / 256) end
      r, g, b = mix(r), mix(g), mix(b)
      c = bor(band(r, 31), lshift(band(g, 31), 5), lshift(band(b, 31), 10))
    end
    p.pal[i] = c
  end
  p.dirty = true
end

-- ---------------------------------------------------------------- states
function St:state0() -- StaffrollTask_State0
  local f = self.field
  if f.save then f.save.sawStaffroll = true end
  if f.setFlag then f:setFlag("global", GAMECLEAR, true) end
  self.state = 1
  self.menuType, self.timer = 0, 180
  self.ptr = 0
  self.bgmStarted = false
  self.ppu = self:newPpu()
  local p = self.ppu
  if p then
    p.dispcnt = 0x640
    p.bg[0].control, p.bg[1].control, p.bg[2].control, p.bg[3].control = 0, 0x1E4D, 0x1DC3, 0
    p:loadPaletteGroup(0xB); p:loadPaletteGroup(0xC); p:setColor(0, 0)
    self:snap()
  end
  self.alpha = 0x1000
  if f.bgm then f:bgm(nil) end -- InitSoundPlayingInfo
  self:setFade(bor(FADE_IN_OUT, 4), 0x100)
end

function St:next() -- sub_080A3954
  local e = self.T and St.readEntry(self.T, self.ptr) or { menuType = 7, font = 0, timer = 60, gfxEntry = 0, bg2x = 0, unk14 = 0 }
  self.menuType, self.overlay = e.menuType, 0
  self.gfxEntry, self.timer, self.bg2x, self.fontN = e.gfxEntry, e.timer, e.bg2x, e.font
  self.ptr = self.ptr + 1
  self.entries = (self.entries or 0) + 1
end

function St:clearBg(n)
  local p = self.ppu
  if not p then return end
  p:fill(n == 1 and BG1BUF or 0x020344B0, 0x800, 0)
  p.bg[n].updated = true
end

function St:state1()
  local mt, f = self.menuType, self.field
  if mt == 0 then
    self.timer = self.timer - 1
    if self.timer <= 0 then self:next() end
  elseif mt == 1 then
    if not self.fade.active then
      local p = self.ppu
      if p and self.G then
        local a = 0x08127CEC + 2 * self.gfxEntry
        self:palGroup(self.G.u8(a))
        p:loadGfxGroup(self.G.u8(a + 1)) -- (tiles and BG2's map straight into VRAM; BG2's buffer stays as it is)
      end
      self:clearBg(1)
      if p then p.bg[2].x = self.bg2x >= 0x8000 and self.bg2x - 0x10000 or self.bg2x; p.dirty = true end
      self.alpha = 0x1000
      self.menuType = 0
      if not self.bgmStarted then
        self.bgmStarted = true
        if f.bgm then f:bgm(BGM_CREDITS) end
      end
      self:setFade(4, 8)
    end
  elseif mt == 2 then
    local o = self.overlay
    if o == 0 then
      self:clearBg(1)
      if self.ppu then self.ppu:showTextBox(self.gfxEntry, font(self.fontN)); self.ppu.bg[1].updated = true end
      self.overlay, self.u18 = 1, 0
      self.shown = self.gfxEntry
    elseif o == 1 then
      if self.fade.active or self.frame % 2 == 1 then return end
      self.u18 = self.u18 + 1
      self.alpha = bor(lshift(16 - self.u18, 8), self.u18)
      if self.u18 >= 0x10 then self.overlay = 2 end
    elseif o == 2 then
      self.timer = self.timer - 1
      if self.timer <= 0 then self.overlay = 3 end
    elseif o == 3 then
      if self.frame % 2 == 1 then return end
      self.u18 = self.u18 - 1
      self.alpha = bor(lshift(16 - self.u18, 8), self.u18)
      if self.u18 <= 0 then self.overlay = 4 end
    else
      if not self.fade.active then self.fade.mask = 0xFFFFFFFF; self:next() end
    end
  elseif mt == 3 then
    self.timer = self.timer - 1
    if self.timer <= 0 then self:next(); self:setFade(bor(FADE_IN_OUT, 4), 8) end
  elseif mt == 4 then
    local t = self.timer
    self.fade.mask = 0xFFFF7FFF
    self:setFade(bor(FADE_IN_OUT, 4), 4)
    self:setFadeProgress(t)
    self:next()
  elseif mt == 5 then
    local t = self.timer
    self:setFade(4, 4)
    self:setFadeProgress(t)
    self:next()
  elseif mt == 6 then
    if not self.fade.active then
      self:clearBg(1); self:clearBg(2)
      self.alpha = 0x1000
      self.menuType = 0
      self:setFade(4, 8)
    end
  elseif mt == 7 then
    if not self.fade.active then
      self:setFade(bor(FADE_IN_OUT, FADE_BLACK_WHITE, 4), 8)
      self.state, self.overlay = 2, 0
    end
  end
end

function St:state2(input)
  local f = self.field
  local o = self.overlay
  local function pressed(k) return input and input.pressed and input.pressed(k) end
  if o == 0 then
    self.overlay, self.timer, self.choice = 1, 30, 0
    if f and f.assets and f.assets.manifest and f.assets.manifest.gfxGroups then
      self.go = require("src.zelda.tmc.GameOver").new(f)
      self.go.ppu.dispcnt = bor(self.go.ppu.dispcnt, 0x600)
      self.go:popup(0, 0)
    end
    self:setFade(4, 8)
  elseif o == 1 then
    if self.fade.active then return end
    if self.timer > 0 then self.timer = self.timer - 1 return end
    local c = self.choice
    if pressed("up") then c = 0 elseif pressed("down") then c = 1
    elseif pressed("a") then
      self.overlay = c ~= 0 and 4 or 2
      self.timer = 60
      if f.sound then f:sound(SFX_TEXTBOX_SELECT) end
    end
    if c ~= self.choice then
      self.choice = c
      if self.go then self.go:popup(0, c) end
      if f.sound then f:sound(SFX_TEXTBOX_CHOICE) end
    end
  elseif o == 2 then -- HandleSave(0)
    local host = f.game and f.game.opts and f.game.opts.host
    if host and host.requestSave then host:requestSave() end
    self.saved = true
    self.overlay = 4
  else
    self:setFade(bor(FADE_IN_OUT, FADE_BLACK_WHITE, 4), 8)
    self.state, self.overlay = 3, 0
  end
end

-- returns "title" when the task ends (DoSoftReset)
function St:update(input)
  self.frame = self.frame + 1
  if self.state == 1 then self:state1()
  elseif self.state == 2 then self:state2(input)
  elseif self.state == 3 then
    if not self.fade.active then return "title" end
  end
  self:fadeStep()
  return nil
end

function St:draw()
  if not (love and love.graphics) then return end
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, Ppu.W, Ppu.H)
  g.setColor(1, 1, 1, 1)
  if self.state <= 1 or not self.go then
    local p = self.ppu
    if p then
      p.blend = { t1 = 0x02, eva = band(self.alpha, 0x1F), evb = band(rshift(self.alpha, 8), 0x1F) }
      self:applyFade()
      p:flush()
      g.draw(p:render(), 0, 0)
    end
    if self.state <= 1 then return end
  else
    local p = self.go.ppu
    p:flush()
    g.draw(p:render(), 0, 0)
  end
  local lv = self:fadeLevel()
  if lv > 0 then
    local c = self.fade.white and 1 or 0
    g.setColor(c, c, c, math.min(1, lv / 256))
    g.rectangle("fill", 0, 0, Ppu.W, Ppu.H)
    g.setColor(1, 1, 1, 1)
  end
end

return St
