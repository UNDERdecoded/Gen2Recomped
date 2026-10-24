package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local Fixture = dofile(root .. "/tests/charge_required/fixture.lua")
local f = Fixture.new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/charge_required/cases.lua").run(f)
f.close()
for _, failing in ipairs({ false, true }) do
  local native = Fixture.new(root, backend, version, tonumber(api), format, not failing, failing)
  if failing then
    native.T.check(#native.result.errors > 0, "failed entry recorded")
  else
    native.T.eq(native.result.loader.exports.portable_charge_required, nil, "genuine no-mod filesystem")
  end
  for _, link in ipairs(require("src.mods.Runtime").hooks.chains["battle.charge_required"] or {}) do
    native.T.check(link.owner ~= "portable_charge_required", "no-mod/rollback removes owner")
  end
  local b = native.fresh("FLY")
  local pp, hp = b.pp(), b.hp()
  b.use()
  native.T.eq(b.charging(), true, "no-mod/rollback native charge")
  rows[#rows + 1] = {
    label = failing and "rollback" or "no mod",
    charging = b.charging(),
    spent = pp - b.pp(),
    damaged = b.hp() < hp,
  }
  native.close()
end
print("CHARGE_NATIVE_POLICY " .. require("src.link.Json").encode(f.nativePolicy))
print("CHARGE_REQUIRED_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable native charge decisions")
