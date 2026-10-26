package.path = "./?.lua;./?/init.lua;" .. package.path
local root = assert(arg[1], "pass the checkout containing this contract")
local version = assert(arg[2], "pass a game version")
local api = assert(tonumber(arg[3]), "pass an API version")
local format = assert(arg[4], "pass a callback format")
local f = dofile(root .. "/tests/quit_to_launcher/fixture.lua").new(root, version, api, format)
local rows = dofile(root .. "/tests/quit_to_launcher/cases.lua").run(f)
print("QUIT_CONTRACT_RESULT " .. require("src.link.Json").encode({
  rows = rows,
  version = version,
  api = api,
  format = format,
}))
f.close()
f.T.finish("portable quit decision contract")
