package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Runtime = require("src.core.GameVersion"), require("src.mods.Runtime")
local Fixture, Cases = dofile("tests/field_residual/fixture.lua"), dofile("tests/field_residual/cases.lua")
local old = V.get()
for _, version in ipairs(V.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    T.eq(f.e.api:supports("hooks", "battle.field_residual"), f.gen <= 3, "honest native field capability")
    if f.gen <= 3 then
      Cases.run(f)
    else
      f.e.state.requests = { { side = "player", amount = 99999 } }
      f.run()
      T.eq(f.e.state.calls, 0, "DS never dispatches unavailable field hook")
      T.eq(f.hp("player"), 400, "DS ignores unavailable field requests")
    end
    f.close()
    for _, failing in ipairs({ false, true }) do
      local bare = Fixture.new(".", "gen2", version, mode[1], mode[2], not failing, failing)
      if failing then
        T.check(#bare.result.errors > 0, "entry failure recorded")
      else
        T.eq(bare.result.loader.exports.portable_field_residual, nil, "genuine no-mod fixture")
      end
      for _, link in ipairs(Runtime.hooks.chains["battle.field_residual"] or {}) do
        T.check(link.owner ~= "portable_field_residual", "rollback removes field owner")
      end
      local call = Runtime.call
      Runtime.call = function(name, ...)
        assert(name ~= "battle.field_residual", "empty field hook chain dispatched")
        return call(name, ...)
      end
      require("src.battle.FieldResiduals").apply(setmetatable({}, {
        __index = function()
          error("empty-chain field path inspected battle")
        end,
      }))
      bare.run()
      Runtime.call = call
      T.eq(bare.hp("player"), 400, "no-mod/rollback native player HP")
      T.eq(bare.hp("enemy"), 400, "no-mod/rollback native enemy HP")
      bare.close()
    end
  end
end
V.set(old)
T.finish("native field residuals and public SDK contracts")
