package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.flags")
local F = require("src.mods.Api3Flags")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared native flags: " .. tostring(why))
end
-- Every generated catalog alias resolves to the live VM/save-converter key.
local vm = require("src.script.Gen3ScriptVM")
for _, version in ipairs({ "red", "blue", "yellow", "firered", "emerald" }) do
  local key = version == "blue" and "red" or version
  local data = require("src.mods.flag_names." .. key)
  local gen = Version.generation(version)
  for number, row in pairs(data.records) do
    local expected = gen == 1 and row[1] or vm.flagName(number)
    if row[1] then
      T.eq(F.resolve(gen, version, number), expected, "catalog numeric resolves to native key")
    end
    for _, alias in ipairs(row) do
      if alias then
        T.eq(F.resolve(gen, version, alias), expected, "catalog alias resolves to native key")
      end
    end
  end
end
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  for number = 0, 2047 do
    T.eq(
      F.resolve(2, version, number),
      require("src.script.Gen2Flags").eventFlag(number),
      "native Gen2 bit key"
    )
  end
end
for _, version in ipairs({ "prism", "polishedcrystal" }) do
  T.eq(F.resolve(2, version, 16), nil, "no cartridge flag numbering guessed for hacks")
end
for _, bad in ipairs({ {}, false, 0 / 0, math.huge, -1, 0.5, string.rep("A", 257), "FLAG\0BAD" }) do
  local f = fixture()
  T.eq(f.exports.set(bad, true), nil, "malformed native ref refused")
  T.eq(next(f.game.save.flags), nil, "refusal leaves native store untouched")
end
for _, bad in ipairs({ 0, "yes", {}, function() end }) do
  local f = fixture()
  T.eq(f.exports.set(f.number, bad), nil, "real boolean required")
  T.eq(next(f.game.save.flags), nil, "bad value not stored")
end
for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local f = fixture(version)
  local storage = assert(F.resolve(f.gen, version, f.number))
  T.check(f.exports.set(f.number, true), "native set")
  T.eq(f.game.save.flags[storage], true, "native VM sees same flag")
  T.check(f.exports.set(f.number, false), "native clear")
  T.eq(f.game.save.flags[storage], false, "clear distinguished from untouched for visibility")
  T.eq(f.exports.get(f.number), false, "public clear boolean")
  f.game.save.flags = false
  T.eq(f.exports.get(f.number), nil, "malformed native store refused")
  T.eq(f.exports.set(f.number, true), nil, "malformed native store not overwritten")
  T.eq(f.game.save.flags, false, "malformed native store retained")
end
do
  local f = fixture("firered")
  local storage = assert(F.resolve(3, "firered", f.number))
  local own = { index = 1, eventFlag = storage }
  local other = { index = 2, eventFlag = "unrelated" }
  f.ow.map.def.objects = { own, other }
  local calls = {}
  function f.ow:syncObjectVisibility(object)
    calls[#calls + 1] = object
  end
  T.check(f.exports.set(f.symbol, true), "visibility flag set")
  T.eq(#calls, 1, "only affected actor synchronized")
  T.eq(calls[1], own, "synchronization scoped to native flag")
  T.eq(f.ow.map.def.objects[2], other, "unrelated template unchanged")
end
do
  local f = fixture()
  local observed = 0
  f.loader.events:on("flag.changed", function()
    observed = observed + 1
    local ok, why = f.exports.set(f.number, false)
    T.eq(ok, nil, "flag event cannot reenter a write")
    T.eq(why, "world is busy", "flag reentry diagnosed")
  end, 0, "probe")
  T.check(f.exports.set(f.number, true), "outer write accepted")
  T.eq(observed, 1, "no recursive event loop")
  T.eq(f.exports.get(f.number), true, "reentrant attempt cannot alter committed flag")
end
for _, action in ipairs({ "rollback", "reload", "teardown" }) do
  local f = fixture()
  if action == "rollback" then
    f.loader:_rollback("flags")
  elseif action == "reload" then
    fixture()
  else
    Loader.teardown()
  end
  T.eq(f.exports.set(f.number, true), nil, "retired native setter")
  T.eq(f.exports.set("mod:key", true), nil, "retired private setter")
  T.eq(next(f.game.save.flags), nil, "retired setter no effects")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("API 3 native flags")
