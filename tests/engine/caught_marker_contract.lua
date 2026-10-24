package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Runtime = require("src.core.GameVersion"), require("src.mods.Runtime")
local Fixture = dofile("tests/caught_marker/fixture.lua")
local old = V.get()
for _, version in ipairs(V.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    T.eq(
      f.e.api:supports("hooks", "battle.caught_marker_visible"),
      f.gen <= 3,
      "version-aware marker capability"
    )
    if f.gen <= 3 then
      dofile("tests/caught_marker/cases.lua").run(f)
    else
      f.e.state.mode = "show"
      T.eq(f.visible(), false, "DS helper never dispatches unavailable marker hook")
      T.eq(f.e.state.calls, 0, "DS callback remains unused")
    end
    f.close()
    for _, failing in ipairs({ false, true }) do
      local bare = Fixture.new(".", "gen2", version, mode[1], mode[2], not failing, failing)
      if failing then
        T.check(#bare.result.errors > 0, "failed entry recorded")
      else
        T.eq(bare.result.loader.exports.portable_caught_marker, nil, "no-mod consumer is absent")
      end
      for _, link in ipairs(Runtime.hooks.chains["battle.caught_marker_visible"] or {}) do
        T.check(link.owner ~= "portable_caught_marker", "rollback removes marker wrappers")
      end
      local call = Runtime.call
      Runtime.call = function(name, ...)
        assert(name ~= "battle.caught_marker_visible", "empty-chain marker path dispatched")
        return call(name, ...)
      end
      T.eq(bare.visible(), bare.gen > 1 and bare.gen <= 3, "native default after no-mod/rollback")
      Runtime.call = call
      bare.close()
    end
  end
end
V.set(old)
T.finish("native caught marker hook and public SDK contracts")
