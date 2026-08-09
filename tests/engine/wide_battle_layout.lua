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

-- animation frames shift as one rigid group toward the side they play on
local px, py = WideBattle.animationOffset({ { x = 24 }, { x = 64 } })
T.eq(px, 20, "a player-side frame lands on the player anchor")
T.eq(py, 8, "a player-side frame lands on the player baseline")
local ex, ey = WideBattle.animationOffset({ { x = 104 }, { x = 144 } })
T.eq(ex, 136, "an enemy-side frame lands on the enemy anchor")
T.eq(ey, 0, "an enemy-side frame lands on the enemy baseline")

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
