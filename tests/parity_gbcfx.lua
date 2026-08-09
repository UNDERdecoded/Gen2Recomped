-- Parity test,  GBC FX ladder (Pixel Transparency shader).
-- Unit-tests the Lua-side API of src/render/GBCFX.lua headless under the
-- love stub: level clamping, the OFF→1→2→3→4→OFF cycle, options plumbing,
-- level labels, and that active()/present() degrade gracefully when the
-- stub offers no love.graphics.newShader (shader() returns nil).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity gbcfx")
local check, eq = S.check, S.eq

-- === assertions ===

local GBCFX = require("src.render.GBCFX")

-- defaults
eq(GBCFX.level, 0, "gbcfx starts at level 0 (OFF)")
eq(#GBCFX.LABELS, 5, "five labels (OFF + 4 levels)")
eq(GBCFX.LABELS[1], "OFF", "first label is OFF")

-- setLevel clamps and floors
GBCFX.setLevel(2)
eq(GBCFX.level, 2, "setLevel stores an in-range level")
GBCFX.setLevel(-3)
eq(GBCFX.level, 0, "setLevel clamps below to 0")
GBCFX.setLevel(99)
eq(GBCFX.level, 4, "setLevel clamps above to 4")
GBCFX.setLevel(2.9)
eq(GBCFX.level, 2, "setLevel floors fractional levels")
GBCFX.setLevel("3")
eq(GBCFX.level, 3, "setLevel accepts numeric strings")
GBCFX.setLevel(nil)
eq(GBCFX.level, 0, "setLevel(nil) resets to OFF")
GBCFX.setLevel("junk")
eq(GBCFX.level, 0, "setLevel(non-numeric) resets to OFF")

-- cycle wraps OFF→1→2→3→4→OFF and returns the new level
GBCFX.setLevel(0)
eq(GBCFX.cycle(), 1, "cycle OFF -> 1")
eq(GBCFX.cycle(), 2, "cycle 1 -> 2")
eq(GBCFX.cycle(), 3, "cycle 2 -> 3")
eq(GBCFX.cycle(), 4, "cycle 3 -> 4")
eq(GBCFX.cycle(), 0, "cycle 4 wraps to OFF")
eq(GBCFX.level, 0, "cycle leaves the wrapped level stored")

-- applyOptions reads opts.gbcfx
GBCFX.applyOptions({ gbcfx = 3 })
eq(GBCFX.level, 3, "applyOptions reads opts.gbcfx")
GBCFX.applyOptions({})
eq(GBCFX.level, 0, "applyOptions without gbcfx resets to OFF")
GBCFX.setLevel(2)
GBCFX.applyOptions(nil)
eq(GBCFX.level, 0, "applyOptions(nil) resets to OFF")

-- labels
eq(GBCFX.levelLabel(0), "OFF", "label for level 0")
eq(GBCFX.levelLabel(1), "1", "label for level 1")
eq(GBCFX.levelLabel(4), "4", "label for level 4")
GBCFX.setLevel(3)
eq(GBCFX.levelLabel(), "3", "levelLabel() defaults to the current level")
eq(GBCFX.levelLabel(42), "OFF", "out-of-range label falls back to OFF")

-- headless: the love stub has no newShader, so the shader never compiles
eq(GBCFX.shader(), nil, "shader() is nil headless")
GBCFX.setLevel(4)
check(not GBCFX.active(), "active() is false headless even at level 4")

-- present() falls back to a plain draw when the shader is unavailable
local drawn = nil
local g = love.graphics
local oldDraw, oldSetColor = g.draw, g.setColor
g.draw = function(c, x, y) drawn = { c, x, y } end
g.setColor = g.setColor or function() end
local canvas = {}
local ok, err = pcall(GBCFX.present, canvas, 5)
g.draw = oldDraw
g.setColor = oldSetColor
check(ok, "present() does not error headless (" .. tostring(err) .. ")")
check(drawn and drawn[1] == canvas and drawn[2] == 0 and drawn[3] == 0,
      "present() falls back to a plain draw at (0,0)")

GBCFX.setLevel(0)

-- issue #136: Android/iOS refuse GBC FX (shader soft-bricks the APK)
check(GBCFX.isSupported(), "desktop / headless stub supports GBC FX")
local prevSystem = love.system
love.system = { getOS = function() return "Android" end }
check(not GBCFX.isSupported(), "Android reports GBC FX unsupported")
GBCFX.setLevel(3)
eq(GBCFX.level, 0, "setLevel forces OFF on Android")
eq(GBCFX.cycle(), 0, "cycle stays OFF on Android")
local opts = { gbcfx = 4 }
check(GBCFX.applyOptions(opts) == true,
      "applyOptions reports a cleared persisted level on Android")
eq(opts.gbcfx, 0, "applyOptions clears opts.gbcfx on Android")
eq(GBCFX.level, 0, "applyOptions leaves level OFF on Android")
check(not GBCFX.active(), "active() is false on Android")
eq(GBCFX.shader(), nil, "shader() is nil on Android")
love.system = { getOS = function() return "iOS" end }
check(not GBCFX.isSupported(), "iOS reports GBC FX unsupported")
love.system = prevSystem
check(GBCFX.isSupported(), "support restores when OS stub is removed")
-- desktop path still applies a level after leaving the mobile gate
GBCFX.applyOptions({ gbcfx = 2 })
eq(GBCFX.level, 2, "applyOptions still sets levels on desktop")
GBCFX.setLevel(0)

-- Options menu hides the GBC FX row on Android
local OptionsMenu = require("src.ui.OptionsMenu")
love.system = { getOS = function() return "Android" end }
local om = OptionsMenu.new({
  data = { rulesets = {}, constants = {} },
  save = { options = {} },
  stack = { pop = function() end },
  input = { wasPressed = function() return false end },
  modStatus = { available = {} },
})
local hasGbc = false
for _, row in ipairs(om.rows) do
  if row.id == "gbcfx" then hasGbc = true end
end
check(not hasGbc, "Options menu omits GBC FX on Android")
love.system = prevSystem

-- POKEPORT_GBCFX overrides the platform default both ways.  Handheld packs
-- (build-rg34xxsp.sh) export 0 because their getOS() says "Linux" while the
-- GPU is phone class; 1 is the escape hatch if a device turns out to cope.
local prevEnv = os.getenv("POKEPORT_GBCFX")
local realGetenv = os.getenv
local stubEnv
os.getenv = function(name)
  if name == "POKEPORT_GBCFX" then return stubEnv end
  return realGetenv(name)
end

stubEnv = "0"
check(not GBCFX.isSupported(), "POKEPORT_GBCFX=0 refuses GBC FX on desktop")
GBCFX.setLevel(3)
eq(GBCFX.level, 0, "setLevel forces OFF under POKEPORT_GBCFX=0")
local handheldOpts = { gbcfx = 4 }
check(GBCFX.applyOptions(handheldOpts) == true,
      "applyOptions reports a cleared level under POKEPORT_GBCFX=0")
eq(handheldOpts.gbcfx, 0, "applyOptions heals a persisted level on a handheld")
check(not GBCFX.active(), "active() is false under POKEPORT_GBCFX=0")

local omHandheld = OptionsMenu.new({
  data = { rulesets = {}, constants = {} },
  save = { options = {} },
  stack = { pop = function() end },
  input = { wasPressed = function() return false end },
  modStatus = { available = {} },
})
hasGbc = false
for _, row in ipairs(omHandheld.rows) do
  if row.id == "gbcfx" then hasGbc = true end
end
check(not hasGbc, "Options menu omits GBC FX under POKEPORT_GBCFX=0")

-- "1" wins over the Android gate, so the override is a real two-way door.
stubEnv = "1"
love.system = { getOS = function() return "Android" end }
check(GBCFX.isSupported(), "POKEPORT_GBCFX=1 forces GBC FX on despite Android")
love.system = prevSystem

stubEnv = nil
check(GBCFX.isSupported(), "unset POKEPORT_GBCFX falls back to the OS check")
os.getenv = realGetenv
eq(os.getenv("POKEPORT_GBCFX"), prevEnv, "os.getenv restored")
GBCFX.setLevel(0)

-- === summary ===
S.finish()
