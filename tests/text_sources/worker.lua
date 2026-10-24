package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local rows =
  dofile(root .. "/tests/text_sources/cases.lua").run(root, backend, version, tonumber(api), format)
print("TEXT_SOURCE_CONTRACT " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("portable native script text")
