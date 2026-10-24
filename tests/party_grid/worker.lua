package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local f = dofile(root .. "/tests/party_grid/fixture.lua").new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/party_grid/cases.lua").run(f)
f.close()
print("PARTY_GRID_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable ui.party.grid_navigation native controllers")
