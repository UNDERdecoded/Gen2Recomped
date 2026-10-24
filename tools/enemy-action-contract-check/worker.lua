package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = unpack(arg)
local T = require("tests.modkit")
local rows =
  dofile(root .. "/tests/enemy_actions/cases.lua").run(root, backend, version, tonumber(api), "unified")
print("ENEMY_ACTION_OBSERVATIONS " .. require("src.link.Json").encode(rows))
T.finish("enemy action contract")
