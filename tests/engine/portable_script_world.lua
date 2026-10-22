package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_world")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared world script contract: " .. tostring(why))
end
for _, rows in ipairs({
  { { "hide_object", "HOME", "NPC" }, { "show_object", "HOME", "MISSING" } },
  { { "hide_object", "HOME", "NPC" }, { "replace_block", 99, 0, 8 } },
  { { "replace_block", 0, 0, 9 } },
  { { "replace_block", -1, 0, 8 } },
  { { "replace_block", 0, 0, 256 } },
  { { "show_object", "HOME", false } },
  { { "show_object", "MISSING", "NPC" } },
  { { "hide_object", "HOME", "NPC", true } },
}) do
  local f = fixture()
  T.eq(f.exports.queue(rows), nil, "invalid list refused before prefix")
  T.eq(f.visible.NPC, true, "object unchanged after refusal")
  T.eq(f.rebuilds + f.reloads + f.syncs, 0, "no native effects on refusal")
end
for _, version in ipairs({ "red", "gold", "firered", "emerald" }) do
  for _, target in ipairs({ "object", "block" }) do
    local f = fixture(version)
    local row = target == "object" and { "hide_object", f.home, "NPC" } or { "replace_block", 0, 0, 8 }
    T.check(f.exports.queue({ { "wait", 1 }, row, { "set_flag", "mod:after" } }), "world script queued")
    local overlay = {}
    f.game.stack.states[2] = overlay
    for _ = 1, 5 do
      f:tick()
    end
    T.eq(f.exports.result().done, 0, "foreign overlay pauses native edit")
    T.eq(#f.exports.result().events, 0, "paused edit emits nothing")
    f.game.stack.states[2] = nil
    f:drain()
    T.eq(f.exports.result().success, true, "edit resumes after overlay")
    T.eq(f.exports.get("mod:after"), true, "script continues after native edit")
    T.eq(#f.exports.result().events, 1, "single native event")
  end
end
for _, field in ipairs({ "objectToggles", "flags" }) do
  local f = fixture()
  T.check(
    f.exports.queue({ { "wait", 1 }, { "hide_object", f.home, "NPC" } }),
    "deferred object edit admitted"
  )
  f.game.save[field] = false
  f:drain()
  T.eq(f.exports.result().success, false, "live malformed store refuses edit")
  T.eq(f.visible.NPC, true, "malformed live store has no write")
end
do
  local f = fixture()
  T.check(f.exports.queue({ { "wait", 1 }, { "replace_block", 0, 0, 8 } }), "deferred block edit admitted")
  f.ow.map.renderer = nil
  f:drain()
  T.eq(f.exports.result().success, false, "live missing renderer refuses edit")
  T.eq(f.rebuilds, 0, "no partial replacement")
end
for _, change in ipairs({ "rollback", "save", "map", "runner" }) do
  local f = fixture()
  local original = f.ow.runner
  T.check(f.exports.queue({ { "wait", 1 }, { "hide_object", f.home, "NPC" } }), "owned edit admitted")
  local replacement
  if change == "rollback" then
    f.loader:_rollback("script_world")
  elseif change == "save" then
    f.game.save = {}
  elseif change == "map" then
    f.ow.map = { id = f.home }
  else
    replacement = { update = function() end }
    f.ow.runner = replacement
  end
  f:tick()
  T.eq(f.exports.result().done, 1, "changed context cancels once")
  T.eq(f.exports.result().success, false, "changed context fails")
  T.eq(f.visible.NPC, true, "cancelled edit cannot run")
  T.eq(f.ow.runner, replacement or original, "foreign or original runner preserved")
end
do
  local f = fixture()
  local original = f.ow.runner
  f.loader.events:on("world.object_toggled", function()
    f.loader:_rollback("script_world")
  end, 0, "probe")
  T.check(
    f.exports.queue({ { "hide_object", f.home, "NPC" }, { "set_flag", "mod:after" } }),
    "native event retires owner"
  )
  T.eq(f.exports.result().done, 1, "event cancellation completes once")
  T.eq(f.exports.result().success, false, "event cancellation reported")
  T.check(f.ow.runner ~= original and not f.ow.runner:isRunning(), "reload's new idle runner retained")
  T.eq(f.exports.get("mod:after"), false, "retired owner cannot execute following flag")
end
do
  local f = fixture()
  local old = f.ow.runner
  T.check(
    f.exports.queue({ { "hide_object", f.home, "NPC" }, { "wait", 2 }, { "set_flag", "mod:after" } }),
    "native reload continuation admitted"
  )
  f:drain()
  T.eq(f.exports.result().success, true, "continuation survives native map and runner replacement")
  T.check(f.ow.runner ~= old and not f.ow.runner:isRunning(), "destination idle runner restored")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script world edits")
