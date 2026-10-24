package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Contract = require("tests.api3_contract.run")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, love }
love = nil
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  for _, failing in ipairs({ false, true }) do
    local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version, failing)
    T.check(ok, version .. (failing and " rollback: " or ": ") .. tostring(why))
  end
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, love = saved[2], saved[3], saved[4], saved[5]
T.finish("API 3 cross-engine contracts")
