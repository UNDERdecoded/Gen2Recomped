package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Loader = require("src.mods.Loader")
local WorldAPI = require("src.world.WorldAPI")
local Actions = require("src.world.WorldActions")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Merge = require("src.mods.Merge")
local Json = require("src.link.Json")
local G4Fly = require("src.world.Gen4Fly")
local Gen3Show = require("src.world.Gen3FieldMove")
local saved = { GameVersion.get(), Runtime.events, Runtime.hooks, Runtime.errors, love, Gen3Show.show }
love = nil
-- Deterministic no-picture native fallback for the cross-version cases.
Gen3Show.show = function()
  return false
end
local function boot(version)
  GameVersion.set(version)
  local gen = GameVersion.generation()
  local data = {
    pokemon = {},
    moves = {},
    items = {},
    constants = { badges = {} },
    tilesets = { TEST = { blockCells = gen < 3 and 2 or 1 } },
    maps = {
      HOME = {
        id = "HOME",
        width = 20,
        height = 20,
        tileset = "TEST",
        outdoor = true,
        mapType = "ROUTE",
        allowFly = true,
        gen5Flags = 0x2000,
      },
      DEST = { id = "DEST", width = 20, height = 20, tileset = "TEST", outdoor = true, mapType = "CITY" },
    },
    field = { flyOrder = { "DEST" }, flyWarps = { DEST = { x = 3, y = 4 } } },
  }
  for i = 1, 16 do
    data.constants.badges[i] = { id = "BADGE_" .. i }
  end
  local save = {
    party = {
      { species = "A", hp = 1, moves = { { id = gen >= 4 and 19 or "FLY" } } },
      {
        species = "B",
        hp = 0,
        moves = {},
      },
    },
    visited = { DEST = true },
    lastHeal = { map = "DEST", x = 3, y = 4 },
    flags = {},
    badges = {},
  }
  for i = 1, 16 do
    save.badges["BADGE_" .. i] = true
  end
  if gen == 4 then
    data.gen4_version =
      { family = (version == "heartgold" or version == "soulsilver") and "hgss" or "platinum" }
    local row = { index = 0, firstArrival = 1, fly = { map = "DEST", x = 3, y = 4 } }
    data.field.healLocations = { row }
    save.flags[G4Fly.rowFlagKey(data, row)] = true
  elseif gen == 5 then
    data.maps.Z001 = data.maps.DEST
    data.gen5_town_map =
      { locations = { { zone = 1, flyPoint = true, spawn = { main = true, x = 3, z = 4 } } } }
    save.gen5FlyZones = { ["1"] = true }
  end
  local calls = {}
  local ow = {
    isOverworld = true,
    map = { id = "HOME", def = data.maps.HOME },
    player = { cellX = 2, cellY = 3, facing = "up" },
    scriptMoves = {},
    pendingScripts = {},
    runner = {
      isRunning = function()
        return false
      end,
    },
  }
  ow.player.facingCell = function(p)
    return p.cellX, p.cellY - 1
  end
  local game
  ow.partyKnows = function(_, move)
    if move == "FLY" then
      return game.save.party[1]
    end
  end
  ow.flyTo = function(_, id, mon)
    calls[#calls + 1] = { kind = "fly", id = id, mon = mon }
    ow.flyAnim = {}
  end
  ow.gen4FlyTo = function(_, dest, mon)
    calls[#calls + 1] = { kind = "fly", id = dest.map, x = dest.x, y = dest.y, mon = mon }
    ow.flyAnim = {}
  end
  local stack = { states = { ow } }
  function stack:top()
    return self.states[#self.states]
  end
  function stack:push(state)
    self.states[#self.states + 1] = state
  end
  function stack:pop()
    return table.remove(self.states)
  end
  game = { data = data, save = save, overworld = ow, stack = stack }
  local files = {
    ["mods/probe/manifest.json"] = Json.encode({
      id = "probe",
      name = "Probe",
      version = "1.0.0",
      api = 2,
      entry = "main.lua",
    }),
    ["mods/probe/main.lua"] = "return function(mod) mod.exports.api=mod end",
  }
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(files[p], p)
    end,
    getDirectoryItems = function(p)
      return p == "mods" and { "probe" } or {}
    end,
    getInfo = function(p)
      if p == "mods" or p == "mods/probe" then
        return { type = "directory" }
      end
      if files[p] then
        return { type = "file" }
      end
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false })
  local resolved = 0
  loader._game = function()
    resolved = resolved + 1
    return game
  end
  assert(loader:load(data), table.concat(loader.errors, "; "))
  return loader.apis.probe, game, ow, calls, function()
    return resolved
  end
end
for _, version in ipairs(GameVersion.ORDER) do
  local api, game, ow, calls, resolved = boot(version)
  local label = version .. ": "
  T.eq(resolved(), 0, label .. "building API does not construct Game")
  if api.supports then
    for _, name in ipairs({
      "canReorderParty",
      "reorderParty",
      "availableFieldActions",
      "useFieldAction",
      "canFly",
      "flyTo",
    }) do
      T.eq(api:supports("world", name), true, label .. "capability " .. name)
    end
    T.eq(resolved(), 0, label .. "capability probes do not construct Game")
  end
  local world = api.world
  local before = Merge.deepCopy(game)
  T.eq(world:canReorderParty(), true, label .. "free-roam party can reorder")
  T.eq(world:canFly(), true, label .. "native flight checks pass")
  T.same(game, before, label .. "availability does not alter save/world")
  local p = game.save.party
  local a, b = p[1], p[2]
  T.eq(world:reorderParty(1, 2), true, label .. "swap accepted")
  T.eq(game.save.party, p, label .. "party list identity retained")
  T.eq(p[1], b, label .. "fainted party member may move")
  T.eq(p[2], a, label .. "Pokemon identity retained")
  T.eq(world:reorderParty(1, 2), true, label .. "swap back accepted")
  T.eq(world:reorderParty(1, 1), true, label .. "same-slot no-op accepted")
  for _, slot in ipairs({ 0, -1, 3, 7, 1.5, "1", math.huge, 0 / 0 }) do
    before = Merge.deepCopy(game)
    local ok, reason = world:reorderParty(slot, 1)
    T.check(ok == nil and reason == "invalid party slot", label .. "invalid slot refused")
    T.same(game, before, label .. "bad swap atomic")
  end
  local locks = {
    "transitioning",
    "flyAnim",
    "teleportOut",
    "engaging",
    "emote",
    "pikaHop",
    "healAnim",
    "whirlSpin",
    "gen4Waterfall",
    "gen5SeamPending",
    "gen3Decorate",
    "frameScriptThisTick",
    "_modScriptLock",
  }
  for _, lock in ipairs(locks) do
    ow[lock] = true
    before = Merge.deepCopy(game)
    T.eq(world:canReorderParty(), false, label .. lock .. " blocks reorder probe")
    T.eq(world:canFly(), false, label .. lock .. " blocks fly probe")
    T.eq(world:reorderParty(1, 2), nil, label .. lock .. " blocks swap")
    T.eq(world:flyTo("DEST"), nil, label .. lock .. " blocks flight")
    T.eq(world:useFieldAction("surf"), nil, label .. lock .. " blocks field use")
    T.same(world:availableFieldActions(), {}, label .. lock .. " suppresses actions")
    T.same(game, before, label .. lock .. " refusal leaves game unchanged")
    ow[lock] = nil
  end
  for _, lock in ipairs({ "moving", "inputLocked", "stairExit", "spinning", "fieldMove" }) do
    ow.player[lock] = true
    before = Merge.deepCopy(game)
    T.eq(world:reorderParty(1, 2), nil, label .. "player " .. lock .. " blocks swap")
    T.eq(world:flyTo("DEST"), nil, label .. "player " .. lock .. " blocks fly")
    T.same(game, before, label .. "player " .. lock .. " no mutation")
    ow.player[lock] = nil
  end
  game.stack:push({ isBattle = true })
  T.eq(world:reorderParty(1, 2), nil, label .. "battle/screen above world blocks swap")
  T.eq(world:flyTo("DEST"), nil, label .. "battle/screen blocks fly")
  game.stack:pop()
  ow.runner.isRunning = function()
    return true
  end
  T.eq(world:reorderParty(1, 2), nil, label .. "running VM blocks swap")
  ow.runner.isRunning = function()
    return false
  end
  ow.pendingScripts[1] = {}
  T.eq(world:flyTo("DEST"), nil, label .. "pending scene blocks flight")
  ow.pendingScripts = {}
  ow.scriptMoves[1] = {}
  T.eq(world:reorderParty(1, 2), nil, label .. "scripted movement blocks swap")
  ow.scriptMoves = {}
  game.linkSession = {}
  T.eq(world:flyTo("DEST"), nil, label .. "link lock blocks flight")
  game.linkSession = nil
  game.linkNet = { closed = false }
  T.eq(world:reorderParty(1, 2), nil, label .. "live link net blocks swap")
  game.linkNet = nil
  local destination = GameVersion.generation() == 5 and "Z001" or "DEST"
  before = Merge.deepCopy(game)
  T.eq(world:flyTo("MISSING"), nil, label .. "unknown destination refused")
  T.eq(world:flyTo({}), nil, label .. "non-string destination refused")
  T.same(game, before, label .. "invalid destinations leave save/world unchanged")
  T.eq(#calls, 0, label .. "no gameplay handlers ran on refusal")
  T.eq(world:flyTo(destination), true, label .. "flight accepted")
  T.eq(#calls, 1, label .. "one native departure")
  T.eq(calls[1].id, destination, label .. "native destination selected")
  T.eq(calls[1].mon, a, label .. "native carrier identity retained")
  T.eq(world:flyTo(destination), nil, label .. "in-flight repeat refused")
  T.eq(#calls, 1, label .. "repeat does not replay departure")
  ow.flyAnim = nil
  a.isEgg = true
  T.eq(world:canFly(), false, label .. "egg cannot carry flight")
  a.isEgg = nil
  if GameVersion.generation() == 4 then
    game.save.flags.FLAG_G4_0961 = true
    T.eq(world:canFly(), false, label .. "native partner restriction retained")
    game.save.flags.FLAG_G4_0961 = nil
    if version == "heartgold" or version == "soulsilver" then
      game.save.hgssRocketCostume = true
      T.eq(world:canFly(), false, label .. "Rocket costume restriction retained")
      game.save.hgssRocketCostume = nil
    end
  end
  game.save = nil
  T.eq(world:canReorderParty(), false, label .. "no save probe safe")
  T.eq(world:reorderParty(1, 2), nil, label .. "no save swap safe")
  T.eq(world:canFly(), false, label .. "no save fly probe safe")
  T.eq(world:flyTo(destination), nil, label .. "no save fly safe")
end

-- Exercise the actual native carrier/badge lookup and departure methods,
-- including their input lock and animation/landing state, without graphics.
local OW = require("src.world.OverworldController")
love = {} -- native sound entry points expect a host table, but need no audio device
local gameUpvalue, oldGame
for i = 1, 30 do
  local name, value = debug.getupvalue(OW.flyTo, i)
  if name == "Game" then
    gameUpvalue = i
    oldGame = value
    break
  end
end
assert(gameUpvalue, "native Game binding")
for _, version in ipairs(GameVersion.ORDER) do
  local api, game, ow = boot(version)
  debug.setupvalue(OW.flyTo, gameUpvalue, game)
  ow.partyKnows = OW.partyKnows
  ow.flyTo = OW.flyTo
  ow.gen4FlyTo = OW.gen4FlyTo
  ow.closeToMap = OW.closeToMap
  ow.clearBikeFlags = function() end
  ow.hasFlyBird = function()
    return false
  end
  ow.syncSurfingPikachu = function() end
  local gen = GameVersion.generation()
  if gen <= 2 then
    game.data.constants.hmBadges = { FLY = { badge = "FLY_ALLOWED" } }
    game.save.flags.FLY_ALLOWED = true
  elseif gen == 3 then
    game.data.constants.gen3FieldMoves = { FLY = { badgeFlag = 0x820 } }
    game.save.flags.FLAG_G3_0820 = true
  end
  local destination = gen == 5 and "Z001" or "DEST"
  T.eq(api.world:canFly(), true, version .. " actual native eligibility")
  local before = Merge.deepCopy(game)
  if gen <= 2 then
    game.save.flags.FLY_ALLOWED = nil
  elseif gen == 3 then
    game.save.flags.FLAG_G3_0820 = nil
  elseif gen == 4 then
    for k in pairs(game.save.badges) do
      game.save.badges[k] = nil
    end
  end
  if gen < 5 then
    T.eq(api.world:canFly(), false, version .. " native missing badge refuses flight")
    T.eq(api.world:flyTo(destination), nil, version .. " missing badge has no departure")
    T.eq(ow.flyAnim, nil, version .. " denied departure has no animation")
  end
  game.save = Merge.deepCopy(before.save)
  if gen <= 3 then
    game.save.visited.DEST = nil
  elseif gen == 4 then
    game.save.flags = {}
  else
    game.save.gen5FlyZones = {}
  end
  T.eq(api.world:canFly(), false, version .. " unvisited/locked destinations unavailable")
  T.eq(api.world:flyTo(destination), nil, version .. " locked destination refuses native handler")
  game.save = Merge.deepCopy(before.save)
  -- Validate the landing before any departure-side state is changed.
  if gen <= 3 then
    game.data.field.flyWarps.DEST.x = -1
  elseif gen == 4 then
    game.data.field.healLocations[1].fly.x = -1
  else
    game.data.gen5_town_map.locations[1].spawn.x = -1
  end
  T.eq(api.world:flyTo(destination), nil, version .. " invalid landing refused")
  T.eq(ow.flyAnim, nil, version .. " invalid landing leaves animation absent")
  if gen <= 3 then
    game.data.field.flyWarps.DEST.x = 3
  elseif gen == 4 then
    game.data.field.healLocations[1].fly.x = 3
  else
    game.data.gen5_town_map.locations[1].spawn.x = 3
  end
  game.save.onBike = true
  ow.player.surfing = true
  T.eq(api.world:flyTo(destination), true, version .. " native departure accepted")
  T.eq(ow.flyAnim.frames, 48, version .. " native flight timing preserved")
  T.eq(ow.flyDest.map, destination, version .. " native landing map preserved")
  T.eq(ow.flyDest.x, 3, version .. " native landing x preserved")
  T.eq(ow.flyDest.y, 4, version .. " native landing y preserved")
  T.eq(ow.player.inputLocked, true, version .. " native input lock applied")
  T.eq(ow.player.surfing, false, version .. " native surfing cleared")
  T.eq(game.save.onBike, false, version .. " native bicycle state cleared")
end
for _, version in ipairs({ "red", "gold", "emerald" }) do
  local api, game, ow = boot(version)
  debug.setupvalue(OW.flyTo, gameUpvalue, game)
  local gen = GameVersion.generation()
  ow.partyKnows = OW.partyKnows
  ow.beginTeleportOut = OW.beginTeleportOut
  ow.syncSurfingPikachu = function() end
  ow.escapePoint = function()
    return { map = "DEST", x = 3, y = 4 }
  end
  game.save.party[1].moves = { { id = "DIG" }, { id = "TELEPORT" } }
  ow.map.def.tileset = "CAVERN"
  ow.map.def.environment = 4
  ow.map.def.allowEscaping = true
  T.eq(api.world:useFieldAction("dig"), true, version .. " actual native Dig starts")
  T.eq(ow.teleportOut.frames, 48, version .. " native Dig animation timing")
  T.eq(ow.teleportOut.escape, gen >= 2 and true or nil, version .. " native Dig escape destination semantics")
  T.eq(ow.player.inputLocked, true, version .. " native Dig input lock")
  ow.teleportOut = nil
  ow.player.inputLocked = false
  ow.player.spinning = false
  ow.map.def.tileset = "OVERWORLD"
  ow.map.def.environment = 1
  T.eq(api.world:useFieldAction("teleport"), true, version .. " actual native Teleport starts")
  T.eq(ow.teleportOut.frames, 48, version .. " native Teleport animation timing")
  T.eq(ow.teleportOut.escape, nil, version .. " native Teleport uses last heal point")
end
debug.setupvalue(OW.flyTo, gameUpvalue, oldGame)
love = nil

-- Field dispatch is tested separately from presentation, using native IDs
-- and the exact overworld methods called by the existing party menus.
for _, version in ipairs({ "red", "gold", "emerald", "platinum", "black" }) do
  local api, game, ow, calls = boot(version)
  local world = api.world
  local gen = GameVersion.generation()
  local mon = game.save.party[1]
  ow.partyKnows = function()
    return mon
  end
  ow.useSurfFieldMove = function()
    return "ok"
  end
  ow.useCutFieldMove = function()
    return "ok"
  end
  ow.trySurf = function(_, x, y, close, carrier)
    calls[#calls + 1] = { kind = "surf", carrier = carrier, x = x, y = y }
    game.stack:push({ isText = true })
  end
  ow.tryCut = function(_, x, y)
    calls[#calls + 1] = { kind = "cut", x = x, y = y }
    game.stack:push({ isText = true })
    return true
  end
  ow.beginTeleportOut = function(_, done, opts)
    calls[#calls + 1] = { kind = "escape", escape = opts.escape }
    ow.teleportOut = {}
  end
  ow.escapePoint = function()
    return { map = "DEST", x = 3, y = 4 }
  end
  local before = Merge.deepCopy(game)
  local list = world:availableFieldActions()
  T.same(game, before, version .. " field availability is data-only with native pure gates")
  local names = {}
  for _, row in ipairs(list) do
    names[row.id] = true
  end
  T.eq(names.surf, gen <= 3 and true or nil, version .. " verified surf coverage")
  T.eq(names.cut, gen <= 2 and true or nil, version .. " verified cut coverage")
  T.eq(names.teleport, gen <= 3 and true or nil, version .. " verified teleport coverage")
  if list[1] then
    list[1].id = "MUTATED"
    T.check(world:availableFieldActions()[1].id ~= "MUTATED", version .. " action rows detached")
  end
  T.eq(world:useFieldAction("unknown"), nil, version .. " unknown action refused")
  T.eq(world:useFieldAction("surf", { sourceSlot = 1 }), nil, version .. " unsupported options refused")
  if gen <= 3 then
    T.eq(world:useFieldAction("surf"), true, version .. " native surf started")
    T.eq(calls[#calls].carrier, mon, version .. " surf uses validated carrier")
    T.eq(world:useFieldAction("surf"), nil, version .. " active dialogue prevents replay")
    game.stack:pop()
    ow.player.surfing = true
    T.eq(world:useFieldAction("surf"), nil, version .. " no invented dismount action")
    ow.player.surfing = false
    T.eq(world:useFieldAction("teleport"), true, version .. " native Teleport started")
    T.eq(calls[#calls].escape, nil, version .. " Teleport keeps heal-point semantics")
    ow.teleportOut = nil
    ow.map.def.tileset = "CAVERN"
    ow.map.def.environment = 4
    ow.map.def.allowEscaping = true
    T.eq(world:useFieldAction("dig"), true, version .. " native Dig started")
    T.eq(
      calls[#calls].escape,
      gen >= 2 and true or nil,
      version .. " Dig keeps generation-specific destination"
    )
    ow.teleportOut = nil
    if gen <= 2 then
      T.eq(world:useFieldAction("cut"), true, version .. " native Cut started")
      game.stack:pop()
    end
  else
    T.eq(world:useFieldAction("surf"), nil, version .. " unsupported script adapter is explicit")
    T.eq(#calls, 0, version .. " unsupported field dispatch has no effects")
  end
end

-- Deferred Gen 3 cut-ins own the request until completion; callbacks may be
-- invoked twice or outlive a replaced map/save, but effects must not replay.
local api, game, ow, calls = boot("emerald")
local world = api.world
local finish
Gen3Show.show = function(g, mon, done)
  finish = done
  g.stack:push({ isCutin = true })
  return true
end
T.eq(world:flyTo("DEST"), true, "cut-in queued")
T.eq(#calls, 0, "no departure before cut-in finishes")
T.eq(world:reorderParty(1, 2), nil, "cut-in blocks competing action")
game.stack:pop()
finish()
finish()
T.eq(#calls, 1, "cut-in completion departs once")
ow.flyAnim = nil
T.eq(world:flyTo("DEST"), true, "second independent request queued")
game.stack:pop()
game.save = Merge.deepCopy(game.save)
finish()
T.eq(#calls, 1, "save replacement cancels pending effect")
T.eq(world:canReorderParty(), true, "cancelled request releases its lock")
T.eq(world:flyTo("DEST"), true, "request can resume after cancellation")
game.stack:pop()
ow.map = { id = "OTHER", def = game.data.maps.HOME }
finish()
T.eq(#calls, 1, "map replacement cancels pending effect")
T.eq(world:canReorderParty(), true, "map cancellation releases lock")
T.eq(world:flyTo("DEST"), true, "abandoned presentation queued")
game.stack:pop() -- simulate native UI being dismissed without completion
T.eq(world:canReorderParty(), true, "abandoned cut-in does not leave a permanent API lock")
finish()
T.eq(#calls, 1, "abandoned callback cannot later run")
Gen3Show.show = function(g, mon, done)
  done()
  error("after completion")
end
local ok, err = pcall(function()
  world:flyTo("DEST")
end)
T.check(
  not ok and tostring(err):find("after completion", 1, true) ~= nil,
  "native presentation error is propagated"
)
T.eq(#calls, 2, "presentation failure never retries a completed departure")
Gen3Show.show = function()
  return false
end
ow.flyAnim = nil
-- Hooks cannot recursively start a second action or move the source unnoticed.
ow.partyKnows = function()
  T.eq(world:reorderParty(1, 2), nil, "nested mutation during eligibility is refused")
  return game.save.party[1]
end
T.eq(world:canFly(), true, "recursive capability probe terminates")
ow.partyKnows = function()
  ow.player.cellX = ow.player.cellX + 1
  return game.save.party[1]
end
T.eq(world:flyTo("DEST"), nil, "eligibility hook changing source position cancels action")
T.eq(#calls, 2, "changed source never reaches native handler")

local nestedApi, nestedGame, nestedWorld = boot("red")
nestedWorld.flyTo = function()
  T.eq(nestedApi.world:reorderParty(1, 2), nil, "native dispatch callback cannot reorder concurrently")
  T.eq(nestedApi.world:flyTo("DEST"), nil, "native dispatch callback cannot start a second flight")
  nestedWorld.flyAnim = {}
end
T.eq(nestedApi.world:flyTo("DEST"), true, "guarded native dispatch still starts once")
nestedWorld.flyAnim = nil
local nativeError = { native = true }
nestedWorld.flyTo = function()
  error(nativeError)
end
local okNative, errNative = pcall(function()
  nestedApi.world:flyTo("DEST")
end)
T.check(not okNative and errNative == nativeError, "native error identity retained")
T.eq(nestedApi.world:canReorderParty(), true, "throwing handler releases only the API dispatch lock")

local empty = WorldAPI.new(nil, "empty")
T.eq(empty:reorderParty(1, 2), nil, "missing game mutation safe")
T.eq(empty:canFly(), false, "missing game probe safe")
T.same(empty:availableFieldActions(), {}, "missing game has no field actions")
for _, name in ipairs({
  "canReorderParty",
  "reorderParty",
  "availableFieldActions",
  "useFieldAction",
  "canFly",
  "flyTo",
}) do
  T.check(Actions.supports(name), "action capability " .. name)
end
T.eq(Actions.supports("party"), false, "reader capability remains separate")
GameVersion.set(saved[1])
Runtime.install(saved[2], saved[3], saved[4])
love = saved[5]
Gen3Show.show = saved[6]
T.finish()
