package.path = "./?.lua;./?/init.lua;" .. package.path
local Fixture = dofile("tests/trainer_preparation/fixture.lua")
local _, T = dofile("tests/trainer_preparation/cases.lua").run(function(noMod, failing)
  return Fixture.new(".", "gen2", "red", 3, "unified", noMod, failing)
end)
-- Keep an executable public-API proof in the engine corpus as well as the
-- shared worker helpers (the coverage gate scans only its explicit tiers).
local f = Fixture.new(".", "gen2", "red", 3, "unified")
local mod, calls = f.exports.api, 0
local off = mod.hooks:wrap("trainer.before_battle", function(next, ...)
  calls = calls + 1
  return next(...)
end, 100)
f.start()
T.eq(calls, 1, "public API callback reached from native preparation")
T.eq(f.starts(), 0, "downstream preparation defers")
T.eq(f.exports.continue(), true, "public continuation starts native battle")
T.eq(f.starts(), 1, "public continuation constructs once")
off()
f.close()
T.finish("portable trainer.before_battle")
