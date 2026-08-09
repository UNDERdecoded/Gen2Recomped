-- HORDE MODE: the readout.
--
-- Health, ammunition, score, wave, the crosshair, the hit marker, the red
-- that closes in when something reaches you, and the banners -- "A
-- DARKNESS APPROACHES", then "WAVE 1" and every wave after it.
--
-- IT IS DRAWN TWICE, INTO TWO DIFFERENT PLACES, and that is not
-- duplication for its own sake. The flat screen's HUD goes into the SCENE
-- canvas through Voxel3D.beginOverlay -- the same seam the overworld's FX
-- bubbles use -- because that canvas is what the window composites. A
-- headset never sees that canvas: with VR live the window's world pass
-- short-circuits to the mirror, and the eyes are rendered on their own in
-- lib/VR. So the eye canvases get their own pass, at the same instant the
-- VR frame paints its fade over them, in the same 2D idiom.
--
-- Both call the same draw with a different scale and a different safe
-- area: a headset wants everything well inside the lens rather than
-- pinned to the corners, because the corners of a VR frame are off the
-- edge of the visible world.
--
-- EVERY WORD IS ON A WHITE PLATE, and that is not a style choice -- it is
-- what the font is. The Game Boy font sheets are BLACK glyphs on
-- transparent, so setColor cannot make a letter pale: multiplying black
-- by white is still black. That is why every box in the game is drawn
-- white first and its text black on top (Font.drawBox, then
-- setColor(0,0,0)), and it is why a first cut of this HUD -- pale text,
-- straight onto the night -- composited as black letters on a black
-- street and could not be read at all. Plates also happen to be the right
-- answer aesthetically: the game already talks to the player in white
-- boxes, and a horde mode that shouts in the same voice belongs to it.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Horde = V.require("Horde")

local HordeHud = {}

local Font = nil
local function font()
  if Font then return Font end
  local ok, F = pcall(require, "src.render.Font")
  if ok then Font = F end
  return Font
end

-- the pulse under the low-health plate and the banner's own breathing
local blink = 0

function HordeHud.update(dt)
  blink = (blink + (dt or 0)) % 1.0
end

-- named for the suite: the banner's line breaking, which is the part with
-- an answer worth pinning
HordeHud._layout = nil        -- assigned below, once `layout` exists

-- ------- pieces
--
-- Every helper takes a scale `s` and draws in GB pixels multiplied by it,
-- so one layout serves a 4x window and a headset's eye buffer alike.

local PAD = 3           -- plate padding, in GB pixels

-- A white plate with a dark edge: the surface a black glyph can be read
-- on. Returns the interior origin, so a caller lays text out from there.
local function plate(x, y, w, h, s, alpha)
  love.graphics.setColor(0.06, 0.05, 0.09, (alpha or 1) * 0.92)
  love.graphics.rectangle("fill", x - s, y - s, w + 2 * s, h + 2 * s)
  love.graphics.setColor(0.93, 0.94, 0.90, alpha or 1)
  love.graphics.rectangle("fill", x, y, w, h)
  return x + PAD * s, y + PAD * s
end

local function textWidth(str, s)
  local F = font()
  if not F then return 0 end
  return F.width(str) * s
end

-- Black glyphs at `s` times their size. Black because that is the only
-- colour the font has (see the header).
local function text(str, x, y, s)
  local F = font()
  if not F then return 0 end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.push()
  love.graphics.translate(math.floor(x), math.floor(y))
  love.graphics.scale(s, s)
  F.draw(str, 0, 0)
  love.graphics.pop()
end

-- One line of text on its own plate, anchored left or right.
local function label(str, x, y, s, align)
  local tw = textWidth(str, s)
  local pw, ph = tw + PAD * 2 * s, 8 * s + PAD * 2 * s
  local px = (align == "right") and (x - pw) or x
  local ix, iy = plate(px, y, pw, ph, s)
  text(str, ix, iy, s)
  return pw, ph
end

-- The health bar: a plate with a red bar inside it, so the red reads
-- against white rather than against a night street.
local function healthBar(x, y, w, h, s, fill, flash)
  local ix, iy = plate(x, y, w, h, s)
  local iw, ih = w - PAD * 2 * s, h - PAD * 2 * s
  love.graphics.setColor(0.80, 0.80, 0.78, 1)
  love.graphics.rectangle("fill", ix, iy, iw, ih)
  local r, g, b = 0.78, 0.12, 0.16
  if flash then r, g, b = 1, 0.45, 0.35 end
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", ix, iy, math.max(0, iw * fill), ih)
end

-- The crosshair: four ticks around a gap that opens as the gun kicks, and
-- gone entirely down the sights, where the iron sights ARE the crosshair.
-- Drawn as a dark pair under a light pair so it survives both a white
-- wall and a black doorway.
local function crosshair(cx, cy, s, spread, alpha)
  local gap = (3 + spread * 4) * s
  local len = 4 * s
  local t = math.max(1, s)
  local function ticks(o, thick, r, g, b, a)
    love.graphics.setColor(r, g, b, a)
    love.graphics.rectangle("fill", cx - gap - len - o, cy - thick / 2 - o,
                            len + 2 * o, thick + 2 * o)
    love.graphics.rectangle("fill", cx + gap - o, cy - thick / 2 - o,
                            len + 2 * o, thick + 2 * o)
    love.graphics.rectangle("fill", cx - thick / 2 - o, cy - gap - len - o,
                            thick + 2 * o, len + 2 * o)
    love.graphics.rectangle("fill", cx - thick / 2 - o, cy + gap - o,
                            thick + 2 * o, len + 2 * o)
  end
  ticks(math.max(1, s * 0.5), t, 0, 0, 0, alpha * 0.85)
  ticks(0, t, 0.98, 0.98, 1, alpha)
end

local function hitMarker(cx, cy, s, amount)
  if amount <= 0 then return end
  love.graphics.setColor(1, 0.30, 0.26, amount)
  local o = 5 * s
  local len = 5 * s
  local t = math.max(1, s)
  for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    love.graphics.push()
    love.graphics.translate(cx + d[1] * o, cy + d[2] * o)
    love.graphics.rotate(math.pi / 4 * (d[1] * d[2] > 0 and 1 or -1))
    love.graphics.rectangle("fill", -t / 2, -len / 2, t, len)
    love.graphics.pop()
  end
end

-- How wide a run of glyphs comes out at `bs` pixels per font pixel, with
-- `track` of air after each one.
local function runWidth(F, codes, bs, track)
  local total = 0
  for _, code in ipairs(codes) do
    total = total + F.advanceOf(code) * bs + track
  end
  return total - track
end

-- The banner's lines, and the size to draw them at.
--
-- THE SCALE IS NEGOTIATED, not assumed. The caller's scale comes from the
-- window's own zoom, so a player zoomed well in gets a large `s` -- and
-- "A DARKNESS APPROACHES" at twice a large scale is wider than the
-- screen, which is how the words ran off both edges. So: shrink until the
-- longest single WORD fits, then wrap the words into as many lines as
-- that leaves. Wrapping first and shrinking only when a word alone cannot
-- fit keeps the announcement as big as the frame can carry it.
local function layout(F, str, scale, maxW)
  local words = {}
  for word in tostring(str):gmatch("%S+") do words[#words + 1] = word end
  if #words == 0 then return nil end

  local bs = math.max(1, scale * 2)
  local function track(size) return math.max(1, math.floor(size / 2)) end
  while bs > 1 do
    local widest = 0
    for _, word in ipairs(words) do
      local ww = runWidth(F, F.encode(word), bs, track(bs))
      if ww > widest then widest = ww end
    end
    if widest <= maxW then break end
    bs = bs - 1
  end

  local tr = track(bs)
  local spaceW = runWidth(F, F.encode(" "), bs, tr) + tr
  local lines, line, lineW = {}, nil, 0
  for _, word in ipairs(words) do
    local ww = runWidth(F, F.encode(word), bs, tr)
    if not line then
      line, lineW = word, ww
    elseif lineW + spaceW + ww <= maxW then
      line, lineW = line .. " " .. word, lineW + spaceW + ww
    else
      lines[#lines + 1] = { text = line, width = lineW }
      line, lineW = word, ww
    end
  end
  lines[#lines + 1] = { text = line, width = lineW }
  return lines, bs, tr
end

HordeHud._layout = layout

-- The banner: a plate across the middle of the frame with the words on
-- it, as big as the frame can carry. It fades in and out rather than
-- cutting -- an announcement, not a notification -- and the plate fades
-- with it.
local function banner(w, h, scale)
  local sess = Horde.session
  if not (sess and sess.bannerText) then return end
  local t, hold = sess.bannerT, sess.bannerHold
  local alpha
  if t < 0.4 then alpha = t / 0.4
  elseif t < hold then alpha = 1
  else alpha = math.max(0, 1 - (t - hold) / 1.1) end
  if alpha <= 0 then return end

  local F = font()
  if not F then return end
  local margin = 6 * scale
  local lines, bs, tr = layout(F, sess.bannerText, scale, w - margin * 2)
  if not lines then return end

  local lineH = 8 * bs
  local gap = math.max(1, math.floor(bs * 0.4))
  local pad = PAD * 2 * scale
  local ph = #lines * lineH + (#lines - 1) * gap + pad * 2
  local y = math.floor(h * 0.30 - ph / 2)
  -- the plate runs the full width: a band across the world, which reads
  -- as the game interrupting itself rather than as a label on it
  plate(0, y, w, ph, scale, alpha)
  local iy = y + pad

  love.graphics.setColor(0, 0, 0, alpha)
  for i, line in ipairs(lines) do
    local pen = math.floor((w - line.width) / 2)
    local ly = iy + (i - 1) * (lineH + gap)
    for _, code in ipairs(F.encode(line.text)) do
      love.graphics.push()
      love.graphics.translate(pen, ly)
      love.graphics.scale(bs, bs)
      F.drawCode(code, 0, 0)
      love.graphics.pop()
      pen = pen + F.advanceOf(code) * bs + tr
    end
  end
end

-- ------- the whole thing
--
-- `inset` is how far off the edges the corners sit, which is the one real
-- difference between a window and a headset.

local function draw(w, h, s, inset)
  local sess = Horde.session
  if not sess then return end
  local Gun = V.require("HordeGun")
  local ammo, mag, reloading = Gun.ammo()
  local ads = Gun.adsBlend()

  love.graphics.push("all")
  love.graphics.setBlendMode("alpha")

  -- The red. A VIGNETTE rather than a wash over everything: a full-screen
  -- fill strong enough to register at a glance also hides the thing that
  -- just hit you, which in a mode about being surrounded is the one thing
  -- it must not do. Bands closing in from the edges instead, so the
  -- middle of the frame stays readable and the alarm arrives in the
  -- corner of the eye.
  local hurt = sess.damageFlash
  local low = 1 - math.min(1, sess.hp / (sess.maxHp * 0.35))
  local wash = math.max(hurt * 0.9, low * 0.6
                        * (0.7 + 0.3 * math.sin(blink * math.pi * 2)))
  if wash > 0 then
    local band = math.min(w, h) * 0.38
    local steps = 8
    for i = 1, steps do
      local t = i / steps
      local d = band * t
      love.graphics.setColor(0.60, 0.02, 0.06, wash * 0.13)
      love.graphics.rectangle("fill", 0, 0, w, d)
      love.graphics.rectangle("fill", 0, h - d, w, d)
      love.graphics.rectangle("fill", 0, 0, d, h)
      love.graphics.rectangle("fill", w - d, 0, d, h)
    end
  end

  -- health, top left
  local barW, barH = 60 * s, 8 * s + PAD * 2 * s
  healthBar(inset, inset, barW, barH, s, sess.hp / sess.maxHp, hurt > 0.3)
  label(("%d"):format(math.ceil(sess.hp)), inset, inset + barH + 3 * s, s)

  -- score and wave, top right
  label(("SCORE %d"):format(math.floor(sess.score)), w - inset, inset, s,
        "right")
  label(("WAVE %d"):format(math.max(1, sess.wave)),
        w - inset, inset + (8 * s + PAD * 2 * s) + 3 * s, s, "right")

  -- ammunition, bottom right: the rounds as pips over the count, which
  -- reads at a glance in a firefight where a number does not
  local ammoStr = reloading and "RELOADING" or ("%d / %d"):format(ammo, mag)
  local _, ah = label(ammoStr, w - inset, h - inset - (8 * s + PAD * 2 * s), s,
                      "right")
  local pipW, pipH, pipGap = 3 * s, 7 * s, 2 * s
  local pipsW = mag * (pipW + pipGap) - pipGap
  local px = w - inset - pipsW
  local py = h - inset - ah - pipH - 5 * s
  love.graphics.setColor(0.06, 0.05, 0.09, 0.85)
  love.graphics.rectangle("fill", px - 2 * s, py - 2 * s,
                          pipsW + 4 * s, pipH + 4 * s)
  for i = 1, mag do
    if i <= ammo and not reloading then
      love.graphics.setColor(0.98, 0.86, 0.36, 1)
    else
      love.graphics.setColor(0.32, 0.30, 0.36, 1)
    end
    love.graphics.rectangle("fill", px + (i - 1) * (pipW + pipGap), py,
                            pipW, pipH)
  end
  if reloading then
    local t = math.min(1, Gun.state.reloadT / Gun.RELOAD_TIME)
    love.graphics.setColor(0.55, 0.78, 0.98, 1)
    love.graphics.rectangle("fill", px, py + pipH + 1 * s, pipsW * t, 2 * s)
  end

  -- the sight picture
  local cx, cy = w / 2, h / 2
  if ads < 0.6 then
    crosshair(cx, cy, s, Gun.state.kick, (1 - ads / 0.6) * 0.9)
  end
  hitMarker(cx, cy, s, sess.hitMarker)

  banner(w, h, s)

  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------- the two callers

-- The flat window. Called from the voxel pipeline's overlay block, into
-- the scene canvas -- which is at the window's PIXEL size and may be
-- supersampled on top of that, so the caller's scale carries both.
--
-- The caller's scale is CAPPED against the canvas rather than taken as
-- given, because that scale is the world's zoom: zoom in far enough and
-- the health bar was a metre wide and half of it off the top of the
-- screen. A readout is not part of the world and should not zoom with
-- it -- so it sizes off the frame it is drawn in, which keeps its
-- apparent size the same at every zoom and grows it honestly on a bigger
-- display (and with supersampling, which is in both numbers).
function HordeHud.drawFlat(w, h, scale)
  if not Horde.active then return end
  local cap = math.max(1, math.floor(h / 260))
  local s = math.max(1, math.min(math.floor((scale or 1) + 0.5), cap))
  draw(w, h, s, 8 * s)
end

-- ------- and the headset's, which is not a screen overlay at all
--
-- A VR eye gets NO 2D overlay. An earlier cut drew this same HUD into
-- both eye canvases and it came out torn down the middle: the eye frusta
-- are ASYMMETRIC, so the same canvas pixel is a different ANGLE in each
-- eye, and the two images never fuse. Nor is there a crosshair to draw --
-- the gun is a real object with real sights and the shot goes down its
-- barrel, so a dot painted at the centre of the frame would be pointing
-- at something else entirely.
--
-- What the headset gets instead is this: the readout as a TEXTURE, which
-- lib/VR puts on the POKEDEX in the player's left hand -- already
-- tracked, already lit, and already the surface this mod shows
-- information on. Geometry in the world, so both eyes see it from their
-- own position and the stereo is correct by construction. (It rode the
-- gun for one revision and that was worse: a screen on the slide sits
-- exactly where the iron sights have to be looked through.)
--
-- Sized to the device's own screen, which is the GB frame's 10:9.

local panelCanvas = nil
local PANEL_W, PANEL_H = 160, 144

function HordeHud.panelTexture()
  if not Horde.active then return nil end
  if not (love.graphics and love.graphics.newCanvas) then return nil end
  local sess = Horde.session
  if not sess then return nil end
  local F = font()
  if not F then return nil end

  if not panelCanvas then
    local ok, c = pcall(love.graphics.newCanvas, PANEL_W, PANEL_H)
    if not ok then return nil end
    panelCanvas = c
    pcall(panelCanvas.setFilter, panelCanvas, "nearest", "nearest")
  end

  local Gun = V.require("HordeGun")
  local ammo, mag, reloading = Gun.ammo()

  local ok = pcall(function()
    love.graphics.push("all")
    love.graphics.setCanvas(panelCanvas)
    love.graphics.setBlendMode("alpha")
    love.graphics.clear(0.93, 0.94, 0.90, 1)

    -- the health bar, framed, across the top
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 8, 8, PANEL_W - 16, 20)
    love.graphics.setColor(0.80, 0.80, 0.78, 1)
    love.graphics.rectangle("fill", 11, 11, PANEL_W - 22, 14)
    love.graphics.setColor(0.78, 0.12, 0.16, 1)
    love.graphics.rectangle("fill", 11, 11,
                            (PANEL_W - 22) * math.max(0, sess.hp / sess.maxHp),
                            14)

    love.graphics.setColor(0, 0, 0, 1)
    F.draw(("HP %d"):format(math.ceil(sess.hp)), 8, 34)
    F.draw(reloading and "RELOADING" or ("AMMO %d/%d"):format(ammo, mag),
           8, 50)

    -- the round pips, so ammunition reads without counting digits
    local pipW, gap = 9, 5
    for i = 1, mag do
      if i <= ammo and not reloading then
        love.graphics.setColor(0.85, 0.65, 0.10, 1)
      else
        love.graphics.setColor(0.72, 0.73, 0.70, 1)
      end
      love.graphics.rectangle("fill", 8 + (i - 1) * (pipW + gap), 66, pipW, 12)
    end

    love.graphics.setColor(0, 0, 0, 1)
    F.draw(("WAVE %d"):format(math.max(1, sess.wave)), 8, 86)
    F.draw(("%d"):format(math.floor(sess.score)), 8, 102)

    -- and the banner, wrapped to the panel rather than to the frame.
    -- BLACK on the panel's own white, like everything else here: the font
    -- sheets are black glyphs on transparent, so a pale letter is not a
    -- thing that can be drawn (see the header).
    if sess.bannerText then
      local lines, bs, tr = layout(F, sess.bannerText, 1, PANEL_W - 8)
      if lines then
        local top = PANEL_H - 8 * bs * #lines - 5
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, top - 2, PANEL_W, 1)
        for i, line in ipairs(lines) do
          local pen = math.floor((PANEL_W - line.width) / 2)
          local ly = PANEL_H - 8 * bs * (#lines - i + 1) - 3
          for _, code in ipairs(F.encode(line.text)) do
            love.graphics.push()
            love.graphics.translate(pen, ly)
            love.graphics.scale(bs, bs)
            F.drawCode(code, 0, 0)
            love.graphics.pop()
            pen = pen + F.advanceOf(code) * bs + tr
          end
        end
      end
    end

    love.graphics.setCanvas()
    love.graphics.pop()
  end)
  pcall(love.graphics.setCanvas)
  if not ok then return nil end
  return panelCanvas
end

-- window resize / hot reload
function HordeHud.invalidate()
  if panelCanvas and panelCanvas.release then
    pcall(panelCanvas.release, panelCanvas)
  end
  panelCanvas = nil
end

return HordeHud
