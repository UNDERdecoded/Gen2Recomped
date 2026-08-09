-- Overworld battles: giving a battle pic its paper back.
--
-- Gen 1 battle pics are two-bit art whose lightest shade is WHITE, and the
-- engine's decoded PNGs key that shade to alpha 0 -- which was free, because
-- the field behind them was white too. A transparent belly on a white page
-- is a white belly.
--
-- Put a route behind it and the belly is grass. Charizard's chest, the whites
-- of every eye, the highlight down a Pikachu's cheek: all of it turns into a
-- hole with the world showing through, and the mon reads as a stencil.
--
-- So the paper is put back, and only where the paper was. Which pixels those
-- are is the whole problem, and it has to be ANSWERED rather than looked up:
-- the hardware drew the mon's white belly and the white field behind it with
-- the same shade, the decoder keyed both to the same alpha, and nothing in the
-- image says which was which. There is no distinction to recover; there is one
-- to draw.
--
-- The rule is a flood fill from OUTSIDE the figure: whatever the background
-- can reach is background, and whatever it cannot is paper. What makes that
-- work is where the flood is allowed to start.
--
-- Start it at the image border and it fills everything and answers nothing.
-- Gen 1 figures are open drawings and a belly is not a sealed room: it walks
-- out between two legs and off the bottom of the frame. Run over all 352 of
-- this game's battle pics, that finds an enclosed hole in NONE of them -- so
-- it left every mon a stencil, which is the bug this file exists to fix and
-- for a long time did not.
--
-- So the flood is started at the edges of the artwork's own BOUNDING BOX, and
-- the left, the right and the top are seeded whole. The sky between a pair of
-- ears reaches the top edge and stays sky; the gap between a body and a raised
-- tail reaches the side and stays gap.
--
-- The BOTTOM is the interesting one, because two completely different things
-- meet the underside of a figure and they have to be told apart.
--
--   A DRAIN is where the drawing simply ran out -- a belly whose white carries
--   on down until the artist stopped, leaking to the outside through the inch
--   between a body and a leg. Seal it: what is above it is the mon.
--
--   A MOUTH is the space BETWEEN two legs, or under an arch. It is background
--   that happens to be enclosed on three sides. Leave it open: the world
--   should show through the gap in a trainer's stride.
--
-- What separates them is how WIDE the opening is, and on this game's art that
-- is not a close call. Measured along the bottom of every battle pic: the
-- drains run 3 and 4 pixels (Clefairy's back, Wartortle's back, Red's back)
-- and the mouths run 10, 12, 14 and 17 (a Rattata's underbelly, Blue's stride,
-- Brock's, a Pikachu's back). Nothing lands between 4 and 10, so the cut is
-- taken at 6 with room either side rather than tuned to a single sprite.
--
-- Apart from that one number the rule is exact: no pixel is filled for what
-- surrounds it, only because the background provably cannot get to it. And it
-- needs no idea whether it is holding a front pic, a back one or a trainer --
-- fronts are near-solid silhouettes with almost nothing inside them to fill,
-- and they come back untouched because that is what their own shape says, not
-- because they were special-cased.
--
-- The drain/mouth cut is for a pic STANDING ON THE MAP, where a mouth is a
-- real hole with real ground behind it. A pic PINNED TO THE MENU has no such
-- hole to be: under BACK SPRITES the player's mon is drawn in the GB's own
-- slot with its feet flush on the text box (BattleState.backPlacement pins
-- row 96), so the only thing under its lowest row is white box. Nothing can
-- reach it from below, whatever the opening's width, and the caller says so
-- by asking for a SEALED BOTTOM -- for which the rule stops being a heuristic
-- and becomes exact: paper is whatever the background cannot walk to from the
-- left, the right or the top.
--
-- That is the difference between a Pikachu that reads as a mon and one that
-- reads as wireframe. The pale-bodied back pics -- Pikachu, Seel, Dewgong,
-- Chansey, Jigglypuff -- are drawn as OUTLINES: everything inside the ink is
-- shade 0 and every one of them is keyed away, so the figure is a rim with the
-- arena showing through it. Each one also has a wide opening along its bottom,
-- which the drain cut correctly reads as a mouth and the sealed bottom
-- correctly does not. Twelve of this game's 151 back pics turn on it; the
-- other 139 come back byte-identical either way, because they had nothing
-- under them the flood was getting in through.
--
-- The silhouette is untouched, so the mon still cuts cleanly against the
-- world; only its insides stop being see-through.
--
-- Read back off the GPU rather than off the asset, deliberately. What comes
-- back is the pic the engine actually decided to draw -- species palette,
-- forced-mono rebuild, shiny recolour, a mod's replacement art -- so this
-- needs to know nothing about how any of that was arrived at. Once per pic
-- per session, cached on the image itself.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattlePics = {}

-- Cached by the image the engine handed over, one table per bottom rule --
-- the same pic answers differently sealed and unsealed, and a single table
-- would hand the wrong twin back to whichever caller asked second. Weak keys,
-- so a pic that goes out of scope takes its filled twin with it rather than
-- pinning a texture for the session.
local function newCache()
  return {
    [false] = setmetatable({}, { __mode = "k" }),
    [true]  = setmetatable({}, { __mode = "k" }),
  }
end
local cache = newCache()

-- What an enclosed hole is filled with when the pic itself offers nothing
-- better. White, because white is what the battle field was: this restores the
-- pixel the artist drew and the engine then keyed away, it does not invent a
-- new one.
BattlePics.FILL = { 1, 1, 1, 1 }

-- Anything at or under this alpha counts as keyed-out rather than drawn.
local CUT = 0.5

-- Read the pixels the engine would actually blit. A LOVE Image does not hand
-- its data back, so it is drawn into a canvas of its own size and the canvas
-- is read -- which is also what makes this work for every path that produces
-- a pic, without knowing which one produced this one.
--
-- The canvas is forced to dpiscale = 1, and that is the whole difference
-- between a pic and a MONSTER. love.graphics.newCanvas defaults its dpiscale
-- to the surface's, conf.lua turns highdpi on for Android and iOS, and
-- Android's density is routinely 2.75 -- so newCanvas(56, 56) hands back a
-- 154x154 texture there, the pic is drawn into it magnified to fill it, and
-- newImageData reads the magnified copy back at its own PIXEL size. The image
-- built from that is 2.75x the artwork, drawPicsLayer draws it at 1:1 because
-- it trusts getWidth(), and the mon stands on the map nearly three times the
-- size of the square it is supposed to cover. Desktop never saw it: dpiscale
-- is already 1 there. Nor did every species, because only a pic with an
-- enclosed hole in it comes back through here at all (see `changed` below) --
-- so a Pidgey came out giant and the mon beside it did not, which is what
-- makes this read as a sprite bug rather than a scale one. See the engine's
-- own src/render/PixelCanvas.lua, which exists for exactly this reason.
local function readBack(img)
  local w, h = img:getDimensions()
  if w <= 0 or h <= 0 then return nil end
  local prevCanvas = love.graphics.getCanvas()
  local prevBlend, prevAlpha = love.graphics.getBlendMode()
  local prevR, prevG, prevB, prevA = love.graphics.getColor()
  local data = nil
  local ok = pcall(function()
    local canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
    love.graphics.setCanvas()
    data = canvas:newImageData()
    if canvas.release then pcall(canvas.release, canvas) end
  end)
  if prevCanvas then
    love.graphics.setCanvas(prevCanvas)
  else
    love.graphics.setCanvas()
  end
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  love.graphics.setColor(prevR or 1, prevG or 1, prevB or 1, prevA or 1)
  return ok and data or nil
end

-- The box the artwork actually occupies, or nil for a pic with no ink in it.
--
-- Not the image: a pic is centred in a 7x7-tile buffer and a small mon leaves
-- whole rows and columns of nothing around itself. The bottom of THIS box is
-- the cut the rule below turns on, and the bottom of the image is just empty
-- frame some distance under it.
local function inkBounds(data, w, h)
  local x0, y0, x1, y1 = w, h, -1, -1
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = data:getPixel(x, y)
      if a > CUT then
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
      end
    end
  end
  if x1 < x0 then return nil end
  return x0, y0, x1, y1
end

-- The colour the keyed-away shade would have had: the LIGHTEST colour still
-- standing in the pic.
--
-- Pure white is only the right answer while the pic is still grays, and by the
-- time it reaches here it usually is not. picImage hands a pic over AFTER the
-- bake -- a species SGB colour, a BGP fade mid-animation, PAL_BLACK for the
-- whole screen while the blackout text is up -- and shade 0 travels with the
-- rest. A white belly inside a blacked-out mon would be the one lit thing on a
-- dark screen; inside a warm-palette mon it would be a cold patch the artist
-- never drew.
--
-- So the paper is read off the pic rather than assumed, which needs shade 0 to
-- have survived somewhere in it. It always has: every one of this game's 151
-- back pics keeps at least one opaque shade-0 pixel -- a highlight down a
-- cheek, the white of an eye -- because only the shade-0 pixels the decoder
-- could reach were keyed. So what comes back is the baked shade 0 itself, not
-- an approximation of it, and it tracks every palette the engine picks without
-- being told which one that was.
--
-- Ranked by channel sum, which orders four DMG shades exactly: a palette maps
-- all three channels monotonically, so lightest by sum is lightest full stop.
local function paperColor(data, x0, y0, x1, y1)
  local best, pr, pg, pb = -1, nil, nil, nil
  for y = y0, y1 do
    for x = x0, x1 do
      local r, g, b, a = data:getPixel(x, y)
      if a > CUT then
        local lum = r + g + b
        if lum > best then best, pr, pg, pb = lum, r, g, b end
      end
    end
  end
  if best < 0 then return nil end
  return pr, pg, pb
end

-- The widest opening along the bottom of a figure that still counts as a drain
-- rather than a mouth. See the header for the measurements either side of it.
BattlePics.DRAIN = 6

-- Mark every transparent pixel the BACKGROUND can reach, flooding inward from
-- the edges of the artwork's box: the left, the right and the top whole, and
-- along the bottom only those openings wide enough to be background rather
-- than the underside of a figure the drawing ran out of -- or none of them at
-- all, for a pic whose feet are on the text box and which therefore has
-- nothing behind its lowest row to let in.
--
-- Confined to the box as well as seeded from it, so the empty frame under a
-- short pic cannot walk around a sealed drain and come back up through it.
--
-- An explicit stack rather than recursion: a 56x56 pic is three thousand
-- pixels and a keyed-out background is most of them, which is a deeper call
-- chain than is worth risking for no gain.
local function markOutside(data, w, h, x0, y0, x1, y1, sealBottom)
  local outside = {}
  local stack, top = {}, 0
  local function clear(x, y)
    local _, _, _, a = data:getPixel(x, y)
    return a <= CUT
  end
  local function push(x, y)
    if x < x0 or y < y0 or x > x1 or y > y1 then return end
    local key = y * w + x
    if outside[key] then return end
    if not clear(x, y) then return end
    outside[key] = true
    top = top + 1
    stack[top] = key
  end
  for x = x0, x1 do push(x, y0) end
  for y = y0, y1 do
    push(x0, y)
    push(x1, y)
  end
  -- the bottom, run by run: a wide one is the gap between two legs and lets
  -- the world through, a narrow one is where a belly ran out and is sealed.
  -- Skipped whole for a pic on the box, where even the widest of them has
  -- white paper behind it rather than arena.
  if not sealBottom then
    local x = x0
    while x <= x1 do
      if clear(x, y1) then
        local from = x
        while x <= x1 and clear(x, y1) do x = x + 1 end
        if (x - from) > BattlePics.DRAIN then
          for k = from, x - 1 do push(k, y1) end
        end
      else
        x = x + 1
      end
    end
  end
  while top > 0 do
    local key = stack[top]
    top = top - 1
    local x, y = key % w, math.floor(key / w)
    push(x - 1, y)
    push(x + 1, y)
    push(x, y - 1)
    push(x, y + 1)
  end
  return outside
end

-- The pic with its enclosed holes filled, or the pic itself when that could
-- not be done (no pixel access, a driver that refused the readback). Never
-- nil for a non-nil argument: a caller must always have something to draw.
--
-- sealBottom for a pic pinned to the text box rather than standing on the map:
-- see the header. A caller that does not say defaults to the map, which is
-- where all but one of this mod's pics are.
function BattlePics.filled(img, sealBottom)
  if not img then return img end
  sealBottom = sealBottom and true or false
  local slot = cache[sealBottom]
  local hit = slot[img]
  if hit ~= nil then return hit or img end

  local made = nil
  local ok = pcall(function()
    local data = readBack(img)
    if not data then return end
    local w, h = data:getDimensions()
    local x0, y0, x1, y1 = inkBounds(data, w, h)
    if not x0 then return end          -- a pic with nothing drawn in it
    local outside = markOutside(data, w, h, x0, y0, x1, y1, sealBottom)
    local fill = BattlePics.FILL
    local pr, pg, pb = paperColor(data, x0, y0, x1, y1)
    local fr = pr or fill[1]
    local fg = pg or fill[2]
    local fb = pb or fill[3]
    local changed = false
    -- only inside the box: everything beyond it is frame the artist never
    -- reached, and filling that would put the mon in a white rectangle
    for y = y0, y1 do
      local row = y * w
      for x = x0, x1 do
        if not outside[row + x] then
          local _, _, _, a = data:getPixel(x, y)
          if a <= CUT then
            data:setPixel(x, y, fr, fg, fb, fill[4])
            changed = true
          end
        end
      end
    end
    -- nothing enclosed: hand the original back rather than a copy of it
    if not changed then return end
    local out = love.graphics.newImage(data)
    out:setFilter("nearest", "nearest")
    made = out
  end)

  slot[img] = (ok and made) or false
  return made or img
end

function BattlePics.invalidate()
  cache = newCache()
end

return BattlePics
