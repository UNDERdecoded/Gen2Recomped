package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, mode = unpack(arg)
local T = require("tests.modkit")
local rows
if mode == "spit_up" then
  rows = dofile(root .. "/tests/enemy_actions/spit_up.lua").run(root, backend, version)
elseif mode == "helping_hand" then
  rows = dofile(root .. "/tests/enemy_actions/helping_hand.lua").run(root, backend, version)
elseif mode == "follow_me" then
  rows = dofile(root .. "/tests/enemy_actions/follow_me.lua").run(root, backend, version)
elseif mode == "targets" then
  rows = dofile(root .. "/tests/enemy_actions/targets.lua").run(root, backend, version)
elseif mode == "records" then
  rows = dofile(root .. "/tests/enemy_actions/records.lua").run(root, backend, version)
elseif mode == "arguments" then
  rows = dofile(root .. "/tests/enemy_actions/arguments.lua").run(root, backend, version)
else
  rows =
    dofile(root .. "/tests/enemy_actions/cases.lua").run(root, backend, version, tonumber(api), "unified")
end
print("ENEMY_ACTION_OBSERVATIONS " .. require("src.link.Json").encode(rows))
T.finish("enemy action contract")
