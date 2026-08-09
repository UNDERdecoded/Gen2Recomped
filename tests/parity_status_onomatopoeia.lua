-- Parity: sleep/confusion onomatopoeia on status-check text
-- (core.asm CheckPlayerStatusConditions / CheckEnemyStatusConditions).
-- Self-contained: `luajit tests/parity_status_onomatopoeia.lua`; also
-- dofile'd by tests/run_tests.lua's parity_* aggregator.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity status onomatopoeia")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
Game.data = Data
Game.save = require("src.core.SaveData").newGame()
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")

local function freshBattle()
  Game.save.party = { Pokemon.new(Data, "NIDOKING", 40) }
  return BattleState.newWild(Game, "DEWGONG", 30)
end

-- Capture queue order of anim/text rows inserted via *Next helpers.
local function capture(battle)
  local seq = {}
  battle.nextInsert = 0
  battle.queue = {}
  battle.animNext = function(_, name, isPlayer)
    seq[#seq + 1] = { kind = "anim", name = name, isPlayer = isPlayer }
  end
  battle.sayNext = function(_, text)
    seq[#seq + 1] = { kind = "text", text = text }
  end
  return seq
end

-- --- sleep: player anim-before-text, enemy text-before-anim -------------
do
  local b = freshBattle()
  b.rng = function() return 255 end
  local seq = capture(b)
  b.player.mon.status = "SLP"
  b.player.sleepTurns = 3
  check(b:statusInterrupt(b.player, b.enemy) == true, "sleep interrupts the turn")
  eq(#seq, 2, "sleep queues anim + text")
  eq(seq[1].kind, "anim", "player sleep: SLP_PLAYER_ANIM before text")
  eq(seq[1].name, "SLP_PLAYER_ANIM", "player sleep uses SLP_PLAYER_ANIM")
  eq(seq[1].isPlayer, true, "player sleep anim faces the player")
  check(seq[2].text:find("is fast asleep!", 1, true),
        "player sleep text follows the anim")
end

do
  local b = freshBattle()
  b.rng = function() return 255 end
  local seq = capture(b)
  b.enemy.mon.status = "SLP"
  b.enemy.sleepTurns = 3
  check(b:statusInterrupt(b.enemy, b.player) == true, "enemy sleep interrupts")
  eq(seq[1].kind, "text", "enemy sleep: FastAsleepText before anim")
  check(seq[1].text:find("Enemy ", 1, true),
        "enemy sleep text carries the Enemy prefix")
  eq(seq[2].name, "SLP_ANIM", "enemy sleep uses SLP_ANIM (enemy Z coords)")
  eq(seq[2].isPlayer, false, "enemy sleep anim faces the enemy")
end

do
  local b = freshBattle()
  local seq = capture(b)
  b.player.mon.status = "SLP"
  b.player.sleepTurns = 3
  check(b:preRechargeChecks(b.player, b.enemy) == true,
        "pre-recharge sleep still loses the turn")
  eq(seq[1].name, "SLP_PLAYER_ANIM",
     "pre-recharge sleep plays the same onomatopoeia")
end

-- --- confusion: text then CONF_*_ANIM (both sides) ---------------------
-- Status.beforeMove: rng(0,255) < 128 -> hurt itself; else can still move.
do
  local b = freshBattle()
  b.rng = function() return 200 end -- no self-hit
  local seq = capture(b)
  b.player.confusedTurns = 3
  b.player.mon.status = nil
  local stopped = b:statusInterrupt(b.player, b.enemy)
  check(stopped == false, "confusion can still allow a move")
  eq(seq[1].kind, "text", "player confusion: IsConfusedText before anim")
  check(seq[1].text:find("is confused!", 1, true), "player confusion text")
  eq(seq[2].name, "CONF_PLAYER_ANIM", "player confusion uses CONF_PLAYER_ANIM")
  eq(seq[2].isPlayer, true, "player confusion anim faces the player")
end

do
  local b = freshBattle()
  b.rng = function() return 0 end -- self-hit
  local seq = capture(b)
  b.computeDamage = function() return 1 end
  b.applyDamage = function() end
  b.onFaint = function() end
  b.enemy.confusedTurns = 3
  b.enemy.mon.status = nil
  local stopped = b:statusInterrupt(b.enemy, b.player)
  check(stopped == true, "confusion self-hit interrupts")
  eq(seq[1].kind, "text", "enemy confusion text first")
  check(seq[1].text:find("is confused!", 1, true), "enemy confusion text")
  eq(seq[2].name, "CONF_ANIM", "enemy confusion uses CONF_ANIM")
  eq(seq[2].isPlayer, false, "enemy confusion anim faces the enemy")
  check(seq[3] and seq[3].text:find("hurt itself", 1, true),
        "hurt-itself text follows the confusion anim")
end

-- wake stays text-only (no onomatopoeia)
do
  local b = freshBattle()
  b.rng = function() return 0 end
  local seq = capture(b)
  b.player.mon.status = "SLP"
  b.player.sleepTurns = 1
  b:statusInterrupt(b.player, b.enemy)
  eq(#seq, 1, "waking up is text-only")
  check(seq[1].text:find("woke up!", 1, true), "wake text")
end

S.finish()
