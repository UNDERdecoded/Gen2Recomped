package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_flags")
local Program = require("src.mods.ScriptProgram")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared script flags: " .. tostring(why))
end
for _, verb in ipairs({ "set_flag", "clear_flag", "check_flag", "wait_flag", "setflag", "clearflag" }) do
  T.eq(Program.supports(verb), true, "flag verb advertised")
end
for _, rows in ipairs({
  { { "set_flag", "mod:prefix" }, { "set_flag", "no_such_flag" } },
  { { "jump", "end" }, { "set_flag", "no_such_flag" } },
  { { "set_flag", "mod:prefix" }, { "check_flag", "mod.other.secret" } },
  { { "set_flag", {} } },
  { { "set_flag", "mod:" } },
  { { "set_flag", "mod:x", true } },
  { { "wait_flag", "mod:x", -1 } },
  { { "wait_flag", "mod:x", 0.5 } },
  { { "wait_flag", "mod:x", math.huge } },
  { { "wait_flag", "mod:x", 36001 } },
  { { "wait_flag", "mod:x", "5" } },
}) do
  local f = fixture()
  local runner = f.ow.runner
  local value, why = f.exports.queue(rows)
  T.eq(value, nil, "entire invalid list declined")
  T.check(type(why) == "string", "invalid row explained")
  T.eq(f.exports.get("mod:prefix"), false, "no accepted prefix executes")
  T.eq(f.ow.runner, runner, "no runner replacement on refusal")
  T.eq(f.exports.result().done, 0, "no completion on refusal")
end
do
  local f = fixture()
  f.game.save.modData = false
  T.eq(f.exports.queue({ { "set_flag", "mod:prefix" } }), nil, "malformed store rejected before admission")
  T.eq(f.game.save.modData, false, "malformed store not overwritten")
end
do
  local f = fixture()
  local rows = { { "wait_flag", "mod:signal" }, { "set_flag", "mod:copied" } }
  T.check(f.exports.queue(rows), "indefinite wait admitted")
  rows[2][2] = "mod:mutated"
  for _ = 1, 5 do
    f:tick()
  end
  T.eq(f.exports.result().done, 0, "omitted timeout keeps waiting")
  T.check(f.exports.set("mod:signal", true), "external signal")
  f:drain()
  T.eq(f.exports.get("mod:copied"), true, "admitted rows detached")
  T.eq(f.exports.get("mod:mutated"), false, "caller mutation ignored")
end
for _, timeout in ipairs({ 0, 1, 2 }) do
  local f = fixture()
  T.check(
    f.exports.queue({
      { "wait_flag", "mod:signal", timeout },
      { "jump_if_true", "end" },
      {
        "set_flag",
        "mod:timed",
      },
    }),
    "timeout admitted"
  )
  T.eq(f.exports.result().done, 0, "even zero yields once")
  f:drain()
  T.eq(f.exports.get("mod:timed"), true, "timeout sets lastCheck false")
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "wait_flag", "mod:signal", 1 }, { "set_flag", "mod:resumed" } }),
    "wait admitted before overlay"
  )
  local overlay = {}
  f.game.stack.states[2] = overlay
  for _ = 1, 5 do
    f:tick()
  end
  T.eq(f.exports.result().done, 0, "foreign overlay pauses timeout")
  T.eq(f.game.stack.states[2], overlay, "owned wait does not pop foreign screen")
  f.game.stack.states[2] = nil
  f:drain()
  T.eq(f.exports.result().success, true, "wait resumes after uncovering")
end
for _, change in ipairs({ "save", "data", "map", "version", "rollback", "teardown" }) do
  local f = fixture()
  local original = f.ow.runner
  T.check(
    f.exports.queue({ { "wait_flag", "mod:signal" }, { "set_flag", "mod:late" } }),
    "wait starts before " .. change
  )
  local owned = f.ow.runner
  if change == "version" then
    Version.set("blue")
  elseif change == "rollback" then
    f.loader:_rollback("script_flags")
  elseif change == "teardown" then
    Loader.teardown()
  elseif change == "map" then
    f.ow.map = { id = f.home, def = f.ow.map.def }
  else
    f.game[change] = {}
  end
  f:tick()
  T.eq(f.exports.result().done, 1, "changed context completes once")
  T.eq(f.exports.result().success, false, "changed context cancels wait")
  T.eq(f.ow.runner, original, "original runner restored")
  owned:resume(true)
  T.eq(f.exports.result().done, 1, "late condition cannot replay completion")
end
for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local f = fixture(version)
  local ref = version == "red" and 0 or (f.gen == 2 and 16 or 1)
  T.check(
    f.exports.queue({
      { "set_flag", ref },
      { "check_flag", ref },
      { "jump_if_false", "end" },
      { "set_flag", "mod:native" },
      { "clear_flag", ref },
    }),
    "native flag program admitted"
  )
  f:drain()
  T.eq(f.exports.get("mod:native"), true, "native condition drives control flow")
  T.eq(f.exports.get(ref), false, "native flag cleared")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script flags")
