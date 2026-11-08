-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- TV / CAST: WHAT A SECOND DISPLAY IS FOR, FROM THE LUA END.
--
-- Reported from play: casting a phone to a TV over Wi-Fi showed the DS bottom
-- screen on the TV instead of the game. Android hands a cast sink to apps as a
-- presentation display, the host put the bottom screen on every such display,
-- and Lua took any second display for a bottom-screen panel.
--
-- This drives the REAL src/render/SecondScreen.lua, src/ui/SecondScreen.lua,
-- src/ui/CastDisplay.lua, src/ui/LauncherSecondScreen.lua and
-- src/render/CastTop.lua against host.txt files written the way each kind of
-- host writes them -- an old four-field APK, a built-in panel, a cast display
-- in each mode -- and checks what every one of them decides:
--
--   * is the display a bottom-screen panel (`deviceReady`), the main
--     picture's (`castTop`), or nothing (MIRROR);
--   * what a Gen 4 game's `mode` answers, and whether a frame goes out;
--   * whether the launcher's own lower panel runs;
--   * the never-set defaults (built-in BOTTOM, external MIRROR), the option's
--     storage in second_display/mode.txt, and that it is only offered by a
--     host that reads it;
--   * TOP's geometry: the TV copy's size and the phone's tap mapping.
--
-- The Java end is checked by tools/second_display_protocol_check.py.
--
-- Usage: python tools/run_lua_check.py tools/second_display_cast_check.lua

local root = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
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

-- ---------------------------------------------------------------------------
-- A filesystem in a table, and just enough of love.graphics for the launcher
-- panel and CastTop to run headless.
-- ---------------------------------------------------------------------------
local FS = { files = {}, clock = 1000 }
local function canvas(w, h)
  local c = { w = w, h = h }
  function c:getWidth() return self.w end
  function c:getHeight() return self.h end
  function c:getDimensions() return self.w, self.h end
  function c:getPixelDimensions() return self.w, self.h end
  function c:setFilter() end
  function c:release() end
  function c:newImageData()
    local d = { w = self.w, h = self.h }
    function d:getDimensions() return self.w, self.h end
    function d:getString() return string.rep("\0\0\0\255", self.w * self.h) end
    function d:release() end
    return d
  end
  return c
end
local noop = function() end
love = {
  timer = { getTime = function() return FS.clock end },
  filesystem = {
    getInfo = function(path)
      local f = FS.files[path]
      if not f then return nil end
      return { size = #f.body, modtime = f.modtime, type = "file" }
    end,
    read = function(path)
      local f = FS.files[path]
      if not f then return nil end
      return f.body, #f.body
    end,
    write = function(path, body)
      FS.files[path] = { body = body or "", modtime = FS.clock }
      return true
    end,
    createDirectory = function() return true end,
  },
  graphics = setmetatable({
    getDimensions = function() return 800, 360 end,
    getWidth = function() return 800 end,
    getHeight = function() return 360 end,
    getDPIScale = function() return 1 end,
    newCanvas = function(w, h) return canvas(w, h) end,
    newFont = function() return { getWidth = function() return 10 end,
                                  getHeight = function() return 8 end } end,
    getFont = function() return { getWidth = function() return 10 end,
                                  getHeight = function() return 8 end } end,
  }, { __index = function() return noop end }),
}

local T = require("src.render.SecondScreen")
local UI = require("src.ui.SecondScreen")
local CastDisplay = require("src.ui.CastDisplay")
local LSS = require("src.ui.LauncherSecondScreen")
local CastTop = require("src.render.CastTop")

-- Each scenario starts from a clean probe: the transport caches for half a
-- second of LOVE's clock, so the clock moves on and the caches are dropped.
local function fresh()
  FS.clock = FS.clock + 10
  T.forget()
  CastDisplay.forget()
end
local function host(line)
  love.filesystem.write(T.HOST, line .. "\n")
  fresh()
end
local function clearHost()
  FS.files[T.HOST] = nil
  fresh()
end
local function setMode(word)
  if word == nil then FS.files[T.MODE_FILE] = nil
  else love.filesystem.write(T.MODE_FILE, word .. "\n") end
  fresh()
end

-- A Gen 4 game, as far as SecondScreen asks: the cache flag answers
-- `available`, and the options table is where a layout lives.
local function gen4(opts)
  local frames = 0
  local game = { data = { isGen4Cache = true },
                 save = { options = opts or {} } }
  game.pushes = function() return frames end
  return game
end

-- ---------------------------------------------------------------------------
section("1. host.txt: four fields, six fields, junk after four")
-- ---------------------------------------------------------------------------
host("1 2 1280 720")
local h = T.readHost()
ok(h and h.displays == 2 and h.width == 1280 and h.kind == nil and h.mode == nil,
   "a four-field host parsed with kind=%s mode=%s", tostring(h and h.kind),
   tostring(h and h.mode))
ok(T.castSupported() == false, "an old four-field host was offered TV / CAST")
ok(T.hostKind() == "builtin", "an old host with a panel is %s, not builtin",
   T.hostKind())
ok(T.panelRole() == "bottom", "an old host's panel is for %s",
   tostring(T.panelRole()))

host("1 2 1920 1080 external top")
h = T.readHost()
ok(h and h.kind == "external" and h.mode == "top",
   "a six-field host parsed as kind=%s mode=%s", tostring(h and h.kind),
   tostring(h and h.mode))
ok(T.castSupported() == true, "a six-field host was not offered TV / CAST")

host("1 1 0 0 none auto")
ok(T.castSupported() == true, "a host with no display cannot take the option")
ok(T.hostKind() == "none", "no display reads as %s", T.hostKind())
ok(T.panelRole() == nil, "no display has a panel role %s", tostring(T.panelRole()))

-- one stray word, or words that are not the vocabulary: the OLD host, not
-- half of a new one
for _, line in ipairs({ "1 2 256 192 builtin", "1 2 256 192 wifi top",
                        "1 2 256 192 builtin sideways", "1 2 256 192 99 98" }) do
  host(line)
  h = T.readHost()
  ok(h and h.displays == 2 and h.kind == nil and h.mode == nil,
     "%q was half-read as kind=%s mode=%s", line, tostring(h and h.kind),
     tostring(h and h.mode))
  ok(T.panelRole() == "bottom", "%q is not treated as the old host", line)
end
-- an old Lua reads only the first four: the six-field line keeps them intact
do
  local line = "1 2 640 480 builtin bottom"
  local v, d, w, hh = line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
  ok(v == "1" and d == "2" and w == "640" and hh == "480",
     "the pre-cast pattern no longer reads a six-field host")
end

-- ---------------------------------------------------------------------------
section("2. what each host means, for a Gen 4 game and the launcher")
-- ---------------------------------------------------------------------------
-- {label, host line, mode.txt, deviceReady, castTop, game mode, launcher panel}
local cases = {
  { "no host (desktop / iOS)",      nil,                           nil,      false, false, "swap",    false },
  { "old APK, Thor panel",          "1 2 1080 1240",               nil,      true,  false, "display", true  },
  { "new APK, no display",          "1 1 0 0 none auto",           nil,      false, false, "swap",    false },
  { "Thor panel, never set",        "1 2 1080 1240 builtin bottom", nil,     true,  false, "display", true  },
  { "Thor panel, TOP",              "1 2 1080 1240 builtin top",   "top",    false, true,  "display", false },
  { "Thor panel, MIRROR",           "1 1 0 0 builtin mirror",      "mirror", false, false, "swap",    false },
  { "cast, never set (mirror)",     "1 1 0 0 external mirror",     nil,      false, false, "swap",    false },
  { "cast, BOTTOM",                 "1 2 1920 1080 external bottom", "bottom", true, false, "display", true },
  { "cast, TOP",                    "1 2 1920 1080 external top",  "top",    false, true,  "display", false },
  -- a host that has not caught up with mode.txt yet: its own word wins,
  -- because it is what the TV is actually showing
  { "cast, MIRROR picked, host still BOTTOM", "1 2 1920 1080 external bottom", "mirror", true, false, "display", true },
  -- a host contradicting itself (a panel up in mirror) gets no panel
  { "self-contradicting host",      "1 2 1920 1080 external mirror", nil,    false, false, "swap",    false },
}
for _, c in ipairs(cases) do
  local label, line, word, ready, top, gmode, panel =
    c[1], c[2], c[3], c[4], c[5], c[6], c[7]
  if line then host(line) else clearHost() end
  setMode(word)
  ok(UI.deviceReady() == ready, "%s: deviceReady is %s", label,
     tostring(UI.deviceReady()))
  ok(UI.castTop() == top, "%s: castTop is %s", label, tostring(UI.castTop()))
  ok(CastTop.active() == top, "%s: CastTop.active is %s", label,
     tostring(CastTop.active()))
  local game = gen4()
  ok(UI.mode(game) == gmode, "%s: a never-set Gen 4 game is in %s, not %s",
     label, UI.mode(game), gmode)
  -- a player who picked SWAP for one screen still gets the phone as the
  -- bottom screen in TOP, and DEVICE still means the panel in BOTTOM
  local swapper = gen4({ secondScreenMode = "swap" })
  ok(UI.mode(swapper) == (top and "display" or "swap"),
     "%s: a SWAP game answers %s", label, UI.mode(swapper))
  local device = gen4({ secondScreenMode = "display" })
  ok(UI.mode(device) == ((ready or top) and "display" or "swap"),
     "%s: a DEVICE game answers %s", label, UI.mode(device))
  ok(LSS.active() == panel, "%s: the launcher's lower panel active=%s", label,
     tostring(LSS.active()))
end

-- ---------------------------------------------------------------------------
section("3. frames: BOTTOM sends the lower screen, TOP never does")
-- ---------------------------------------------------------------------------
do
  local function frameAfterFlush(line, word)
    host(line); setMode(word)
    FS.files[T.FRAME] = nil
    local game = gen4()
    game.secondScreenCanvas = canvas(256, 192)
    game.secondScreenDirty = true
    UI.flush(game)
    return FS.files[T.FRAME] ~= nil
  end
  ok(frameAfterFlush("1 2 1080 1240 builtin bottom", nil) == true,
     "BOTTOM on the Thor panel no longer sends the bottom screen")
  ok(frameAfterFlush("1 2 1920 1080 external top", "top") == false,
     "TOP sent the bottom screen to the TV")
  ok(frameAfterFlush("1 1 0 0 external mirror", nil) == false,
     "MIRROR sent a frame to a display the host is not drawing on")
  -- taps the TV recorded in TOP are drained, never injected
  host("1 2 1920 1080 external top"); setMode("top")
  love.filesystem.write(T.TOUCH, "down 1 10 10\nup 1 10 10\n")
  local game = gen4()
  local hits = 0
  game.touchpressed = function() hits = hits + 1 end
  game.touchreleased = function() hits = hits + 1 end
  ok(UI.pumpInput(game) == 0 and hits == 0,
     "TOP injected %d tap(s) from the TV", hits)
  ok((FS.files[T.TOUCH].body or "") == "", "TOP left the TV's taps in touch.txt")
  host("1 2 1080 1240 builtin bottom"); setMode(nil)
  love.filesystem.write(T.TOUCH, "down 1 10 10\nup 1 10 10\n")
  hits = 0
  ok(UI.pumpInput(game) == 2 and hits == 2,
     "BOTTOM no longer delivers the panel's taps (%d)", hits)
end

-- ---------------------------------------------------------------------------
section("4. the option: defaults, storage, stepping, where it is offered")
-- ---------------------------------------------------------------------------
setMode(nil)
host("1 2 1080 1240 builtin bottom")
ok(CastDisplay.supported(), "a cast-aware host does not offer the option")
ok(CastDisplay.setting() == nil, "a fresh install has a stored choice")
ok(CastDisplay.effective() == "bottom" and CastDisplay.label() == "BOTTOM",
   "a built-in panel defaults to %s", CastDisplay.effective())
host("1 1 0 0 external mirror")
ok(CastDisplay.effective() == "mirror" and CastDisplay.label() == "MIRROR",
   "a cast display defaults to %s", CastDisplay.effective())
host("1 1 0 0 none auto")
ok(CastDisplay.effective() == "mirror",
   "with nothing attached the row reads %s", CastDisplay.effective())
host("1 2 1080 1240")
ok(not CastDisplay.supported(), "an old APK is offered an option it ignores")
clearHost()
ok(not CastDisplay.supported(), "a machine with no host is offered TV / CAST")

host("1 1 0 0 external mirror")
ok(CastDisplay.set("top"), "the choice could not be stored")
ok(FS.files[T.MODE_FILE] and FS.files[T.MODE_FILE].body == "top\n",
   "mode.txt holds %q", tostring(FS.files[T.MODE_FILE] and FS.files[T.MODE_FILE].body))
CastDisplay.forget()
ok(CastDisplay.setting() == "top", "the stored choice read back as %s",
   tostring(CastDisplay.setting()))
-- stepping: from never-set, the first press moves off the default it shows
setMode(nil)
host("1 1 0 0 external mirror")
ok(CastDisplay.step(1) == "bottom", "MIRROR (default) + right is not BOTTOM")
ok(CastDisplay.step(1) == "top", "BOTTOM + right is not TOP")
ok(CastDisplay.step(1) == "mirror", "TOP + right does not wrap to MIRROR")
ok(CastDisplay.step(-1) == "top", "MIRROR + left does not wrap to TOP")
CastDisplay.set(nil)
ok(FS.files[T.MODE_FILE].body == "auto\n", "clearing wrote %q",
   FS.files[T.MODE_FILE].body)
CastDisplay.forget()
ok(CastDisplay.setting() == nil, "auto read back as a choice")
-- garbage in mode.txt is auto, not a crash and not a mode
love.filesystem.write(T.MODE_FILE, "SIDEWAYS\n"); fresh()
ok(CastDisplay.setting() == nil, "mode.txt junk read as %s",
   tostring(CastDisplay.setting()))
love.filesystem.write(T.MODE_FILE, "  Top\r\n"); fresh()
ok(CastDisplay.setting() == "top", "mode.txt ' Top' read as %s",
   tostring(CastDisplay.setting()))

-- the rows themselves, by source: both menus carry the same option and it is
-- gated on the host, not on a generation
local function src(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local s = f:read("*a"); f:close()
  return (s:gsub(string.char(13, 10), string.char(10)))
end
local opt = src("src/ui/OptionsMenu.lua")
local a = opt:find('id = "castDisplay"', 1, true)
local lastDual = opt:find('id = "startMenuStyle"', 1, true)
-- the dual-screen block's rows are indented four spaces inside
-- `if SecondScreen.available(game)`; this one opens its own top-level `do`
local own = opt:find("\n  do\n    local okCast, CastDisplay", 1, true)
ok(a ~= nil, "OptionsMenu has no castDisplay row")
ok(a and lastDual and own and own > lastDual and own < a,
   "the castDisplay row is not at top level after the dual-screen block")
ok(opt:find("CastDisplay.supported()", 1, true) ~= nil,
   "OptionsMenu does not gate the row on the host")
local ri = src("src/import/RomImporter.lua")
ok(ri:find('scope = "cast"', 1, true) ~= nil, "the launcher settings page has no TV / CAST row")
ok(ri:find('entry.scope == "cast"', 1, true) ~= nil,
   "the launcher does not read/write the cast scope")

-- ---------------------------------------------------------------------------
section("5. TOP's geometry: the TV copy and the phone's taps")
-- ---------------------------------------------------------------------------
do
  local w, hh = CastTop.tvSize(2400, 1080)
  ok(w == 640 and hh == 288, "a 2400x1080 phone sends %dx%d, not 640x288", w, hh)
  w, hh = CastTop.tvSize(1080, 2400)
  ok(hh <= 360 and w <= 640 and math.abs(w / hh - 1080 / 2400) < 0.02,
     "a portrait phone sends %dx%d", w, hh)
  w, hh = CastTop.tvSize(320, 240)
  ok(w == 320 and hh == 240, "a small window was upscaled to %dx%d", w, hh)
  w, hh = CastTop.tvSize(1920, 1080)
  ok(w == 640 and hh == 360, "a 16:9 window sends %dx%d", w, hh)
  ok(w * hh * 4 <= 640 * 360 * 4, "the TV copy is over the size budget")

  local x, y, s = CastTop.fit(800, 360)
  ok(math.abs(s - 1.875) < 1e-9 and math.abs(x - 160) < 1e-9 and y == 0,
     "the bottom screen fits an 800x360 phone at %s,%s x%s", x, y, s)

  -- the routing: a tap in the picture reaches the game in 256x192, a tap in
  -- the letterbox does not, and a drag that started inside stays captured
  host("1 2 1920 1080 external top"); setMode("top")
  local game = gen4()
  local got = {}
  for _, m in ipairs({ "touchpressed", "touchmoved", "touchreleased" }) do
    game[m] = function(_, id, lx, ly)
      got[#got + 1] = { m = m, x = lx, y = ly, injecting = game.secondScreenInjecting }
    end
  end
  CastTop._state.rect = { x = x, y = y, s = s }
  -- Game:offerPointer records the screen that claimed a press here; a drag
  -- that leaves the picture is only delivered to an owner
  game.pointerOwners = { [7] = true }
  ok(CastTop.routeTouch(game, "touchpressed", 7, 160 + 128 * s, 96 * s) == true,
     "a tap on the phone's bottom screen was not taken")
  ok(got[1] and math.abs(got[1].x - 128) < 1e-6 and math.abs(got[1].y - 96) < 1e-6
     and got[1].injecting == true,
     "it reached the game at %s,%s (injecting=%s)", tostring(got[1] and got[1].x),
     tostring(got[1] and got[1].y), tostring(got[1] and got[1].injecting))
  ok(CastTop.routeTouch(game, "touchmoved", 7, 10, 10) == true,
     "a drag that left the picture was dropped")
  ok(CastTop.routeTouch(game, "touchreleased", 7, 10, 10) == true and #got == 3,
     "the release of a captured drag did not arrive")
  ok(CastTop.routeTouch(game, "touchpressed", 8, 20, 100) == false,
     "a tap in the letterbox was mapped onto the bottom screen")
  ok(CastTop.routeTouch(game, "touchmoved", 9, 300, 100) == false,
     "a drag the module never took was routed")
  -- outside TOP nothing is taken, whatever the last frame left behind
  host("1 2 1080 1240 builtin bottom"); setMode(nil)
  ok(CastTop.routeTouch(game, "touchpressed", 10, 400, 180) == false,
     "BOTTOM mode routed a phone tap into the bottom screen")
  ok(CastTop.begin(game) == false, "CastTop redirected a frame outside TOP")
  CastTop._state.rect = nil
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
if fails > 0 then error(("%d check(s) failed"):format(fails), 0) end
