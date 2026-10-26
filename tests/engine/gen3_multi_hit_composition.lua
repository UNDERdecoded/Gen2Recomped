package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ "delegate", "override", "damage", "fallback" }) do
    local entry
    if mode ~= "fallback" then
      entry = [[return function(mod)
    local base=assert(mod.content.move_effects:get('TWO_TO_FIVE_ATTACKS_EFFECT'))
    local count=base.hitCount
    mod.exports.counts,mod.exports.hits=0,0
    base.hitCount=function(ctx)
      mod.exports.counts=mod.exports.counts+1
      ]] .. (mode == "delegate" and "return count(ctx)" or "return 4") .. [[
    end
    ]] .. (mode == "damage" and [[
    base.chooseDamage=function() return 2,{crit=false,typeMult=10} end
    base.perHitDamage=function()
      mod.exports.hits=mod.exports.hits+1
      return 2,{crit=false,typeMult=10}
    end
    ]] or "") .. [[
    assert(mod.content.move_effects:override('TWO_TO_FIVE_ATTACKS_EFFECT',base))
    mod.exports.api=mod
   end]]
    end
    local f = require("tests.enemy_actions.multi_hit").fixture(".", "gen2", version, entry)
    local c = f.fresh("TACKLE", { enemy = true })
    local b = c.battle
    b:syncSides()
    c.user.mon.moves = { { id = f.ids.DOUBLE_SLAP, pp = 10 } }
    c.user.curMoves = c.user.mon.moves
    local original = b.data.move_effects
    if mode == "fallback" then
      b.data.move_effects = nil
    end
    local draws, hits = {}, {}
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return hi
    end
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    local off = f.e.api.events:on("battle.damage_dealt", function(e)
      hits[#hits + 1] = e.damage
    end)
    b:executeAction(c.user, c.target, c.user.curMoves[1])
    T.eq(
      #hits,
      (mode == "delegate" or mode == "fallback") and 5 or 4,
      "authored count or native delegation controls the actual hits"
    )
    T.eq(c.user.curMoves[1].pp, 9, "composed multi-hit spends exactly one PP")
    if mode ~= "fallback" then
      T.eq(f.e.counts, 1, "the public count handler is called once")
    end
    if mode == "damage" then
      T.eq(f.e.hits, 4, "explicit authored per-hit damage is never replaced")
      T.same(hits, { 2, 2, 2, 2 }, "authored per-hit amounts reach real HP and events")
    end
    if mode == "delegate" or mode == "fallback" then
      T.same(draws[2], { 0, 3 }, "native count keeps its raw bounded RNG opcode")
    end
    local before = #hits
    f.data.moves[f.ids.DOUBLE_SLAP].accuracy = 90
    b:executeAction(c.user, c.target, c.user.curMoves[1])
    T.eq(#hits, before, "a failed accuracy check emits no hit")
    if mode ~= "fallback" then
      T.eq(f.e.counts, 1, "a failed accuracy check never invokes authored hit count")
    end
    off()
    b.data.move_effects = original
    f.close()
  end
  for _, caller in ipairs({ "sleep_talk", "other" }) do
    local f = require("tests.enemy_actions.multi_hit").fixture(".", "gen2", version)
    local c = f.fresh("TACKLE")
    local b = c.battle
    b:syncSides()
    -- Test the actual nested dispatcher after the calling move's selection.
    f.data.moves.CALLER = {
      id = "CALLER",
      index = caller == "sleep_talk" and 214 or 118,
      gen3Effect = caller == "sleep_talk" and 97 or 83,
      name = "CALLER",
      power = 0,
      type = "NORMAL",
      accuracy = 100,
      pp = 10,
      effect = "TEST_CALLER",
    }
    b.data.move_effects.TEST_CALLER = {
      kind = "full",
      callsMove = function()
        return f.ids.DOUBLE_SLAP
      end,
    }
    c.user.mon.status = "SLP"
    c.user.curMoves = { { id = "CALLER", pp = 10 } }
    c.user.mon.moves = c.user.curMoves
    local hits = 0
    local off = f.e.api.events:on("battle.damage_dealt", function()
      hits = hits + 1
    end)
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    b.rng = function(_, hi)
      return hi
    end
    b:performMove(c.user, c.target, c.user.curMoves[1])
    T.eq(
      hits,
      caller == "sleep_talk" and 5 or 1,
      "only a real Sleep Talk parent exempts sleeping multi-hit continuation"
    )
    T.eq(c.user.curMoves[1].pp, 9, "the actual calling slot alone spends PP")
    T.eq(b._gbaMoveFrame, nil, "nested frames restore the native dispatcher after completion")
    off()
    f.close()
  end
end
local M = require("src.battle.Gen3MultiHit")
local raw = require("src.battle.MoveEffects").RECORDS.TWO_TO_FIVE_ATTACKS_EFFECT
V.set("firered")
local adapted = M.builtin("TWO_TO_FIVE_ATTACKS_EFFECT", raw)
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  V.set(version)
  T.eq(M.builtin("TWO_TO_FIVE_ATTACKS_EFFECT", raw), raw, "older games keep original builtin identity")
  local calls = {}
  local ctx = {
    move = {},
    rng = function(lo, hi)
      calls[#calls + 1] = { lo, hi }
      return hi
    end,
  }
  T.eq(adapted.hitCount(ctx), 5, "a reused native adapter delegates back to legacy policy")
  T.same(calls, { { 0, 7 } }, "older games keep the original eight-value hit-count draw")
end
T.finish("native ordinary multi-hit builtin composition and called-move boundaries")
