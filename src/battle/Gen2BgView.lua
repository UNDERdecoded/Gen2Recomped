-- Gen1Recomp-derived BG presenter, pinned at535a5ec0. GPLv3 plus
-- Additional Terms: compat/gen1-gsc/LICENSE.MD and provenance.json.
-- Native integration retains the real BG scanline pipeline and uses this
-- engine's palette and pixel-canvas owners. OAM is composited afterwards.
local PixelCanvas=require('src.render.PixelCanvas')
local Chrome=require('src.battle.Gen2BgPaint')
local GbcPalette=require('src.render.Gen2PaletteDraw')
local BgView={}
local SCREEN_W,SCREEN_H=160,144
local function signed(value)
  value=(value or 0)%256
  return value<0x80 and value or value-256
end
local function needsCanvas(runner)
  local bg = runner.bg
  -- engine/battle_anims/bg_effects.asm:448-465: a lifted battler row stays
  -- out of the BG until the next pic redraw, so those frames stay baked too.
  local lifted = bg.liftedRows
  if lifted and (lifted.player or lifted.enemy) then return true end
  if bg.scx ~= 0 or bg.scy ~= 0 then return true end
  if not bg.lcdc then return false end
  if bg.lyEnd <= bg.lyStart then return false end
  for row = bg.lyStart, math.min(bg.lyEnd, SCREEN_H) - 1 do
    if (bg.lyBackup[row] or 0) ~= 0 then return true end
  end
  return false
end

-- The battle background is BG colour 0 everywhere the two pic boxes and the
function BgView:fillBackground(palByte)
  local SCREEN_W=self.bgWidth or 160
  if self.bgTransparent then return end
  local previousBgp = GbcPalette.setBgp(palByte)
  local ok, err = pcall(Chrome.paletteFill, 0, 0, SCREEN_W, SCREEN_H)
  GbcPalette.setBgp(previousBgp)
  if not ok then error(err, 0) end
end

-- One reusable quad, re-aimed per scanline.  A row shifted by `dx` is drawn
-- CLIPPED to the 160-pixel screen rather than allowed to hang over the edge:
-- the cart's BG map wraps, so a scrolled scanline never spills past the LCD.
function BgView:blitRowAt(srcRow, destRow, dx)
  local SCREEN_W=self.bgWidth or 160
  local canvas = self.canvas
  if not self.blitQuad then
    self.blitQuad = love.graphics.newQuad(0, 0, SCREEN_W, 1, SCREEN_W, SCREEN_H)
  end
  local srcX, width, destX = 0, SCREEN_W, dx
  if dx > 0 then
    width = SCREEN_W - dx
  elseif dx < 0 then
    srcX, width, destX = -dx, SCREEN_W + dx, 0
  end
  if width <= 0 then return end
  self.blitQuad:setViewport(srcX, srcRow, width, 1, SCREEN_W, SCREEN_H)
  love.graphics.draw(canvas, self.blitQuad, destX, destRow)
end

function BgView:blitRow(row, dx, dy)
  self:blitRowAt(row, row + dy, dx)
end

-- Draw the battle panel into the blit canvas, optionally with an rBGP byte
-- folded into every palette on the way in.
--
-- The byte is set on GbcPalette rather than applied afterwards, which is what
-- makes it exact: the panel is still being DRAWN, so its palettes can take
-- CopyPals' permutation before they ever reach the shader.  That is bit for bit
-- what DmgToCgbBGPals does, and it is why nothing here has to guess which
-- palette entry produced a finished pixel.
--
-- pcall so a drawBg that throws cannot leave the byte standing on GbcPalette
-- for the rest of the frame.
function BgView:bake(drawBg, palByte)
  local SCREEN_W=self.bgWidth or 160
  local G = love.graphics
  if not self.canvas then
    self.canvas = PixelCanvas.new(SCREEN_W, SCREEN_H)
    self.canvas:setFilter("nearest", "nearest")
  end
  local previousBgp = GbcPalette.setBgp(palByte)
  G.push('all')
  local ok, err = pcall(function()
    G.setCanvas(self.canvas)
    G.setScissor()
    G.clear(0,0,0,0)
    G.origin()
    drawBg()
  end)
  G.pop()
  GbcPalette.setBgp(previousBgp)
  if not ok then error(err,0) end
end

-- The rBGP window's scanlines grouped by the byte they hold, identity first.
--
-- `.SetLYOverridesBackup` writes one value on every SECOND row and leaves the
-- rest on whatever ClearLYOverrides put there, so a beta send-out frame holds
-- two bytes and FadeMonsToBlackRepeating's DMG path holds two bands of one
-- each.  Grouping means the panel is re-baked twice a frame rather than 144
-- times, and the grouping is by VALUE so a table that happens to repeat costs
-- nothing extra.
local function bgpBands(bg)
  local base = bg.bgp or GbcPalette.BGP_IDENTITY
  local order, bands = {}, {}
  for row = 0, SCREEN_H - 1 do
    -- home/lcd.asm:12
    local inWindow = row > bg.lyStart and row <= bg.lyEnd
    -- Outside the window the register still reads whatever wBGP holds.
    local byte = inWindow and (bg.lyBackup[row - 1] or base) or base
    local band = bands[byte]
    if not band then
      band = { byte = byte, rows = {} }
      bands[byte] = band
      order[#order + 1] = band
    end
    band.rows[#band.rows + 1] = row
  end
  -- The base band first so the fillBackground below it happens before any blit
  -- and the common band is the one drawn from the first bake.
  table.sort(order, function(a, b)
    if a.byte == b.byte then return false end
    if a.byte == base then return true end
    if b.byte == base then return false end
    return a.rows[1] < b.rows[1]
  end)
  return order
end
BgView.bgpBands = bgpBands

-- engine/battle_anims/bg_effects.asm:2638
--
-- One scanline's source row and x shift, or nil when the row shows nothing.
local function scanline(bg, scy, row)
  local dx, src = 0, row + scy
  -- home/lcd.asm:12
  local inWindow = bg.lcdc and bg.lcdc ~= "BGP"
    and row > bg.lyStart and row <= bg.lyEnd
  local byte = inWindow and (bg.lyBackup[row - 1] or 0) or 0
  if inWindow then
    local value = signed(byte)
    if bg.lcdc == "SCX" then dx = -value else src = src + value end
    -- home/lcd.asm:3
    if byte ~= 0x90 and scy == 0 then
      if src < 0 then src = 0 elseif src >= SCREEN_H then src = SCREEN_H - 1 end
    end
  end
  if (not inWindow or byte ~= 0x90) and src >= 0 and src < SCREEN_H then
    return src, dx
  end
  return nil
end

function BgView.scanlines(bg)
  local lines = {}
  local scy = signed(bg.scy)
  for row = 0, SCREEN_H - 1 do
    local src, dx = scanline(bg, scy, row)
    if src then
      lines[#lines + 1] = { src = src, dest = row, dx = dx }
    end
  end
  return lines
end

-- Runs `drawBg` (the battle panel) and puts it on screen through the
-- animation's BG registers; skips the canvas when nothing needs one.
function BgView:present(runner, drawBg, battle)
  local SCREEN_W=self.bgWidth or 160
  if not (love and love.graphics) then return end
  local bg = runner.bg
  -- engine/battle_anims/anim_commands.asm:1293
  local byte = bg.bgp ~= GbcPalette.BGP_IDENTITY and bg.bgp or nil
  if not byte and not needsCanvas(runner) then
    drawBg()
    return
  end
  local G = love.graphics

  -- hLCDCPointer can also aim at rBGP, in which case each scanline gets its own
  -- PALETTE rather than its own scroll (the beta send-out effects, and
  -- FadeMonsToBlackRepeating on the DMG path).  Nothing scrolls on that path,
  -- so the whole of it is: bake the panel once per distinct byte and blit that
  -- byte's rows out of it.
  if bg.lcdc == "BGP" and GbcPalette.available() then
    local baseX, baseY = -signed(bg.scx), -signed(bg.scy)
    local bands = bgpBands(bg)
    local filled = false
    for _, band in ipairs(bands) do
      self:bake(drawBg, band.byte)
      G.setShader()
      if not filled then
        self:fillBackground(band.byte)
        filled = true
      end
      G.setColor(1, 1, 1, 1)
      for _, row in ipairs(band.rows) do
        self:blitRow(row, baseX, baseY)
      end
    end
    return
  end

  self:bake(drawBg, byte)
  G.setShader()

  -- A shifted scanline exposes the blank tile beside the pic boxes; without
  -- this the exposed strip is the canvas's own transparency.
  self:fillBackground(byte)
  G.setColor(1, 1, 1, 1)
  -- hSCX / hSCY move the whole background; the per-scanline overrides only
  -- apply inside the effect's own window.
  local baseX = -signed(bg.scx)
  -- BgView.scanlines row by row, without a table per scanline.
  local scy = signed(bg.scy)
  for row = 0, SCREEN_H - 1 do
    local src, dx = scanline(bg, scy, row)
    if src then self:blitRowAt(src, row, baseX + dx) end
  end
  -- Shaderless boot: the panel is raw grayscale, so there are no palettes to
  -- permute and the entry's BRIGHTNESS is the only thing left to reproduce.
  if bg.lcdc == "BGP" then
    for row = bg.lyStart + 1, math.min(bg.lyEnd, SCREEN_H - 1) do
      local veil = BgView.palVeil(bg.lyBackup[row - 1])
      if veil ~= 0 then
        local shade = veil > 0 and 0 or 1
        G.setColor(shade, shade, shade, math.min(1, math.abs(veil)))
        G.rectangle("fill", 0, row, SCREEN_W, 1)
      end
    end
    G.setColor(1, 1, 1, 1)
  end
end

-- A DMG palette byte's mean shade against the identity %11100100, signed:
-- +1 is solid black ($ff), -1 solid white ($00), 0 the identity.  The
-- approximation, kept for the shaderless path in `present` above.
function BgView.palVeil(palByte)
  if not palByte then return 0 end
  local sum = 0
  for index = 0, 3 do
    sum = sum + math.floor(palByte / (4 ^ index)) % 4
  end
  return (sum - 6) / 6
end

--------------------------------------------------------------------------
-- The battle intro slide (engine/battle/sliding_intro.asm)
--------------------------------------------------------------------------

-- BattleIntroSlidingPics runs 72 frames.  It holds three SCX values at once:
-- scanlines 0-$3f take `c`, which starts at $90 and falls by 2 a frame, so
-- the enemy's half enters from the RIGHT; $40-$5f take `b`, which starts at
-- $70 and RISES by 2, wrapping to 0 on the last frame, so the player's half
-- enters from the LEFT; everything from $60 down is already in place.
BgView.SLIDE_FRAMES = 72

function BgView.slideOffsets(frame)
  local step = math.max(0, math.min(BgView.SLIDE_FRAMES, frame))
  local top = (0x90 - step * 2) % 256
  local middle = (0x70 + step * 2) % 256
  return top, middle
end

-- The pixels the cart's OAM back-pic copy still has to travel at `frame`:
-- CopyBackpic parks 18 sprites just off the RIGHT edge (x = 168 in OAM
-- terms) and the slide's `.subfunction1` walks every one left 2px a frame,
-- so the whole pic crosses 144px to its resting column in the 72 frames.
function BgView.slideBackpicOffset(frame)
  local step = math.max(0, math.min(BgView.SLIDE_FRAMES, frame))
  return (BgView.SLIDE_FRAMES - step) * 2
end

-- The same band-at-a-time blit `present` uses, with the intro's own offsets.
--
-- `drawBackpic(offset)`, when given, draws the player's back pic OVER the
-- bands the way the cart's OAM copy rides over them: InitBattleDisplay clears
-- the pic's top rows out of the BG before the slide (the hlcoord 1, 5
-- ClearBox) precisely because the pic straddles the $40 scanline where the
-- two bands part ways -- baked into the bands it tears in half there, its top
-- rows riding the enemy's offset and its bottom rows the player's.  The
-- caller must leave the pic OUT of drawBg and hand it here instead.
function BgView:presentSlide(frame, drawBg, drawBackpic)
  local SCREEN_W=self.bgWidth or 160
  if not (love and love.graphics) then return end
  local top, middle = BgView.slideOffsets(frame)
  if top == 0 and middle == 0 then
    drawBg()
    if drawBackpic then drawBackpic(0) end
    return
  end
  local G = love.graphics
  self:bake(drawBg, nil)
  G.setShader()
  self:fillBackground()
  G.setColor(1, 1, 1, 1)
  for row = 0, SCREEN_H - 1 do
    local scx = 0
    if row < 0x40 then
      scx = top
    elseif row < 0x60 then
      scx = middle
    end
    -- SCX is unsigned and the map wraps at 256, so a value over half the
    -- screen reads as "coming in from the other side" rather than as a jump.
    local dx = -scx
    if scx > 128 then dx = 256 - scx end
    self:blitRow(row, dx, 0)
  end
  if drawBackpic then
    drawBackpic(BgView.slideBackpicOffset(frame))
  end
end

-- A DMG palette byte read as a shade remap, so a BG effect that fades a mon
-- through $f8/$fc can be applied to that mon's four CGB colours.  The same
-- CopyPals permutation `present` now folds into the whole panel, which is why
-- it lives in GbcPalette and this is a name for it rather than a second copy.
function BgView.shadeColors(colors, palByte)
  return GbcPalette.remap(colors, palByte)
end

BgView.SCREEN_W = SCREEN_W
BgView.SCREEN_H = SCREEN_H
BgView.needsCanvas = needsCanvas

function BgView:setBgSize(width)
  width=width or 160
  assert(type(width)=='number' and width>0 and width%1==0,'invalid native battle surface width')
  if self.bgWidth==width then return end
  self:releaseBg()
  self.bgWidth=width
end
function BgView:releaseBg()
  if self.canvas and self.canvas.release then self.canvas:release() end
  self.canvas,self.blitQuad=nil,nil
end

-- Public draw seams restore the caller's graphics owner; no animation time
-- runs here. The real native scene supplies its transparency and surface.
local present=BgView.present
function BgView:present(runner,drawBg,battle,width)
  if not(love and love.graphics)then return end
  self:setBgSize(width)
  local transparent=self.bgTransparent
  self.bgTransparent=battle and type(battle.worldBackdrop)=='function' and battle:worldBackdrop() or false
  local g=love.graphics
  g.push('all')
  local ok,why=pcall(present,self,runner,drawBg,battle)
  g.pop()
  self.bgTransparent=transparent
  if not ok then error(why,0) end
end
local presentSlide=BgView.presentSlide
function BgView:presentSlide(frame,drawBg,drawBackpic,width)
  if not(love and love.graphics)then return end
  self:setBgSize(width)
  local g=love.graphics
  g.push('all')
  local ok,why=pcall(presentSlide,self,frame,drawBg,drawBackpic)
  g.pop()
  if not ok then error(why,0) end
end
return BgView
