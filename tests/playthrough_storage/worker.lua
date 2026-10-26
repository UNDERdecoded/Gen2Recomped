package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local f = dofile(root .. "/tests/playthrough_storage/fixture.lua").new(root, backend, version)
local rows = dofile(root .. "/tests/playthrough_storage/cases.lua").run(f, version)
local lifecycle = dofile(root .. "/tests/playthrough_storage/lifecycle.lua").run(f, version)
for _, row in ipairs(lifecycle) do
  rows[#rows + 1] = row
end
f.close()
print("STORAGE_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable playthrough storage")
