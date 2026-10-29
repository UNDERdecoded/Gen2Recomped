package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_fields")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(v)
  return Contract.fixture("tests/api3_contract", "gen2", v or "red")
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared field contract: " .. tostring(why))
end
local cyclic = {}
cyclic.self = cyclic
local deep = {}
local node = deep
for _ = 1, 18 do
  node.child = {}
  node = node.child
end
local wide = {}
for i = 1, 600 do
  wide[i] = i
end
for _, row in ipairs({
  { "set_field", "modData", {} },
  { "set_field", "mod:" },
  { "set_field", "mod.other.x", 1 },
  { "set_field", "foreign:x", 1 },
  { "set_option", "x\n", 1 },
  { "set_field", "", 1 },
  { "set_field", false, 1 },
  { "set_field", "x", function() end },
  { "set_field", "x", 0 / 0 },
  { "set_field", "x", math.huge },
  { "set_field", "x", cyclic },
  { "set_field", "x", deep },
  { "set_field", "x", wide },
  { "set_field", "x", string.rep("a", 32769) },
  { "set_field", "x", { [false] = 1 } },
  { "set_field", "x", setmetatable({}, {}) },
  { "set_option", "x", { nested = function() end } },
  { "set_option", "x", 1, 2 },
}) do
  local f = fixture()
  T.eq(f.exports.queue({ { "set_flag", "mod:prefix" }, row }), nil, "invalid field rejected")
  T.eq(f.exports.get("mod:prefix"), false, "invalid field prevents prefix")
end
for _, store in ipairs({ "options", "modData", "bucket" }) do
  for _, value in ipairs({ false, setmetatable({}, {}) }) do
    local f = fixture()
    local verb, key = "set_option", "choice"
    if store == "bucket" then
      f.game.save.modData.script_fields = value
      verb, key = "set_field", "mod:x"
    else
      f.game.save[store] = value
      if store == "modData" then
        verb, key = "set_field", "mod:x"
      end
    end
    T.eq(
      f.exports.queue({ { "set_field", "portableRoot", true }, { verb, key, 1 } }),
      nil,
      "invalid store refused"
    )
    T.eq(f.game.save.portableRoot, nil, "store failure before prefix")
  end
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "wait", 1 }, { "set_field", "mod:x", 1 }, { "set_flag", "mod:after" } }),
    "changed bucket fixture"
  )
  f.game.save.modData.script_fields = false
  f:drain()
  T.eq(f.exports.result().success, false, "store revalidated at dispatch")
  T.eq(f.game.save.modData.script_fields, false, "changed bucket retained")
  T.eq(f.exports.get("mod:after"), nil, "changed bucket has no continuation")
end
do
  local f = fixture()
  T.eq(
    f.exports.queue({ { "set_field", "options", false }, { "set_option", "x", 1 } }),
    nil,
    "future options shape preflight"
  )
  T.eq(f.game.save.options, nil, "future invalid store leaves original untouched")
end
do
  local f = fixture()
  local value = { a = { 3, false, "x" } }
  T.check(
    f.exports.queue({
      { "set_field", "mod:a", value },
      { "set_field", "portableRoot", 9 },
      { "set_option", "portableChoice", true },
    }),
    "values written"
  )
  f:drain()
  T.eq(f.game.save.modData.script_fields.a.a[2], false, "false preserved")
  value.a[1] = 7
  T.eq(f.game.save.modData.script_fields.a.a[1], 3, "caller table not aliased")
  T.check(
    f.exports.queue({ { "set_field", "mod:a" }, { "set_field", "portableRoot" }, {
      "set_option",
      "portableChoice",
    } }),
    "omitted value deletes"
  )
  f:drain()
  T.eq(f.game.save.modData.script_fields.a, nil, "private field cleared")
  T.eq(f.game.save.portableRoot, nil, "root field cleared")
  T.eq(f.game.save.options.portableChoice, nil, "option cleared")
end
do
  local F = require("src.mods.ScriptFields")
  local game = { save = {} }
  local rows = { { "set_field", "mod:x", { n = 1 } } }
  local run = assert(F.prepare(game, "owner", rows))
  run({}, rows[1])
  game.save.modData.owner.x.n = 4
  run({}, rows[1])
  T.eq(game.save.modData.owner.x.n, 1, "repeated dispatch copies compiled value")
  local rows = {}
  for i = 1, 5 do
    rows[i] = { "set_field", "mod:x", string.rep("a", 32768) }
  end
  T.eq(F.prepare(game, "owner", rows), nil, "aggregate data string limit")
  local rows = {}
  for i = 1, 20 do
    local v = {}
    for j = 1, 250 do
      v[j] = j
    end
    rows[i] = { "set_field", "mod:x", v }
  end
  T.eq(F.prepare(game, "owner", rows), nil, "aggregate data node limit")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod = saved[2], saved[3], saved[4], saved[5]
love = saved[6]
T.finish()
