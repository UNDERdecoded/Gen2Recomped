-- The into-battle transition (engine/battle/battle_transitions.asm):
-- one of the original's eight wipes selected by three bits,  trainer
-- battle (bit 0), enemy at least 3 levels above the lead (bit 1),
-- dungeon map (bit 2):
--   %000 DoubleCircle  %001 Spiral(in)  %010 Circle    %011 Spiral(out)
--   %100 HStripes      %101 Shrink      %110 VStripes  %111 Split
-- Only the two circle wipes flash the screen first (only they call
-- BattleTransition_FlashScreen); the spiral runs inward unless the
-- enemy is stronger (wBattleTransitionSpiralDirection).
-- Pushed above the overworld; pops itself and runs onDone at the end.

local Runtime = require("src.mods.Runtime")

local BattleTransition = {}
BattleTransition.__index = BattleTransition
BattleTransition.isOpaque = false -- draws over the frozen overworld

-- BattleTransition_FlashScreenPalettes: fade to black and back, then to
-- white and back; each palette held 2 frames, whole sequence played 3
-- times. Positive = black overlay strength, negative = white.
local FLASH_STEPS = { 1 / 3, 2 / 3, 1, 2 / 3, 1 / 3, 0,
                      -1 / 3, -2 / 3, -1, -2 / 3, -1 / 3, 0 }
local FLASH_HOLD = 2   -- frames per palette step
local FLASH_CYCLES = 3

-- The screen stays black after the wipe lands.  Shrink and Split ask for it
-- outright (BattleTransition_BlackScreen, then `ld c, 10 / jp DelayFrames`:
-- battle_transitions.asm:390-392 and 422-424); the other six get the same gap
-- for free, because BattleTransition_BlackScreen has already set rBGP/rOBP0/
-- rOBP1 to $ff (:168-174) while DoBattleTransitionAndInitBattleVariables
-- reloads the HUD tile patterns and clears the screen (core.asm:6152-6185),
-- InitBattleCommon decompresses the front pic (core.asm:6694-6730), and
-- SlidePlayerAndEnemySilhouettesOnScreen rebuilds the whole tilemap between
-- DisableLCD and EnableLCD (core.asm:9-49) before anything moves.  This port
-- has no load to hide behind, so the hold has to be explicit (#315).  This is
-- a frame budget for that work, not a number pokered states.
--
-- 60 comes from pokered-c (BTRANS_BLACK_HOLD_FRAMES), which itemized the
-- derivable floor at ~13 frames -- LoadHpBarAndStatusTilePatterns 4,
-- LoadHudTilePatterns 2, ClearScreen's Delay3 3, the DisableLCD LY wait 1,
-- Delay3 after EnableLCD 3 -- and then noted that the two sprite
-- decompressors (UncompressSpriteFromDE for the 7x7 front pic,
-- LoadPlayerBackPic's uncompress + ScaleSpriteByTwo) are bit-level RLE/delta
-- decoders whose cost cannot be cycle-counted from the asm at all.  So the
-- derivation bottoms out around 25-30 with an unbounded remainder, and 60
-- was set by ear against the real ROM ("a solid second") and confirmed as
-- ~95% right rather than frame-matched.  The credible range is 30-60; do NOT
-- "correct" this down toward the floor on the strength of the derivation,
-- because the omitted decompressors are exactly the unbounded part.  It
-- wants a frame-by-frame capture against hardware to pin exactly.
local BLACK_HOLD = 60
local FRLG_INTRO_FRAMES = 32
local FRLG_INTRO_GRAY = 11 / 31

local TILE = 8
local COLS, ROWS = 160 / TILE, 144 / TILE -- 20 x 18 tiles

-- outward spiral (%011): BattleTransition_OutwardSpiral_ walks from
-- (10,10) counterclockwise (right/up/left/down), turning whenever the
-- tile on its outer side is unfilled; 120 frames x 3 fills = 360 fills
-- on linear tilemap memory. At the screen edges the walk reads (and
-- fills) adjacent WRAM, so the left column and part of the top row stay
-- unfilled until the final blackout,  reproduced here by tracking those
-- cells but not drawing them.
local function outwardSpiralOrder()
  local order, filled = {}, {}
  local addr = 10 * COLS + 10 -- hlcoord 10,10
  local dir = 3               -- 0 up / 1 left / 2 down / 3 right
  local checkOff = { [0] = -1, [1] = COLS, [2] = 1, [3] = -COLS }
  local moveOff = { [0] = -COLS, [1] = -1, [2] = COLS, [3] = 1 }
  for _ = 1, COLS * ROWS do
    local checked = addr + checkOff[dir]
    if not filled[checked] then
      addr = checked
      dir = (dir + 1) % 4
    else
      addr = addr + moveOff[dir]
    end
    if not filled[addr] then
      filled[addr] = true
      if addr >= 0 and addr < COLS * ROWS then
        order[#order + 1] = { addr % COLS, math.floor(addr / COLS) }
      end
    end
  end
  return order
end

-- inward spiral (%001): BattleTransition_InwardSpiral starts at (0,0)
-- and walks the perimeter counterclockwise,  down the left edge, right
-- along the bottom, up the right edge, left along the top,  spiraling
-- in; 359 fills, the center tile is left for the final blackout
local function inwardSpiralOrder()
  local order = {}
  local x, y = 0, 0
  local function run(dx, dy, n)
    for _ = 1, n do
      order[#order + 1] = { x, y }
      x, y = x + dx, y + dy
    end
  end
  run(0, 1, 17) -- SCREEN_HEIGHT - 1
  local c = 18
  while true do
    c = c + 1
    run(1, 0, c)  -- right
    c = c - 2
    run(0, -1, c) -- up
    c = c + 1
    run(-1, 0, c) -- left
    c = c - 2
    if c == 0 then break end
    run(0, 1, c)  -- down
  end
  return order
end

-- sweep order (the Circle wipes): tiles sorted by angle from the center.
-- pokered sweeps counterclockwise starting at the right edge middle
-- (BattleTransition_HalfCircle1 runs (18,6) up over the top to (1,6);
-- HalfCircle2 continues (1,11) down under the bottom back to (18,11)).
-- arms = 1 (Circle, halves in sequence) or 2 (DoubleCircle, both halves
-- at once, so opposite arms)
local function sweepOrder(arms, cols, rows)
  cols, rows = cols or COLS, rows or ROWS
  local cx, cy = cols / 2, rows / 2
  local tiles = {}
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local a = math.atan2(cy - (y + 0.5), x + 0.5 - cx)
      if a < 0 then a = a + 2 * math.pi end
      if arms == 2 then a = a % math.pi end
      tiles[#tiles + 1] = { x, y, a }
    end
  end
  table.sort(tiles, function(p, q) return p[3] < q[3] end)
  return tiles
end

-- ---------------------------------------------------------------------
-- Arbitrary-grid wipes, for the surface OUTSIDE the classic letterbox
-- ---------------------------------------------------------------------
--
-- The builders above reproduce the ROM's exact walks on its 20x18 tilemap,
-- overrun and all, and stay the authority inside the 160x144 box.  A zoomed
-- or windowed surface has more grid than the Game Boy ever had, and no
-- hardware behaviour to be faithful to out there -- but filling it with a
-- generic square cascade made a spiral read as "a spiral in a box, with
-- something else happening around it".  These generalise the same shapes to
-- whatever grid the window works out to so the whole surface wipes as one
-- figure.

-- perimeter inward, counterclockwise, starting down the left edge -- the
-- direction BattleTransition_InwardSpiral walks
local function spiralInGrid(cols, rows)
  local order = {}
  local x0, y0, x1, y1 = 0, 0, cols - 1, rows - 1
  while x0 <= x1 and y0 <= y1 do
    for y = y0, y1 do order[#order + 1] = { x0, y } end
    x0 = x0 + 1
    if x0 > x1 then break end
    for x = x0, x1 do order[#order + 1] = { x, y1 } end
    y1 = y1 - 1
    if y0 > y1 then break end
    for y = y1, y0, -1 do order[#order + 1] = { x1, y } end
    x1 = x1 - 1
    if x0 > x1 then break end
    for x = x1, x0, -1 do order[#order + 1] = { x, y0 } end
    y0 = y0 + 1
  end
  return order
end

-- the outward spiral is the same walk read from the middle out
local function spiralOutGrid(cols, rows)
  local inward = spiralInGrid(cols, rows)
  local order = {}
  for i = #inward, 1, -1 do order[#order + 1] = inward[i] end
  return order
end

-- ---------------------------------------------------------------------------
-- HOENN'S OWN WIPES
--
-- Reported from play: "also seem to be missing a lot of the battle
-- transitions from emerald that play when you start a wild encounter or
-- trainer battle".  They were missing, and deliberately: the pair above this
-- are FADES, because a fade is the one shape that ports exactly, and the note
-- there says the showier ones "are a feature rather than a fix".  This is
-- that feature.
--
-- WHAT THESE ARE AND ARE NOT.  Emerald's transitions are scanline and palette
-- tricks -- a real slice shears the BG registers line by line, a real ripple
-- is a sine table written into BGHOFS every scanline.  This engine composites
-- whole frames, so none of those can be replayed literally.  What CAN be
-- replayed is the FIGURE each one draws: the order the screen goes dark in.
-- That is what the wipe machinery already expresses -- a walk over the tile
-- grid -- and it is why the Game Boy's eight look right here at any window
-- size.  So each of these is Emerald's figure on this engine's wipe, and the
-- name says which cartridge transition it is standing in for.
--
-- Every one is written against an arbitrary cols x rows grid rather than
-- against 20x18, so they are continuous out through the letterbox like the
-- rest (see Renderer:drawBattleWipe).

-- B_TRANSITION_GRID_SQUARES: the screen breaks up into squares rather than
-- being swept.  An ordered (Bayer) threshold is the honest way to write that
-- as a walk -- it scatters without being random, so it looks the same every
-- time, which the cartridge's does too.
local BAYER4 = {
  {  0,  8,  2, 10 },
  { 12,  4, 14,  6 },
  {  3, 11,  1,  9 },
  { 15,  7, 13,  5 },
}

local function gridSquaresOrder(cols, rows)
  local buckets = {}
  for i = 0, 15 do buckets[i] = {} end
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local b = BAYER4[y % 4 + 1][x % 4 + 1]
      buckets[b][#buckets[b] + 1] = { x, y }
    end
  end
  local order = {}
  for i = 0, 15 do
    for _, t in ipairs(buckets[i]) do order[#order + 1] = t end
  end
  return order
end

-- B_TRANSITION_SLICE: every row moves at once, and neighbouring rows move
-- OPPOSITE WAYS -- that counter-shear is the whole look.  Walking one row at
-- a time would read as a set of stripes instead, so the walk is column-major:
-- one tile from every row, then the next, which advances all of them together.
local function sliceOrder(cols, rows)
  local order = {}
  for step = 0, cols - 1 do
    for y = 0, rows - 1 do
      local x = (y % 2 == 0) and step or (cols - 1 - step)
      order[#order + 1] = { x, y }
    end
  end
  return order
end

-- B_TRANSITION_ANGLED_WIPES: a diagonal front crossing the screen.  The band
-- is two tiles of run per tile of drop, which is the slope the cartridge's
-- wipes lean at.
local ANGLE_RUN = 2

local function angledOrder(cols, rows)
  local bands = {}
  local most = cols + rows * ANGLE_RUN
  for i = 0, most do bands[i] = {} end
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local k = x + y * ANGLE_RUN
      bands[k][#bands[k] + 1] = { x, y }
    end
  end
  local order = {}
  for i = 0, most do
    for _, t in ipairs(bands[i] or {}) do order[#order + 1] = t end
  end
  return order
end

-- B_TRANSITION_BIG_POKEBALL: a ball opens out of the middle of the screen.
-- As a walk that is tiles in order of distance from the centre -- a disc
-- growing rather than a sweep going round, which is what tells it apart from
-- `circle` above.
local function pokeballOrder(cols, rows)
  local cx, cy = (cols - 1) / 2, (rows - 1) / 2
  -- the grid is tiles, and a tile is square, so the two axes are already in
  -- the same units; no aspect correction belongs here
  local list = {}
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local dx, dy = x - cx, y - cy
      list[#list + 1] = { x, y, dx * dx + dy * dy }
    end
  end
  table.sort(list, function(a, b)
    if a[3] ~= b[3] then return a[3] < b[3] end
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  local order = {}
  for _, t in ipairs(list) do order[#order + 1] = { t[1], t[2] } end
  return order
end

-- B_TRANSITION_SHUFFLE: the screen's tiles are dealt out rather than swept.
-- A hash rather than a random draw, so the same battle always shuffles the
-- same way, which is what the cartridge's own permutation does.
local function shuffleOrder(cols, rows)
  local list = {}
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      -- a cheap integer hash: multiply, mix the halves, keep it deterministic
      local h = (x * 73856093 + y * 19349663) % 1048573
      h = (h * 2654435761) % 1048573
      list[#list + 1] = { x, y, h }
    end
  end
  table.sort(list, function(a, b)
    if a[3] ~= b[3] then return a[3] < b[3] end
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  local order = {}
  for _, t in ipairs(list) do order[#order + 1] = { t[1], t[2] } end
  return order
end

-- B_TRANSITION_RIPPLE: rings spreading out from the middle of the screen,
-- which is what a sine written down the scanlines reads as.  Ordered by
-- distance from the middle ROW rather than from a point: the cartridge's
-- ripple moves the rows, not the pixels.
local function rippleOrder(cols, rows)
  local mid = (rows - 1) / 2
  local bands = {}
  for y = 0, rows - 1 do
    local d = math.floor(math.abs(y - mid))
    bands[d] = bands[d] or {}
    for x = 0, cols - 1 do
      bands[d][#bands[d] + 1] = { x, y }
    end
  end
  local order = {}
  for d = 0, rows do
    for _, t in ipairs(bands[d] or {}) do order[#order + 1] = t end
  end
  return order
end

-- B_TRANSITION_WAVE: a front crossing the screen whose edge is a sine, so it
-- arrives at different columns at different times down the screen.
local WAVE_ROWS = 8              -- one whole wave over this many rows
local WAVE_LEAN = 3              -- how many columns the crest runs ahead

local function waveOrder(cols, rows)
  local bands = {}
  local most = cols + WAVE_LEAN * 2 + 2
  for i = 0, most do bands[i] = {} end
  for y = 0, rows - 1 do
    local lead = math.floor(WAVE_LEAN
                            * math.sin(y / WAVE_ROWS * 2 * math.pi) + 0.5)
    for x = 0, cols - 1 do
      local k = math.max(0, math.min(most, x - lead + WAVE_LEAN))
      bands[k][#bands[k] + 1] = { x, y }
    end
  end
  local order = {}
  for i = 0, most do
    for _, t in ipairs(bands[i] or {}) do order[#order + 1] = t end
  end
  return order
end

-- B_TRANSITION_POKEBALLS_TRAIL: balls cross the screen one row band at a
-- time and the dark follows them, so the walk is a shallow diagonal -- much
-- shallower than the shards' (ANGLE_RUN), because a ball travels far across
-- for every row it drops.
local TRAIL_RUN = 6

local function trailOrder(cols, rows)
  local bands = {}
  local most = cols + rows * TRAIL_RUN
  for i = 0, most do bands[i] = {} end
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local k = (y % 2 == 0) and (x + y * TRAIL_RUN)
                or ((cols - 1 - x) + y * TRAIL_RUN)
      bands[k][#bands[k] + 1] = { x, y }
    end
  end
  local order = {}
  for i = 0, most do
    for _, t in ipairs(bands[i] or {}) do order[#order + 1] = t end
  end
  return order
end

local GRID_BUILDERS = {
  spiralin     = spiralInGrid,
  spiralout    = spiralOutGrid,
  circle       = function(c, r) return sweepOrder(1, c, r) end,
  doublecircle = function(c, r) return sweepOrder(2, c, r) end,
  g3_grid      = gridSquaresOrder,
  g3_slice     = sliceOrder,
  g3_angled    = angledOrder,
  g3_pokeball  = pokeballOrder,
  -- the rest of the cartridge's twenty-five (see GEN3_STYLE_FOR below)
  g3_swirl              = spiralInGrid,
  g3_shuffle            = shuffleOrder,
  g3_clockwiseBlackfade = function(c, r) return sweepOrder(1, c, r) end,
  g3_ripple             = rippleOrder,
  g3_wave               = waveOrder,
  g3_pokeballsTrail     = trailOrder,
  g3_mugshot            = angledOrder,
}

-- Tile order for `style` on an arbitrary cols x rows grid, or nil for the
-- styles whose shape is plain geometry (stripes / shrink / split) and which
-- the caller extends with rectangles instead.  Cached per style+size: the
-- window grid only changes on a resize or a zoom step.
local orderFor -- defined below; the authentic 20x18 builders

local gridCache = {}
function BattleTransition.gridOrder(style, cols, rows)
  local build = GRID_BUILDERS[style]
  if not build or cols < 1 or rows < 1 then return nil end
  -- At exactly the Game Boy's grid the ROM's own walk is the answer, overrun
  -- and all -- so an unzoomed window is the classic wipe, not a lookalike.
  --
  -- ...FOR THE STYLES THAT HAVE ONE.  This used to return whatever orderFor
  -- answered, which is nil for any style with no builtin 20x18 walk -- so a
  -- wipe added later (Hoenn's four below) would draw NOTHING at exactly that
  -- grid and be correct at every other size, which is the worst shape a bug
  -- can have.  A style with no classic walk falls through to its builder.
  if cols == COLS and rows == ROWS then
    local classic = orderFor(style, nil)
    if classic then return classic end
  end
  local key = style .. ":" .. cols .. "x" .. rows
  local hit = gridCache[key]
  if hit == nil then
    hit = build(cols, rows) or false
    gridCache[key] = hit
  end
  return hit or nil
end

-- Wipe lengths, taken from pokered-c's battle_transition.c frame budget --
-- derived from battle_transitions.asm and then checked on a live
-- side-by-side against the ROM.  Each wipe is `steps x frames-per-step`:
--
--   DoubleCircle   10 x 3 =  30      SpiralOut  360 fills / 3 per frame = 120
--   Circle         20 x 3 =  60      HStripes    20 x 3 = 60
--   Shrink          9 x 6 =  54      VStripes    18 x 3 = 54
--   Split           9 x 6 =  54      (asm:386-392 and :418-424)
--
-- The port used a flat 40/24 for all eight, which ran every wipe between
-- 1.5x and 3x too fast -- the single biggest reason a battle used to open
-- so much more abruptly here than on hardware.
--
-- The inward spiral is the one that bites.  It writes one tile per
-- iteration and calls BattleTransition_TransferDelay3 every seventh tile
-- (wInwardSpiralUpdateScreenCounter counts 7 down to 0), and that helper is
-- `ld a,1 / ldh [hAutoBGTransferEnabled] / call Delay3 / xor a / ldh [...]`
-- (battle_transitions.asm:619) -- THREE frames, not a one-frame transfer.
-- Reading it as one frame runs the whole spiral 3x too fast; pokered-c
-- caught that against the real ROM.  Deriving the length from the path we
-- actually walk keeps the cadence right if the order ever changes.
local SPIRAL_IN_TILES_PER_STEP = 7
local SPIRAL_IN_STEP_FRAMES = 3 -- TransferDelay3
local SPIRAL_IN_FRAMES = math.ceil(#inwardSpiralOrder()
                                   / SPIRAL_IN_TILES_PER_STEP)
                         * SPIRAL_IN_STEP_FRAMES

-- The eight wipes as records: frames is the wipe length, flash marks the
-- two circle wipes that call BattleTransition_FlashScreen first.  new()
-- reads them, and the transitions registry serves the same table.
-- ---------------------------------------------------------------------------
-- THE TWO THAT ARE NOT THE GAME BOY'S.
--
-- Reported from play: "Gen 1 Battle Transition instead of Gen3s".  Exactly
-- right, and the reason is that there was nothing else to pick: the Gen 3
-- extractor writes no `transitions` table at all, so an Emerald battle fell
-- all the way through styleDef to the eight pokered wipes below, chosen by
-- pokered's own three-bit rule.  Every battle in Hoenn opened with a Game Boy
-- spiral.
--
-- These two are fades, and a fade is the one shape that ports EXACTLY: it is
-- a veil over every pixel the screen shows, which is what Renderer.screenVeil
-- already is -- so they are correct at any window size and any zoom, with no
-- letterbox to escape from. Emerald's showier transitions (the slice, the
-- mosaic, the ripple, the big Poke Ball) are scanline and palette effects and
-- are a feature rather than a fix; they are NOT covered here.
--
-- What this does buy: no Gen 3 battle opens with a Game Boy wipe any more.
local function fadeDraw(shade)
  return function(self, prog)
    local r = self.game and self.game.renderer
    -- out to the shade over the first half, then down to black -- which is
    -- what the screen is holding when the battle draws its first frame
    local a, s
    if prog < 0.5 then a, s = prog / 0.5, shade
    else a, s = 1, shade * (1 - (prog - 0.5) / 0.5) end
    if r then r.screenVeil = { s, a } return end
    love.graphics.setColor(s, s, s, a)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- RECONSTRUCTED LENGTHS.  The Game Boy's eight are derived above -- steps
-- times frames per step, off the routines themselves.  These four cannot be
-- derived the same way: the routines they stand in for count scanlines rather
-- than tiles, so there is no step count to multiply.  They are timed to sit
-- in the same band as the wipes beside them -- about a second -- and they are
-- listed as records so a mod, or a later derivation, can retime them without
-- touching this file.
-- ---------------------------------------------------------------------------
-- FIRERED'S OWN (pokefirered src/battle_transition.c), drawn over the whole
-- window rather than on a tile grid.  Each receives the wipe record, 0..1
-- progress and the window size in pixels.
-- ---------------------------------------------------------------------------
local function frlgSlice(_, prog, ww, wh, _, Sy)
  -- B_TRANSITION_SLICE: alternate scanlines slide off opposite edges,
  -- accelerating, and leave black behind
  local line = math.max(1, Sy or 1)
  local off = ww * prog * prog
  local y, i = 0, 0
  love.graphics.setColor(0, 0, 0, 1)
  while y < wh do
    if i % 2 == 0 then love.graphics.rectangle("fill", 0, y, off, line)
    else love.graphics.rectangle("fill", ww - off, y, off, line) end
    y, i = y + line, i + 1
  end
end

local function frlgWhiteBars(_, prog, ww, wh)
  -- B_TRANSITION_WHITE_BARS_FADE: eight white bars sweep across one after
  -- another, then the white screen fades down to black
  local bars = 8
  local bh = wh / bars
  if prog < 0.55 then
    local p = prog / 0.55
    love.graphics.setColor(1, 1, 1, 1)
    for b = 0, bars - 1 do
      local start = b / (bars + 2)
      local q = math.max(0, math.min(1, (p - start) / 0.35))
      local w = ww * q
      if b % 2 == 0 then love.graphics.rectangle("fill", ww - w, b * bh, w, bh + 1)
      else love.graphics.rectangle("fill", 0, b * bh, w, bh + 1) end
    end
  else
    local s = 1 - (prog - 0.55) / 0.45
    love.graphics.setColor(s, s, s, 1)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
  end
end

local function frlgClockwise(_, prog, ww, wh)
  -- B_TRANSITION_CLOCKWISE_WIPE: a black sweep round from twelve o'clock
  local cx, cy = ww / 2, wh / 2
  local r = math.sqrt(cx * cx + cy * cy) + 2
  love.graphics.setColor(0, 0, 0, 1)
  if prog > 0 then
    love.graphics.arc("fill", "pie", cx, cy, r, -math.pi / 2,
                      -math.pi / 2 + 2 * math.pi * prog, 64)
  end
end

local ballSheetCache = {}
local function frlgPokeballsTrail(wipe, prog, ww, wh)
  -- B_TRANSITION_POKEBALLS_TRAIL: Poke Balls roll across the screen in five
  -- rows, alternately from each side, each dragging black behind it
  local rows = 5
  local rh = wh / rows
  local data = wipe.game and wipe.game.data
  local rec = data and data.constants and data.constants.gen3BallAnim
  local path = rec and rec.images and rec.images.balls
  local sheet = path and ballSheetCache[path]
  if path and sheet == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    sheet = ok and img or false
    ballSheetCache[path] = sheet
  end
  for row = 0, rows - 1 do
    local start = ({ 0, 0.3, 0.12, 0.42, 0.22 })[row + 1]
    local q = math.max(0, math.min(1, (prog - start) / (1 - 0.45)))
    local x = (ww + rh) * q
    local fromLeft = row % 2 == 0
    local y = row * rh
    love.graphics.setColor(0, 0, 0, 1)
    if fromLeft then love.graphics.rectangle("fill", 0, y, math.max(0, x - rh / 2), rh + 1)
    else love.graphics.rectangle("fill", ww - math.max(0, x - rh / 2), y, math.max(0, x - rh / 2), rh + 1) end
    if q > 0 and q < 1 and sheet then
      local size = rec.size or 16
      local iw, ih = sheet:getDimensions()
      local bx = fromLeft and (x - rh) or (ww - x)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(sheet, love.graphics.newQuad(0, 0, size, size, iw, ih),
                         bx + rh / 2, y + rh / 2, (fromLeft and 1 or -1) * q * 12,
                         rh / size, rh / size, size / 2, size / 2)
    end
  end
end

-- B_TRANSITION_SWIRL is not a spiral-shaped blackout.  FireRed writes one
-- sine-derived BG horizontal offset per scanline while a normal palette fade
-- takes the entire screen to black (battle_transition.c Task_Swirl).
--
-- source is an untouched snapshot of the renderer's finished world+UI
-- composite.  Redrawing one scanline band at its HBlank offset is the direct
-- whole-frame equivalent of writing BG1HOFS/BG2HOFS/BG3HOFS on each scanline.
local swirlQuads = {}
local function frlgSin(index, amplitude)
  -- trig.c stores sin(index*pi/128) as Q8.8 truncated toward zero, then Sin()
  -- multiplies by the amplitude and arithmetic-shifts by 8.  Keeping those
  -- two quantization steps matters once the wave grows past a few pixels.
  local s = math.sin((index % 256) * (2 * math.pi / 256)) * 256
  local q = s < 0 and math.ceil(s) or math.floor(s)
  return math.floor(amplitude * q / 256)
end

local function frlgSwirlFade(age)
  -- BeginNormalPaletteFade(PALETTES_ALL, 4, 0, 16, RGB_BLACK) updates BG and
  -- OBJ palettes on alternating calls.  With delay 4, both halves have
  -- completed the next +2 blend step every six main-transition frames:
  -- t=6,12,...,48.  A single composited canvas cannot split BG/OBJ by the one
  -- intervening frame, so use the coefficient once both palette halves agree.
  return math.min(1, math.floor(age / 6) * 2 / 16)
end

local function frlgSwirl(wipe, prog, ww, wh, Sx, Sy, source, ox, oy, vpw, vph)
  local age = math.max(0, tonumber(wipe.t) or 0)
  local fade = frlgSwirlFade(age)
  if not (source and source.getDimensions) then
    love.graphics.setColor(0, 0, 0, fade)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
    return
  end
  local sw, sh = source:getDimensions()
  local sinIndex = age * 4
  local amplitude = age * 8
  love.graphics.setColor(1, 1, 1, 1)
  -- Renderer supplies a screen-sized frozen composite.  Continue the 160-line
  -- HBlank wave through any extended world area outside the native viewport,
  -- keeping line 0 phase-locked to the top of the 240x160 playfield.  This is
  -- the same whole-window extension used by the other FireRed transitions.
  if math.abs(sw - ww) < 0.01 and math.abs(sh - wh) < 0.01 then
    local line = math.max(0.01, Sy or 1)
    local first = math.floor(-oy / line)
    local last = math.ceil((wh - oy) / line) - 1
    for scan = first, last do
      local y0 = math.max(0, oy + scan * line)
      local y1 = math.min(wh, oy + (scan + 1) * line)
      local offset = frlgSin(sinIndex + scan * 2, amplitude)
      local dx = (offset * (Sx or 1)) % ww
      if y1 > y0 then
        -- Clip the untouched whole frame to this scanline band instead of
        -- building texture quads.  Canvas texture resolution can differ from
        -- its LOVE-unit dimensions on high-DPI displays, while target scissor
        -- coordinates stay in the same units as ww/wh.
        love.graphics.setScissor(0, y0, ww, y1 - y0)
        -- Hardware BGs wrap.  Three copies cover the surface for either sign.
        love.graphics.draw(source, -dx, 0)
        love.graphics.draw(source, -dx + ww, 0)
        love.graphics.draw(source, -dx - ww, 0)
      end
    end
    love.graphics.setScissor(0, 0, ww, wh)
  else
    -- Headless/legacy fallback: a native GBA canvas scales into the viewport.
    local key = sw .. "x" .. sh
    local quads = swirlQuads[key]
    if not quads then
      quads = {}
      for y = 0, sh - 1 do
        quads[y + 1] = love.graphics.newQuad(0, y, sw, 1, sw, sh)
      end
      swirlQuads[key] = quads
    end
    local sx = vpw / sw
    local sy = vph / sh
    love.graphics.rectangle("fill", ox, oy, vpw, vph)
    for y = 0, sh - 1 do
      local offset = frlgSin(sinIndex + y * 2, amplitude)
      local dx = (offset * sx) % vpw
      local dy = oy + y * sy
      love.graphics.draw(source, quads[y + 1], ox - dx, dy, 0, sx, sy)
      love.graphics.draw(source, quads[y + 1], ox - dx + vpw, dy, 0, sx, sy)
      love.graphics.draw(source, quads[y + 1], ox - dx - vpw, dy, 0, sx, sy)
    end
  end
  -- The renderer has no palette RAM, so the source cadence above is applied as
  -- one full-screen veil after the scanline offsets have been drawn.
  love.graphics.setColor(0, 0, 0, fade)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
end

-- THE ONES THAT DRAW A PICTURE, which is five of the cartridge's own
-- backgrounds and three silhouettes.
--
-- The team logos, the three Regi dot faces and the big Poke Ball are real
-- 4bpp backgrounds in the image and the import composes them
-- (gen3BattleTransitions.pictures).  Groudon, Kyogre and Rayquaza have no
-- background of their own -- their transitions are scanline and palette work
-- -- so they take the one picture of themselves this dataset does have, the
-- front sprite, as a silhouette over their own colour.  The COLOURS are this
-- file's; everything else on the screen is the cartridge's.
local LEGEND_TINT = {
  kyogre   = { 0.11, 0.24, 0.62 },
  groudon  = { 0.62, 0.16, 0.11 },
  rayquaza = { 0.10, 0.42, 0.24 },
}

local function transitionPicture(game, id)
  local data = game and game.data
  local record = data and data.constants and data.constants.gen3BattleTransitions
  local pic = record and record.pictures and record.pictures[id]
  if not (pic and pic.image) then return nil end
  local ok, image = pcall(require("src.render.Assets").image, pic.image)
  return ok and image or nil
end

local function transitionMon(game, species)
  local data = game and game.data
  if not (data and species) then return nil end
  local ok, path = pcall(function()
    return require("src.pokemon.Sprites").path(data, species, "front")
  end)
  if not (ok and type(path) == "string") then return nil end
  local okImg, image = pcall(require("src.render.Assets").image, path)
  return okImg and image or nil
end

-- opts: picture (an id in the dataset), species (a silhouette), tint (rgb)
local function pictureDraw(opts)
  return function(self, prog)
    local Gen3Wide = require("src.ui.Gen3Wide")
    local W, H = Gen3Wide.uiSize()
    W = tonumber(W) or 240
    H = tonumber(H) or 160
    local tint = opts.tint or { 0, 0, 0 }
    -- the colour floods first, the figure rides over it, and the whole thing
    -- goes down to black in the last fifth -- which is what the battle's
    -- first frame is drawn against
    local flood = math.min(1, prog / 0.35)
    love.graphics.setColor(tint[1], tint[2], tint[3], flood)
    love.graphics.rectangle("fill", 0, 0, W, H)
    local image = opts.picture and transitionPicture(self.game, opts.picture)
                  or (opts.species and transitionMon(self.game, opts.species))
    if image and prog > 0.15 then
      local iw, ih = image:getDimensions()
      local age = math.min(1, (prog - 0.15) / 0.55)
      -- it comes in at three quarters and settles, with one pulse of alpha so
      -- it reads as flashing rather than sliding
      local scale = (0.75 + 0.25 * age) * math.min(W / iw, H / ih)
      if opts.species then scale = scale * 2.2 end
      local a = 1
      if prog < 0.3 then a = (prog - 0.15) / 0.15 end
      if opts.species then
        love.graphics.setColor(0, 0, 0, a * 0.85)
      else
        love.graphics.setColor(1, 1, 1, a)
      end
      love.graphics.draw(image, W / 2, H / 2, 0, scale, scale, iw / 2, ih / 2)
    end
    if prog > 0.8 then
      love.graphics.setColor(0, 0, 0, (prog - 0.8) / 0.2)
      love.graphics.rectangle("fill", 0, 0, W, H)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

BattleTransition.STYLES = {
  frlg_slice    = { kind = "wipe", frames = 50, screen = frlgSlice },
  frlg_whitebars = { kind = "wipe", frames = 70, screen = frlgWhiteBars },
  frlg_clockwise = { kind = "wipe", frames = 50, screen = frlgClockwise },
  frlg_balltrail = { kind = "wipe", frames = 60, screen = frlgPokeballsTrail },
  -- The palette reaches black on t=48, then palette.c spends five finishing
  -- updates before gPaletteFade.active clears.  Task_Swirl sees that on the
  -- following RunTasks call, so the main task disappears at t=54.
  frlg_swirl     = { kind = "wipe", frames = 48, blackHold = 6,
                     screen = frlgSwirl },
  g3_whitefade = { kind = "fade", frames = 48, draw = fadeDraw(1) },
  g3_blackfade = { kind = "fade", frames = 48, draw = fadeDraw(0) },
  g3_grid      = { kind = "wipe", frames = 48 },
  g3_slice     = { kind = "wipe", frames = 42 },
  g3_angled    = { kind = "wipe", frames = 48 },
  g3_pokeball  = { kind = "wipe", frames = 54, flash = true },
  -- ...and the rest of Emerald's twenty-five
  g3_blur               = { kind = "fade", frames = 54, draw = fadeDraw(0) },
  g3_swirl              = { kind = "wipe", frames = 48 },
  g3_shuffle            = { kind = "wipe", frames = 48 },
  g3_clockwiseBlackfade = { kind = "wipe", frames = 54 },
  g3_ripple             = { kind = "wipe", frames = 48 },
  g3_wave               = { kind = "wipe", frames = 48 },
  g3_pokeballsTrail     = { kind = "wipe", frames = 54, flash = true },
  g3_bigPokeball = { kind = "picture", frames = 60, flash = true,
                     draw = pictureDraw({ picture = "bigPokeball",
                                          tint = { 1, 1, 1 } }) },
  g3_aqua      = { kind = "picture", frames = 60,
                   draw = pictureDraw({ picture = "aqua",
                                        tint = { 0.09, 0.16, 0.55 } }) },
  g3_magma     = { kind = "picture", frames = 60,
                   draw = pictureDraw({ picture = "magma",
                                        tint = { 0.55, 0.10, 0.10 } }) },
  g3_regice    = { kind = "picture", frames = 60,
                   draw = pictureDraw({ picture = "regice",
                                        tint = { 0.10, 0.10, 0.16 } }) },
  g3_registeel = { kind = "picture", frames = 60,
                   draw = pictureDraw({ picture = "registeel",
                                        tint = { 0.10, 0.10, 0.16 } }) },
  g3_regirock  = { kind = "picture", frames = 60,
                   draw = pictureDraw({ picture = "regirock",
                                        tint = { 0.10, 0.10, 0.16 } }) },
  g3_kyogre    = { kind = "picture", frames = 66,
                   draw = pictureDraw({ species = "KYOGRE",
                                        tint = LEGEND_TINT.kyogre }) },
  g3_groudon   = { kind = "picture", frames = 66,
                   draw = pictureDraw({ species = "GROUDON",
                                        tint = LEGEND_TINT.groudon }) },
  g3_rayquaza  = { kind = "picture", frames = 66,
                   draw = pictureDraw({ species = "RAYQUAZA",
                                        tint = LEGEND_TINT.rayquaza }) },
  -- the five mugshot transitions (Sidney, Phoebe, Glacia, Drake, the
  -- Champion) have no background of their own either; they get the shards'
  -- figure with the flash in front of it, which is the shape they share
  g3_mugshot   = { kind = "wipe", frames = 54, flash = true },
  doublecircle = { kind = "wipe", frames = 30, flash = true },
  spiralin     = { kind = "wipe", frames = SPIRAL_IN_FRAMES },
  circle       = { kind = "wipe", frames = 60, flash = true },
  spiralout    = { kind = "wipe", frames = 120 },
  hstripes     = { kind = "wipe", frames = 60 },
  shrink       = { kind = "wipe", frames = 54 },
  vstripes     = { kind = "wipe", frames = 54 },
  split        = { kind = "wipe", frames = 54 },
}

-- EVERY ID THE CARTRIDGE CAN CHOOSE, BY ITS OWN NAME FOR IT.
--
-- The import writes the names in the cartridge's order (the enum is pinned
-- twice over -- see RomExtractorGen3.BATTLE_TRANSITIONS), and this is the one
-- place that says which figure in this engine stands for each of them.  Four
-- of them reuse a style that was already here: whiteBarsFade is the white
-- fade, gridSquares the ordered grid, shards the angled wipe, slice the
-- counter-shear.  The five mugshot transitions share one, because on the
-- cartridge they share a routine and differ only in whose face is on it.
local GEN3_STYLE_FOR = {
  blur = "g3_blur",
  swirl = "g3_swirl",
  shuffle = "g3_shuffle",
  bigPokeball = "g3_bigPokeball",
  pokeballsTrail = "g3_pokeballsTrail",
  clockwiseBlackfade = "g3_clockwiseBlackfade",
  ripple = "g3_ripple",
  wave = "g3_wave",
  slice = "g3_slice",
  whiteBarsFade = "g3_whitefade",
  gridSquares = "g3_grid",
  shards = "g3_angled",
  sidney = "g3_mugshot", phoebe = "g3_mugshot", glacia = "g3_mugshot",
  drake = "g3_mugshot", champion = "g3_mugshot",
  aqua = "g3_aqua", magma = "g3_magma",
  regice = "g3_regice", registeel = "g3_registeel", regirock = "g3_regirock",
  kyogre = "g3_kyogre", groudon = "g3_groudon", rayquaza = "g3_rayquaza",
}
BattleTransition.GEN3_STYLE_FOR = GEN3_STYLE_FOR

-- the eight wipes plus Transition's two warp fades: one registrant owns
-- the whole transitions namespace, so Builtins wires it once
function BattleTransition.registerInto(registry, data, owner)
  for id, record in pairs(BattleTransition.STYLES) do
    registry:register(id, record, owner)
  end
  require("src.render.Transition").registerInto(registry, data, owner)
end

-- the merged record; the built-in table is the fallback for headless
-- callers and for any state built before Data:load
local function styleDef(game, style)
  local data = game and game.data
  local record = data and data.transitions and data.transitions[style]
  return record or BattleTransition.STYLES[style]
end

local ORDERS = {} -- cached per style

local BUILTIN_ORDERS = {
  spiralout = outwardSpiralOrder,
  spiralin = inwardSpiralOrder,
  circle = function() return sweepOrder(1) end,
  doublecircle = function() return sweepOrder(2) end,
}

-- A registered style may bring its own tile order (a list of {x, y}, or a
-- function returning one); the four built-in orders are the defaults for
-- the styles that have always had them.
function orderFor(style, def)
  if ORDERS[style] == nil then
    local order = def and def.order
    if type(order) == "function" then
      local ok, built = pcall(order)
      order = ok and built or nil
    end
    if type(order) ~= "table" then
      local build = BUILTIN_ORDERS[style]
      order = build and build() or false
    end
    ORDERS[style] = order or false
  end
  return ORDERS[style] or nil
end

-- the vanilla 3-bit select (battle_transitions.asm), and the default of
-- the transition.style hook a mod wraps to choose its own wipe
local BIT_STYLES = { [0] = "doublecircle", "spiralin", "circle", "spiralout",
                     "hstripes", "shrink", "vstripes", "split" }

-- WHICH OF EMERALD'S TWENTY-FIVE PLAYS, AND IT IS THE CARTRIDGE THAT SAYS.
--
-- Asked for directly: "Ensure all emerald battle transitions are extracted and
-- used in the engine when theyre supposed to be used based on the actual rom
-- data Including the special legendary transitions as well".
--
-- What used to be here was four figures and a four-way choice written by hand,
-- with a note saying "when the table is read, only this function changes".
-- The table is read now (RomExtractorGen3.BATTLE_TRANSITIONS writes
-- gen3BattleTransitions), so this is that change.
--
-- THE ORDER THE CARTRIDGE ASKS ITS QUESTIONS IN, and it matters -- every one
-- of these runs BEFORE the table is reached:
--
--   a legendary wild battle          BattleSetup_StartLegendaryBattle 00B0934
--                                    StartRegiBattle 00B0A74
--   a Secret Base trainer            GetTrainerBattleTransition 00B0F34
--   an Elite Four / Champion trainer         "
--   a Team Aqua / Team Magma trainer         "
--   otherwise the table, indexed [map type][the lead outclasses the foe]
--
-- and the last of those is a PLAIN COMPARISON of levels, not the Game Boy's
-- three-level margin: `if (enemyLevel < playerLevel)`.  The old code passed a
-- pre-computed `stronger` with the margin baked in, so this takes the levels
-- when it is given them and falls back to the flag when it is not.
local function nameToStyle(name)
  if type(name) ~= "string" then return nil end
  return GEN3_STYLE_FOR[name]
end

local function gen3Record(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local record = data and data.constants and data.constants.gen3BattleTransitions
  if type(record) ~= "table" or type(record.wild) ~= "table" then return nil end
  return record
end

-- GetBattleTransitionTypeByMap's four answers.  The caller works them out --
-- it is the one that can see the map, the flash level and the water -- and
-- this only has to cope with not being told.
local function gen3MapType(ctx, record)
  local t = tonumber(ctx and ctx.mapTransitionType)
  if t and t >= 0 and t < #record.wild then return t end
  -- no map facts: a dungeon reads as the cave row, everything else as normal
  return ctx and ctx.dungeon and (record.mapTypes and record.mapTypes.cave or 1)
         or 0
end

-- `if (enemyLevel < playerLevel)` -- column 1 when the lead outclasses the
-- foe, column 2 when it does not
local function gen3Column(ctx)
  local enemy, lead = tonumber(ctx and ctx.enemyLevel), tonumber(ctx and ctx.leadLevel)
  if enemy and lead then return enemy < lead and 1 or 2 end
  return ctx and ctx.stronger and 2 or 1
end

local function gen3Style(ctx)
  -- FireRed's two tables (battle_setup.c sBattleTransitionTable_Wild /
  -- _Trainer): column 0 when the foe is weaker than the lead.  Unlike the old
  -- shortcut, the ROW matters too: water/flash/cave each have their own pair.
  if require("src.core.GameVersion").get() == "firered" then
    local weaker = ctx.weaker
    if weaker == nil then weaker = not ctx.stronger end
    if ctx.trainer then
      -- GetTrainerBattleTransition checks these before it ever consults the
      -- terrain/level table.  All five FireRed special ids run the same
      -- mugshot transition task with a different opponent portrait.
      local class = tonumber(ctx.trainerClass)
      local opponent = tonumber(ctx.trainerId)
      if opponent == 0x400 or class == 87 or class == 90 then
        return "g3_mugshot"
      end
    end
    local row = tonumber(ctx.mapTransitionType)
    if row == nil then row = ctx.dungeon and 1 or 0 end
    if row < 0 or row > 3 then row = 0 end
    local wild = {
      [0] = { "frlg_slice",     "frlg_whitebars" },
      [1] = { "frlg_clockwise", "g3_grid" },
      [2] = { "g3_blur",        "g3_grid" },
      [3] = { "g3_wave",        "g3_ripple" },
    }
    local trainer = {
      [0] = { "frlg_balltrail", "g3_angled" },
      [1] = { "g3_shuffle",     "g3_bigPokeball" },
      [2] = { "g3_blur",        "g3_grid" },
      [3] = { "frlg_swirl",     "g3_ripple" },
    }
    local pair = (ctx.trainer and trainer or wild)[row]
    return pair[weaker and 1 or 2]
  end
  local record = gen3Record(ctx)
  if not record then
    -- no dataset: the port's own four, which is what it always had
    if ctx.trainer then
      if ctx.dungeon then return ctx.stronger and "g3_angled" or "g3_blackfade" end
      return ctx.stronger and "g3_slice" or "g3_pokeball"
    end
    if ctx.dungeon then return ctx.stronger and "g3_grid" or "g3_blackfade" end
    return ctx.stronger and "g3_slice" or "g3_whitefade"
  end
  local names = record.names or {}
  local function byId(id)
    return nameToStyle(names[id] or names[tostring(id)])
  end

  -- THE LEGENDS, which never reach the table at all
  local species = ctx.legendSpecies
  if species then
    local id = (record.regi and (record.regi[species]
                                 or record.regi[tostring(species)]))
    if id == nil then
      id = record.legendary and (record.legendary[species]
                                 or record.legendary[tostring(species)])
    end
    if id == nil and ctx.legendary then id = record.legendaryDefault end
    local style = id ~= nil and byId(id)
    if style then return style end
  end

  if ctx.trainer then
    local class = tonumber(ctx.trainerClass)
    local opponent = tonumber(ctx.trainerId)
    local classes = record.trainerClasses or {}
    local function isOneOf(list)
      for _, v in ipairs(list or {}) do if class == v then return true end end
      return false
    end
    if opponent and record.secretBaseOpponent
       and opponent == record.secretBaseOpponent then
      local style = byId(record.secretBaseTransition)
      if style then return style end
    end
    if class and class == classes.eliteFour then
      -- the cartridge switches on the trainer ID here; the import resolved
      -- those four ids to the names on their cards, because that is what this
      -- engine knows a trainer by.  Anyone else of the class -- and that is
      -- how the cartridge reads it too -- gets the Champion's.
      local id = ctx.trainerName and record.eliteFour
                 and record.eliteFour[ctx.trainerName]
      local style = byId(id or record.championTransition)
      if style then return style end
    end
    if class and class == classes.champion then
      local style = byId(record.championTransition)
      if style then return style end
    end
    if isOneOf(classes.magma) then
      local style = byId(record.magmaTransition)
      if style then return style end
    end
    if isOneOf(classes.aqua) then
      local style = byId(record.aquaTransition)
      if style then return style end
    end
  end

  local rows = ctx.trainer and record.trainer or record.wild
  local row = rows[gen3MapType(ctx, record) + 1] or rows[1]
  local style = row and byId(row[gen3Column(ctx)])
  return style or "g3_blackfade"
end

local function vanillaStyle(ctx)
  -- A DATASET THAT CARRIES THE TABLES IS A HOENN DATASET.  Asking
  -- GameVersion as well was one question too many: the record only exists
  -- because the Emerald import wrote it, and a caller holding that data and
  -- getting a Game Boy wipe is the failure this used to have in every
  -- headless context.
  if gen3Record(ctx) or require("src.core.GameVersion").isGen3() then
    return gen3Style(ctx)
  end
  return BIT_STYLES[(ctx.trainer and 1 or 0) + (ctx.stronger and 2 or 0)
                    + (ctx.dungeon and 4 or 0)]
end

-- opts: trainer (bool), stronger (bool), dungeon (bool)
function BattleTransition.new(game, onDone, opts)
  -- PLATINUM PLAYS ITS OWN: the 31 cut-ins of encounter_effect_core.c, picked
  -- by EncEffects_CutInEffect -- see src/render/Gen4BattleTransition.lua. A
  -- mod that hooks `transition.style` still gets the Game Boy path by
  -- answering a style here; vanilla Platinum never asks it.
  if require("src.core.GameVersion").isGen4()
     and not (opts and opts.forceClassic) then
    return require("src.render.Gen4BattleTransition").new(game, onDone, opts)
  end
  local self = setmetatable({}, BattleTransition)
  self.game = game
  self.onDone = onDone
  self.t = 0
  opts = opts or {}
  -- EVERYTHING EMERALD'S CHOICE ASKS FOR.  The three the Game Boy needed are
  -- still here; the rest are what GetBattleTransitionTypeByMap,
  -- GetTrainerBattleTransition and the legendary starters read, and a caller
  -- that cannot answer one simply leaves it out (see gen3Style).
  local ctx = { trainer = opts.trainer, stronger = opts.stronger,
                weaker = opts.weaker, dungeon = opts.dungeon, game = game,
                mapTransitionType = opts.mapTransitionType,
                enemyLevel = opts.enemyLevel, leadLevel = opts.leadLevel,
                trainerClass = opts.trainerClass, trainerId = opts.trainerId,
                trainerName = opts.trainerName,
                legendSpecies = opts.legendSpecies,
                legendary = opts.legendary }
  local style = Runtime.call("transition.style", vanillaStyle, ctx)
  local def = styleDef(game, style)
  -- a hook that names an unregistered style falls back to the vanilla bits
  if not def then
    style = vanillaStyle(ctx)
    def = styleDef(game, style)
  end
  self.style = style
  self.def = def
  self.fireRed = require("src.core.GameVersion").get() == "firered"
  -- Every FireRed battle transition first runs CreateIntroTask(0,0,2,2,2):
  -- two 16-frame gray pulses.  It does not use the Gen 1 circle-flash prelude.
  if self.fireRed then
    self.phase = "frlg_intro"
  else
    self.phase = def.flash and "flash" or "wipe"
  end
  self.mainPhase = def.flash and "flash" or "wipe"
  if self.fireRed then self.mainPhase = "wipe" end
  self.blackHold = self.fireRed and (def.blackHold or 1) or BLACK_HOLD
  self.wipeLen = def.frames
  return self
end

function BattleTransition:update(dt)
  self.t = self.t + 1
  if self.phase == "frlg_intro" then
    if self.t >= FRLG_INTRO_FRAMES then
      self.phase = self.mainPhase
      self.t = 0
    end
  elseif self.phase == "flash" then
    if self.t >= FLASH_CYCLES * #FLASH_STEPS * FLASH_HOLD then
      self.phase = "wipe"
      self.t = 0
    end
  else
    if self.t >= self.wipeLen + self.blackHold then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

function BattleTransition:draw()
  if self.phase == "frlg_intro" then
    local p = (math.max(1, self.t) - 1) % 16
    local blend = p < 8 and (p + 1) * 2 or (15 - p) * 2
    local a = math.max(0, math.min(1, blend / 16))
    local r = self.game and self.game.renderer
    if r then
      r.screenVeil = { FRLG_INTRO_GRAY, a }
    else
      love.graphics.setColor(FRLG_INTRO_GRAY, FRLG_INTRO_GRAY,
                             FRLG_INTRO_GRAY, a)
      love.graphics.rectangle("fill", 0, 0, 240, 160)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  elseif self.phase == "flash" then
    local step = math.floor(self.t / FLASH_HOLD) % #FLASH_STEPS + 1
    local v = FLASH_STEPS[step]
    if v ~= 0 then
      local shade = v > 0 and 0 or 1
      -- The flash is a palette write (rBGP), so on hardware it tints every
      -- pixel the LCD shows.  Hand it to the renderer as a screen-space veil
      -- so it covers the whole surface at any zoom; only the headless and
      -- no-renderer paths fall back to filling the 160x144 box.
      local r = self.game and self.game.renderer
      if r then
        r.screenVeil = { shade, math.abs(v) }
        return
      end
      love.graphics.setColor(shade, shade, shade, math.abs(v))
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end

  local prog = math.min(1, self.t / self.wipeLen)
  local style = self.style

  -- a registered style may draw itself; the eight built-ins do not.  A custom
  -- draw owns the 160x144 UI canvas as it always has.
  if self.def and self.def.draw then
    love.graphics.setColor(0, 0, 0, 1)
    self.def.draw(self, prog)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- With a renderer the wipe is drawn ONCE over the whole surface in screen
  -- space (Renderer:drawBattleWipe), on a tile grid anchored to the letterbox
  -- and extended outward at the same tile size.  That makes it a single
  -- continuous figure: the spiral starts at the outermost edge of the window
  -- and works inward, instead of one spiral inside the letterbox running
  -- alongside a second one outside it.  Nothing is stretched -- the pattern is
  -- continued with more tiles, not scaled-up pixels -- so at 1x the grid works
  -- out to exactly 20x18 and this is the classic wipe unchanged.
  local renderer = self.game and self.game.renderer
  if renderer then
    renderer.battleWipe = { style = style, prog = prog, t = self.t,
                            game = self.game,
                            screenDraw = self.def and self.def.screen,
                            transition = self }
    return
  end

  -- headless / no renderer: the classic 160x144 path
  love.graphics.setColor(0, 0, 0, 1)

  local order = orderFor(style, self.def)
  if order then
    -- tile-order wipes: spiral / circle sweeps
    local n = math.floor(#order * prog)
    for i = 1, n do
      local c = order[i]
      love.graphics.rectangle("fill", c[1] * TILE, c[2] * TILE, TILE, TILE)
    end
  elseif style == "hstripes" then
    -- interlaced rows wipe from alternating sides
    local w = math.floor(160 * prog)
    for row = 0, ROWS - 1 do
      local y = row * TILE
      if row % 2 == 0 then
        love.graphics.rectangle("fill", 0, y, w, TILE)
      else
        love.graphics.rectangle("fill", 160 - w, y, w, TILE)
      end
    end
  elseif style == "vstripes" then
    -- interlaced columns wipe from alternating ends
    local h = math.floor(144 * prog)
    for col = 0, COLS - 1 do
      local x = col * TILE
      if col % 2 == 0 then
        love.graphics.rectangle("fill", x, 0, TILE, h)
      else
        love.graphics.rectangle("fill", x, 144 - h, TILE, h)
      end
    end
  elseif style == "shrink" then
    -- the image squashes toward the middle: the asm shifts rows and
    -- columns inward in the same loop, so bars close from all four
    -- edges at once
    local h = math.floor(72 * prog)
    local w = math.floor(80 * prog)
    love.graphics.rectangle("fill", 0, 0, 160, h)
    love.graphics.rectangle("fill", 0, 144 - h, 160, h)
    love.graphics.rectangle("fill", 0, 0, w, 144)
    love.graphics.rectangle("fill", 160 - w, 0, w, 144)
  else -- split: the quarters tear apart from the middle; the asm shifts
    -- rows and columns outward each loop, so a black cross grows from
    -- the center in both axes at once
    local h = math.floor(72 * prog)
    local w = math.floor(80 * prog)
    love.graphics.rectangle("fill", 0, 72 - h, 160, h * 2)
    love.graphics.rectangle("fill", 80 - w, 0, w * 2, 144)
  end

  if prog >= 1 then
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return BattleTransition
