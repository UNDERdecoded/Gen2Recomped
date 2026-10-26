package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local rows =
  dofile(root .. "/tests/pokemon_rolls/cases.lua").run(root, backend, version, tonumber(api), format)
print("POKEMON_ROLL_CONTRACT " .. require("src.link.Json").encode(rows))
require("tests.modkit").finish("native Pokemon identity rolls")
