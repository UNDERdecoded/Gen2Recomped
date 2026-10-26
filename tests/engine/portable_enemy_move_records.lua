package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.records").run(".", "gen2", version)
end
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 1, "native")
  local c = f.fresh("TACKLE", { enemy = true })
  local b = c.battle
  local detached = require("src.mods.Merge").deepCopy(b.enemy)
  detached.curMoves = { { id = f.ids.SCRATCH, pp = 7 } }
  detached.mon.moves = detached.curMoves
  f.e.choose(function(nextAction, battle)
    return nextAction(battle, detached)
  end)
  local action = b:enemyAction()
  T.eq(action.id, f.ids.SCRATCH, "native cloned-actor query remains supported")
  b:executeAction(b.enemy, b.player, action)
  T.eq(b.enemy.curMoves[1].pp, 9, "native cloned-actor choice spends caller PP")
  T.eq(detached.curMoves[1].pp, 7, "native cloned-actor query does not mutate queried PP")
  f.close()
end
for _, version in ipairs({ "firered", "emerald" }) do
  for _, field in ipairs({ "move", "id" }) do
    for _, changeNative in ipairs({ false, true }) do
      local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified")
      local c = f.fresh("TACKLE", { enemy = true })
      local b = c.battle
      b.enemy.curMoves[2] = { id = f.ids.SCRATCH, pp = 7 }
      f.e.choose(function()
        return { [field] = "SCRATCH" }
      end)
      local nativeValue, publicValue
      local stopNative = f.result.loader.hooks:wrap("battle.enemy_action", function(nextAction, ...)
        local action = nextAction(...)
        nativeValue = action[field]
        if changeNative then
          action[field] = f.ids.TACKLE
        end
        return action
      end, 100, "native-result-fixture")
      local stopPublic = f.e.api.hooks:wrap("battle.enemy_action", function(nextAction, ...)
        local action = nextAction(...)
        publicValue = action[field]
        return action
      end, 200)
      local action = b:enemyAction()
      T.eq(nativeValue, f.ids.SCRATCH, "mixed native hook retains physical move representation")
      local expected = changeNative and (field == "move" and 33 or "TACKLE") or "SCRATCH"
      T.eq(publicValue, expected, "public view retains authored form or observes native rewrite")
      b:executeAction(b.enemy, b.player, action)
      T.eq(
        b.enemy.curMoves[1].pp,
        changeNative and 9 or 10,
        "mixed result preserves native rewrite PP ownership"
      )
      T.eq(b.enemy.curMoves[2].pp, changeNative and 7 or 6, "mixed result spends actual selected PP")
      stopPublic()
      stopNative()
      f.close()
    end
  end
end
T.finish("portable enemy move records")
