-- ROM-free tests through the real loader and real runtime Map objects.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Loader = require("src.mods.Loader")
local WorldAPI = require("src.world.WorldAPI")
local Map = require("src.world.Map")
local MapLoader = require("src.world.MapLoader")
local Merge = require("src.mods.Merge")
local Runtime = require("src.mods.Runtime")
local GameVersion = require("src.core.GameVersion")
local Json = require("src.link.Json")
local Reads = require("src.mods.WorldReads")
local savedLove, savedVersion = love, GameVersion.get()
local savedEvents, savedHooks, savedErrors = Runtime.events, Runtime.hooks, Runtime.errors
love = nil
local function pack16(...)
  local out = {}
  for _, v in ipairs({ ... }) do
    out[#out + 1] = string.char(v % 256, math.floor(v / 256))
  end
  return table.concat(out)
end
local function map(id, cells, packed, ds)
  return Map.new({
    id = id,
    width = 3,
    height = 2,
    blocks = packed and pack16(0, 1 + 3 * 1024, 2 + 9 * 4096, 3, 4, 1023) or { 0, 1, 2, 3, 4, 1023 },
    borderBlock = 999,
    generation = ds and 4 or nil,
  }, { blockCells = cells, blockTiles = cells * 2, walkable = {}, blocks = {} })
end
local function boot(version, entry)
  GameVersion.set(version)
  local gen = GameVersion.generation()
  local s, m, item = gen >= 4 and 25 or "PIKACHU", gen >= 4 and 33 or "TACKLE", gen >= 4 and 13 or "POTION"
  local species = { id = s, name = "Pikachu" }
  local move = { id = m, name = "Tackle", pp = 35 }
  local data = {
    pokemon = { [s] = species },
    moves = { [m] = move },
    items = {
      [item] = { id = item, name = "Potion" },
    },
  }
  if gen >= 4 then
    data.pokemon.SPECIES_25 = species
    data.moves.MOVE_33 = move
  end
  local mon = {
    species = s,
    item = item,
    nickname = "Buddy",
    name = "native name",
    level = 7,
    hp = 19,
    status = "PSN",
    stats = { hp = 23, attack = 10, defense = 11, speed = 12, special = 13 },
    moves = { { id = m, pp = 29, ppUps = 1, hidden = false } },
    ivs = { hp = 27 },
    evs = { speed = 3 },
    personality = 12345,
    extension = { flag = false },
    isEgg = false,
  }
  if gen > 1 then
    mon.stats.spatk = 13
    mon.stats.spdef = 14
  end
  local active = map("ACTIVE", gen <= 2 and 2 or 1, gen >= 3, gen >= 4)
  local neighbor = map("NORTH", gen <= 2 and 2 or 1, gen >= 3, gen >= 4)
  local ow = { isOverworld = true, map = active, neighbors = { { map = neighbor, cx = -2, cy = -4 } } }
  local game = {
    data = data,
    save = { party = { mon }, money = 500 },
    stack = { states = { ow, { isMenu = true } } },
    overworld = ow,
  }
  local files = {
    ["mods/probe/manifest.json"] = Json.encode({
      id = "probe",
      name = "Probe",
      version = "1.0.0",
      api = 2,
      entry = "main.lua",
    }),
    ["mods/probe/main.lua"] = entry or "return function(mod) mod.exports.api=mod end",
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
  local resolves = 0
  loader._game = function()
    resolves = resolves + 1
    return game
  end
  assert(loader:load(data), table.concat(loader.errors, "; "))
  local api = assert(loader.apis.probe)
  return api, loader, game, ow, { s, m, item }, function()
    return resolves
  end
end

-- Fail if any reader tries to load a map, generate a Pokemon or use RNG.
local oldMapLoad = MapLoader.load
local Pokemon = require("src.pokemon.Pokemon")
local oldNew = Pokemon.new
local oldRandom = math.random
local function forbidden()
  error("read crossed into gameplay")
end
MapLoader.load, Pokemon.new, math.random = forbidden, forbidden, forbidden

for _, version in ipairs(GameVersion.ORDER) do
  local api, loader, game, ow, ids, resolves = boot(version)
  local label = version .. ": "
  T.eq(resolves(), 0, label .. "entry and read metadata do not instantiate Game")
  if api.supports then
    for _, name in ipairs({ "party", "liveMaps", "activeBlockAt" }) do
      T.eq(api:supports("world", name), true, label .. "capability " .. name)
    end
    T.eq(resolves(), 0, label .. "capability probes do not instantiate Game")
  end
  local before = Merge.deepCopy(game)
  local world = api.world
  T.eq(api.world, world, label .. "same cached facade")
  local party = world:party()
  local mon = party[1]
  T.eq(mon.species, "PIKACHU", label .. "symbolic species")
  T.eq(mon.item, "POTION", label .. "symbolic item")
  T.eq(mon.moves[1].id, "TACKLE", label .. "symbolic move")
  T.eq(mon.moves[1].pp, 29, label .. "current PP")
  T.eq(mon.moves[1].maxPp, 42, label .. "PP Ups use native rounding")
  T.eq(mon.moves[1].ppUps, 1, label .. "PP Ups exposed")
  T.eq(mon.maxHp, 23, label .. "max HP from stats.hp")
  T.eq(mon.stats.specialAttack, 13, label .. "special attack")
  T.eq(mon.stats.specialDefense, GameVersion.generation() == 1 and 13 or 14, label .. "special defense")
  T.eq(mon.status, "poison", label .. "status normalized")
  T.eq(mon.isEgg, false, label .. "false flags preserved")
  T.eq(mon.native.extension.flag, false, label .. "native false extension preserved")
  T.eq(mon.native.ivs.hp, 27, label .. "native IV diagnostics")
  T.eq(getmetatable(mon), nil, label .. "plain detached mon")
  mon.species = "OTHER"
  mon.stats.hp = 1
  mon.moves[1].pp = 0
  mon.native.ivs.hp = 0
  party[2] = { species = "INJECTED" }
  T.same(game, before, label .. "party mutations do not reach game")
  local nextParty = world:party()
  T.eq(nextParty[1].stats.hp, 23, label .. "fresh nested stat snapshot")
  T.eq(nextParty[1].moves[1].pp, 29, label .. "fresh move snapshot")
  T.eq(#nextParty, 1, label .. "party membership detached")
  game.save.party[1].hp = 18
  T.eq(world:party()[1].hp, 18, label .. "reads current native HP")
  game.save = { party = { { species = ids[1], hp = 1, stats = { hp = 2 }, moves = {} } } }
  T.eq(world:party()[1].hp, 1, label .. "held facade follows a replaced save")
  game.save = before.save

  local cells = ow.map.blockCells
  before = Merge.deepCopy(game)
  local id, metadata = world:activeBlockAt("ACTIVE", 0, 0)
  T.eq(id, 0, label .. "block zero is present")
  T.eq(metadata.tileSize, cells * 16, label .. "block pixel size from runtime map")
  T.eq(metadata.cellSize, 16, label .. "walk-cell pixel size")
  T.eq(metadata.coordinateBase, 0, label .. "zero-based block coordinates")
  T.eq(metadata.width, 3, label .. "block width")
  T.eq(metadata.height, 2, label .. "block height")
  local gen = GameVersion.generation()
  T.eq(
    metadata.kind,
    gen >= 4 and "runtime_cell" or gen >= 3 and "metatile" or "block",
    label .. "honest block kind"
  )
  T.eq(world:activeBlockAt("ACTIVE", 1, 0), 1, label .. "packed collision bits stripped")
  T.eq(world:activeBlockAt("ACTIVE", 2, 0), 2, label .. "packed elevation bits stripped")
  T.eq(world:activeBlockAt("ACTIVE", 2, 1), 1023, label .. "last block / full 10-bit ID")
  T.eq(ow.map.def._blockArray, nil, label .. "cold packed grid remains undecoded")
  metadata.width = 999
  T.eq(select(2, world:activeBlockAt("ACTIVE", 0, 0)).width, 3, label .. "metadata detached")
  for _, xy in ipairs({
    { -1, 0 },
    { 0, -1 },
    { 3, 0 },
    { 0, 2 },
    { 0.5, 0 },
    { 0, 0.5 },
    { math.huge, 0 },
    {
      0,
      0 / 0,
    },
    {
      "1",
      0,
    },
  }) do
    local value, reason = world:activeBlockAt("ACTIVE", xy[1], xy[2])
    T.check(value == nil and type(reason) == "string", label .. "invalid/off-map coordinates rejected")
  end
  local missing, reason = world:activeBlockAt("NORTH", 0, 0)
  T.check(missing == nil and reason == "map is not active", label .. "stale map rejected")
  T.same(game, before, label .. "block reads do not alter world or decoder cache")
  ow.map:setBlock(1, 0, 0)
  local patched = Merge.deepCopy(game)
  T.eq(world:activeBlockAt("ACTIVE", 1, 0), 0, label .. "live zero-valued block patch wins")
  T.same(game, patched, label .. "patch read remains pure")
  ow.map.blockPatch[2] = 777
  T.eq(world:activeBlockAt("ACTIVE", 1, 0), 777, label .. "reads current runtime patch")
  local oldMap = ow.map
  ow.map = ow.neighbors[1].map
  T.eq(world:activeBlockAt("ACTIVE", 0, 0), nil, label .. "held facade rejects map after warp")
  T.eq(world:activeBlockAt("NORTH", 0, 0), 0, label .. "held facade reads new active map")
  ow.map = oldMap

  before = Merge.deepCopy(game)
  local legacy = world:loadedMaps()
  local maps = world:liveMaps()
  T.eq(#maps, 2, label .. "only loaded maps returned")
  T.eq(maps[1].mapId, "ACTIVE", label .. "active first")
  T.eq(maps[1].active, true, label .. "active tagged")
  T.eq(maps[1].width, 3 * cells, label .. "map dimensions in cells")
  T.eq(maps[2].mapId, "NORTH", label .. "loaded neighbor included")
  T.eq(maps[2].x, -2, label .. "neighbor x offset in cells")
  T.eq(maps[2].y, -4, label .. "neighbor y offset in cells")
  T.eq(maps[2].block.tileSize, cells * 16, label .. "per-map block units")
  maps[1].mapId = "MUTATED"
  maps[2].block.width = 9
  maps[2].x = 123
  T.same(game, before, label .. "live map snapshots detached")
  T.same(world:loadedMaps(), legacy, label .. "legacy loadedMaps shape unchanged")
  T.eq(world:liveMaps()[2].x, -2, label .. "fresh map snapshots")

  game.stack.states = {}
  game.overworld = nil
  T.eq(world:activeBlockAt("ACTIVE", 0, 0), nil, label .. "no active world block result")
  T.eq(select(2, world:activeBlockAt("ACTIVE", 0, 0)), "no overworld", label .. "no world reason")
  T.eq(world:liveMaps(), nil, label .. "no active world maps result")
  T.check(world:party() ~= nil, label .. "party available without world")
  game.save = nil
  T.eq(world:party(), nil, label .. "no save party result")
  T.eq(select(2, world:party()), "no save", label .. "no save reason")
end

MapLoader.load, Pokemon.new, math.random = oldMapLoad, oldNew, oldRandom
-- Trap LÖVE's RNG too when the host provides one; queries remain ordinary
-- data reads in a host with no graphics/filesystem surface.
love = { math = { random = forbidden } }
local rngApi = WorldAPI.new(
  { data = {}, save = { party = {} }, overworld = { isOverworld = true, map = map("RNG", 1, true, false) } },
  "rng"
)
T.check(rngApi:party() ~= nil, "party never calls love.math.random")
T.eq(rngApi:activeBlockAt("RNG", 0, 0), 0, "block never calls love.math.random")
T.eq(#rngApi:liveMaps(), 1, "map list never calls love.math.random")
love = nil
-- Direct engine construction also produces symbolic records without a loader.
local data = {
  pokemon = { [999] = { name = "Mr. Mime" } },
  moves = { [888] = { name = "Ember", pp = 25 } },
  items = {
    [777] = { name = "Potion" },
  },
}
local raw = {
  species = 999,
  item = 777,
  hp = 3,
  stats = { hp = 9 },
  moves = { { id = 888, pp = 5 } },
  extension = {
    flag = false,
  },
}
local direct = WorldAPI.new({ data = data, save = { party = { raw } } }, "direct")
local before = Merge.deepCopy(data)
local p = direct:party()
T.eq(p[1].species, "MR_MIME", "standalone numeric species resolves by imported name")
T.eq(p[1].moves[1].id, "EMBER", "standalone numeric move resolves")
T.eq(p[1].native.extension.flag, false, "standalone false diagnostics retained")
T.same(data, before, "standalone resolver does not mutate data")
raw.self = raw
raw.callback = function() end
raw[{}] = { hidden = true }
local cyclic = direct:party()[1]
T.eq(cyclic.native.self, cyclic.native, "cyclic diagnostics detached consistently")
T.eq(cyclic.native.callback, nil, "diagnostics do not expose functions")
local tableKey = false
for k in pairs(cyclic.native) do
  if type(k) == "table" then
    tableKey = true
  end
end
T.eq(tableKey, false, "diagnostics do not retain native table keys")
raw.self = nil
raw.callback = nil

-- Metadata comes from the actual tileset even when its size is unusual.
local mixed = map("MIXED", 3, false, false)
local mixedApi = WorldAPI.new({ overworld = { isOverworld = true, map = mixed } }, "mixed")
T.eq(
  select(2, mixedApi:activeBlockAt("MIXED", 0, 0)).tileSize,
  48,
  "custom block size is not inferred from generation"
)
local missingMap = map("SHORT", 1, true, false)
missingMap.def.blocks = "\1"
local shortApi = WorldAPI.new({ overworld = { isOverworld = true, map = missingMap } }, "short")
T.eq(shortApi:activeBlockAt("SHORT", 0, 0), nil, "truncated packed block refused")
missingMap.def.blocks = {}
T.eq(shortApi:activeBlockAt("SHORT", 0, 0), nil, "missing array cell refused")
missingMap.def.blocks = { -1 }
T.eq(shortApi:activeBlockAt("SHORT", 0, 0), nil, "negative block ID refused")
missingMap.def.blocks = pack16(1)
missingMap.def._blockArray = { 7 }
T.eq(shortApi:activeBlockAt("SHORT", 0, 0), 7, "warm decoder cache matches Map:blockAt")
local cache = missingMap.def._blockArray
T.eq(cache[1], 7, "warm cache unmodified")
missingMap.blockTiles = 3
T.eq(shortApi:activeBlockAt("SHORT", 0, 0), nil, "inconsistent runtime geometry refused")
local placements = { isOverworld = true, map = map("HOME", 1, false, false) }
local repeated = map("NORTH", 1, false, false)
placements.neighbors = {
  { map = repeated, cx = 0, cy = -2 },
  { map = repeated, cx = 0, cy = -2 },
  { map = repeated, cx = 3, cy = 0 },
  { map = placements.map, cx = 0, cy = 0 },
  { map = map("OTHER", 2, false, false), cx = -4, cy = 0 },
}
local list = WorldAPI.new({ overworld = placements }, "placements"):liveMaps()
T.eq(#list, 4, "duplicate placements collapse, different placements of the same map remain")
T.eq(list[2].mapId, list[3].mapId, "two placements share map identity")
T.eq(list[3].x, 3, "second placement offset preserved")
T.eq(list[4].block.tileSize, 32, "mixed-neighborhood block sizes describe each map")
T.eq(list[4].width, 6, "mixed-neighborhood width remains in walk cells")
local empty = WorldAPI.new(nil, "empty")
T.eq(empty:party(), nil, "no Game party read safe")
T.eq(empty:liveMaps(), nil, "no Game map read safe")
T.eq(empty:activeBlockAt("MAP", 0, 0), nil, "no Game block read safe")

-- IDs stay bound to pre-merge identity despite presentation patches and
-- registrations made after the API/context was constructed.
local api, loader, game = boot(
  "platinum",
  [[return function(mod)
  mod.exports.api=mod
  mod.content.pokemon:patch("SPECIES_25",{name="A localized display name"})
  mod.content.pokemon:register("CUSTOMMON",{
    id="CUSTOMMON",dex=999,name="Another display name",types={"NORMAL"},
    catchRate=45,baseExp=64,level1Moves={},growthRate="MEDIUM_FAST",
    learnset={},evolutions={},spriteFront="front.png",spriteBack="back.png",frontSize=5,
    baseStats={hp=40,attack=40,defense=40,speed=40,special=40},
  })
end]]
)
game.save.party[1].species = "SPECIES_25"
game.save.party[2] = { species = "CUSTOMMON", level = 1, stats = {}, moves = {} }
T.eq(api.world:party()[1].species, "PIKACHU", "patched alias keeps canonical pre-merge ID")
T.eq(api.world:party()[2].species, "CUSTOMMON", "late mod registration uses its authored ID")
local emptyParty = game.save.party
game.save.party = {}
T.same(api.world:party(), {}, "empty saved party returns an empty snapshot")
game.save.party = emptyParty
game.save.party[1].item = 0
game.save.party[1].status = nil
game.save.party[1].isEgg = true
T.eq(api.world:party()[1].item, nil, "no-item native sentinel is absent")
T.eq(api.world:party()[1].status, nil, "healthy status is absent")
T.eq(api.world:party()[1].isEgg, true, "egg flag exposed")
-- Optional integration gate against #92's actual event record encoder.
if pcall(require, "src.mods.UnifiedCallbacks") then
  local Unified = require("src.mods.UnifiedCallbacks")
  Unified.install(loader, api, "probe", 4)
  local eventMon
  api.events:on("pokemon.received", function(event)
    eventMon = event.mon
  end)
  loader.events:emit("pokemon.received", { mon = game.save.party[1] })
  T.same(api.world:party()[1], eventMon, "party/event live record shapes match exactly")
end

-- Verify both normal RNG streams independently, without relying only on the
-- tripwire above. Lua's sequence must remain unchanged by the real readers.
math.randomseed(24680)
local expected = { math.random(), math.random(), math.random() }
math.randomseed(24680)
api.world:party()
api.world:activeBlockAt("ACTIVE", 1, 0)
api.world:liveMaps()
T.same({ math.random(), math.random(), math.random() }, expected, "reader calls leave RNG sequence unchanged")
for _, name in ipairs({ "party", "activeBlockAt", "liveMaps" }) do
  T.check(Reads.supports(name), "new capability " .. name)
end
T.check(not Reads.supports("flyTo") and not Reads.supports({}), "reader capability list stays narrow")

GameVersion.set(savedVersion)
Runtime.install(savedEvents, savedHooks, savedErrors)
love = savedLove
T.finish()
