-- Composed proof: requires the public canonical effect adapter from #121.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
require("src.mods.UnifiedEffects")
for _, version in ipairs({ "firered", "emerald" }) do
  local entry = [[return function(mod)
    assert(mod.content.moves:patch("TACKLE",{effect="EFFECT_BEAT_UP",power=10}))
    assert(mod.content.pokemon:patch("CHARMANDER",{baseStats={attack=133,defense=40}}))
    mod.exports.effect=assert(mod.content.moves:get("TACKLE")).effect
    mod.exports.attack=assert(mod.content.pokemon:get("CHARMANDER")).baseStats.attack
    mod.exports.hits,mod.exports.calls={},{crit=0,damage=0}
    mod.hooks:wrap("battle.enemy_action",function() return {move="TACKLE",target=0} end)
    mod.hooks:wrap("battle.crit",function() mod.exports.calls.crit=mod.exports.calls.crit+1;return true end)
    mod.hooks:wrap("battle.damage",function(nextDamage,...)
      mod.exports.calls.damage=mod.exports.calls.damage+1;return nextDamage(...)
    end)
    mod.events:on("battle.damage_dealt",function(e)
      mod.exports.hits[#mod.exports.hits+1]={amount=e.damage,crit=e.crit,kind=e.kind}
    end)
  end]]
  local function configure(data, _, ids)
    data.moves[ids.TACKLE].target = 0
  end
  local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure, entry)
  local b = f.fresh("TACKLE", { enemy = true }).battle
  T.eq(f.e.effect, "EFFECT_BEAT_UP", "canonical effect roundtrips through the real loader")
  T.eq(f.e.attack, 133, "public species base patch loads")
  T.eq(f.data.moves[f.ids.TACKLE].gen3Effect, 154, "canonical effect selects native semantic 154")
  local second = require("src.mods.Merge").deepCopy(b.enemy.mon)
  b.enemy.mon.level, second.level = 10, 30
  b.enemyParty = { b.enemy.mon, second }
  b.rng = function(lo, hi)
    if lo == 85 and hi == 100 then
      return 100
    end
    if lo == 1 and hi == 16 then
      return 16
    end
    return lo or 0
  end
  b:executeAction(b.enemy, b.player, b:enemyAction(b.enemy))
  T.same(
    f.e.hits,
    { { amount = 5, crit = false, kind = "special" }, { amount = 11, crit = false, kind = "special" } },
    "the patched native effect reads each party level and the public species base"
  )
  T.same(f.e.calls, { crit = 0, damage = 0 }, "scripted strikes bypass ordinary damage and critical hooks")
  T.eq(b.enemy.curMoves[1].pp, 9, "the whole sequence consumes owned PP once")
  T.eq(b.player.specialDamageTaken, 11, "counter memory keeps the final strike")
  f.close()
end
T.finish("composed public Beat Up effect")
