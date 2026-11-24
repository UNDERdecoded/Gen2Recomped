-- Round 90: the Sanctuary's story panels -- the aux cutscene behind
-- sub_080536B8 (src/cutscene.c), played when Link looks at the stained glass
-- after the Four Sword (script_MinishVillageObjectPictureBackRoom).
--
-- sub_080536B8: sub_080A71C4(5, 3, FADE_INSTANT, 4) + SetFade(FADE_IN_OUT |
--   FADE_INSTANT, $100): the game is frozen (GAMEMAIN_SUBTASK), the aux
--   cutscene sCutsceneData[3] runs (CutsceneMain_Update, field_0x3 2 ->
--   sub_0805373C), and on the way back (Subtask_FadeOut) the room fades in
--   with gUI.fadeType FADE_INSTANT at speed 4 -- the script's next
--   WaitForFadeFinish waits for that.  (The port used to leave the room black
--   here: the whole Vaati reveal that follows played on a black screen.)
-- sub_0805373C's steps (gUnk_080FCD40):
--   sub_08053758  DISPCNT $2640 (BG1, BG2, WIN0), BLDCNT $2244 (BG2 over BG1
--                 + backdrop), BLDALPHA $1000, WININ $1F, WINOUT $3F, WIN0
--                 $F0 x $60, BG1 $1C4E, BG2 $1DC1 (256 colours), BGM_STORY,
--                 faded out at once; panel 0 next.
--   sub_08053800  (fade done) panel i = gUnk_080FCCB4[i] {font, width,
--                 height, transitionTimer, fadeSpeed}: palette group $8A + i,
--                 gfx group $3A + i, BG1 cleared, ShowTextBox(TEXT_PICORI
--                 1 + i, font), BLDALPHA $10, WIN0 width x height, fade in at
--                 fadeSpeed.
--   sub_08053894  (fade done) the timer; after 30 frames the alpha steps
--                 every second frame (n = 1..16: EVB n, EVA 16 - n / 2): the
--                 text under BG2 shows outside the window; at 0 fade out (8).
--   x 6 panels, then sub_080539F4 (fade done: DispReset(1), 60 frames),
--   sub_08053A1C (MessageFromTarget(TEXT_PICORI 7) at window (1, 8), fade
--   in (8)), sub_08053A5C (the message closed, 8 frames: fade out (8)),
--   sub_08053A90 (fade done: Subtask_FadeOut).
-- The tables (the two Font descriptors gUnk_080FCC84 / gUnk_080FCC9C and
-- gUnk_080FCCB4[6]) are read from the player's ROM at import
-- (M.ROM_RANGES -> manifest.r26b, ExtractR26.lua).
--
-- SIMPLIFIED: the TEXT_PICORI 7 message box is the field's own text box (it
--   is not faded with the palettes); WIN0 is drawn as a second picture
--   without the blend over the window's rectangle.
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local Ppu = require("src.zelda.tmc.Ppu")
local St = require("src.zelda.tmc.Staffroll")
local N = require("src.zelda.tmc.Native").N

local M = {}

M.ROM_RANGES = {
  story90 = { 0x080FCC84, 0x080FCCFC }, -- cutscene.c gUnk_080FCC84 / gUnk_080FCC9C (Font) + gUnk_080FCCB4[6] (struct_080FCCB4)
}

local FADE_IN_OUT, FADE_INSTANT = 1, 4
local BGM_STORY = 0x0F
local TEXT_PICORI = 0x0F
local PANELS = 6
local TABLE = 0x080FCCB4
M.TABLE, M.PANELS, M.BGM_STORY, M.TEXT_PICORI = TABLE, PANELS, BGM_STORY, TEXT_PICORI

local S = setmetatable({}, { __index = St })
S.__index = S
M.Story = S

local function tables(f, name)
  local ok, X = pcall(require, "src.zelda.tmc.ExtractR26")
  if ok and X.tables then return X.tables(f, name) end
end

-- a Font descriptor (message.h) at `a`
function M.readFont(T, a)
  local fl = T.u8(a + 19)
  return { dest = T.u32(a), gfx_dest = T.u32(a + 4), buffer = T.u32(a + 8), gfx_src = T.u16(a + 16),
           width = T.u8(a + 18), centre = band(fl, 1) ~= 0, sm_border = band(fl, 2) ~= 0,
           draw_border = band(fl, 8) ~= 0, border_type = rshift(fl, 4), fill = T.u8(a + 20),
           charColor = T.u8(a + 21), spacing = T.u8(a + 22), stylized = T.u8(a + 23) }
end
-- struct_080FCCB4 i
function M.readPanel(T, i)
  local a = TABLE + 12 * i
  return { font = T.u32(a), width = T.u16(a + 4), height = T.u16(a + 6), timer = T.u16(a + 8), fadeSpeed = T.u16(a + 10) }
end

function M.new(field, opts)
  local self = setmetatable({ field = field, frame = 0, opts = opts or {}, overlay = 0, panel = 0 }, S)
  self.T = (self.opts.tables or tables)(field, "story90")
  self.fade = { active = false, progress = 0x100, sustain = 0, speed = 0, type = 0, mask = 0xFFFFFFFF }
  self.alpha, self.win = 0x1000, { 0, 0 }
  return self
end

-- sub_08053758
function S:setup()
  local f = self.field
  self.overlay = 1
  self.timer, self.wait = 120, 0x1E
  self.panel = 0
  self.ppu = self:newPpu()
  local p = self.ppu
  if p then
    p.dispcnt = 0x2640
    p.bg[0].control, p.bg[1].control, p.bg[2].control, p.bg[3].control = 0, 0x1C4E, 0x1DC1, 0
    -- the game's BG palette 15 (the message palette, palette group $C as TextBox.lua loads it) stays
    -- through the subtask: the panels' text is drawn with it
    p:loadPaletteGroup(0x0C)
    p:setColor(0, 0)
    self:snap()
  end
  self.alpha = 0x1000
  self.win = { 0xF0, 0x60 }
  if f and f.bgm then f:bgm(BGM_STORY) end
  self:setFade(bor(FADE_IN_OUT, FADE_INSTANT), 0x100)
end

-- sub_08053800
function S:loadPanel()
  if self.fade.active then return end
  local i = self.panel
  local pn = self.T and M.readPanel(self.T, i) or { font = 0, width = 0, height = 0, timer = 1, fadeSpeed = 0x100 } -- (an old cache: no panels)
  self.timer, self.wait = pn.timer, 0x1E
  self.panel = i + 1
  self.overlay = self.overlay + 1
  self.step = 0
  local p = self.ppu
  if p then
    self:palGroup(0x8A + i)
    p:loadGfxGroup(0x3A + i)
    self:clearBg(1)
    if self.T and pn.font ~= 0 then p:showTextBox(lshift(TEXT_PICORI, 8) + 1 + i, M.readFont(self.T, pn.font)) end
    p.bg[1].updated = true -- (the gfx group writes BG2's tiles and map straight into VRAM)
  end
  self.alpha = 0x10
  self.win = { pn.width, pn.height }
  self:setFade(FADE_INSTANT, pn.fadeSpeed)
end

-- sub_08053894
function S:holdPanel()
  if self.fade.active then return end
  self.timer = self.timer - 1
  if self.wait ~= 0 then
    self.wait = self.wait - 1
  elseif self.frame % 2 == 0 and self.step < 0x10 then
    self.step = self.step + 1
    self.alpha = bor(lshift(self.step, 8), 0x10 - rshift(self.step, 1))
  end
  if self.timer <= 0 then
    self.overlay = self.overlay + 1
    self:setFade(bor(FADE_IN_OUT, FADE_INSTANT), 8)
  end
end

function S:update(input)
  self.frame = self.frame + 1
  local f = self.field
  local o = self.overlay
  local last = 1 + 2 * PANELS -- the first step after the panels
  if o == 0 then self:setup()
  elseif o < last then
    if o % 2 == 1 then self:loadPanel() else self:holdPanel() end
  elseif o == last then -- sub_080539F4
    if not self.fade.active then self.blank, self.overlay, self.timer = true, o + 1, 60 end
  elseif o == last + 1 then -- sub_08053A1C
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.overlay, self.timer = o + 1, 8
      if f and f.message then
        f:message(lshift(TEXT_PICORI, 8) + 7)
        if f.textbox then f.textbox.posX, f.textbox.posY = 1, 8 end
      end
      self:setFade(FADE_INSTANT, 8)
    end
  elseif o == last + 2 then -- sub_08053A5C
    if f and f.textbox then
      local ti = input
      local function pr(k) return ti and ti.pressed and ti.pressed(k) or false end
      f.textbox:update({ a = pr("a"), b = pr("b") or pr("r"), left = pr("left"), right = pr("right"), up = pr("up"), down = pr("down") })
      if f.textbox.done then f.textbox = nil; f.textClosedAt = f.frame end
    else
      self.timer = self.timer - 1
      if self.timer <= 0 then self.overlay = o + 1; self:setFade(bor(FADE_IN_OUT, FADE_INSTANT), 8) end
    end
  elseif o == last + 3 then -- sub_08053A90
    if not self.fade.active then self.overlay = o + 1; return "done" end
  end
  self:fadeStep()
  return nil
end

function S:draw()
  if not (love and love.graphics) then return end
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, Ppu.W, Ppu.H)
  g.setColor(1, 1, 1, 1)
  local p = self.ppu
  if p and not self.blank and self.overlay > 0 then
    self:applyFade()
    p:flush()
    -- outside WIN0 (WINOUT $3F): BG2 blended over BG1 + the backdrop
    p.blend = { t1 = 0x04, eva = band(self.alpha, 0x1F), evb = band(rshift(self.alpha, 8), 0x1F) }
    g.draw(p:render(), 0, 0)
    -- inside WIN0 (WININ $1F): no colour effect
    p.blend = nil
    local w, h = math.min(Ppu.W, self.win[1] or 0), math.min(Ppu.H, self.win[2] or 0)
    if w > 0 and h > 0 then
      local img = p:render("win0")
      self.quad = self.quad or g.newQuad(0, 0, w, h, Ppu.W, Ppu.H)
      self.quad:setViewport(0, 0, w, h, Ppu.W, Ppu.H)
      g.draw(img, self.quad, 0, 0)
    end
  end
  local lv = self:fadeLevel()
  if lv > 0 then
    g.setColor(0, 0, 0, math.min(1, lv / 256))
    g.rectangle("fill", 0, 0, Ppu.W, Ppu.H)
    g.setColor(1, 1, 1, 1)
  end
end

-- ---------------------------------------------------------------- hooks
-- sub_080536B8 (script_MinishVillageObjectPictureBackRoom)
function M.start(f)
  f.story90 = M.new(f)
  -- the subtask owns the screen; the field's fade is put back on the way out
  f.fadeLevel, f.fadeTarget, f.iris = 0, 0, nil
end
N[0x080536B8] = function(f) M.start(f) end

-- Subtask_FadeOut: back in the room, SetFade(FADE_INSTANT, 4)
function M.finish(f)
  f.story90 = nil
  f.fadeLevel, f.fadeTarget = 1, 1
  f:fade("in", false, 4)
end

function M.frame(f, input)
  local s = f.story90
  if not s then return false end
  f.fadeLevel, f.fadeTarget = 0, 0
  if s:update(input) == "done" then M.finish(f) end
  return true
end

function M.draw(f, font)
  if f.story90 then return f.story90:draw() end
  if (f.fadeLevel or 0) > 0 and M.textKept(f) and love and love.graphics then
    local g = love.graphics
    local c = f.fadeWhite and 1 or 0
    g.setColor(c, c, c, f.fadeLevel)
    g.rectangle("fill", -4096, -4096, 8192, 8192)
    g.setColor(1, 1, 1, 1)
  end
end

-- SetFadeMask $FFFF7FFF (script_MinishVillageObjectPictureBackRoom before TEXT_VAATI2 4): every palette but BG
-- palette 15 -- the message window's -- fades: the room, the sprites and the HUD go black, the text box stays.
-- (Fade70.lua takes the BG-only masks; this is the "all but the text" one: the fade is drawn just under the text
-- box -- R27B's draw hook -- instead of over it.)
function M.maskTextKept(m)
  if not m then return false end
  return band(m, 0xFFFF0000) == bit.tobit(0xFFFF0000) and band(m, 0x8000) == 0 and band(m, 0x7FFF) ~= 0
end
function M.textKept(f)
  if not f or f.fadeMask70Room ~= f.room then return false end
  return M.maskTextKept(f.fadeMask70)
end

return M
