-- Parity / regression for #73: Gen 1 fight-menu SELECT reorders moves.
--
-- Select marks a slot, move the cursor, Select (or A) swaps. Defaults:
-- Tab / either Shift / gamepad Back. Self-contained; also picked up by
-- tests/run_tests.lua's parity_* glob.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local Input = require("src.core.Input")
local S = require("tests.harness").suite("parity move swap")
local check, eq = S.check, S.eq

local function freshGame()
  local mon = Pokemon.new(Data, "NIDORAN_M", 8)
  mon.moves = {
    { id = "TACKLE", pp = 35 },
    { id = "LEER", pp = 30 },
    { id = "HORN_ATTACK", pp = 25 },
    { id = "POISON_STING", pp = 35 },
  }
  return {
    data = Data,
    input = Input,
    save = {
      party = { mon },
      player = { name = "RED" },
      inventory = {},
      options = {},
      pokedex = { seen = {}, owned = {} },
      flags = {},
      money = 0,
    },
    stack = { push = function() end, pop = function() end, top = function() end },
  }
end

local function tapKey(battle, key)
  Input:keypressed(key)
  Input:step()
  battle:update(0)
  Input:keyreleased(key)
end

local function tapPad(battle, button)
  Input:gamepadpressed(nil, button)
  Input:step()
  battle:update(0)
  Input:gamepadreleased(nil, button)
end

-- Default Select sources all edge the logical select button.
do
  Input:init()
  for _, key in ipairs({ "tab", "rshift", "lshift" }) do
    Input:reset()
    Input:keypressed(key)
    Input:step()
    check(Input:wasPressed("select"), key .. " maps to select")
  end
  Input:reset()
  Input:gamepadpressed(nil, "back")
  Input:step()
  check(Input:wasPressed("select"), "gamepad back maps to select")
end

-- Fight menu: Select, move, Select swaps slots 1 and 2.
do
  Input:init()
  local game = freshGame()
  local battle = BattleState.newWild(game, "PIDGEY", 5)
  battle.phase = "moveSelect"
  battle.moveIndex = 1
  battle.moveSwapIndex = nil
  local a = battle.player.curMoves[1].id
  local b = battle.player.curMoves[2].id
  tapKey(battle, "tab")
  eq(battle.moveSwapIndex, 1, "first Select marks the current slot")
  tapKey(battle, "down")
  eq(battle.moveIndex, 2, "cursor moved to slot 2")
  tapKey(battle, "tab")
  check(battle.moveSwapIndex == nil, "second Select clears the mark")
  eq(battle.player.curMoves[1].id, b, "slot 1 holds the former slot 2 move")
  eq(battle.player.curMoves[2].id, a, "slot 2 holds the former slot 1 move")
  eq(battle.player.mon.moves[1].id, b, "party moves table stays in sync")
end

-- Same reorder via gamepad Back (SDL "back" = controller Select/View).
do
  Input:init()
  local game = freshGame()
  local battle = BattleState.newWild(game, "PIDGEY", 5)
  battle.phase = "moveSelect"
  battle.moveIndex = 1
  battle.moveSwapIndex = nil
  local a = battle.player.curMoves[1].id
  local b = battle.player.curMoves[2].id
  tapPad(battle, "back")
  tapPad(battle, "dpdown")
  tapPad(battle, "back")
  eq(battle.player.curMoves[1].id, b, "pad Select swaps slot 1")
  eq(battle.player.curMoves[2].id, a, "pad Select swaps slot 2")
end

-- A confirms a pending swap (bag-style), without starting the turn.
do
  Input:init()
  local game = freshGame()
  local battle = BattleState.newWild(game, "PIDGEY", 5)
  battle.phase = "moveSelect"
  battle.moveIndex = 1
  battle.moveSwapIndex = nil
  local a = battle.player.curMoves[1].id
  local b = battle.player.curMoves[2].id
  tapKey(battle, "tab")
  tapKey(battle, "down")
  tapKey(battle, "z") -- A
  eq(battle.phase, "moveSelect", "A completes a pending swap without attacking")
  eq(battle.player.curMoves[1].id, b, "A-confirm swapped slot 1")
  eq(battle.player.curMoves[2].id, a, "A-confirm swapped slot 2")
end

S.finish()
