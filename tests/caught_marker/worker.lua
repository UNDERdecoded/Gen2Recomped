package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local Fixture = dofile(root .. "/tests/caught_marker/fixture.lua")
local f = Fixture.new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/caught_marker/cases.lua").run(f)
f.close()
for _, failing in ipairs({ false, true }) do
  local bare = Fixture.new(root, backend, version, tonumber(api), format, not failing, failing)
  if failing then
    bare.T.check(#bare.result.errors > 0, "intentional failed entry recorded")
  else
    bare.T.eq(bare.result.loader.exports.portable_caught_marker, nil, "genuine no-mod filesystem")
  end
  for _, link in ipairs(require("src.mods.Runtime").hooks.chains["battle.caught_marker_visible"] or {}) do
    bare.T.check(link.owner ~= "portable_caught_marker", "no rollback owner survives")
  end
  bare.T.eq(bare.visible(), bare.gen > 1, "no-mod/rollback restores native default")
  rows[#rows + 1] = { label = failing and "rollback" or "no mod", visible = bare.visible() }
  bare.close()
end
print("CAUGHT_MARKER_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable native caught marker")
