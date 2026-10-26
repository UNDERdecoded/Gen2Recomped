package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Contract = require("tests.api3_contract.world_edits")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Loader = require("src.mods.Loader")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
love = nil
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared object/block contracts: " .. tostring(why))
end
for _, version in ipairs({ "red", "gold", "firered", "emerald" }) do
  for _, key in ipairs({ "flags", "objectToggles", "g2ObjectToggles", "gen3Spawned", "gen3SessionObjects" }) do
    local gen = Version.generation(version)
    if
      gen == 1 and (key == "objectToggles" or key == "flags")
      or gen == 2 and (key == "flags" or key == "g2ObjectToggles" or key == "objectToggles")
      or gen == 3
        and (key == "flags" or key == "gen3Spawned" or key == "gen3SessionObjects" or key == "objectToggles")
    then
      local f = fixture(version)
      f.game.save[key] = "keep"
      local ok, why = f.exports.toggle(f.home, "NPC", false)
      T.eq(ok, nil, key .. " malformed store rejected")
      T.check(type(why) == "string", "store refusal explained")
      T.eq(f.game.save[key], "keep", "malformed store retained")
      T.eq(#f.exports.events(), 0, "malformed store emits no event")
      T.eq(f.visible.NPC, true, "malformed store leaves native object untouched")
    end
  end
end
for _, version in ipairs({ "red", "firered" }) do
  local f = fixture(version)
  local key = f.gen == 1 and "objectToggles" or "gen3Spawned"
  f.game.save[key] = { [f.home] = "keep" }
  T.eq(f.exports.toggle(f.home, "NPC", false), nil, "malformed nested bucket rejected")
  T.eq(f.game.save[key][f.home], "keep", "nested bucket never replaced")
  T.eq(#f.exports.events(), 0, "no event for malformed nested bucket")
end
for _, lock in ipairs({
  "linkSession",
  "linkNet",
  "gen3Locked",
  "parallelRunners",
  "parallelQueue",
  "pendingScripts",
  "_modScriptLock",
}) do
  local f = fixture()
  if lock == "linkSession" then
    f.game.linkSession = {}
  elseif lock == "linkNet" then
    f.game.linkNet = { closed = false }
  elseif lock == "parallelRunners" or lock == "parallelQueue" or lock == "pendingScripts" then
    f.ow[lock] = { {} }
  else
    f.ow[lock] = true
  end
  T.eq(f.exports.toggle(f.home, "NPC", false), nil, lock .. " blocks objects")
  T.eq(f.exports.replace(0, 0, 7), nil, lock .. " blocks blocks")
  T.eq(#f.exports.events(), 0, "busy requests never emit effects")
end
for _, failure in ipairs({
  "renderer",
  "coordinates",
  "geometry",
  "current_block",
  "objects",
  "object_runtime",
}) do
  local f = fixture("gold")
  if failure == "renderer" then
    f.ow.map.renderer = nil
  elseif failure == "coordinates" then
    f.ow.map.def.width = 0
  elseif failure == "geometry" then
    f.ow.map.blockCells, f.ow.map.blockTiles = 1, 2
  elseif failure == "current_block" then
    f.ow.map.def.blocks[1] = nil
  elseif failure == "objects" then
    f.ow.map.def.objects = nil
  else
    f.ow.syncObjectVisibility = nil
  end
  local ok, why
  if failure == "objects" or failure == "object_runtime" then
    ok, why = f.exports.toggle(f.home, "NPC", false)
  else
    ok, why = f.exports.replace(0, 0, 7)
  end
  T.eq(ok, nil, failure .. " refuses safely")
  T.check(type(why) == "string", "native context refusal explained")
  T.eq(#f.exports.events(), 0, "invalid context emits nothing")
  T.eq(f.rebuilds + f.syncs + f.reloads, 0, "invalid context performs no native work")
end
for _, operation in ipairs({ "rollback", "reload", "teardown" }) do
  local f = fixture()
  if operation == "rollback" then
    f.loader:_rollback("edits")
  elseif operation == "reload" then
    fixture()
  else
    Loader.teardown()
  end
  local ok, why = f.exports.toggle(f.home, "NPC", false)
  T.eq(ok, nil, operation .. " retires object action")
  T.eq(why, "world facade is retired", "retired object diagnostic")
  ok, why = f.exports.replace(0, 0, 7)
  T.eq(ok, nil, operation .. " retires block action")
  T.eq(why, "world facade is retired", "retired block diagnostic")
  T.eq(#f.exports.events(), 0, "retired facade emits nothing")
end
do
  local f = fixture()
  f.exports.reenter(true)
  T.check(f.exports.toggle(f.home, "NPC", false), "outer edit accepted")
  T.eq(f.exports.nested()[1], nil, "event cannot reenter a partially committed edit")
  T.eq(f.exports.nested()[2], "world is busy", "reentry refused explicitly")
  T.eq(f.rebuilds, 0, "nested edit never redraws")
  T.eq(#f.exports.events(), 1, "outer edit emits once")
  f.exports.reenter(false)
  T.check(f.exports.replace(0, 0, 8), "guard released after successful edit")
  local rebuild = f.ow.map.renderer.rebuild
  f.ow.map.renderer.rebuild = function()
    error("draw probe", 0)
  end
  local ok, why = f.exports.replace(0, 0, 7)
  T.eq(ok, nil, "native redraw failure contained")
  T.check(why:find("draw probe", 1, true), "native failure explained")
  f.ow.map.renderer.rebuild = rebuild
  T.check(f.exports.replace(0, 0, 8), "guard released after native exception")
end
-- Packed Gen3 source reads remain observational; replacement uses instance patches.
do
  local f = fixture("emerald")
  f.ow.map.def.blocks = string.rep(string.char(7, 0), 6)
  f.ow.map.def._blockArray = nil
  f.ow.map.collisionPatch[1] = 1
  f.ow.map.shutCells = { ["0:0"] = true }
  T.check(f.exports.replace(0, 0, 8), "packed metatile map writable")
  T.eq(f.exports.read(f.home, 0, 0), 8, "reads see metatile patch")
  T.eq(f.ow.map.def.blocks, string.rep(string.char(7, 0), 6), "generated source bytes untouched")
  T.eq(f.ow.map.def._blockArray, nil, "validation does not decode/cache source")
  T.eq(f.ow.map.collisionPatch[1], 0, "native default clears stale collision override")
  T.eq(f.ow.map.shutCells["0:0"], nil, "native default clears stale shut cell")
end
-- Native controller methods; no actor construction or graphics are mocked.
love = require("tests.love_stub")
local OW = require("src.world.OverworldController")
local function bind(game)
  for i = 1, 100 do
    local name, old = debug.getupvalue(OW.syncObjectVisibility, i)
    if not name then
      break
    end
    if name == "Game" then
      debug.setupvalue(OW.syncObjectVisibility, i, game)
      return function()
        debug.setupvalue(OW.syncObjectVisibility, i, old)
      end
    end
  end
  error("native Game upvalue missing")
end
for _, version in ipairs({ "gold", "silver", "crystal", "firered", "emerald" }) do
  local f = fixture(version)
  local restore = bind(f.game)
  setmetatable(f.ow, { __index = OW })
  f.ow.syncObjectVisibility = OW.syncObjectVisibility
  f.ow.replaceBlock = OW.replaceBlock
  local function actor(def, x)
    return {
      id = f.home .. "_obj_" .. def.index,
      def = def,
      cellX = x,
      cellY = 1,
      px = x * 16,
      py = 16,
      facing = "right",
    }
  end
  local target, sibling = actor(f.flagged, 3), actor(f.flagless, 2)
  -- Distinct live actors share one persistent flag; only the named actor moves.
  f.flagless.eventFlag = f.flagged.eventFlag
  f.ow.npcs = { target, sibling }
  f.ow.entities = { f.player, target, sibling }
  f.ow.npcPool = { [target.id] = target, [sibling.id] = sibling }
  T.check(f.exports.toggle(f.home, "NPC", false), version .. " actual native removal")
  T.eq(#f.ow.npcs, 1, "only target removed")
  T.eq(f.ow.npcs[1], sibling, "shared-flag sibling retained live")
  T.eq(sibling.cellX, 2, "unrelated actor not relocated")
  T.check(f.exports.toggle(f.home, "NPC", true), "actual native respawn")
  T.eq(#f.ow.npcs, 2, "one actor restored")
  T.eq(target.cellX, 3, "pooled position retained")
  T.eq(target.facing, "right", "pooled facing retained")
  f.flagless.eventFlag = nil
  T.check(f.exports.toggle(f.home, "TEMP", false), "flagless object hidden for visit")
  T.eq(OW.objectVisible(f.game.save, f.home, f.flagless), false, "native spawn predicate sees session hide")
  f.game.save.g2ObjectToggles = nil
  f.game.save.gen3SessionObjects = nil
  T.eq(OW.objectVisible(f.game.save, f.home, f.flagless), true, "flagless default restored after visit reset")
  T.check(f.exports.replace(1, 2, 7), "actual native block/redraw path")
  T.eq(f.ow.map:blockAt(1, 2), 7, "actual Map returns patched block")
  T.eq(f.ow.map.def.blocks[6], 8, "generated map record retained")
  T.eq(f.ow.map.blocksDirty, nil, "native redraw consumes dirty flag")
  restore()
end
for _, version in ipairs({ "firered", "emerald" }) do
  local f = fixture(version)
  T.check(f.exports.toggle("HOME", "NPC", false), "unprefixed Gen3 active map resolves")
  T.eq(f.exports.events()[1].mapId, f.home, "event reports resolved native map ID")
end
do
  local f = fixture("gold")
  require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  Commands.g2ResetObjectBase()
  local ctx = { game = f.game, save = f.game.save, overworld = f.ow }
  Commands.g2_object(ctx, 2, true) -- Cache the native script numbering first.
  f.game.data.field = { objectScriptBase = 1 }
  T.check(f.exports.toggle(f.home, 1, false), "public slot resolves independently of cached script IDs")
  T.eq(f.visible.NPC, false, "current native template receives visibility effect")
  Commands.g2_object(ctx, 1, true)
  T.eq(f.visible.NPC, false, "public adapter leaves existing script-ID cache unchanged")
  Commands.g2ResetObjectBase()
end
-- Existing native/API-2 facade retains its own coercion/validation behavior.
do
  local f = fixture()
  local api = require("src.world.WorldAPI").new(f.game, "legacy")
  T.check(api:toggleObject("UNKNOWN", "missing", "truthy"), "legacy off-map toggle unchanged")
  T.eq(f.game.save.objectToggles.UNKNOWN.missing, true, "legacy boolean coercion unchanged")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("API 3 object and block edits")
