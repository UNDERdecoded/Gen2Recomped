package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local f = dofile(root .. "/tests/item_use/fixture.lua").new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/item_use/cases.lua").run(f)
f.close()
for _, failing in ipairs({ false, true }) do
  local native = dofile(root .. "/tests/item_use/fixture.lua").new(
    root,
    backend,
    version,
    tonumber(api),
    format,
    not failing,
    failing
  )
  if failing then
    native.T.check(#native.result.errors > 0, "entry rollback is recorded")
  end
  native.begin("POTION", false)
  native.target()
  native.T.eq(native.count("POTION"), 2, "no mod/rollback retain actual native item effect")
  rows[#rows + 1] = { label = failing and "rollback" or "no mod", count = native.count("POTION") }
  native.close()
end
print("ITEM_USE_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable GB item dispatch")
