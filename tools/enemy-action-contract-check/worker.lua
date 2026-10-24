package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, mode = unpack(arg)
local T = require("tests.modkit")
local rows
if mode == "arguments" then
  rows = dofile(root .. "/tests/enemy_actions/arguments.lua").run(root, backend, version)
else
  rows =
    dofile(root .. "/tests/enemy_actions/cases.lua").run(root, backend, version, tonumber(api), "unified")
end
print("ENEMY_ACTION_OBSERVATIONS " .. require("src.link.Json").encode(rows))
T.finish("enemy action contract")
