package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.targets").run(".", "gen2", version)
end
local function fresh(f)
  local b = f.fresh("TACKLE", { enemy = true }).battle
  b.double = true
  local S, copy = require("src.battle.BattleState"), require("src.mods.Merge").deepCopy
  b:placeBattler(2, S.makeBattler(f.data, copy(b.player.mon), true))
  b:placeBattler(3, S.makeBattler(f.data, copy(b.enemy.mon), false))
  b:syncSides()
  for _, actor in b:activeBattlers() do
    actor.mon.hp, actor.abilityOverride, actor.mon.item = 400, false, nil
    actor.curStats = { hp = 400, attack = 50, defense = 50, speed = 50, special = 50, spatk = 50, spdef = 50 }
    actor.mon.stats = actor.curStats
  end
  return b
end
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 1, "native")
  for _, row in ipairs({
    { true },
    { false },
    { "P2" },
    { {} },
    { -1 },
    { 4 },
    { 1.5 },
    { math.huge },
    { 0 / 0 },
    { function() end },
  }) do
    local b = fresh(f)
    f.e.choose(function()
      return { move = "TACKLE", target = row[1] }
    end)
    local ok, err = pcall(function()
      b:executeAction(b.enemy, b.player, b:enemyAction())
    end)
    T.check(ok, "malformed action target retains safe native fallback: " .. tostring(err))
    T.check(b.player.mon.hp < 400, "malformed action target still executes against ordinary foe")
    T.eq(b:battlerAt(2).mon.hp, 400, "malformed action target cannot select arbitrary actor")
  end
  local b = fresh(f)
  f.e.choose(function()
    return { move = "TACKLE", target = b:battlerAt(2) }
  end)
  b:executeAction(b.enemy, b.player, b:enemyAction())
  T.check(b:battlerAt(2).mon.hp < 400, "legacy native target handle still selects its actual actor")
  T.eq(b.player.mon.hp, 400, "legacy target handle preserves the other foe")
  local runs = {}
  for _, explicit in ipairs({ false, true }) do
    local randomBattle = fresh(f)
    randomBattle.data.moves[f.ids.TACKLE].target = 4
    local draws = {}
    randomBattle.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo
    end
    f.e.choose(function()
      return { move = "TACKLE", target = explicit and 2 or nil }
    end)
    randomBattle:executeAction(randomBattle.enemy, randomBattle.player, randomBattle:enemyAction())
    runs[#runs + 1] = {
      draws = draws,
      hp = { randomBattle.player.mon.hp, randomBattle:battlerAt(2).mon.hp },
      pp = randomBattle.enemy.curMoves[1].pp,
    }
  end
  T.same(runs[1], runs[2], "random-target policy ignores a chosen hint without adding target RNG")
  f.close()
end
T.finish("portable enemy targets")
