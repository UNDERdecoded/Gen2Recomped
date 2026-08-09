-- Parity: the main battle-menu cursor stops at an edge instead of wrapping
-- to the opposite command (#485).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity battle menu cursor")
local eq = S.eq

local pressed = {}
local save = SaveData.newGame()
save.party = { Pokemon.new(Data, "BULBASAUR", 5) }
local game = {
  data = Data,
  save = save,
  input = { wasPressed = function(_, key) return pressed[key] == true end },
  stack = { push = function() end, pop = function() end, top = function() end },
}
local battle = BattleState.newWild(game, "RATTATA", 2)
battle.phase = "menu"

local function pressAt(state, index, key)
  state.menuIndex = index
  pressed[key] = true
  state:update(1 / 60)
  pressed[key] = nil
  return state.menuIndex
end

eq(pressAt(battle, 1, "left"), 1, "FIGHT stays selected when pressing left")
eq(pressAt(battle, 2, "right"), 2, "PKMN stays selected when pressing right")
eq(pressAt(battle, 1, "up"), 1, "FIGHT stays selected when pressing up")
eq(pressAt(battle, 4, "down"), 4, "RUN stays selected when pressing down")
eq(pressAt(battle, 1, "right"), 2, "FIGHT moves right to PKMN")
eq(pressAt(battle, 1, "down"), 3, "FIGHT moves down to ITEM")

local safari = BattleState.newWild(game, "RATTATA", 2)
safari:makeSafari({ balls = 30 })
safari.phase = "menu"
eq(pressAt(safari, 1, "left"), 1, "SAFARI BALL stays selected when pressing left")
eq(pressAt(safari, 2, "right"), 2, "BAIT stays selected when pressing right")
eq(pressAt(safari, 1, "up"), 1, "SAFARI BALL stays selected when pressing up")
eq(pressAt(safari, 4, "down"), 4, "RUN stays selected when pressing down")

S.finish()
