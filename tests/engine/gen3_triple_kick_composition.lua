package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ "delegate", "count", "full", "damage", "neverMiss", "fallback" }) do
    local entry
    if mode ~= "fallback" then
      entry = [[return function(mod)
        local base = assert(mod.content.move_effects:get("TRIPLE_KICK_EFFECT"))
        local count = base.hitCount
        mod.exports.counts, mod.exports.hits = 0, 0
        ]] .. (mode == "full" and 'base = {kind="full", hitCount=count}' or "") .. [[
        ]] .. (mode == "neverMiss" and "base.neverMiss = true" or "") .. [[
        base.hitCount = function(ctx)
          mod.exports.counts = mod.exports.counts + 1
          ]] .. (mode == "count" and "return 2" or "return count(ctx)") .. [[
        end
        ]] .. (mode == "damage" and [[
        base.chooseDamage = function() return 2, {crit=false,typeMult=10} end
        base.perHitDamage = function()
          mod.exports.hits = mod.exports.hits + 1
          return 2, {crit=false,typeMult=10}
        end
        ]] or "") .. [[
        assert(mod.content.move_effects:override("TRIPLE_KICK_EFFECT", base))
        mod.exports.api = mod
      end]]
    end
    local f = require("tests.enemy_actions.triple_kick").fixture(".", "gen2", version, entry)
    local c = f.fresh("TACKLE", { enemy = true })
    local b = c.battle
    b:syncSides()
    c.user.mon.moves = { { id = f.ids.TRIPLE_KICK, pp = 10 } }
    c.user.curMoves = c.user.mon.moves
    local original = b.data.move_effects
    if mode == "fallback" then
      b.data.move_effects = nil
    end
    local draws, hits = {}, {}
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo == 1 and hi == 100 and 1 or hi
    end
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    local off = f.e.api.events:on("battle.damage_dealt", function(e)
      hits[#hits + 1] = e.damage
    end)
    b:executeAction(c.user, c.target, c.user.curMoves[1])
    T.eq(#hits, mode == "count" and 2 or 3, "authored count remains authoritative")
    T.eq(c.user.curMoves[1].pp, 9, "composed Triple Kick spends one PP")
    local accuracy = 0
    for _, d in ipairs(draws) do
      if d[1] == 1 and d[2] == 100 then
        accuracy = accuracy + 1
      end
    end
    T.eq(
      accuracy,
      mode == "neverMiss" and 0 or mode == "full" and 1 or #hits,
      "complete authored scripts own their accuracy policy"
    )
    if mode == "delegate" or mode == "count" or mode == "fallback" then
      T.check(hits[1] < hits[2], "native delegation retains increasing kick power")
    elseif mode == "full" then
      T.eq(hits[1], hits[2], "complete authored override has no private native ramp")
    elseif mode == "damage" then
      T.same(hits, { 2, 2, 2 }, "explicit authored damage is not replaced")
      T.eq(f.e.hits, 3, "every authored per-hit handler runs")
    end
    if mode ~= "fallback" then
      T.eq(f.e.counts, 1, "count handler runs once per attack")
    end
    T.eq(
      require("src.battle.Gen3MoveEffects").full.TRIPLE_KICK_EFFECT.gbaTripleKick,
      nil,
      "per-load adapter leaves shared builtin statics untouched"
    )
    off()
    b.data.move_effects = original
    f.close()
  end
end
T.finish("native Triple Kick content composition")
