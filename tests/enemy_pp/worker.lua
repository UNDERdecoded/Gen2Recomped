package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = unpack(arg)
local Fixture = dofile(root .. "/tests/charge_required/fixture.lua")
local f = Fixture.new(root, backend, version, 3, "unified", false, false, "portable_enemy_pp")
local rows = dofile(root .. "/tests/enemy_pp/cases.lua").run(f)
f.close()
print("ENEMY_PP_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("native enemy PP and public observer")
