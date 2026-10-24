package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local Fixture = dofile(root .. "/tests/held_item/fixture.lua")
local f = Fixture.new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/held_item/scheduling.lua").run(f)
for _, row in ipairs(dofile(root .. "/tests/held_item/cases.lua").run(f)) do rows[#rows + 1] = row end
f.close()
-- Keep the raw native policy in the report as well as the paired action/
-- residual cases. Strict CI compares the complete record, including reads.
local policy = Fixture.new(root, backend, version, tonumber(api), format)
policy.e.state.mode, policy.e.state.trigger, policy.e.state.holder = "override", "residual", "PLAYER"
policy.e.state.effect, policy.e.state.parameter, policy.e.state.requiresItem = "HELD_BERRY", 7, false
policy.mon("player").hp = 100
policy.residual()
local nativePolicy = {
  unrestricted_residual_heal = policy.mon("player").hp - 100,
  residual_reads = policy.e.state.seen.residual,
}
policy.close()
print("HELD_ITEM_NATIVE_POLICY " .. require("src.link.Json").encode(nativePolicy))
for _, failing in ipairs({ false, true }) do
  local bare = Fixture.new(root, backend, version, tonumber(api), format, not failing, failing)
  if failing then
    bare.T.check(#bare.result.errors > 0, "entry failure recorded")
  else
    bare.T.eq(bare.result.loader.exports.portable_held_item, nil, "genuine no-mod fixture")
  end
  for _, link in ipairs(require("src.mods.Runtime").hooks.chains["held_item.trigger"] or {}) do
    bare.T.check(link.owner ~= "portable_held_item", "rollback removes held owner")
  end
  bare.mon("player").hp = 100
  bare.residual()
  bare.T.eq(bare.mon("player").hp, 125, "no-mod/rollback native Leftovers")
  bare.close()
  rows[#rows + 1] = { label = failing and "rollback" or "no mod", healed = 25 }
end
print("HELD_ITEM_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable held-effect decisions and native residuals")
