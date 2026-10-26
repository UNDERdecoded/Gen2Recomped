-- Composed proof: also requires the canonical effect adapter from #121.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
require("src.mods.UnifiedEffects")
for _, version in ipairs({ "firered", "emerald" }) do
  local entry = [[return function(mod)
    assert(mod.content.moves:patch("TACKLE",{effect="SPIT_UP",power=100}))
    mod.exports.effect=assert(mod.content.moves:get("TACKLE")).effect
    local selected="STOCKPILE"
    mod.exports.release=function() selected="TACKLE" end
    mod.exports.hits,mod.exports.calls={},{crit=0,damage=0}
    mod.hooks:wrap("battle.enemy_action",function() return {move=selected,target=0} end)
    mod.hooks:wrap("battle.crit",function() mod.exports.calls.crit=mod.exports.calls.crit+1;return true end)
    mod.hooks:wrap("battle.damage",function(nextDamage,...)
      mod.exports.calls.damage=mod.exports.calls.damage+1;return nextDamage(...)
    end)
    mod.events:on("battle.damage_dealt",function(e)
      mod.exports.hits[#mod.exports.hits+1]={amount=e.damage,crit=e.crit,target=e.target.mon.nickname}
    end)
  end]]
  local function configure(data, _, ids)
    ids.STOCKPILE = "MOVE_254"
    data.moves.MOVE_254 = {
      id = "MOVE_254",
      index = 254,
      name = "STOCKPILE",
      type = "NORMAL",
      power = 0,
      pp = 20,
      accuracy = 100,
      accuracyRaw = 255,
      effect = "STOCKPILE_EFFECT",
      gen3Effect = 160,
      target = 16,
      protectAffected = false,
    }
    data.moves[ids.TACKLE].target = 0
  end
  local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure, entry)
  local b = f.fresh("TACKLE", { enemy = true }).battle
  T.eq(f.e.effect, "SPIT_UP", "canonical effect roundtrips through the real loader")
  T.eq(f.data.moves[f.ids.TACKLE].gen3Effect, 161, "canonical effect selects native semantic 161")
  for _, a in ipairs({ b.player, b.enemy }) do
    a.curTypes, a.abilityOverride = { "NORMAL" }, false
    a.curStats = { hp = 10000, attack = 50, defense = 50, speed = 50, special = 50, spatk = 50, spdef = 50 }
    a.mon.stats, a.mon.hp = a.curStats, 10000
  end
  b.player.mon.nickname = "TARGET"
  b.enemy.curMoves = { { id = f.ids.STOCKPILE, pp = 20 }, { id = f.ids.TACKLE, pp = 10 } }
  b.enemy.mon.moves = b.enemy.curMoves
  for i = 1, 2 do
    b:executeAction(b.enemy, b.player, b:enemyAction(b.enemy))
  end
  f.e.release()
  b:executeAction(b.enemy, b.player, b:enemyAction(b.enemy))
  T.same(
    f.e.hits,
    { { amount = 90, crit = false, target = "TARGET" } },
    "canonical patch releases the real two-stack base"
  )
  T.same(
    f.e.calls,
    { crit = 0, damage = 0 },
    "native set damage does not enter ordinary mod damage or critical hooks"
  )
  T.eq(b.enemy.stockpile, 0, "release consumes the counter")
  T.eq(b.enemy.curMoves[1].pp, 18, "real Stockpile casts consume their owned PP")
  T.eq(b.enemy.curMoves[2].pp, 9, "real release consumes its owned PP")
  f.close()
end
T.finish("composed public Spit Up effect")
