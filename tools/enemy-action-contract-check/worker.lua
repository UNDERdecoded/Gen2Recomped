package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, mode = unpack(arg)
local T = require("tests.modkit")
local rows
if mode == "triple_kick" then
  rows = dofile(root .. "/tests/enemy_actions/triple_kick.lua").run(root, backend, version)
elseif mode == "rage" then
  rows = dofile(root .. "/tests/enemy_actions/rage.lua").run(root, backend, version)
elseif mode == "multi_hit" then
  rows = dofile(root .. "/tests/enemy_actions/multi_hit.lua").run(root, backend, version)
elseif mode == "disable" then
  rows = dofile(root .. "/tests/enemy_actions/disable.lua").run(root, backend, version)
elseif mode == "encore" then
  rows = dofile(root .. "/tests/enemy_actions/encore.lua").run(root, backend, version)
elseif mode == "baton_pass" then
  rows = dofile(root .. "/tests/enemy_actions/baton_pass.lua").run(root, backend, version)
elseif mode == "lock_on" then
  rows = dofile(root .. "/tests/enemy_actions/lock_on.lua").run(root, backend, version)
elseif mode == "party_codec_hooks" then
  rows = dofile(root .. "/tests/enemy_actions/party_codec_hooks.lua").run(root, backend, version)
elseif mode == "party_codec" then
  rows = dofile(root .. "/tests/enemy_actions/party_codec.lua").run(root, backend, version)
elseif mode == "secondary" or mode == "secondary_execution" then
  rows = dofile(root .. "/tests/enemy_actions/secondary.lua").run(root, backend, version, mode == "secondary_execution")
elseif mode == "accuracy_execution" then
  rows = dofile(root .. "/tests/enemy_actions/accuracy.lua").run(root, backend, version, true)
elseif mode == "accuracy" then
  rows = dofile(root .. "/tests/enemy_actions/accuracy.lua").run(root, backend, version)
elseif mode == "constrained_party" then
  rows = dofile(root .. "/tests/enemy_actions/constrained_party.lua").run(root, backend, version)
elseif mode == "critical_context" then
  rows = dofile(root .. "/tests/enemy_actions/critical_kinds.lua").run(root, backend, version)
elseif mode == "beat_up_side_party" then
  rows = dofile(root .. "/tests/enemy_actions/beat_up.lua").run(
    root,
    backend,
    version,
    false,
    { sideParty = true }
  )
elseif mode == "beat_up_adjustment" then
  rows = dofile(root .. "/tests/enemy_actions/beat_up.lua").run(
    root,
    backend,
    version,
    false,
    { adjustment = true }
  )
elseif mode == "beat_up_content" then
  rows = dofile(root .. "/tests/enemy_actions/beat_up.lua").run(root, backend, version, true)
elseif mode == "beat_up" then
  rows = dofile(root .. "/tests/enemy_actions/beat_up.lua").run(root, backend, version)
elseif mode == "spit_up" then
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
