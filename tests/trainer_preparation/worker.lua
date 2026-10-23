package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local Fixture = dofile(root .. "/tests/trainer_preparation/fixture.lua")
local rows, T = dofile(root .. "/tests/trainer_preparation/cases.lua").run(function(noMod, failing)
  return Fixture.new(root, backend, version, api, format, noMod, failing)
end)
print("TRAINER_PREPARATION_CONTRACT " .. require("src.link.Json").encode(rows))
T.finish("portable trainer.before_battle contract")
