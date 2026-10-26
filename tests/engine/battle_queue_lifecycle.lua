-- Native insertion cursors and HP holds belong to one queue/drain, not to
-- later command menus. Exercise the real writers and retain their frame cost.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local original = Version.get()
local Battle = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local Save = require("src.core.SaveData")
local Timing = require("src.core.Timing")
for _, version in ipairs({ "red", "gold", "silver", "crystal", "firered", "emerald" }) do
  Version.set(version)
  local data = T.fixtures.fresh()
  require("src.render.Font").load(data)
  local save = Save.newGame()
  save.party = { Pokemon.new(data, "FIXMON_A", 30) }
  local game = { data = data, save = save, stack = { top = function() end } }
  local battle = Battle.newWild(game, "FIXMON_C", 40)
  battle.queue, battle.current = {}, nil
  local seen = {}
  battle:act(function()
    T.eq(battle.nextInsert, 0, version .. " callback owns insertion cursor")
    battle:actNext(function()
      seen[#seen + 1] = "nested"
      battle:actNext(function() seen[#seen + 1] = "inner" end)
    end)
    battle:actNext(function() seen[#seen + 1] = "sibling" end)
  end)
  battle:act(function() seen[#seen + 1] = "tail" end)
  for _ = 1, 5 do
    T.eq(battle:updateQueue(), true, version .. " one native callback per row")
    T.eq(battle.nextInsert, nil, version .. " callback releases insertion cursor")
  end
  T.same(seen, { "nested", "inner", "sibling", "tail" }, version .. " nested insertion order")
  T.eq(battle:updateQueue(), false, version .. " drained queue is idle")
  -- UI completions may call *Next outside a fn. This cursor must also retire
  -- when their final row completes, without changing insertion order.
  battle.nextInsert = 0
  battle:waitNext(1)
  for _ = 1, 5 do battle:updateQueue() end
  T.eq(battle.nextInsert, nil, version .. " UI-inserted queue releases cursor")
  for _, actor in ipairs({ battle.player, battle.enemy }) do
    -- One HP per bar pixel avoids the enemy's existing zero-cost trailing
    -- point batching; this regression concerns retirement, not that rounding.
    actor.mon.stats.hp, actor.mon.hp, actor.shownHP = 48, 40, 40
    local from = actor.mon.hp
    actor.mon.hp = from - 2
    local frames = 0
    while battle:stepHPDrain() and frames < 1000 do frames = frames + 1 end
    T.eq(frames, Timing.hpDrainFrames(from, actor.mon.hp, actor.mon.stats.hp,
      actor.isPlayer == true), version .. " exact native HP timing")
    T.eq(actor.shownHP, actor.mon.hp, version .. " actual HP caught up")
    T.eq(actor.draining, nil, version .. " drain retired")
    T.eq(actor.drainHold, nil, version .. " completed closing hold retired")
    T.eq(battle:stepHPDrain(), false, version .. " following frame remains idle")
  end
end
Version.set(original)
T.finish("native battle transient lifecycle")
