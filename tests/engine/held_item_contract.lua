package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Runtime = require("src.core.GameVersion"), require("src.mods.Runtime")
local Fixture, Cases = dofile("tests/held_item/fixture.lua"), dofile("tests/held_item/cases.lua")
local old = V.get()
for _, version in ipairs(V.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local available = f.gen == 2 or f.gen == 3
    T.eq(f.e.api:supports("hooks", "held_item.trigger"), available, "honest held comparison capability")
    if available then
      Cases.run(f)
    else
      f.e.state.mode, f.e.state.effect, f.e.state.parameter = "override", "HELD_BERRY", 7
      f.read("residual")
      T.eq(f.e.state.calls, 0, "GB/DS never dispatch unavailable held seam")
    end
    f.close()
    for _, failing in ipairs({ false, true }) do
      local bare = Fixture.new(".", "gen2", version, mode[1], mode[2], not failing, failing)
      if failing then
        T.check(#bare.result.errors > 0, "entry failure recorded")
      else
        T.eq(bare.result.loader.exports.portable_held_item, nil, "genuine no-mod fixture")
      end
      for _, link in ipairs(Runtime.hooks.chains["held_item.trigger"] or {}) do
        T.check(link.owner ~= "portable_held_item", "rollback removes held owner")
      end
      local call = Runtime.call
      Runtime.call = function(name, ...)
        assert(name ~= "held_item.trigger", "empty held chain dispatched")
        return call(name, ...)
      end
      bare.mon("player").hp = 100
      bare.residual()
      Runtime.call = call
      T.eq(bare.mon("player").hp, bare.gen == 1 and 100 or 125, "native no-mod/rollback held behavior")
      bare.close()
    end
  end
end
V.set(old)
T.finish("native held-item public contract and generation boundaries")
