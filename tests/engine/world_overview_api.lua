package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Map = require("src.world.Map")
local WorldAPI = require("src.world.WorldAPI")
local Encounter = require("src.world.Encounter")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local GameVersion = require("src.core.GameVersion")
local Assets = require("src.render.Assets")
local Loader = require("src.mods.Loader")
local Json = require("src.link.Json")
local savedVersion, savedHooks = GameVersion.get(), Runtime.hooks
local function copy(t, seen)
  if type(t) ~= "table" then
    return t
  end
  seen = seen or {}
  if seen[t] then
    return seen[t]
  end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do
    out[copy(k, seen)] = copy(v, seen)
  end
  return out
end
-- Exact reference/key/metatable freeze; cycles (Game -> world -> Game) are real.
local function freeze(root)
  local graph = {}
  local function walk(t)
    if type(t) ~= "table" or graph[t] then
      return
    end
    local keys = {}
    graph[t] = { keys = keys, mt = getmetatable(t) }
    for k, v in pairs(t) do
      keys[k] = v
      walk(k)
      walk(v)
    end
  end
  walk(root)
  return function(label)
    for t, before in pairs(graph) do
      T.eq(getmetatable(t), before.mt, label .. " metatable")
      for k, v in pairs(before.keys) do
        T.eq(rawget(t, k), v, label .. " value")
      end
      for k, v in pairs(t) do
        T.eq(before.keys[k], v, label .. " no new key")
      end
    end
  end
end
local function pack(...)
  local out = {}
  for _, n in ipairs({ ... }) do
    out[#out + 1] = string.char(n % 256, math.floor(n / 256))
  end
  return table.concat(out)
end
local function uniform(n)
  local out = {}
  for i = 1, 16 do
    out[i] = n
  end
  return out
end
local function scene(version)
  GameVersion.set(version)
  local gen = GameVersion.generation()
  local def = {
    id = "ACTIVE",
    width = 2,
    height = 2,
    borderBlock = 0,
    blocks = { 1, 2, 3, 4 },
    warps = { { x = 1, y = 1 }, { x = -1, y = 1 } },
    signs = {
      { x = 0, y = 1, item = "POTION", eventFlag = "FOUND" },
      {
        x = 1,
        y = 0,
        item = "POTION",
        eventFlag = "HIDDEN",
      },
    },
  }
  local ts = {
    blockCells = 2,
    blockTiles = 4,
    blocks = { uniform(0), uniform(0), uniform(1), uniform(2), uniform(3) },
    walkable = { 0, 2 },
    waterTiles = { 1 },
    shoreTiles = {},
    warpTiles = { 3 },
    image = "overview-test.png",
    tilesPerRow = 4,
  }
  if gen == 2 then
    ts.collision = { 255, 255, 255, 255, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3 }
  elseif gen >= 3 then
    def.blocks = pack(1 + 1024, 2 + 4096, 3, 4)
    def.collisionCells = { 0, 0, 1, 0 }
    def.elevationCells = gen == 3 and { 3, 1, 3, 3 } or nil
    ts.blockCells, ts.blockTiles, ts.blocks, ts.collision = 1, 2, nil, { 0, 0, 1, 2, 3 }
    ts.behaviourBytes = true
    ts.warpsAreEvents = true
    if gen >= 4 then
      def.generation = 4
      def.gen5 = gen == 5 or nil
      def.behaviorCells = string.char(0, gen == 5 and 0x3D or 0x10, 0, 0)
    end
  end
  local map = Map.new(def, ts)
  local ow = {
    isOverworld = true,
    map = map,
    npcs = {
      { def = { item = "POTION" }, cellX = 0, cellY = 0 },
      { def = { item = "POTION" }, cellX = 1, cellY = 0, hidden = true },
      { def = { item = "POTION", fruitTree = true }, cellX = 0, cellY = 1 },
      { def = { item = 0 }, cellX = 0, cellY = 1 },
      { def = { item = "POTION" }, cellX = 99, cellY = 99 },
    },
    tod = "NITE",
    player = { cellX = 0, cellY = 0 },
  }
  local game = {
    data = {
      maps = { ACTIVE = def },
      field = { hiddenItems = { ACTIVE = { { x = 0, y = 0 }, { x = 1, y = 1 } } } },
    },
    save = { flags = { HIDDEN = true }, hiddenTaken = { ACTIVE_1_1 = true } },
    overworld = ow,
    stack = { states = { ow, { isMenu = true } } },
  }
  ow.game = game
  return WorldAPI.new(game, "probe"), game, ow
end
local savedLoveRandom, savedMathRandom = love.math.random, math.random
local draws = 0
love.math.random = function()
  draws = draws + 1
  error("query consumed love RNG")
end
math.random = function()
  draws = draws + 1
  error("query consumed math RNG")
end
Runtime.hooks = Hooks.new()
local callbacks = 0
for _, name in ipairs({ "encounter.roll", "encounter.species" }) do
  Runtime.hooks:wrap(name, function()
    callbacks = callbacks + 1
    error("query executed encounter hook")
  end)
end
for _, version in ipairs({
  "red",
  "gold",
  "silver",
  "crystal",
  "emerald",
  "firered",
  "platinum",
  "heartgold",
  "black",
  "white",
}) do
  local api, game, ow = scene(version)
  for _, warm in ipairs({ false, true }) do
    if warm then
      ow.map:blockAt(0, 0)
    end
    local stable = freeze(game)
    local out = assert(api:mapOverview())
    stable(version .. " overview")
    T.eq(out.mapId, "ACTIVE", version .. " map ID")
    T.eq(out.width, ow.map.widthCells, version .. " width")
    T.eq(#out.rows, out.height, version .. " rows")
    -- Native classifiers on an independent map give the exact terrain contract.
    local native = Map.new(copy(ow.map.def), copy(ow.map.tileset))
    for y = 0, out.height - 1 do
      T.eq(#out.rows[y + 1], out.width, version .. " row width")
      for x = 0, out.width - 1 do
        local expected = native:isWarpTileCell(x, y) and "+"
          or native:isWaterCell(x, y) and "~"
          or native:isWalkableCell(x, y) and "."
          or " "
        T.eq(out.rows[y + 1]:sub(x + 1, x + 1), expected, version .. " native terrain")
      end
    end
    T.same(out.markers, {
      { kind = "warp", x = 1, y = 1 },
      { kind = "item", x = 0, y = 0 },
      { kind = "hidden", x = 0, y = 0 },
      {
        kind = "hidden",
        x = 0,
        y = 1,
      },
    }, version .. " only active markers")
    out.markers[1].x = 999
    out.rows[1] = "corrupted"
    T.eq(api:mapOverview().markers[1].x, 1, version .. " detached markers")
  end
  local old = assert(api:mapOverview())
  ow.npcs = {}
  game.save.flags.FOUND = true
  game.save.hiddenTaken.ACTIVE_0_0 = true
  T.eq(#api:mapOverview().markers, 1, version .. " live removals reflected")
  T.eq(#old.markers, 4, version .. " old snapshot remains detached")
  ow.map:setBlock(0, 0, 0, true)
  local stable = freeze(game)
  local patched = assert(api:mapOverview())
  stable(version .. " patched map")
  T.eq(patched.rows[1]:sub(1, 1), " ", version .. " live shut cell")
  if GameVersion.generation() >= 4 then
    ow.map.def.behaviorCells = nil
    local result, why = api:mapOverview()
    T.eq(result, nil, version .. " streamed raster refused")
    T.check(why:find("streamed", 1, true), version .. " streamed reason")
  end
end
-- Literal terrain reference: whitespace is an impassable cell, not a missing row.
do
  local api = scene("red")
  T.same(api:mapOverview().rows, { "..~~", "..~~", "..++", "..++" }, "GB literal terrain grid")
end
-- GB visuals use actual 8x8 pixel means/quadrants; no placeholder art on failure.
do
  local api, game, ow = scene("gold")
  local saved = love.image
  love.image = {}
  local reads = 0
  love.image.newImageData = function(path)
    reads = reads + 1
    T.eq(path, "overview-test.png", "resolved image path")
    return {
      getDimensions = function()
        return 32, 8
      end,
      getPixel = function(_, x, y)
        local shade = math.floor(x / 8)
        if shade == 2 then
          shade = (x % 8 < 4 and 0 or 3)
        end
        local v = 1 - shade / 3
        return v, v, v, 1
      end,
    }
  end
  Assets.invalidate()
  local stable = freeze(game)
  local out = assert(api:mapOverview())
  stable("visual pure")
  T.eq(out.tileRows[1], "00001111", "literal GB tile shades")
  T.eq(out.tileRows[5], "22223333", "literal averaged split tile")
  T.eq(out.tileDetailRows[9], "0303030333333333", "literal GB quadrants")
  T.eq(out.tileWidth, 8, "2x tile width")
  T.eq(out.tileDetailWidth, 16, "4x detail width")
  out.tileRows[1] = "broken"
  out.tileDetailRows[1] = "broken"
  T.eq(api:mapOverview().tileRows[1], "00001111", "detached visual rows")
  T.eq(reads, 1, "visual cache reused")
  Assets.invalidate()
  api:mapOverview()
  T.eq(reads, 2, "asset reload invalidates visual cache")
  love.image.newImageData = function()
    error("missing image")
  end
  Assets.invalidate()
  T.eq(api:mapOverview().tileRows, nil, "unavailable art is omitted")
  love.image = saved
  Assets.invalidate()
end
local function tableDef(rate, buckets, species)
  local slots = {}
  for i, id in ipairs(species or { "RATTATA", "PIDGEY", "RATTATA" }) do
    slots[i] = { species = id, min = 2, max = 7 }
  end
  return { rate = rate, buckets = buckets or { 51, 102, 256 }, slots = slots }
end
local function encounters(version)
  GameVersion.set(version)
  local a = tableDef(60)
  a.byTime = {
    morn = tableDef(80, nil, { "PIDGEY", "PIDGEY", "RATTATA" }),
    nite = tableDef(20, nil, { "HOOTHOOT", "RATTATA", "HOOTHOOT" }),
  }
  local maps = {
    A = { id = "A", label = "RouteA", encounters = GameVersion.generation() >= 4 and 7 or nil },
    B = {
      id = "B",
    },
  }
  local data = {
    maps = maps,
    encounters = {
      [maps.A.encounters or "A"] = {
        grass = a,
        water = tableDef(10, { 128, 256 }, { "MAGIKARP", "POLIWAG" }),
      },
    },
    field = {},
    pokemon = {
      RATTATA = { name = "Rattata" },
      PIDGEY = { name = "Pidgey" },
      HOOTHOOT = { name = "Hoothoot" },
      MAGIKARP = { name = "Magikarp" },
      POLIWAG = { name = "Poliwag" },
    },
  }
  local game = { data = data, save = { party = {}, flags = {} }, stack = { states = {} } }
  return WorldAPI.new(game, "probe"), game, a
end
local function nativeParity(api, game, opts)
  local hour = opts.daytime == "NITE" and 22 or opts.daytime == "MORNING" and 6 or 12
  local enc = Encounter.forMap(game.data, game.data.maps.A, "A", hour, game.save)
  local slots = Encounter.atTime(enc.grass, opts.daytime)
  local counts = {}
  Encounter.load(game.data)
  for pick = 0, (slots.bucketSpan or 256) - 1 do
    local n = 0
    local result = Encounter.chooseTable(slots, function(lo)
      n = n + 1
      if n == 1 then
        return pick
      end
      return lo
    end)
    if result then
      counts[tostring(result.species)] = (counts[tostring(result.species)] or 0) + 1
    end
  end
  local stable = freeze(game)
  local out = assert(api:effectiveEncounters("A", "grass", opts))
  stable("encounter graph")
  T.same(out.dist, counts, "native exhaustive bucket distribution")
  local passed = 0
  for gate = 0, (slots.rateMax or 256) - 1 do
    local n = 0
    local result = Encounter.rollTable(slots, function(lo)
      n = n + 1
      if n == 1 then
        return gate
      end
      return lo
    end)
    if result then
      passed = passed + 1
    end
  end
  T.eq(out.chance, passed / (slots.rateMax or 256), "native exhaustive rate gate")
  return out
end
for _, version in ipairs({ "red", "gold", "silver", "crystal", "emerald", "firered" }) do
  local api, game = encounters(version)
  for _, period in ipairs({ "MORNING", "DAY", "NITE" }) do
    nativeParity(api, game, { daytime = period })
  end
  local out = api:effectiveEncounters("A", "grass", { daytime = "DAY" })
  T.same(out.dist, { RATTATA = 205, PIDGEY = 51 }, version .. " duplicate species aggregated")
  out.dist.RATTATA = 0
  T.eq(api:effectiveEncounters("A", "grass", { daytime = "DAY" }).dist.RATTATA, 205, "distribution detached")
  T.same(
    api:effectiveEncounters("A", "indoor", { daytime = "NITE" }),
    api:effectiveEncounters("A", "grass", { daytime = "NITE" }),
    "indoor grass alias"
  )
  T.same(
    api:effectiveEncounters("A", "water", { daytime = "NITE" }).dist,
    { MAGIKARP = 128, POLIWAG = 128 },
    "water table"
  )
  T.same(api:effectiveEncounters("B", "grass"), { chance = 0, dist = {} }, "known map with no encounters")
  T.eq(api:effectiveEncounters("missing", "grass"), nil, "unknown map refused")
  for _, bad in ipairs({ "fishing", "darkGrass", false }) do
    T.eq(api:effectiveEncounters("A", bad), nil, "terrain refused")
  end
  T.eq(api:effectiveEncounters("A", "grass", "NITE"), nil, "options must be table")
  T.eq(api:effectiveEncounters("A", "grass", { daytime = "dusk" }), nil, "invalid time refused")
  T.same(
    api:effectiveEncounters("A", "grass", { daytime = "night" }),
    api:effectiveEncounters("A", "grass", { daytime = "NITE" }),
    "time aliases"
  )
  game.data.encounters = nil
  T.eq(api:effectiveEncounters("A", "grass"), nil, "unloaded data refused")
end
-- Gen2 outbreaks use the same native map selection for all three cartridges.
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local api, game = encounters(version)
  game.data.field.gen2Swarms = {
    maps = { RouteA = { grass = tableDef(200, nil, { "HOOTHOOT", "HOOTHOOT", "HOOTHOOT" }) } },
    flags = { [0] = 17 },
  }
  game.save.g2Swarm = { kind = 0, map = "A" }
  if version == "crystal" then
    game.save.flags[require("src.script.Gen2Flags").scriptFlag(17)] = true
  end
  nativeParity(api, game, { daytime = "DAY" })
  T.same(
    api:effectiveEncounters("A", "grass", { daytime = "DAY" }).dist,
    { HOOTHOOT = 256 },
    version .. " outbreak table"
  )
  game.save.g2Swarm = nil
  T.eq(
    api:effectiveEncounters("A", "grass", { daytime = "DAY" }).dist.RATTATA,
    205,
    "outbreak ends immediately"
  )
end
-- DS rates/bucket spans, time substitutions, daily replacements and seasons.
for _, version in ipairs({ "platinum", "heartgold", "black", "white" }) do
  local api, game = encounters(version)
  local slots = {}
  for i, chance in ipairs({ 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }) do
    slots[i] = { species = i % 2 == 0 and "PIDGEY" or "RATTATA", level = 5, chance = chance }
  end
  local raw = {
    grassRate = 30,
    grass = slots,
    surf = {
      rate = 20,
      slots = { { species = "MAGIKARP", level = 5, chance = 100 } },
    },
  }
  game.data.encounters[7] = raw
  if version == "black" or version == "white" then
    raw.family = "bw"
    raw.seasons =
      { winter = { grassRate = 50, grass = { { species = "HOOTHOOT", level = 5, chance = 100 } } } }
    game.save.gen5Season = 3
  end
  for _, period in ipairs({ "MORNING", "DAY", "NITE" }) do
    nativeParity(api, game, { daytime = period })
  end
  if raw.family == "bw" then
    T.same(api:effectiveEncounters("A", "grass").dist, { HOOTHOOT = 100 }, "BW current season")
    game.save.gen5Season = 0
    T.eq(api:effectiveEncounters("A", "grass").chance, 0.3, "BW season changes immediately")
  end
end
-- Cold DS resolver views: timed slots and daily replacements are reflected
-- without initializing save state or exposing mutable source slot records.
for _, version in ipairs({ "platinum", "heartgold" }) do
  local api, game = encounters(version)
  local slots = {}
  for i, chance in ipairs({ 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }) do
    slots[i] = { species = "RATTATA", level = 5, chance = chance }
  end
  local raw = { grassRate = 30, grass = slots, day = { 25, 25 }, night = { 163, 163 }, swarm = { 129, 129 } }
  if version == "heartgold" then
    raw.timed = { day = {}, night = {} }
    for i = 1, 12 do
      raw.timed.day[i] = 25
      raw.timed.night[i] = 163
    end
  end
  game.data.pokemon[25] = { name = "Pikachu" }
  game.data.pokemon[163] = { name = "Hoothoot" }
  game.data.pokemon[129] = { name = "Magikarp" }
  game.data.encounters[7] = raw
  local stable = freeze(game)
  local day = assert(api:effectiveEncounters("A", "grass", { daytime = "DAY" }))
  local night = assert(api:effectiveEncounters("A", "grass", { daytime = "NITE" }))
  T.eq(day.dist.PIKACHU, version == "heartgold" and 100 or 20, "DS time species day")
  T.eq(night.dist.HOOTHOOT, version == "heartgold" and 100 or 20, "DS time species night")
  stable("cold DS timed query")
  local Swarms = require("src.world.Gen4Swarms")
  game.data.maps.A.header = Swarms.HEADERS[1]
  game.save.gen4Swarm = { enabled = true, daily = 0, rand = 123 }
  stable = freeze(game)
  local outbreak = assert(api:effectiveEncounters("A", "grass", { daytime = "DAY" }))
  T.eq(outbreak.dist.MAGIKARP, 40, "DS daily swarm slots")
  stable("DS daily swarm read")
  outbreak.dist.MAGIKARP = 0
  T.eq(
    api:effectiveEncounters("A", "grass", { daytime = "DAY" }).dist.MAGIKARP,
    40,
    "DS distribution detached"
  )
  game.save.gen4Swarm.enabled = false
  if version == "platinum" then
    game.data.maps.A.header = 287
    game.save.pokedex = { national = true }
    game.save.gen4TrophyGarden = { slot1 = 0, slot2 = 1 }
    game.data.gen4_special_encounters = { trophyGarden = { 25, 163 } }
    stable = freeze(game)
    local garden = assert(api:effectiveEncounters("A", "grass", { daytime = "MORNING" }))
    T.eq(garden.dist.PIKACHU, 5, "garden first daily slot")
    T.eq(garden.dist.HOOTHOOT, 5, "garden second daily slot")
    stable("DS garden read")
  end
end
-- A water table is not time-swapped by the native step path.
do
  local api, game = encounters("gold")
  game.data.encounters.A.water.byTime = { nite = tableDef(255, { 256 }, { "HOOTHOOT" }) }
  T.same(
    api:effectiveEncounters("A", "water", { daytime = "NITE" }).dist,
    { MAGIKARP = 128, POLIWAG = 128 },
    "water ignores land time selector"
  )
end
-- Numeric IDs follow the shared public name contract, including loader aliases.
do
  local api, game = encounters("platinum")
  game.data.pokemon[25] = { id = 25, name = "Pikachu" }
  game.data.encounters[7] = { grass = tableDef(50, { 256 }, { 25 }) }
  T.same(api:effectiveEncounters("A", "grass").dist, { PIKACHU = 256 }, "numeric species -> portable ID")
end
-- Default Gen2 period follows the clock, and queries never run world.tod hooks.
do
  local api, game = encounters("gold")
  local date = os.date
  os.date = function(format)
    if format == "%H" then
      return "23"
    end
    return date(format)
  end
  T.same(
    api:effectiveEncounters("A", "grass"),
    api:effectiveEncounters("A", "grass", { daytime = "NITE" }),
    "live Gen2 clock"
  )
  Runtime.hooks:wrap("world.tod", function()
    callbacks = callbacks + 1
  end)
  game.overworld = { isOverworld = true, map = { id = "A" }, tod = "MORNING" }
  game.stack.states = { game.overworld }
  T.same(
    api:effectiveEncounters("A", "grass"),
    api:effectiveEncounters("A", "grass", { daytime = "MORNING" }),
    "cached effective mod period"
  )
  os.date = date
end
-- Malformed tables and exceptional positional tables fail explicitly.
do
  local api, game, a = encounters("red")
  for _, bad in ipairs({ 0, -1, math.huge, 0 / 0 }) do
    a.rateMax = bad
    T.eq(api:effectiveEncounters("A", "grass"), nil, "invalid denominator")
  end
  a.rateMax = nil
  a.buckets = { 51, 50, 256 }
  T.eq(api:effectiveEncounters("A", "grass"), nil, "descending buckets refused")
  a.buckets = { 51, 102, 257 }
  T.eq(api:effectiveEncounters("A", "grass"), nil, "unreachable bucket refused")
  a.buckets = "bad"
  T.eq(api:effectiveEncounters("A", "grass"), nil, "invalid bucket type refused")
  a.buckets = { 51, 102, 256 }
  local originalSlots = a.slots
  a.slots = "bad"
  T.eq(api:effectiveEncounters("A", "grass"), nil, "invalid slot type refused")
  a.slots = originalSlots
  a.buckets = { 51, 102, 256 }
  a.rate = 0
  T.same(api:effectiveEncounters("A", "grass"), { chance = 0, dist = {} }, "zero rate")
  a.rate = 999
  T.eq(api:effectiveEncounters("A", "grass").chance, 1, "saturated rate")
  GameVersion.set("heartgold")
  local S = require("src.world.HgssSafariZone")
  game.data.maps.A.layout = S.LAYOUT
  game.data.maps.A.cameraFamily = "hgss"
  local stable = freeze(game)
  T.eq(api:effectiveEncounters("A", "grass"), nil, "Safari query refused")
  stable("Safari does not seed save")
  GameVersion.set("emerald")
  for _, id in ipairs({
    require("src.script.Gen3BattlePike").WILD_ROOM,
    require("src.script.Gen3BattlePyramid").FLOOR,
  }) do
    game.data.maps[id] = { id = id }
    T.eq(api:effectiveEncounters(id, "grass"), nil, "facility query refused")
  end
end
-- API1/2 native mod loading, lazy capability queries and live table patches.
for _, apiVersion in ipairs({ 1, 2 }) do
  GameVersion.set("gold")
  local data = T.fixtures.fresh()
  local files = {
    ["mods/probe/manifest.json"] = Json.encode({
      id = "probe",
      name = "Probe",
      version = "1.0.0",
      api = apiVersion,
      entry = "main.lua",
      content_format = os.getenv("WORLD_OVERVIEW_ALL_FORMATS") == "1" and apiVersion == 2 and "unified"
        or nil,
      callback_format = os.getenv("WORLD_OVERVIEW_ALL_FORMATS") == "1" and apiVersion == 2 and "unified"
        or nil,
      script_format = os.getenv("WORLD_OVERVIEW_ALL_FORMATS") == "1" and apiVersion == 2 and "unified" or nil,
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
      elseif files[p] then
        return { type = "file" }
      end
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false })
  local resolves = 0
  loader._game = function(self)
    resolves = resolves + 1
    return self.game
  end
  T.check(loader:load(data), "real loader succeeds")
  local mod = loader.apis.probe
  if os.getenv("WORLD_OVERVIEW_ALL_FORMATS") == "1" and apiVersion == 2 then
    T.eq(mod.contentFormat, "unified", "unified content facade")
    T.eq(mod.callbackFormat, "unified", "unified callback facade")
    T.eq(mod.scriptFormat, "unified", "portable script facade")
  end
  T.eq(resolves, 0, "entry and ID context stay lazy")
  if mod.supports then
    T.eq(mod:supports("world", "mapOverview"), true, "overview capability")
    T.eq(mod:supports("world", "effectiveEncounters"), true, "encounter capability")
    T.eq(resolves, 0, "capability query stays lazy")
  end
  loader.game = { data = data, save = {}, stack = { states = {} } }
  local world = mod.world
  T.eq(world:mapOverview(), nil, "title screen overview is quiet")
  local out = assert(world:effectiveEncounters("FIX_ROUTE", "grass"))
  T.check(next(out.dist) ~= nil, "query available at title screen")
  local before = out.chance
  local id = next(out.dist)
  data.pokemon[id].name = "Renamed presentation"
  T.check(
    world:effectiveEncounters("FIX_ROUTE", "grass").dist[id] ~= nil,
    "public identity survives name patch"
  )
  data.encounters.FIX_ROUTE.grass.rate = 100
  T.check(world:effectiveEncounters("FIX_ROUTE", "grass").chance ~= before, "live data patch reflected")
end
T.eq(draws, 0, "all queries consume zero RNG draws")
T.eq(callbacks, 0, "all queries execute zero hook callbacks")
love.math.random, math.random = savedLoveRandom, savedMathRandom
Runtime.hooks = savedHooks
GameVersion.set(savedVersion)
T.finish("world overview and encounter API")
