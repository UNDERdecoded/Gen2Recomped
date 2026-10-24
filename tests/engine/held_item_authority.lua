package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local Fixture = dofile("tests/held_item/fixture.lua")
local old = V.get()
for _, version in ipairs({ "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local e = f.e
    local b = f.battle
    local holder = b.enemy
    -- External/link constructors and replacements bind to the real battle.
    local replacement = require("src.battle.BattleState").makeBattler(f.data, holder.mon, false)
    b:placeBattler(1, replacement)
    f.read("damage", "enemy")
    T.eq(e.state.last.battle, b, "placed battler is bound to actual battle")
    T.eq(e.state.last.mon.nickname, "ENEMY", "placed holder has actual Pokemon")
    b.enemy = require("src.battle.BattleState").makeBattler(f.data, replacement.mon, false)
    b:syncSides()
    collectgarbage("collect")
    f.read("accuracy", "enemy")
    T.eq(e.state.last.battle, b, "sync binds external/linked battlers across GC")
    -- Field/party reads do not turn into battle comparisons.
    f.reset("LEFTOVERS")
    local before = e.state.calls
    require("src.battle.HeldItems").effect(f.data, f.mon("player"), "damage")
    require("src.battle.HeldItems").cleanseTagRate(f.data, { f.mon("player") }, 100)
    T.eq(e.state.calls, before, "raw field/party item reads do not dispatch battle hook")
    if mode[2] == "unified" then
      f.reset("LEFTOVERS")
      local off = e.api.hooks:wrap("held_item.trigger", function(next, ctx)
        ctx.mon.hp = 1
        ctx.def.heldEffect = {}
        return next(ctx)
      end, 100)
      T.eq(f.read("residual"), f.effect("HELD_LEFTOVERS"), "invalid definition edit recovers native verdict")
      off()
      T.eq(f.mon("player").hp, 400, "invalid definition edit cannot partially commit Pokemon changes")
      T.eq(e.state.last.effect, "HELD_LEFTOVERS", "invalid definition edit does not mutate stored effect")
    end
    if f.gen == 2 then
      b = f.reset("LEFTOVERS")
      e.state.mode, e.state.effect, e.state.trigger = "override", "HELD_PORTABLE_CUSTOM", "damage"
      T.eq(
        f.read("damage"),
        "HELD_PORTABLE_CUSTOM",
        "Gold retains unknown named effects for native comparisons"
      )
      local nativeItem = f.data.items.LEFTOVERS
      T.eq(nativeItem.heldEffect, 3, "effect substitution does not rewrite stored attributes")
      T.eq(nativeItem.heldParam, 10, "effect substitution does not rewrite stored parameter")
    else
      b = f.reset("LEFTOVERS")
      local nativeItem = f.data.items.ITEM_200
      for _, name in ipairs({ "HELD_QUICK_CLAW", "HELD_BRIGHTPOWDER", "HELD_FOCUS_BAND", "HELD_FLINCH" }) do
        for _, parameter in ipairs({ -10, 0, 256, 300 }) do
          e.state.mode, e.state.effect, e.state.parameter = "override", name, parameter
          local _, actual = f.read("check")
          T.eq(
            actual,
            math.max(0, math.min(256, parameter)) * 100 / 256,
            "GBA public byte odds clamp at native boundary"
          )
        end
      end
      T.eq(nativeItem.holdEffect, "LEFTOVERS", "GBA substitution leaves imported held enum unchanged")
      T.eq(nativeItem.holdEffectParam, 10, "GBA substitution leaves imported parameter unchanged")
    end
    f.close()
  end
end
V.set(old)
T.finish("held item native ownership and metadata transaction authority")
