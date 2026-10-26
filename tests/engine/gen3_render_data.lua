-- The same ROM-free consumer used by the cross-engine checker. The tier
-- runner already launches this suite in its own process.
arg[1], arg[2], arg[3], arg[4] = ".", "gen2", "firered", "2"
arg[5] = "quiet"
dofile("tests/render_contract/worker.lua")
