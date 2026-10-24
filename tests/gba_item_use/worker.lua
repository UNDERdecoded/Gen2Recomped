package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local f = dofile(root .. "/tests/gba_item_use/fixture.lua").new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/gba_item_use/cases.lua").run(f)
f.close()
for _, failing in ipairs({ false, true }) do
  local native = dofile(root .. "/tests/gba_item_use/fixture.lua").new(
    root,
    backend,
    version,
    tonumber(api),
    format,
    not failing,
    failing
  )
  if not failing then
    native.T.eq(native.result.loader.exports.portable_gba_item_use, nil, "no-mod filesystem excludes consumer")
  end
  if failing then
    native.T.check(#native.result.errors > 0, "entry rollback is recorded")
  end
  local ok, kind = native.use("POTION", 1)
  native.T.eq(ok, true, "no mod/rollback preserves native GBA effect")
  native.T.eq(kind, "heal", "no mod/rollback preserves native GBA kind")
  native.T.eq(native.count("POTION"), 2, "no mod/rollback consumes native item once")
  rows[#rows + 1] =
    { label = failing and "rollback" or "no mod", count = native.count("POTION"), hp = native.mon.hp }
  native.close()
end
print("GBA_ITEM_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable GBA field items")
