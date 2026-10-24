package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local rows =
  dofile(root .. "/tests/mart_content/cases.lua").run(root, backend, version, tonumber(api), format)
print("MART_CONTENT_CONTRACT " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native mart content")
