package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local f =
  dofile(root .. "/tests/field_residual/fixture.lua").new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/field_residual/cases.lua").run(f)
f.close()
for _, failing in ipairs({ false, true }) do
  local bare = dofile(root .. "/tests/field_residual/fixture.lua").new(
    root,
    backend,
    version,
    tonumber(api),
    format,
    not failing,
    failing
  )
  if failing then
    bare.T.check(#bare.result.errors > 0, "failed entry recorded")
  else
    bare.T.eq(bare.result.loader.exports.portable_field_residual, nil, "genuine no-mod filesystem")
  end
  for _, link in ipairs(require("src.mods.Runtime").hooks.chains["battle.field_residual"] or {}) do
    bare.T.check(link.owner ~= "portable_field_residual", "rollback removes field owner")
  end
  bare.run()
  bare.T.eq(bare.hp("enemy"), 400, "no-mod/rollback preserves native enemy HP")
  bare.T.check(bare.hp("player") > 0, "no-mod/rollback preserves living native player")
  if backend ~= "gen1" or bare.gen ~= 2 then
    bare.T.eq(bare.hp("player"), 400, "no-mod/rollback adds no field damage")
  end
  bare.close()
  rows[#rows + 1] = { label = failing and "rollback" or "no mod", native = true }
end
print("FIELD_RESIDUAL_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable native field residuals")
