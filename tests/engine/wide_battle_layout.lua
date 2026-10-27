-- BATTLE LAYOUT = WIDE (src/battle/WideBattle.lua): the surface it asks
-- for, the 2x2 move-grid navigation, and the rigid per-frame offset that
-- moves an animation authored in 160px space onto one of the two anchors.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local WideBattle = require("src.battle.WideBattle")
local Renderer = require("src.render.Renderer")
local Game = require("src.core.Game")

T.eq(WideBattle.WIDTH, 304, "the wide layout runs on a 304px native surface")
T.eq(WideBattle.HEIGHT, 144, "the wide surface keeps the native height")
T.eq(WideBattle.FIELD_BOTTOM, 104,
  "the lower 40 rows are the message / command windows")

local wide = { isWideBattleLayout = function() return true end }
local normal = { isWideBattleLayout = function() return false end }
T.eq(Game.wideBattleInStack({ states = { normal, wide, normal } }), wide,
  "a wide battle remains the surface owner under a classic overlay")
T.eq(Game.wideBattleInStack({ states = { normal } }), nil,
  "a classic stack keeps the normal surface")

-- move grid: slots are laid out 1 2 / 3 4
T.eq(WideBattle.moveGridIndex(1, 4, "right"), 2, "RIGHT crosses the row")
T.eq(WideBattle.moveGridIndex(2, 4, "left"), 1, "LEFT crosses the row")
T.eq(WideBattle.moveGridIndex(1, 4, "down"), 3, "DOWN crosses the column")
T.eq(WideBattle.moveGridIndex(4, 4, "up"), 2, "UP crosses the column")
T.eq(WideBattle.moveGridIndex(3, 3, "right"), 3,
  "an absent fourth move cannot be selected")
T.eq(WideBattle.moveGridIndex(1, 0, "right"), nil,
  "an empty move list has nothing to navigate")

local function pressing(key)
  return { wasPressed = function(_, k) return k == key end }
end
T.eq(WideBattle.navigate(1, 4, pressing("right")), 2,
  "navigate maps a direction onto the grid")
T.eq(WideBattle.navigate(1, 4, pressing("a")), nil,
  "navigate leaves A / B / SELECT to the battle engine")

-- OAM x is the right edge of an 8px sprite. These groups are centered on
-- the authored player (26) and enemy (124) anchors, rather than merely
-- falling somewhere on their half of the 160px screen.
local px, py = WideBattle.animationOffset({ { x = 14 }, { x = 46 } })
T.eq(px, 20, "the player anchor maps to its wide-layout offset")
T.eq(py, 8, "the player anchor maps to its wide-layout baseline")
local ex, ey = WideBattle.animationOffset({ { x = 112 }, { x = 144 } })
T.eq(ex, 136, "the enemy anchor maps to its wide-layout offset")
T.eq(ey, 0, "the enemy anchor maps to its wide-layout baseline")

local function offset(x, wantX, wantY, label)
  local dx, dy = WideBattle.animationOffset({ { x = x } })
  T.eq(dx, wantX, label .. " horizontal offset")
  T.eq(dy, wantY, label .. " vertical offset")
end
offset(30, 20, 8, "single sprite at the player anchor")
offset(128, 136, 0, "single sprite at the enemy anchor")
offset(79, 78, 4, "midpoint between anchors")
-- Wobble must continue across the anchor instead of sticking at it.
offset(29, 19, 8, "one pixel before the player anchor")
offset(31, 21, 8, "one pixel after the player anchor")
offset(127, 135, 0, "one pixel before the enemy anchor")
offset(129, 137, 0, "one pixel after the enemy anchor")
-- Bounded overshoot lets balls leave the picture without unbounded offsets.
offset(-1000, -3, 10, "far left overshoot")
offset(1000, 159, -2, "far right overshoot")
local rx, ry = WideBattle.animationOffset({ { x = 46 }, { x = 14 } })
T.eq(rx, px, "sprite ordering does not change the rigid frame offset")
T.eq(ry, py, "sprite ordering does not change the baseline")
local emptyX, emptyY = WideBattle.animationOffset({})
T.eq(emptyX, 0, "an empty frame has no horizontal offset")
T.eq(emptyY, 0, "an empty frame has no vertical offset")

local mx, my = WideBattle.animationOffset({ { x = 79 } })
T.eq(mx, 78, "a crossing frame interpolates halfway between picture anchors")
T.eq(my, 4, "the crossing baseline interpolates with the same fraction")
local ox = WideBattle.animationOffset({ { x = 20 } })
T.check(ox < 20, "motion can overshoot the player anchor without the old 40px clamp")

-- the surface: a request outside the bounds falls back to the GB screen,
-- and the canvas is only reallocated when the size actually changes
Renderer:init()
T.eq(select(1, Renderer:uiSize()), 160, "the default surface is the GB screen")
Renderer:setUISize(WideBattle.WIDTH, WideBattle.HEIGHT)
local w, h = Renderer:uiSize()
T.eq(w, 304, "setUISize widens the surface")
T.eq(h, 144, "setUISize keeps the height")
Renderer:setUISize(64, 64)
T.eq(select(1, Renderer:uiSize()), 160,
  "a surface smaller than the GB screen falls back")
Renderer:setUISize(99999, 99999)
T.eq(select(1, Renderer:uiSize()), 160, "an oversized surface falls back")
Renderer:setUISize(160, 144)

T.finish("wide battle layout")
