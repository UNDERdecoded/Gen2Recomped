package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_motion")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
local function dispose(f)
  f.restoreRenderer()
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " motion contract: " .. tostring(why))
end
for _, rows in ipairs({
  { { "face_player_dir", "up" }, { "move_npc", 99, "down" } },
  { { "move_player", "north" } },
  { { "move_player", "down", -1 } },
  { { "move_player", "down", 1025 } },
  { { "move_npc_to", 1, 0.5, 0 } },
  { { "place_npc", 1, 0, 0, "north" } },
  { { "place_npc", 1, 0, math.huge } },
  { { "face_object", 1, "down", { hold = -1 } } },
  { { "face_object", 1, "down", { other = 1 } } },
  { { "face", "down" } },
  { { "face_player" } },
  { { "face_npc" } },
}) do
  local f = fixture()
  T.eq(f.exports.queue(rows), nil, "invalid later command preflight")
  T.eq(f.player.facing, "left", "invalid prefix does not turn player")
  T.eq(#f.ow.scriptMoves, 0, "preflight creates no native track")
  dispose(f)
end
for _, version in ipairs({ "red", "gold", "firered", "emerald" }) do
  for _, kind in ipairs({ "player", "npc" }) do
    local f = fixture(version)
    local actor = kind == "player" and f.player or f.imported
    local row = kind == "player" and { "move_player", "left", 2 } or { "move_npc", 1, "left", 2 }
    local x = actor.cellX
    T.check(f.exports.queue({ row, { "set_flag", "mod:after" } }), "two-step movement admitted")
    local old = f.pending.callback
    f:complete()
    local overlay = {}
    f.game.stack.states[2] = overlay
    old()
    old()
    for _ = 1, 4 do
      f:tick()
    end
    T.eq(actor.cellX, x - 1, "overlay pauses next owned step")
    T.eq(f.exports.result().done, 0, "old callback cannot skip movement")
    f.game.stack.states[2] = nil
    f:drain()
    T.eq(actor.cellX, x - 2, "two native steps completed once")
    T.eq(f.exports.result().success, true, "native continuation completes")
    T.eq(f.exports.get("mod:after"), true, "only finished walk resumes script")
    dispose(f)
  end
end
for _, action in ipairs({ "cancel", "rollback", "save", "map", "actor" }) do
  local f = fixture()
  local original = f.ow.runner
  T.check(
    f.exports.queue({ { "move_npc", 1, "left", 2 }, { "set_flag", "mod:after" } }),
    "cancellable track admitted"
  )
  local callback = f.pending.callback
  local foreign = { entity = f.imported, dir = "up", remaining = 1, onDone = function() end }
  f.ow.scriptMoves[#f.ow.scriptMoves + 1] = foreign
  if action == "cancel" then
    require("src.mods.PortableScripts").cancelAll(f.loader, "script_motion", "probe cancellation")
  elseif action == "rollback" then
    f.loader:_rollback("script_motion")
  elseif action == "save" then
    f.game.save = {}
  elseif action == "map" then
    f.ow.map = { id = f.home }
  else
    f.ow.npcs = {}
  end
  f:tick()
  T.eq(f.exports.result().done, 1, "retired movement completes once")
  T.eq(f.exports.result().success, false, "retirement fails script")
  T.eq(#f.ow.scriptMoves, 1, "only owned track removed")
  T.eq(f.ow.scriptMoves[1], foreign, "foreign actor track retained")
  callback()
  callback()
  T.eq(f.exports.result().done, 1, "retained callback cannot replay")
  T.eq(f.ow.runner, original, "original runner restored")
  dispose(f)
end
do
  local f = fixture()
  f.synchronous = true
  T.check(
    f.exports.queue({ { "move_player", "left", 2 }, { "set_flag", "mod:after" } }),
    "synchronous native steps admitted"
  )
  T.eq(f.exports.result().success, true, "synchronous callback completes without yielding forever")
  T.eq(f.player.cellX, 5, "synchronous two-step position")
  dispose(f)
end
for _, failure in ipairs({ "refuse", "throw", "unload" }) do
  local f = fixture()
  local native = f.ow.scriptMove
  function f.ow:scriptMove(...)
    native(self, ...)
    if failure == "refuse" then
      return false, "probe refusal"
    elseif failure == "throw" then
      error("probe native error")
    else
      f.loader:_rollback("script_motion")
    end
  end
  T.check(
    f.exports.queue({ { "move_player", "left", 2 }, { "set_flag", "mod:after" } }),
    "native failure after admission"
  )
  T.eq(f.exports.result().success, false, "native failure reported")
  T.eq(#f.ow.scriptMoves, 0, "late native track cleaned")
  T.eq(f.player.moving, false, "owned actor unlocked")
  dispose(f)
end
do
  local f = fixture()
  f.ow.talkNpc = f.imported
  T.check(
    f.exports.queue({
      { "face", "left" },
      { "face_npc" },
      { "face_player" },
      {
        "face_object",
        1,
        "up",
        { hold = 20 },
      },
    }),
    "context facing admitted"
  )
  T.eq(f.exports.result().success, true, "context facing completes")
  T.eq(f.player.facing, "up", "player faces talking NPC")
  T.eq(f.imported.facing, "up", "arbitrary object explicit direction")
  T.eq(f.imported.timer, 20, "bounded facing hold carried")
  dispose(f)
end
do
  local f = fixture()
  T.check(f.exports.queue({ { "move_player", "left" } }), "stalled native track admitted")
  for _ = 1, 3601 do
    f:tick()
  end
  T.eq(f.exports.result().success, false, "stalled track times out")
  T.eq(#f.ow.scriptMoves, 0, "timeout removes owned track")
  dispose(f)
end
-- Borrow the actual production movement queue and both walker updates.
local OW = require("src.world.OverworldController")
local Player = require("src.world.Player")
for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local f = fixture(version)
  f.ow.scriptMove = OW.scriptMove
  f.imported.frozen = true
  f.player.turnTimer, f.player.progress = 0, 0
  T.check(
    f.exports.queue({ { "move_player", "left", 2 }, { "move_npc", 1, "up", 2 }, { "set_flag", "mod:after" } }),
    version .. " native queues admitted"
  )
  for _ = 1, 100 do
    OW.updateScriptMoves(f.ow)
    Player.update(f.player)
    f.imported:update(f.ow.map, f.ow.entities)
    f:tick()
  end
  T.eq(f.player.cellX, 5, "actual player updater walks exactly two cells")
  T.eq(f.imported.cellY, 4, "actual NPC updater walks exactly two cells")
  T.eq(#f.ow.scriptMoves, 0, "actual native tracks released")
  T.eq(f.exports.result().success, true, "actual native movement resumes script")
  T.eq(f.exports.get("mod:after"), true, "native walk continuation runs once")
  dispose(f)
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script movement")
