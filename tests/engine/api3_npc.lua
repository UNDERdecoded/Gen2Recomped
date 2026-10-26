package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Contract = require("tests.api3_contract.npcs")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Loader = require("src.mods.Loader")
local Renderer = require("src.render.SpriteRenderer")
local originalRenderer = Renderer.new
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
love = nil
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
local function spawn(f)
  local id = assert(
    f.exports.spawn(
      f.home,
      { x = 0, y = 0, name = "OWN", sprite = "PROBE", movement = "STAY", range = "DOWN" }
    )
  )
  return assert(f.exports.npc(f.home, id)), f.ow.npcPool[id]
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared NPC contract: " .. tostring(why))
end
local cycle = { x = 0, y = 0 }
cycle.self = cycle
local meta = setmetatable({ x = 0, y = 0 }, {})
local deep = { x = 0, y = 0 }
local child = deep
for _ = 1, 18 do
  child.next = {}
  child = child.next
end
local wide = { x = 0, y = 0 }
for i = 1, 260 do
  wide[i] = i
end
for _, row in ipairs({
  cycle,
  meta,
  deep,
  wide,
  { x = 0, y = 0, handler = function() end },
  { x = math.huge, y = 0 },
  { x = 0 / 0, y = 0 },
  { x = 1000001, y = 0 },
  { x = 0, y = -1 },
  { x = 0, y = 0.5 },
  { x = 0, y = 0, name = "bad\nname" },
  { x = 0, y = 0, sprite = "missing" },
  { x = 0, y = 0, facing = "north" },
  { x = 0, y = 0, payload = string.rep("x", 4097) },
}) do
  local f = fixture()
  local value, why = f.exports.spawn(f.home, row)
  T.eq(value, nil, "invalid definition refused")
  T.check(type(why) == "string", "definition failure explained")
  T.eq(#f.game.data.maps[f.home].objects, 1, "invalid definition adds no template")
  T.eq(#f.ow.npcs, 1, "invalid definition adds no actor")
end
for _, version in ipairs({ "red", "gold", "firered" }) do
  for _, lock in ipairs({ "overlay", "player", "script", "link", "parallel", "controller" }) do
    local f = fixture(version)
    local handle, actor = spawn(f)
    if lock == "overlay" then
      f.game.stack.states[2] = {}
    elseif lock == "player" then
      f.player.moving = true
    elseif lock == "script" then
      f.ow.runner.isRunning = function()
        return true
      end
    elseif lock == "link" then
      f.game.linkSession = {}
    elseif lock == "parallel" then
      f.ow.parallelRunners = { {} }
    else
      f.ow._modScriptLock = {}
    end
    T.eq(handle:position(), 0, "busy world permits position read")
    T.eq(handle:isMoving(), false, "busy world permits motion read")
    T.eq(handle:face("left"), nil, lock .. " blocks mutation")
    T.eq(f.exports.spawn(f.home, { x = 0, y = 0 }), nil, lock .. " blocks spawn")
    T.eq(f.exports.remove(handle.id), nil, lock .. " blocks removal")
    T.eq(actor.facing, "down", "refusal does not change actor")
  end
end
for _, method in ipairs({ "face", "stepNow", "scriptMove", "canStep" }) do
  for _, bad in ipairs({ "north", false, {}, 1 }) do
    local f = fixture()
    local handle = spawn(f)
    local ok, why = handle[method](handle, bad)
    T.eq(ok, nil, "bad direction refused for " .. method)
    T.eq(why, "invalid direction", "bad direction diagnosed")
    T.eq(#f.ow.scriptMoves, 0, "no queued movement on invalid direction")
  end
end
for _, bad in ipairs({ 0, -1, 0.5, math.huge, 0 / 0, 1025, "1" }) do
  local f = fixture()
  local handle = spawn(f)
  T.eq(handle:scriptMove("up", bad), nil, "invalid move count refused")
  T.eq(#f.ow.scriptMoves, 0, "invalid count has no effect")
end
do
  local f = fixture()
  local handle, actor = spawn(f)
  local native = f.ow.addRuntimeObject
  function f.ow:addRuntimeObject(...)
    local value, why = handle:face("left")
    T.eq(value, nil, "native construction cannot reenter NPC mutation")
    T.eq(why, "world is busy", "NPC reentry diagnosed")
    value, why = f.exports.toggle(f.home, "IMPORTED", false)
    T.eq(value, nil, "NPC construction cannot reenter object edit")
    T.eq(why, "world is busy", "shared mutation guard diagnosed")
    return native(self, ...)
  end
  T.check(f.exports.spawn(f.home, { x = 2, y = 2, sprite = "PROBE" }), "outer construction succeeds")
  T.eq(actor.facing, "down", "reentry leaves actor untouched")
  T.check(handle:face("right"), "construction releases guard")
  local constructor = Renderer.new
  Renderer.new = function()
    error("renderer failed", 0)
  end
  local def, sprite = actor.def, actor.sprite
  T.eq(handle:setAppearance("ALT"), nil, "failed renderer construction contained")
  T.eq(actor.def, def, "failed renderer retains original definition")
  T.eq(actor.sprite, sprite, "failed renderer retains original sprite")
  Renderer.new = constructor
  T.check(handle:face("up"), "renderer exception releases guard")
end
for _, change in ipairs({ "game", "save", "data", "stack", "world", "map", "actor", "version", "bus" }) do
  local f = fixture()
  local handle, actor = spawn(f)
  T.check(handle:scriptMove("right", 2, f.exports.done), "movement starts before " .. change)
  local callback = f.pending.callback
  local restore
  if change == "game" then
    local old = f.live
    f.live = {}
    restore = function()
      f.live = old
    end
  elseif change == "version" then
    Version.set("blue")
    restore = function()
      Version.set("red")
    end
  elseif change == "world" then
    local old = f.game.overworld
    f.game.overworld = {}
    restore = function()
      f.game.overworld = old
    end
  elseif change == "bus" then
    local old = Runtime.events
    Runtime.events = require("src.mods.Events").new()
    restore = function()
      Runtime.events = old
    end
  elseif change == "actor" then
    table.remove(f.ow.npcs, #f.ow.npcs)
    restore = function()
      f.ow.npcs[#f.ow.npcs + 1] = actor
    end
  else
    local object = (change == "map") and f.ow or f.game
    local old = object[change]
    object[change] = {}
    restore = function()
      object[change] = old
    end
  end
  f:update()
  T.eq(#f.ow.scriptMoves, 0, "changed context retires only owned movement")
  restore()
  callback("stale")
  callback("replayed")
  T.eq(f.exports.result().calls, 0, "restored " .. change .. " cannot revive callback")
end
for _, event in ipairs({ "map.exited", "map.entered" }) do
  local f = fixture()
  local handle = spawn(f)
  T.check(handle:scriptMove("right", 1, f.exports.done), "movement starts before map lifecycle")
  local callback = f.pending.callback
  Runtime.emit(event, { mapId = f.home })
  T.eq(#f.ow.scriptMoves, 0, "map lifecycle retires movement immediately")
  callback()
  T.eq(f.exports.result().calls, 0, "old map callback suppressed")
end
for _, action in ipairs({ "rollback", "reload", "teardown" }) do
  local f = fixture()
  local handle, actor = spawn(f)
  local foreign = f:spawn(f.home, { name = "OTHER", sprite = "PROBE", x = 5, y = 5 }, "other")
  T.check(handle:scriptMove("right", 1, f.exports.done), "queue before " .. action)
  local callback = f.pending.callback
  local foreignEntry = {
    entity = f.imported,
    remaining = 1,
    onDone = function()
      error("do not invoke")
    end,
  }
  f.ow.scriptMoves[#f.ow.scriptMoves + 1] = foreignEntry
  if action == "rollback" then
    f.loader:_rollback("npcs")
  elseif action == "reload" then
    fixture()
  else
    Loader.teardown()
  end
  T.eq(#f.ow.scriptMoves, 1, "unload removes only owned queue entries")
  T.eq(f.ow.scriptMoves[1], foreignEntry, "foreign movement retained")
  T.eq(#f.game.data.maps[f.home].objects, 2, "unload removes only own runtime template")
  T.eq(f.ow.npcPool[handle.id], nil, "own actor removed from native pool")
  T.check(f.ow.npcPool[foreign], "foreign owner retained")
  callback()
  T.eq(f.exports.result().calls, 0, "unload suppresses native callback")
  T.eq(handle:position(), nil, "unloaded handle retired")
  T.eq(f.exports.npc(f.home, "IMPORTED"), nil, "unloaded facade retired")
end
do
  local f = fixture()
  local handle, actor = spawn(f)
  T.check(f.exports.remove(handle.id), "own removal succeeds")
  local replacement = assert(f.exports.spawn(f.home, { name = "NEW", sprite = "PROBE", x = 1, y = 1 }))
  T.eq(replacement, handle.id, "native ID can be reused")
  local value, why = handle:face("left")
  T.eq(value, nil, "old handle cannot change replacement with same ID")
  T.eq(why, "NPC handle is stale", "stale handle diagnosed")
  T.eq(f.exports.npc(f.home, replacement):position(), 1, "replacement remains untouched")
end
do
  local f = fixture()
  local handle, actor = spawn(f)
  f.synchronous = true
  T.check(
    handle:scriptMove("right", 1, function(...)
      T.eq(Runtime.currentMod, "npcs", "movement callback attributed")
      f.exports.done(...)
      f.synchronous = false
      T.check(handle:face("up"), "synchronous callback runs after commit guard released")
    end),
    "synchronous move accepted"
  )
  T.eq(f.exports.result().calls, 1, "synchronous callback called once")
  T.eq(f.exports.result().args.n, 3, "nil argument holes preserved")
  f.pending.callback()
  T.eq(f.exports.result().calls, 1, "duplicate completion ignored")
  T.eq(Runtime.currentMod, nil, "callback restores runtime owner")
end
for _, err in ipairs({
  "authored failure",
  setmetatable({}, {
    __tostring = function()
      error("hostile tostring")
    end,
  }),
}) do
  local f = fixture()
  local handle = spawn(f)
  T.check(
    handle:scriptMove("right", 1, function()
      error(err, 0)
    end),
    "throwing callback admitted"
  )
  T.check(
    pcall(function()
      f:complete()
      f.pending.callback()
    end),
    "callback errors cannot escape native completion"
  )
  T.eq(#f.loader.errors, 1, "callback error attributed once")
  T.check(
    f.loader.errors[1]:find("npcs: NPC movement callback failed:", 1, true),
    "callback error names owner"
  )
end
do
  local f = fixture()
  local handle = spawn(f)
  f.failMovement, f.synchronous = true, true
  T.eq(handle:scriptMove("right", 1, f.exports.done), nil, "native refusal never counts as admission")
  T.eq(f.exports.result().calls, 0, "callback deferred until native result")
  T.eq(#f.ow.scriptMoves, 0, "native refusal leaves no owned queue entry")
end
do
  local f = fixture()
  local handle = spawn(f)
  local native = f.ow.scriptMove
  function f.ow:scriptMove(...)
    Runtime.emit("map.exited", { mapId = f.home })
    return native(self, ...)
  end
  T.eq(handle:scriptMove("right", 1, f.exports.done), nil, "map change during admission refuses completion")
  T.eq(#f.ow.scriptMoves, 0, "late-created owned entry cleaned after cancellation race")
end
do
  local f = fixture()
  local handle = spawn(f)
  T.check(handle:scriptMove("right"), "optional count/callback accepted")
  f:complete()
  T.eq(handle:position(), 1, "default count is one")
  T.eq(#f.loader.errors, 0, "omitted callback never treated as a callable")
end
-- Real native object creation/removal, NPC updates and movement queue.
local OW = require("src.world.OverworldController")
local function bind(game)
  for i = 1, 100 do
    local name, old = debug.getupvalue(OW.addRuntimeObject, i)
    if not name then
      break
    end
    if name == "Game" then
      debug.setupvalue(OW.addRuntimeObject, i, game)
      return function()
        debug.setupvalue(OW.addRuntimeObject, i, old)
      end
    end
  end
  error("native Game upvalue missing")
end
for _, version in ipairs({ "red", "gold", "crystal", "firered", "emerald" }) do
  local f = fixture(version)
  local restore = bind(f.game)
  f.ow.addRuntimeObject, f.ow.removeRuntimeObject = OW.addRuntimeObject, OW.removeRuntimeObject
  f.ow.scriptMove, f.ow.marchInPlace = OW.scriptMove, OW.marchInPlace
  local handle, actor = spawn(f)
  actor.frozen = true
  T.check(handle:scriptMove("right", 2, f.exports.done), version .. " native movement starts")
  for _ = 1, 40 do
    OW.updateScriptMoves(f.ow)
    actor:update(f.ow.map, f.ow.entities)
  end
  T.eq(handle:position(), 2, "native queue walks exactly two cells")
  T.eq(f.exports.result().calls, 1, "native completion exactly once")
  T.eq(#f.ow.scriptMoves, 0, "native movement releases world input")
  T.check(handle:marchInPlace(f.exports.done), "native march starts")
  for _ = 1, 20 do
    OW.updateScriptMoves(f.ow)
    actor:update(f.ow.map, f.ow.entities)
  end
  T.eq(handle:position(), 2, "march does not translate")
  T.eq(f.exports.result().calls, 2, "native march completes")
  T.check(handle:setAppearance("ALT"), "native renderer refresh path")
  T.eq(actor.def.sprite, "ALT", "actor appearance changed")
  T.eq(
    f.game.data.maps[f.home].objects[2].sprite,
    "PROBE",
    "native template data not rewritten by appearance"
  )
  T.check(f.exports.remove(handle.id), "native removal succeeds")
  T.eq(#f.ow.npcs, 1, "native removal retains imported actor")
  restore()
end
do
  local f = fixture()
  local native = f.ow.addRuntimeObject
  function f.ow:addRuntimeObject(...)
    native(self, ...)
    error("creation failure", 0)
  end
  T.eq(f.exports.spawn(f.home, { sprite = "PROBE", x = 0, y = 0 }), nil, "creation exception contained")
  T.eq(#f.game.data.maps[f.home].objects, 1, "failed creation template rolled back")
  T.eq(#f.ow.npcs, 1, "failed creation actor rolled back")
  T.eq(next(f.ow.npcPool), f.imported.id, "failed creation leaves pool unchanged")
end
do
  local f = fixture()
  local row =
    { name = "LATER", sprite = "PROBE", x = 1, y = 1, owner = "forged", runtime = false, index = 900 }
  local id = assert(f.exports.spawn(f.dest, row))
  local record = f.game.data.maps[f.dest].objects[1]
  T.eq(record.owner, "npcs", "caller cannot forge runtime ownership")
  T.eq(record.runtime, true, "native runtime marker assigned")
  T.eq(record.index, 1, "native identity replaces supplied index")
  T.eq(#f.ow.npcs, 1, "inactive spawn adds no active actor")
  local actor = f:make(f.dest, record)
  actor.def = require("src.mods.Merge").deepCopy(record) -- Native placement/appearance clones.
  local map = require("src.world.Map").new(f.game.data.maps[f.dest], f.ow.map.tileset)
  f.ow.ghosts = { { npc = actor, map = map } }
  f.ow.npcPool[id] = actor
  local handle = assert(f.exports.npc(f.dest, id))
  T.eq(handle:position(), 1, "live neighbor uses its own coordinate frame")
  T.eq(handle:canStep("right"), true, "neighbor collision uses neighbor map")
  local homeHandle, homeActor = spawn(f)
  homeActor.cellX, homeActor.cellY = 2, 1
  local nb = { map = map, cx = 0, cy = 0, peers = { actor } }
  f.ow.neighbors = { nb }
  f.ow.ghosts[1].nb = nb
  require("src.world.OverworldController").updateCast(f.ow)
  T.eq(handle:canStep("right"), false, "neighbor cast sees translated primary actor")
  T.eq(homeHandle:canStep("left"), false, "primary cast sees translated neighbor actor")
  homeActor.passable = true
  actor.passable = true
  require("src.world.OverworldController").updateCast(f.ow)
  T.eq(handle:canStep("right"), true, "neighbor cast respects primary passability")
  T.eq(homeHandle:canStep("left"), true, "primary cast respects neighbor passability")
  T.check(handle:face("left"), "neighbor can face")
  local ok, why = handle:scriptMove("right", 1)
  T.eq(ok, nil, "neighbor track refused")
  T.eq(why, "movement tracks require the active map", "neighbor restriction explicit")
  Loader.teardown()
  T.eq(#f.game.data.maps[f.dest].objects, 0, "inactive template cleaned on unload")
  T.eq(#f.ow.ghosts, 0, "later neighbor actor clone cleaned on unload")
  T.eq(f.ow.npcPool[id], nil, "neighbor pool cleaned on unload")
end
do
  local f = fixture()
  local handle, actor = spawn(f)
  handle.id = f.imported.id
  T.check(handle:face("left"), "public ID field cannot redirect private handle binding")
  T.eq(actor.facing, "left", "original binding changed")
  T.eq(f.imported.facing, "down", "imported actor unaffected")
end
Renderer.new = originalRenderer
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("API 3 public NPC actions")
