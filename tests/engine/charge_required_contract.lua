package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version, Runtime = require("src.core.GameVersion"), require("src.mods.Runtime")
local Fixture, Cases = dofile("tests/charge_required/fixture.lua"), dofile("tests/charge_required/cases.lua")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    T.eq(
      f.e.api:supports("hooks", "battle.charge_required"),
      f.gen <= 3,
      "native charge capability is honest"
    )
    if f.gen <= 3 then
      Cases.run(f)
      local off = f.e.api.hooks:wrap("battle.charge_required", function()
        return false
      end)
      local b = f.fresh("FLY")
      b.use()
      T.eq(b.charging(), false, "fresh public bypass works after consumer unsubscribe")
      if f.gen == 3 then
        local seen = false
        for _, row in ipairs(b.battle.queue) do
          if row.anim == f.ids.FLY then
            seen = true
            T.eq(row.animContext.moveTurn, 1, "GBA bypass uses native release animation branch")
          end
        end
        T.eq(seen, true, "GBA bypass retains ordinary move animation")
      end
      off()
    else
      local calls = 0
      local off = f.e.api.hooks:wrap("battle.charge_required", function()
        calls = calls + 1
        return false
      end)
      local b = f.fresh("FLY")
      b.use()
      T.eq(calls, 0, "DS does not dispatch unavailable seam")
      T.eq(b.charging(), true, "DS native charge flow is preserved")
      off()
    end
    f.close()
    for _, failing in ipairs({ false, true }) do
      local baseline = Fixture.new(".", "gen2", version, mode[1], mode[2], not failing, failing)
      if failing then
        T.check(#baseline.result.errors > 0, "entry failure is recorded")
      else
        T.eq(baseline.result.loader.exports.portable_charge_required, nil, "no-mod consumer is absent")
      end
      for _, link in ipairs(Runtime.hooks.chains["battle.charge_required"] or {}) do
        T.check(link.owner ~= "portable_charge_required", "entry rollback removes owner")
      end
      local call = Runtime.call
      Runtime.call = function(name, ...)
        assert(name ~= "battle.charge_required", "unsubscribed hot path invoked charge producer")
        return call(name, ...)
      end
      local b = baseline.fresh("FLY")
      local pp = b.pp()
      b.use()
      Runtime.call = call
      T.eq(b.charging(), true, "no-mod/rollback restores native continuation")
      T.eq(pp - b.pp(), 1, "no-mod/rollback spends native player PP once")
      baseline.close()
    end
  end
end
Version.set(old)
T.finish("native charge-required decisions and public contract")
