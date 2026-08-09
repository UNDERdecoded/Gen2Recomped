-- TradeAnim InternalClockTradeFuncSequence completes under A-skip and
-- exposes the cable-trade phases (engine/movie/trade.asm).
-- ROM-free: fixture species only (CI has no data/generated/).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()
local ids = T.fixtures.ids

local S = require("tests.harness").suite("trade anim")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local TradeAnim = require("src.ui.TradeAnim")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
require("src.render.Font").load(Data)

local sent = Pokemon.new(Data, ids.species[1], 10)
local recv = Pokemon.new(Data, ids.species[2], 10)
recv.nickname = "DUX"
recv.ot = "TRAINER"
recv.otId = 8193

local done = false
local anim = TradeAnim.new(Game, {
  sent = sent, received = recv, enemyName = "TRAINER",
  onDone = function() done = true end,
})
Game.stack:push(anim)
if anim.enter then anim:enter() end

local seen = {}
local guard = 0
while not done and guard < 20000 do
  guard = guard + 1
  seen[anim.phase] = true
  Input.pressed = { a = true }
  StateStack:update(1 / 60)
  Input.pressed = {}
end

check(done, "TradeAnim reaches onDone")
for _, phase in ipairs({
  "show_player", "open_cable", "ball_enter", "transfer_lr",
  "went_to", "transfer_rl", "show_enemy",
}) do
  check(seen[phase], "saw phase " .. phase)
end
eq(Game.stack:top(), nil, "TradeAnim pops itself")

S.finish()
