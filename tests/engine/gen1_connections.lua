package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local checks = dofile("tests/gba_layout/connections.lua")(require("src.core.game3.connections"))
T.check(checks > 12000, "unchanged connection consumer exercises parallel offsets and all edge/corner samples")
T.finish("Legacy connection compatibility (" .. checks .. " consumer checks)")
