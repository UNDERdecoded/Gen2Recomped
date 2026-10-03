-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- A MAP NARROWER THAN THE WINDOW, AND WHAT THE REST OF THE WINDOW SHOWS.
--
-- Reported from play, three times now: "petalburg gym in emerald still showing
-- as a black background when i warp through the rooms even with no mods on".
--
-- Passes 141 and 144 proved the gym's data, tilesets, id space, window bounds,
-- camera, all 38 warps and every arrival cell correct -- 1,826 checks between
-- them -- and they were right. The gym renders exactly what the cartridge says.
-- What none of them measured is how much of the SCREEN that accounts for.
--
-- It is nine blocks wide. `data/layouts/PetalburgCity_Gym/border.bin` on the
-- cartridge is metatile 0x208 four times, and 0x208 is black in all 256 of its
-- pixels. Nine blocks is 144 world pixels; a Game Boy Advance shows 240, so
-- even the cartridge draws three black columns either side. This engine's
-- world pass shows `windowPixels / zoomScale`, which on a phone in landscape
-- is several times 240 -- and every extra column is more of the same black.
--
-- So this measures the thing the reporter can see and the other checks could
-- not: the fraction of the view that is off the map. The fix clamps the view
-- to the map's own extent or the generation's own screen, whichever is larger.
--
-- Usage: texlua tools/gen3_narrow_map_view_check.lua

package.path = "./?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

-- A LOVE stub big enough for Renderer's scale maths and nothing more.
local WIN = { w = 240, h = 160 }
love = {
  graphics = {
    getWidth = function() return WIN.w end,
    getHeight = function() return WIN.h end,
    getDimensions = function() return WIN.w, WIN.h end,
    getPixelDimensions = function() return WIN.w, WIN.h end,
    getDPIScale = function() return 1 end,
  },
  window = { getMode = function() return WIN.w, WIN.h, {} end },
  timer = { getTime = function() return 0 end },
}

local Renderer = require("src.render.Renderer")

local function renderer(uiW, uiH)
  local r = setmetatable({}, { __index = Renderer })
  r.WIDTH, r.HEIGHT = uiW, uiH
  r.MAX_UI_WIDTH, r.MAX_UI_HEIGHT = 4096, 4096
  return r
end

-- the share of a vw x vh view that is OFF a map bw x bh pixels, with the
-- camera centred -- which is what Camera:follow does, always
local function voidShare(vw, vh, bw, bh)
  local onW = math.min(vw, bw)
  local onH = math.min(vh, bh)
  return 1 - (onW * onH) / (vw * vh)
end

-- Petalburg Gym, from the cartridge: 9 x 112 blocks of 16 world pixels.
local GYM_W, GYM_H = 9 * 16, 112 * 16
local GBA_W, GBA_H = 240, 160

-- ---------------------------------------------------------------------------
section("1. the clamp exists and is opt-in")
-- ---------------------------------------------------------------------------
ok(type(Renderer.setWorldBounds) == "function",
   "Renderer:setWorldBounds is missing, so nothing can clamp the view")
do
  local r = renderer(GBA_W, GBA_H)
  -- 640x360, NOT 960x640: at 960x640 the fit scale is a clean 4 and the view
  -- is already 240x160, so a clamp to 240 would be invisible and every check
  -- below it would pass whatever the clamp did. A window whose view is
  -- genuinely wider than the screen is the only one that can tell.
  WIN.w, WIN.h = 640, 360
  local baseW, baseH = r:worldViewSize()
  ok(baseW > GBA_W, "the unclamped view at 640x360 is %d wide, not wider than "
     .. "the GBA's %d -- this section cannot measure anything", baseW, GBA_W)
  -- UNSET IS UNCHANGED. Every caller that is not the overworld -- a battle, a
  -- menu, the title screen -- never sets bounds and must see what it always saw.
  ok(r.worldBoundsW == nil, "bounds are set before anyone asked")
  r:setWorldBounds(nil, nil)
  local w2, h2 = r:worldViewSize()
  ok(w2 == baseW and h2 == baseH,
     "clearing the bounds changed the view from %dx%d to %dx%d",
     baseW, baseH, w2, h2)
  -- zero and negative are not extents. `if bw and bh` would take 0 as true,
  -- so this has to be refused where it is set, not where it is read.
  for _, bad in ipairs({ { -1, 0 }, { 0, 0 }, { 0, 100 }, { "x", "y" } }) do
    r:setWorldBounds(bad[1], bad[2])
    local w3, h3 = r:worldViewSize()
    ok(w3 == baseW and h3 == baseH,
       "bounds %s,%s were accepted: the view became %dx%d instead of %dx%d",
       tostring(bad[1]), tostring(bad[2]), w3, h3, baseW, baseH)
  end
  -- AND BOUNDS THAT WERE SET MUST BE CLEARABLE, or the gym's 144px follows
  -- the player onto the next map and frames the whole region to a doorway.
  r:setWorldBounds(GYM_W, GYM_H)
  local clamped = r:worldViewSize()
  ok(clamped < baseW, "the gym's bounds did not clamp anything (%d)", clamped)
  r:setWorldBounds(nil, nil)
  local w4, h4 = r:worldViewSize()
  ok(w4 == baseW and h4 == baseH,
     "after clearing, the view stayed at %dx%d instead of returning to %dx%d",
     w4, h4, baseW, baseH)
end

-- ---------------------------------------------------------------------------
section("2. a map at least as big as the screen is untouched")
-- ---------------------------------------------------------------------------
for _, win in ipairs({ { 240, 160 }, { 480, 320 }, { 960, 640 }, { 1920, 1080 } }) do
  WIN.w, WIN.h = win[1], win[2]
  local r = renderer(GBA_W, GBA_H)
  local baseW, baseH = r:worldViewSize()
  -- Route 101 is 20x20 blocks; Hoenn's big routes are far larger, and every
  -- Gen 1/2 map is at least a screen across.
  r:setWorldBounds(20 * 16, 20 * 16)
  local w, h = r:worldViewSize()
  local capW = math.max(GBA_W, 320)
  ok(w == math.min(baseW, capW) or w == baseW,
     "a 320px-wide map at window %dx%d came out %d, not %d", win[1], win[2],
     w, baseW)
  -- and a genuinely large map is bit-for-bit what it was
  r:setWorldBounds(120 * 16, 120 * 16)
  local bw, bh = r:worldViewSize()
  ok(bw == baseW and bh == baseH,
     "a 1920px map at window %dx%d changed from %dx%d to %dx%d",
     win[1], win[2], baseW, baseH, bw, bh)
end

-- ---------------------------------------------------------------------------
section("3. the view never drops below the generation's own screen")
-- ---------------------------------------------------------------------------
-- THIS IS THE GUARD THAT KEEPS GEN 1 AND 2 OUT OF IT. Clamping to the map
-- alone would frame a small map tighter than its cartridge ever did.
--
-- THE FLOOR IS ON THE BINDING AXIS, NOT ON BOTH -- and that is a correction,
-- not a loosening. The clamp preserves the window's aspect ratio (it has to:
-- the canvas is then scaled up to COVER the window, and a canvas of a
-- different shape would crop), so on a 16:9 window a 3:2 floor cannot be met
-- on both axes at once. Asking for both asked for something unachievable, and
-- the world the player sees is identical either way: a 240x160 canvas covering
-- a 640x360 window crops to 240x135 of visible world, which is exactly what a
-- 240x136 canvas shows without the waste.
--
-- What the floor still forbids, and what this still catches: a cap tighter
-- than it needs to be. `cap = min(1, availW/vw, availH/vh)` with both avail
-- values at or above the cartridge's screen means one axis always lands
-- exactly on its available extent -- so at least one axis is always >= the
-- screen, and a clamp that shrank BOTH below it is still a failure.
for _, ui in ipairs({ { 160, 144 }, { 240, 160 }, { 256, 192 } }) do
  WIN.w, WIN.h = 1280, 720
  local r = renderer(ui[1], ui[2])
  r:setWorldBounds(32, 32)   -- absurdly small: two blocks
  local w, h = r:worldViewSize()
  ok(w >= ui[1] or h >= ui[2],
     "a 2x2-block map on a %dx%d screen framed to %dx%d -- BOTH axes below the "
     .. "cartridge, so the cap is tighter than it has to be", ui[1], ui[2], w, h)
  -- ...and the aspect the cover depends on
  ok(math.abs(w / h - WIN.w / WIN.h) < 0.05,
     "the clamped view %dx%d is not the window's %dx%d shape, so scaling it to "
     .. "cover would crop", w, h, WIN.w, WIN.h)
end

-- ---------------------------------------------------------------------------
section("4. Petalburg Gym: what the reporter actually sees")
-- ---------------------------------------------------------------------------
io.write("   window     view before   void before   view after   void after\n")
local improved, worsened = 0, 0
for _, win in ipairs({ { 240, 160 }, { 480, 320 }, { 640, 360 },
                       { 960, 540 }, { 1280, 720 } }) do
  WIN.w, WIN.h = win[1], win[2]
  local r = renderer(GBA_W, GBA_H)
  local bw, bh = r:worldViewSize()
  local before = voidShare(bw, bh, GYM_W, GYM_H)
  r:setWorldBounds(GYM_W, GYM_H)
  local aw, ah = r:worldViewSize()
  local after = voidShare(aw, ah, GYM_W, GYM_H)
  io.write(("  %4dx%-4d  %4dx%-4d    %5.1f%%       %4dx%-4d   %5.1f%%\n")
    :format(win[1], win[2], bw, bh, before * 100, aw, ah, after * 100))
  ok(after <= before + 1e-9,
     "at %dx%d the clamp made it WORSE: %.1f%% -> %.1f%%",
     win[1], win[2], before * 100, after * 100)
  -- the cartridge's own framing is the floor on the BINDING axis (see the
  -- note in section 3): one of the two always lands on its available extent,
  -- and the other follows the window's shape so the cover does not crop.
  ok(aw >= GBA_W or ah >= GBA_H,
     "at %dx%d the clamp framed tighter than the GBA on BOTH axes: %dx%d",
     win[1], win[2], aw, ah)
  if after < before - 1e-9 then improved = improved + 1 end
  if after > before + 1e-9 then worsened = worsened + 1 end
end
ok(improved >= 3, "only %d of 5 window sizes showed less void; the clamp is "
   .. "not doing anything on a phone", improved)
ok(worsened == 0, "%d window size(s) got worse", worsened)

-- A CLAMPED VIEW IS STILL AN EVEN ONE. Camera:follow halves it, and an odd
-- half puts the tile layer on a fractional pixel against the sprites -- which
-- is the shimmer the parity fix-up above the clamp exists to stop. The clamp
-- runs after it, so it needs its own.
do
  WIN.w, WIN.h = 1600, 900
  local r = renderer(GBA_W, GBA_H)
  local baseW = r:worldViewSize()
  -- 301 and 171 world pixels: odd, above the GBA's screen so `max` picks them,
  -- and BELOW the unclamped view so `min` actually lands on them.
  r:setWorldBounds(301, 171)
  local w, h = r:worldViewSize()
  ok(w < baseW, "a 301px bound did not clamp a %d-wide view", baseW)
  ok(w % 2 == 0, "the clamped view is %d wide -- odd, so the world layer "
     .. "lands on a half pixel", w)
  ok(h % 2 == 0, "the clamped view is %d tall -- odd", h)
end

-- ...AND THE CONTROL. At the GBA's own size there is nothing to fix, and a
-- clamp that changed the classic framing would be a regression, not a fix.
do
  WIN.w, WIN.h = 240, 160
  local r = renderer(GBA_W, GBA_H)
  local bw, bh = r:worldViewSize()
  r:setWorldBounds(GYM_W, GYM_H)
  local aw, ah = r:worldViewSize()
  ok(aw == bw and ah == bh,
     "at the GBA's own 240x160 the view changed from %dx%d to %dx%d",
     bw, bh, aw, ah)
end


-- ---------------------------------------------------------------------------
section("5. an axis with a connection on it is not bounded at all")
-- ---------------------------------------------------------------------------
-- Reported from play, with a screenshot: zooming out on a Hoenn route left
-- BLACK BARS down both sides of the window instead of the routes either end of
-- it.  Nothing about the gym rule was wrong; it was being asked the wrong
-- question.  "How wide is this map" is only "how much world is there" when the
-- map has nothing attached to that edge.
--
-- `OverworldState:setMap` now answers `math.huge` on an axis the map connects
-- along, which drops straight out of the `min` and leaves that axis at the
-- full window.  A union of the loaded neighbours would have been a feedback
-- loop -- the union depends on the reach, the reach on the view, the view on
-- this bound -- and "unbounded that way" is both honest and a fixed point.
do
  -- ZOOMED OUT, because that is the only place the report lives.  At FIT the
  -- view is a quarter of the window and smaller than any route, so the bound
  -- never binds and this section would pass over nothing.  Survey zoom takes
  -- the scale to 1 px per world pixel, where the view IS the window -- 1280
  -- world pixels across, wider than a 30-block route.
  local Zoom = require("src.render.Zoom")
  local savedOffset = Zoom.offset
  Zoom.offset = -1000               -- clamped to the survey floor by Zoom.scale
  WIN.w, WIN.h = 1280, 720
  local r = renderer(GBA_W, GBA_H)
  local freeW, freeH = r:worldViewSize()
  ok(freeW >= WIN.w, "survey zoom did not reach 1 px per world pixel (view is "
     .. "%d wide for a %d window); the rest of this section cannot bind",
     freeW, WIN.w)

  -- a route: 30 blocks wide, connected east and west, nothing north or south
  local ROUTE_W, ROUTE_H = 30 * 16, 40 * 16
  r:setWorldBounds(ROUTE_W, ROUTE_H)
  local closedW, closedH = r:worldViewSize()
  ok(closedW < freeW,
     "a 480px-wide bound did not clamp a %d-wide view, so this section is "
     .. "measuring nothing", freeW)

  r:setWorldBounds(math.huge, ROUTE_H)
  local openW, openH = r:worldViewSize()
  ok(openW > closedW,
     "an east/west connection did not widen the view: %d, same as the closed "
     .. "map's %d -- the black bars are still there", openW, closedW)
  -- the vertical bound still bites, because nothing connects that way
  ok(openH <= math.max(GBA_H, ROUTE_H),
     "the vertical bound stopped applying when the horizontal one was lifted "
     .. "(%d > %d)", openH, math.max(GBA_H, ROUTE_H))

  -- BOTH axes open -- a map in the middle of a region -- is the unbounded view
  r:setWorldBounds(math.huge, math.huge)
  local allW, allH = r:worldViewSize()
  ok(allW == freeW and allH == freeH,
     "a map connected on every side framed to %dx%d instead of the full "
     .. "%dx%d window view", allW, allH, freeW, freeH)
  Zoom.offset = savedOffset
end

-- AND THE HALF THAT DECIDES IT.  Everything above grades the renderer, which
-- is handed a number; the number comes from `OverworldState:setMap`, and if it
-- goes back to reporting the map's own width this whole section passes while
-- the player still sees black bars.  Source-level because the overworld cannot
-- be loaded under this check's four-function LOVE stub -- but specific: the
-- call site has to consult the map's connections AND pass an infinity.
do
  local f = io.open("src/world/OverworldController.lua", "rb")
  local src = f and f:read("*a") or ""
  if f then f:close() end
  ok(#src > 0, "src/world/OverworldController.lua did not open")
  -- the whole `do ... end` block the bounds are published from
  local block = src:match("(Game%.renderer%.setWorldBounds.-setWorldBounds%b())")
  ok(block ~= nil,
     "could not find the setWorldBounds call site in OverworldController")
  -- ...WITH ITS COMMENTS STRIPPED, and that is not tidiness.  The first run of
  -- this section passed with the fix deleted, because the comment ABOVE the
  -- fix explains it -- and so contains the words "connections", "math.huge"
  -- and "NEIGHBOUR_DIRS" that the assertions were looking for.  A prose
  -- paragraph was grading the code it describes.  (claude/check_design_lessons
  -- shape 3a: a pattern that matched, just not the thing it meant to match.)
  local code = block and block:gsub("%-%-[^\r\n]*", "") or nil
  if code then
    ok(code:find("connections", 1, true) ~= nil,
       "the bounds are published without looking at the map's connections, so "
       .. "a route is bounded by its own width again")
    ok(code:find("math.huge", 1, true) ~= nil,
       "the bounds call site no longer passes math.huge for an open axis")
    ok(code:find("NEIGHBOUR_DIRS", 1, true) ~= nil,
       "the open-axis test no longer filters by NEIGHBOUR_DIRS, so a non-"
       .. "directional key in `connections` would open an axis at random")
  end
end

-- ---------------------------------------------------------------------------
section("6. a clamped canvas is scaled to COVER the window, not centred in it")
-- ---------------------------------------------------------------------------
-- This is the other half of the black bar, and the half that was already
-- written -- for Gen 4 only.  `worldPresentationScale` raises the blit scale
-- so a canvas smaller than the window still covers it; without it the canvas
-- is drawn at the zoom's own scale and centred, and the difference IS the bar.
ok(type(Renderer.worldPresentationScale) == "function",
   "Renderer:worldPresentationScale is missing")
do
  WIN.w, WIN.h = 1280, 720
  local r = renderer(GBA_W, GBA_H)
  -- unset bounds: every caller that is not the overworld, unchanged
  local sp = 3
  ok(r:worldPresentationScale(sp, 1280, 720, 200, 120) == sp,
     "a caller that set no bounds had its blit scale raised")
  -- bounds set and the canvas already covering: still unchanged
  r:setWorldBounds(GYM_W, GYM_H)
  local vw, vh = r:worldViewSize()
  local covering = math.max(1280 / vw, 720 / vh)
  ok(r:worldPresentationScale(covering + 1, 1280, 720, vw, vh) == covering + 1,
     "a blit scale that already covers the window was lowered")
  -- and the case the report is about: a scale that would leave a bar is raised
  local raised = r:worldPresentationScale(1, 1280, 720, vw, vh)
  ok(raised > 1, "the gym's clamped %dx%d canvas was left at scale 1 in a "
     .. "1280x720 window -- that is %d pixels of black down each side",
     vw, vh, math.floor((1280 - vw) / 2))
  ok(math.abs(raised * vw - 1280) < 8 or math.abs(raised * vh - 720) < 8,
     "the raised scale %.3f covers neither dimension of the window", raised)
end

-- ---------------------------------------------------------------------------
section("7. one rule, not a Gen 4 rule")
-- ---------------------------------------------------------------------------
-- Both halves above were already correct and already shipped -- inside
-- `if isGen4()`.  That is this port's recurring shape: a fix written where it
-- was noticed and never published in the other generations' terms.  These two
-- assertions are what stops it being re-split, and they are source-level
-- because the behaviour they forbid is "ask which cartridge this is".
do
  local src = (function()
    local f = io.open("src/render/Renderer.lua", "rb")
    if not f then return "" end
    local s = f:read("*a"); f:close(); return s
  end)()
  ok(#src > 0, "src/render/Renderer.lua did not open, so section 7 tested nothing")
  local sizeFn = src:match("function Renderer:worldViewSize%(%).-\nend")
  ok(sizeFn ~= nil, "could not find Renderer:worldViewSize")
  if sizeFn then
    ok(sizeFn:find("isGen4", 1, true) == nil,
       "worldViewSize asks which generation it is again; the clamp is one rule "
       .. "and a split is how the black bars got there")
  end
  local scaleFn = src:match("function Renderer:worldPresentationScale%(.-\nend")
  ok(scaleFn ~= nil, "could not find Renderer:worldPresentationScale")
  if scaleFn then
    ok(scaleFn:find("isGen4", 1, true) == nil,
       "worldPresentationScale asks which generation it is again, so every "
       .. "generation but Gen 4 goes back to being centred in black")
    -- ...but the Tilt exclusion is NOT the same kind of gate and must stay:
    -- tilt grows the view on purpose and filling would undo the growth.
    ok(scaleFn:find("Tilt.active", 1, true) ~= nil,
       "the Tilt exclusion was removed along with the generation gate")
  end
end


-- ---------------------------------------------------------------------------
section("8. the view always has the WINDOW's shape -- what a 3D pass depends on")
-- ---------------------------------------------------------------------------
-- The second half of the same report: "with dramatic shapes on, zoomed all the
-- way out seems to stretch things instead of just moving the camera back and
-- keeping the proper look".
--
-- It is the same bug wearing a different hat.  A world pipeline is handed
-- `ctx.vw`/`ctx.vh` -- this function's answer -- and DRAMATIC_SHAPE builds its
-- perspective from it: `Mat4.perspective(fov, vw / vh, ...)`, with the camera
-- distance `focal * vh` so zooming out dollies back rather than scaling.  That
-- is correct, and it renders into a canvas the size of the WINDOW in pixels
-- (its `sceneSize`).  So the moment `vw/vh` stops matching the window's aspect
-- the projection is built for one shape and drawn into another, and the
-- picture stretches -- which is exactly what a per-axis clamp did, and exactly
-- when it did it: zoomed out far enough for the bound to bind.
--
-- The flat path showed the same mismatch as a black bar and the 3D path as a
-- stretch.  One cause, so one assertion, and it belongs to the engine rather
-- than to any mod: a renderer cannot be expected to guess that the number it
-- was handed is not the shape of the surface it draws on.
do
  local Zoom = require("src.render.Zoom")
  local saved = Zoom.offset
  local worst = 0
  for _, win in ipairs({ { 1280, 720 }, { 1920, 1080 }, { 1024, 768 },
                         { 2400, 1080 }, { 800, 1280 }, { 1518, 1012 } }) do
    for _, off in ipairs({ 0, -1, -2, -1000 }) do
      for _, bounds in ipairs({ { nil, nil },                  -- unbounded
                                { 9 * 16, 112 * 16 },          -- Petalburg Gym
                                { 30 * 16, 40 * 16 },          -- a closed route
                                { math.huge, 40 * 16 },        -- east/west open
                                { 30 * 16, math.huge },        -- north/south open
                                { math.huge, math.huge },      -- open all round
                                { 20 * 16, 20 * 16 } }) do     -- Route 101
        WIN.w, WIN.h = win[1], win[2]
        Zoom.offset = off
        local r = renderer(GBA_W, GBA_H)
        r:setWorldBounds(bounds[1], bounds[2])
        local vw, vh = r:worldViewSize()
        -- the even-parity fix-up moves each axis by at most one pixel, so a
        -- tolerance is required; anything beyond it is a real mismatch
        local err = math.abs((vw / vh) / (win[1] / win[2]) - 1)
        if err > worst then worst = err end
        ok(err < 0.03,
           "window %dx%d, zoom %d, bounds %s x %s -> view %dx%d, aspect %.3f "
           .. "against the window's %.3f: a 3D pass builds its projection from "
           .. "this and draws into a window-shaped canvas, so the picture "
           .. "stretches by that ratio",
           win[1], win[2], off, tostring(bounds[1]), tostring(bounds[2]),
           vw, vh, vw / vh, win[1] / win[2])
      end
    end
  end
  io.write(("   worst aspect error across %d combinations: %.4f\n")
           :format(6 * 4 * 7, worst))
  Zoom.offset = saved
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
