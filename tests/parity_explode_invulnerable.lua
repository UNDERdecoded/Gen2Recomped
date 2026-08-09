-- Parity test: Self-Destruct/Explosion against a mid-Fly/Dig
-- (semi-invulnerable) target still faints the user (#528).
--
-- EffectRegistry.runDamaging's target.invulnerable branch prints the miss
-- text and returned without ever calling record.onMiss, while the
-- accuracy-roll, type-immunity and floored-damage miss branches all did.
-- EXPLODE_EFFECT (src/battle/MoveEffects.lua) relies on onMiss to run
-- battle:selfDestruct(user); skipping it left the user at full HP.
--
-- pokered engine/battle/core.asm MoveHitTest: "bit INVULNERABLE, [hl] /
-- jp nz, .moveMissed" sets the same wMoveMissed as a failed accuracy roll,
-- and the shared miss handler runs the explode effect regardless of which
-- branch set it ("even if Explosion or Selfdestruct missed, its effect
-- still needs to be activated"). JUMP_KICK_EFFECT's onMiss filters on
-- reason == "accuracy", so a crash-damage kick must NOT also fire here.
--
-- Self-contained; run via `luajit tests/parity_explode_invulnerable.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity explode invulnerable")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
Data:load()

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = require("src.core.SaveData").newGame()

-- Self-Destruct against a target mid-Fly (invulnerable, never-miss moves
-- aside): the move never rolls accuracy at all, it just hits the
-- invulnerable branch in EffectRegistry.runDamaging.
local function selfDestructVsInvulnerable(moveId)
  Game.save.party = { Pokemon.new(Data, "GEODUDE", 30) }
  local b = BattleState.newWild(Game, "PIDGEY", 20)
  b.enemy.invulnerable = true -- mid-Fly/Dig, set by ChargeEffect on turn 1
  local hpBefore = b.enemy.mon.hp
  b:performMove(b.player, b.enemy, { id = moveId, pp = 5 })
  return b, hpBefore
end

for _, moveId in ipairs({ "SELFDESTRUCT", "EXPLOSION" }) do
  local b, enemyHpBefore = selfDestructVsInvulnerable(moveId)
  eq(b.player.mon.hp, 0, moveId .. " vs an invulnerable target still faints the user")
  eq(b.enemy.mon.hp, enemyHpBefore,
     moveId .. " vs an invulnerable target deals the target no damage")
  local sawMiss = false
  for _, r in ipairs(b.queue) do
    if r.text and r.text:find("attack missed", 1, true) then sawMiss = true end
  end
  check(sawMiss, moveId .. " still prints the miss text against an invulnerable target")
end

-- Companion: JUMP_KICK's onMiss must reject the "invulnerable" reason, so
-- a mid-Fly target does not also take Jump Kick's crash damage (its
-- onMiss guard only fires for reason == "accuracy").
Game.save.party = { Pokemon.new(Data, "GEODUDE", 30) }
local jk = BattleState.newWild(Game, "PIDGEY", 20)
jk.enemy.invulnerable = true
local jkHpBefore = jk.player.mon.hp
jk:performMove(jk.player, jk.enemy, { id = "JUMP_KICK", pp = 5 })
eq(jk.player.mon.hp, jkHpBefore,
   "JUMP KICK vs an invulnerable target takes no crash damage (reason filter holds)")

S.finish()
