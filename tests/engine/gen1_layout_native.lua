package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local checks = dofile("tests/gba_layout/consumer.lua")(require("src.core.game3.layout_native"))
T.check(checks > 240, "unchanged legacy layout consumer exercises sampling, writes, workers and invalidation")
T.finish("Gen1 decoded layout compatibility (" .. checks .. " consumer checks)")
