-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that `display` mode -- the bottom screen on a REAL second
-- panel, the AYN Thor's lower screen -- draws to its own surface instead of into
-- the window, that a window click can never be mistaken for a tap on it, that a
-- tap that really did come from the panel still reaches the same handlers as
-- before, and that the whole mode disappears cleanly on a machine with one
-- screen instead of leaving the player with no bottom screen at all.
--
-- THE TRAPS THIS FILE EXISTS TO PIN DOWN, all three of them shapes that have
-- already bitten this module once:
--
--  1. A MODE THAT DEGRADES TO NOTHING.  Saves are portable.  If `display`
--     answered "off" on a desktop -- and "off" is every caller's cue to draw
--     nothing -- a save made on the handheld would open on a PC with no bottom
--     screen anywhere and no obvious way to get it back.  Section 2 requires the
--     fallback to be `swap`, and requires the STORED setting to survive it.
--
--  2. THE HIT TEST AND THE DRAW DISAGREEING ABOUT WHERE THE SURFACE IS.  That
--     is pass 137's bug exactly, and `display` is the one mode where the honest
--     answer flips: the picture is NOT in the window, so `toLocal` must refuse
--     every window point -- otherwise the top-left 256x192 of the field doubles
--     as the battle menu.  Section 3 sweeps the window and requires a total
--     refusal, with `swap` swept in the same run as the control that proves the
--     sweep can pass.
--
--  3. A MID-FRAME CANVAS BIND THAT DOES NOT PUT THE FRAME BACK.  `draw` runs
--     inside somebody else's render pass.  Leaving the canvas, the scissor or
--     the transform changed corrupts everything drawn afterwards, and the damage
--     shows up somewhere else entirely.  Section 4 records every graphics call
--     and requires the state to come back.
--
-- Usage: texlua tools/gen4_second_display_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
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
local W, H = 256, 192

-- ---------------------------------------------------------------------------
-- A RECORDING GRAPHICS STUB.
--
-- Not a mock that returns plausible values: a log.  The questions section 4
-- asks are all about ORDER and RESTORATION -- was the canvas put back, was the
-- scissor cleared before the body ran, was a translate applied -- and none of
-- them can be asked of a stub that only answers.  So every call appends to a
-- list and the assertions read the list.
-- ---------------------------------------------------------------------------
local G = { log = {}, canvas = nil, scissor = nil, stack = 0 }
local function rec(name, ...)
  G.log[#G.log + 1] = { name = name, n = select("#", ...), ... }
end
local function countOf(name)
  local n = 0
  for _, e in ipairs(G.log) do if e.name == name then n = n + 1 end end
  return n
end
local function firstOf(name)
  for i, e in ipairs(G.log) do if e.name == name then return e, i end end
  return nil
end
local function indexOf(name, from)
  for i = (from or 1), #G.log do if G.log[i].name == name then return i end end
  return nil
end

local function newFakeCanvas(w, h)
  local c = { w = w, h = h, released = 0, reads = 0 }
  function c:getWidth() return self.w end
  function c:getHeight() return self.h end
  function c:setFilter() end
  function c:newImageData()
    self.reads = self.reads + 1
    local d = { w = self.w, h = self.h, released = 0 }
    function d:release() self.released = self.released + 1 end
    function d:getWidth() return self.w end
    function d:getHeight() return self.h end
    c.lastData = d
    return d
  end
  return c
end

local clockNow = 100.0
love = {
  timer = { getTime = function() return clockNow end },
  graphics = {
    newCanvas = function(w, h) rec("newCanvas", w, h) return newFakeCanvas(w, h) end,
    getCanvas = function() return G.canvas end,
    setCanvas = function(c) rec("setCanvas", c) G.canvas = c end,
    push = function(what) G.stack = G.stack + 1 rec("push", what) end,
    pop = function() G.stack = G.stack - 1 rec("pop") end,
    origin = function() rec("origin") end,
    translate = function(x, y) rec("translate", x, y) end,
    scale = function(x, y) rec("scale", x, y) end,
    setScissor = function(...) rec("setScissor", ...) G.scissor = (select("#", ...) > 0) and { ... } or nil end,
    getScissor = function() if G.scissor then return G.scissor[1], G.scissor[2], G.scissor[3], G.scissor[4] end end,
    clear = function(...) rec("clear", ...) end,
    setColor = function(...) rec("setColor", ...) end,
    rectangle = function(...) rec("rectangle", ...) end,
  },
}

local SecondScreen = require("src.ui.SecondScreen")

-- A transport that says yes, and remembers what it was handed.
local function fakeTransport(ready)
  local T = { pushes = {}, probes = 0, ready = ready }
  function T.available() T.probes = T.probes + 1 return T.ready end
  function T.push(data, w, h)
    T.pushes[#T.pushes + 1] = { data = data, w = w, h = h }
    return true
  end
  return T
end

local function fakeGame(mode, scaleIndex)
  return {
    data = { isGen4Cache = true },
    save = { options = { secondScreenMode = mode,
                         secondScreenScale = scaleIndex or 2 } },
  }
end

-- ---------------------------------------------------------------------------
section("1. the mode exists and sits where the options row expects it")
-- ---------------------------------------------------------------------------
local modes = SecondScreen.MODES
local seen = {}
for i, name in ipairs(modes) do seen[name] = i end
ok(seen.display ~= nil, "there is no `display` mode at all")
ok(seen.swap and seen.inset and seen.off,
   "one of the original three modes went missing adding the fourth")
ok(#modes == 6, "MODES has %d entries; expected six screen layouts", #modes)
-- `off` stays last so the row's cycle ends on it, which is what every build so
-- far has trained the player to expect.
ok(seen.off == #modes, "`off` is entry %d of %d; it used to be last",
   tostring(seen.off), #modes)
ok(type(SecondScreen.deviceReady) == "function",
   "there is no capability probe, so the mode cannot be gated")
ok(type(SecondScreen.flush) == "function", "nothing sends the frame to the panel")
ok(type(SecondScreen.injectTouch) == "function",
   "nothing can deliver the panel's own touches")

-- ---------------------------------------------------------------------------
section("2. with no panel attached the mode degrades to swap, not to off")
-- ---------------------------------------------------------------------------
SecondScreen._setTransport(nil)
do
  local game = fakeGame("display")
  ok(SecondScreen.deviceReady() == false,
     "deviceReady says yes with no transport at all")
  local answered = SecondScreen.mode(game)
  ok(answered == "swap",
     "with no panel, `display` answers %q; \"off\" would leave a save made on "
     .. "the handheld with no bottom screen anywhere on a desktop", answered)
  ok(game.save.options.secondScreenMode == "display",
     "the fallback REWROTE the stored setting to %q, so carrying the save back "
     .. "to the handheld would not bring the panel back",
     tostring(game.save.options.secondScreenMode))
  -- and the fallback must be a real surface, not a rect of nil
  local rx, ry, scale = SecondScreen.rect(game)
  ok(rx == 0 and ry == 0 and scale == 1,
     "the fallback's rect is %s,%s x%s; swap is 0,0 x1",
     tostring(rx), tostring(ry), tostring(scale))
end
-- a transport that exists but says no is the same case, and is the one that
-- actually happens: an Android build with the symbols linked and one screen.
do
  local T = fakeTransport(false)
  SecondScreen._setTransport(T)
  local game = fakeGame("display")
  ok(SecondScreen.mode(game) == "swap",
     "a transport that reports no second panel still gives `display`")
  ok(T.probes > 0, "the transport was never asked whether a panel is attached")
end
-- and with a panel, the mode is honoured
do
  SecondScreen._setTransport(fakeTransport(true))
  local game = fakeGame("display")
  ok(SecondScreen.mode(game) == "display",
     "with a panel attached the mode still falls back")
  ok(SecondScreen.deviceReady() == true, "deviceReady says no with a panel attached")
end
-- the gate must not leak into the other three modes
do
  SecondScreen._setTransport(fakeTransport(false))
  for _, name in ipairs({ "swap", "inset", "off" }) do
    ok(SecondScreen.mode(fakeGame(name)) == name,
       "%s became something else when the panel gate was added", name)
  end
end

-- ---------------------------------------------------------------------------
section("3. a window click is never a tap on the device's panel")
-- ---------------------------------------------------------------------------
-- The asymmetry that makes this mode different from every other one, swept
-- against `swap` in the same run so a sweep that cannot fail is visible.
SecondScreen._setTransport(fakeTransport(true))
local function sweepAccepted(game)
  local accepted, total = 0, 0
  for py = 0, H - 1, 3 do
    for px = 0, W - 1, 3 do
      total = total + 1
      if SecondScreen.toLocal(game, px, py) then accepted = accepted + 1 end
    end
  end
  return accepted, total
end
do
  local disp = fakeGame("display")
  local a, n = sweepAccepted(disp)
  io.write(("  display: %d of %d window points accepted\n"):format(a, n))
  ok(a == 0,
     "%d of %d window points were taken for taps on the device's panel -- the "
     .. "top-left of the field doubles as the battle menu", a, n)
  -- THE CONTROL, in the same build: the identical sweep on `swap` must accept
  -- everything, or the sweep above proves nothing about `display`.
  local swap = fakeGame("swap")
  local b = select(1, sweepAccepted(swap))
  io.write(("  swap:    %d of %d window points accepted (control)\n"):format(b, n))
  ok(b == n, "the control sweep accepted %d of %d on `swap`, so the display "
     .. "sweep's zero says nothing", b, n)
  -- while injecting, the panel's own coordinates pass straight through
  disp.secondScreenInjecting = true
  local lx, ly = SecondScreen.toLocal(disp, 130, 47)
  ok(lx == 130 and ly == 47,
     "a point from the panel came back as %s,%s instead of 130,47",
     tostring(lx), tostring(ly))
  local off = { SecondScreen.toLocal(disp, W, 10) }
  ok(off[1] == nil, "a point past the panel's right edge was accepted")
  ok(SecondScreen.toLocal(disp, 10, H) == nil,
     "a point below the panel's bottom edge was accepted")
  disp.secondScreenInjecting = nil
end

-- ---------------------------------------------------------------------------
section("4. draw renders to the panel's surface and puts the frame back")
-- ---------------------------------------------------------------------------
do
  SecondScreen._setTransport(fakeTransport(true))
  local game = fakeGame("display")
  -- the renderer's own state, mid-frame
  local rendererCanvas = newFakeCanvas(480, 320)
  G.canvas, G.scissor, G.log, G.stack = rendererCanvas, { 8, 8, 64, 64 }, {}, 0
  local ranOn, bodyRuns = nil, 0
  SecondScreen.draw(game, function()
    bodyRuns = bodyRuns + 1
    ranOn = G.canvas
    ok(G.scissor == nil,
       "the renderer's scissor was still set while the bottom screen drew, so "
       .. "the panel's frame is clipped to wherever the window was drawing")
  end)
  ok(bodyRuns == 1, "the body ran %d times", bodyRuns)
  ok(ranOn ~= nil and ranOn ~= rendererCanvas,
     "the bottom screen drew onto the window's own canvas instead of its own")
  ok(ranOn == SecondScreen.canvas(game),
     "the body did not draw onto the canvas `flush` will read back")
  ok(G.canvas == rendererCanvas,
     "the renderer's canvas was not put back; everything drawn after this frame "
     .. "lands on the bottom screen")
  ok(G.stack == 0, "the graphics stack is %d deep after the draw", G.stack)
  ok(countOf("translate") == 0 and countOf("scale") == 0,
     "the body was translated (%d) or scaled (%d) -- in `display` the surface is "
     .. "its own canvas at 1:1 and a transform would move the picture off it",
     countOf("translate"), countOf("scale"))
  ok(countOf("clear") == 1, "the panel's surface was cleared %d times, not once",
     countOf("clear"))
  local made = firstOf("newCanvas")
  ok(made and made[1] == W and made[2] == H,
     "the panel's surface is %sx%s; the DS's screen is %dx%d",
     made and tostring(made[1]), made and tostring(made[2]), W, H)
  -- ORDER, which is the whole point of a log: origin and setScissor have to come
  -- BEFORE the body, and the canvas restore AFTER it.
  local iBind = indexOf("setCanvas")
  local iOrigin, iScissor = indexOf("origin"), indexOf("setScissor")
  ok(iBind and iOrigin and iScissor and iOrigin > iBind and iScissor > iBind,
     "the transform and scissor were reset before the canvas was bound")
  local iRestore = indexOf("setCanvas", (iBind or 0) + 1)
  ok(iRestore ~= nil and G.log[iRestore][1] == rendererCanvas,
     "there is no second setCanvas putting the renderer's target back")
  ok(game.secondScreenDirty == true,
     "the frame was drawn and nothing marked it as needing to be sent")
  -- the canvas is reused, not rebuilt every frame
  G.log = {}
  SecondScreen.draw(game, function() end)
  ok(countOf("newCanvas") == 0,
     "a second canvas was allocated for the second frame")
end
-- THE CONTROL: the same call on `inset` must still translate into the window
-- and must not touch the canvas at all.
do
  SecondScreen._setTransport(fakeTransport(true))
  local game = fakeGame("inset", 2)
  local rendererCanvas = newFakeCanvas(480, 320)
  G.canvas, G.scissor, G.log, G.stack = rendererCanvas, nil, {}, 0
  SecondScreen.draw(game, function() end)
  ok(countOf("translate") == 1 and countOf("scale") == 1,
     "`inset` no longer translates into the window (%d translates, %d scales)",
     countOf("translate"), countOf("scale"))
  ok(countOf("setCanvas") == 0,
     "`inset` bound a canvas; only `display` may")
  ok(game.secondScreenDirty == nil,
     "`inset` marked a panel frame as pending, and there is no panel")
end

-- ---------------------------------------------------------------------------
section("5. the frame reaches the panel once, and only when there is one")
-- ---------------------------------------------------------------------------
do
  local T = fakeTransport(true)
  SecondScreen._setTransport(T)
  local game = fakeGame("display")
  G.canvas, G.log = nil, {}
  clockNow = 200.0
  ok(SecondScreen.flush(game) == false,
     "flush sent a frame before anything drew one")
  SecondScreen.draw(game, function() end)
  ok(SecondScreen.flush(game) == true, "the first frame never reached the panel")
  ok(#T.pushes == 1, "%d frames were pushed for one draw", #T.pushes)
  local sent = T.pushes[1]
  ok(sent.w == W and sent.h == H, "the frame was pushed as %sx%s, not %dx%d",
     tostring(sent.w), tostring(sent.h), W, H)
  ok(game.secondScreenDirty == false,
     "the dirty flag survived the push, so every later frame re-reads the GPU")
  ok(SecondScreen.flush(game) == false,
     "a second flush with nothing newly drawn still read the canvas back")
  ok(#T.pushes == 1, "the second flush pushed anyway (%d total)", #T.pushes)
  -- the readback must be released; 192KB a frame leaked is 5MB a second
  local canvas = SecondScreen.canvas(game)
  ok(canvas.lastData and canvas.lastData.released == 1,
     "the ImageData read off the GPU was not released")
  -- THE INTERVAL.  A screen that redraws every frame must not turn the readback
  -- into the frame budget.
  SecondScreen.draw(game, function() end)
  ok(SecondScreen.flush(game) == false,
     "a redraw in the same instant pushed again; the interval does nothing")
  clockNow = 200.0 + SecondScreen.PUSH_INTERVAL + 0.001
  ok(SecondScreen.flush(game) == true,
     "a redraw a full interval later did NOT push, so the panel freezes")
  ok(#T.pushes == 2, "%d pushes after the interval elapsed", #T.pushes)
  -- and no other mode may push at all
  for _, name in ipairs({ "swap", "inset", "off" }) do
    local other = fakeGame(name)
    other.secondScreenDirty = true
    other.secondScreenCanvas = newFakeCanvas(W, H)
    ok(SecondScreen.flush(other) == false, "`%s` pushed a frame to a panel", name)
  end
  ok(#T.pushes == 2, "another mode pushed after all (%d total)", #T.pushes)
end

-- ---------------------------------------------------------------------------
section("6. a tap from the panel reaches the handler the window's taps reach")
-- ---------------------------------------------------------------------------
do
  SecondScreen._setTransport(fakeTransport(true))
  local game = fakeGame("display")
  local got = {}
  game.touchpressed = function(self, id, x, y)
    -- the point must resolve INSIDE the handler, which is where every caller
    -- asks -- the battle, the mining screen, the Poketch
    local lx, ly = SecondScreen.toLocal(self, x, y)
    got[#got + 1] = { id = id, x = x, y = y, lx = lx, ly = ly }
  end
  ok(SecondScreen.injectTouch(game, "touchpressed", 7, 120, 60) == true,
     "a tap from the panel was refused")
  ok(#got == 1, "%d taps arrived for one injected", #got)
  ok(got[1] and got[1].lx == 120 and got[1].ly == 60,
     "the handler resolved the panel's tap to %s,%s instead of 120,60",
     got[1] and tostring(got[1].lx), got[1] and tostring(got[1].ly))
  ok(game.secondScreenInjecting == nil,
     "the injecting flag was left set, so every later WINDOW click is taken for "
     .. "a tap on the panel")
  -- out of bounds, a missing handler, and the wrong mode are all refusals
  ok(SecondScreen.injectTouch(game, "touchpressed", 7, W, 10) == false,
     "a tap past the panel's edge was delivered")
  ok(#got == 1, "the out-of-bounds tap reached the handler anyway")
  ok(SecondScreen.injectTouch(game, "nosuchhandler", 7, 10, 10) == false,
     "injectTouch claimed to deliver to a handler that does not exist")
  local swap = fakeGame("swap")
  swap.touchpressed = function() got[#got + 1] = "swap" end
  ok(SecondScreen.injectTouch(swap, "touchpressed", 7, 10, 10) == false,
     "a panel tap was delivered on a mode with no panel")
end

-- ---------------------------------------------------------------------------
section("7. it is actually wired in, and the row can actually reach it")
-- ---------------------------------------------------------------------------
-- Everything above is a library nobody runs unless the game calls it.
local function slurp(rel)
  local f = io.open(root .. "../" .. rel, "rb") or io.open(rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return (s:gsub("\r\n", "\n"))
end
local gm = slurp("src/core/Game.lua")
ok(gm ~= nil, "could not open Game.lua")
if gm then
  ok(gm:find("pcall(SS.flush, self)", 1, true) ~= nil,
     "nothing in Game.lua sends the panel its frame, so `display` draws to a "
     .. "canvas nobody ever reads")
  -- INSIDE Game:draw and AFTER the frame, not before it: the readback wants the
  -- drawing finished, and a screen pushed late still has to get out.
  local draw = gm:match("\nfunction Game:draw%(%)(.-)\nend\n")
  ok(draw ~= nil, "Game:draw could not be found to check where the flush sits")
  if draw then
    local iDraw = draw:find("self:_draw()", 1, true)
    local iFlush = draw:find("SS.flush", 1, true)
    ok(iDraw and iFlush and iFlush > iDraw,
       "the flush is not inside Game:draw after the frame (_draw at %s, flush "
       .. "at %s)", tostring(iDraw), tostring(iFlush))
  end
end
local om = slurp("src/ui/OptionsMenu.lua")
ok(om ~= nil, "could not open OptionsMenu.lua")
if om then
  ok(om:find('display = Strings("DEVICE")', 1, true) ~= nil,
     "the 2ND SCREEN row has no label for `display`, so it reads as blank")
  ok(om:find('if name ~= "display" or SecondScreen.deviceReady() then', 1, true) ~= nil,
     "the row's step does not skip `display` when no panel is attached, so the "
     .. "cursor parks on a setting that does nothing")
end
local tr = slurp("src/render/SecondScreen.lua")
ok(tr ~= nil, "could not open the transport")
if tr then
  ok(tr:find("PROBE_INTERVAL", 1, true) ~= nil,
     "the transport's readiness probe is not cached, and `mode` asks it several "
     .. "times a frame from every caller that has to decide where to draw")
  for _, sym in ipairs({ "love_android_secondary_ready",
                         "love_android_push_secondary",
                         "love_android_secondary_enable" }) do
    ok(tr:find(sym, 1, true) ~= nil, "the transport lost the %s symbol", sym)
  end
end
local ui = slurp("src/ui/SecondScreen.lua")
if ui then
  -- pass 137's bug, in this mode's shape: a refusal keyed to the wrong question
  ok(ui:find('mode == "display"' , 1, true) ~= nil,
     "toLocal no longer distinguishes `display` at all")
  ok(ui:find("g.setCanvas(previous)", 1, true) ~= nil,
     "the mid-frame canvas bind does not put the renderer's target back")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
