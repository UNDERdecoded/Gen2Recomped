package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local f = dofile(root .. "/tests/live_maps/fixture.lua").new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/live_maps/cases.lua").run(f)
f.close()
print("LIVE_MAPS_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable live-map lifecycle")
