package.path = "./?.lua;./?/init.lua;" .. package.path
local checks, signature = dofile(arg[1] .. "/tests/gba_layout/connections.lua")(require("src.core.game3.connections"))
print(checks)
print(signature)
