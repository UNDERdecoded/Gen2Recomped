local M = {}
function M.new(root, backend, version, api, format, noMod, failing)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  assert(Version.VERSIONS[version], "unsupported native version: " .. tostring(version))
  Version.set(version)
  local gen = Version.generation()
  local data
  if backend == "gen1" and gen == 3 then
    data = T.sdk.gen3Data()
  else
    data = {
      pokemon = {},
      moves = {},
      items = {},
      maps = {},
      encounters = {},
      trainers = {},
      audio = {},
      type_chart = { types = { NORMAL = {} }, matchups = {} },
    }
    for _, id in ipairs({ "MEW", "PIDGEY", "CHARMANDER" }) do
      local stats = { hp = 40, attack = 40, defense = 40, speed = 40, special = 40 }
      local mon = {
        id = id,
        name = id,
        dex = id == "MEW" and 151 or id == "PIDGEY" and 16 or 4,
        baseStats = stats,
        types = { "NORMAL" },
        catchRate = 45,
        baseExp = 64,
        growthRate = "MEDIUM_FAST",
        spriteFront = "fixture.png",
        spriteBack = "fixture.png",
        frontSize = 5,
        level1Moves = { "POUND" },
        learnset = {},
        evolutions = {},
      }
      if gen > 1 then
        stats.spatk, stats.spdef = 40, 40
      end
      if backend == "gen1" and gen == 2 then
        stats.special, stats.spatk, stats.spdef = nil, nil, nil
        stats.specialAttack, stats.specialDefense = 40, 40
        mon.level1Moves, mon.learnset, mon.frontSize = nil, nil, nil
        mon.levelMoves, mon.picSize = { { level = 1, move = "POUND" } }, 5
      end
      data.pokemon[id] = mon
    end
    if backend == "gen1" and gen == 2 then
      data.pokemon.growthRates =
        { MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
    end
    data.moves.POUND = {
      id = "POUND",
      name = "POUND",
      type = "NORMAL",
      power = 40,
      accuracy = 100,
      pp = 35,
      effect = backend == "gen1" and gen == 2 and "EFFECT_NORMAL_HIT" or "NO_ADDITIONAL_EFFECT",
    }
  end
  data.maps.PROBE, data.maps.EMPTY =
    { id = "PROBE", width = 2, height = 2 }, { id = "EMPTY", width = 2, height = 2 }
  local grassWeights = gen == 1 and { 51, 51, 39, 25, 25, 25, 13, 13, 9, 5 }
    or gen == 2 and { 30, 30, 20, 10, 5, 4, 1 }
    or { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
  local waterWeights = gen == 1 and grassWeights or gen == 2 and { 60, 30, 10 } or { 60, 30, 5, 4, 1 }
  local function tableFor(weights, night)
    local slots, buckets, total = {}, {}, 0
    for i, weight in ipairs(weights) do
      local species = i % 2 == 0 and "CHARMANDER" or "PIDGEY"
      if night then
        species = "MEW"
      end
      slots[i] = { species = species, level = 5, minLevel = 5, maxLevel = 5 }
      if backend == "gen1" and gen == 3 then
        slots[i].species = species == "PIDGEY" and 16 or species == "CHARMANDER" and 4 or 151
      end
      total = total + weight
      buckets[i] = total
    end
    return {
      rate = 20,
      slots = slots,
      buckets = buckets,
      bucketSpan = total,
      rateMax = gen == 3 and 180 or 256,
    }
  end
  local land, water, night = tableFor(grassWeights), tableFor(waterWeights), tableFor(grassWeights, true)
  if backend == "gen1" and gen == 2 then
    data.gen2Maps = data.maps
    data.encounters = {
      grass = {
        PROBE = {
          rates = { MORN = 20, DAY = 20, NITE = 40 },
          slots = { MORN = land.slots, DAY = land.slots, NITE = night.slots },
        },
      },
      water = { PROBE = water },
    }
  elseif backend == "gen1" and gen == 3 then
    data.gen3Encounters = { PROBE = { land = land, water = water } }
  else
    data.encounters.PROBE = { grass = land, water = water }
    if gen == 2 then
      land.byTime = { morn = tableFor(grassWeights), day = tableFor(grassWeights), nite = night }
      night.rate = 40
    end
  end
  local Json, files = require("src.link.Json"), {}
  for _, name in ipairs({ "manifest.json", "main.lua" }) do
    local f = assert(io.open(root .. "/examples/portable_encounter_table/" .. name, "rb"))
    files["mods/portable_encounter_table/" .. name] = f:read("*a")
    f:close()
  end
  local manifest = Json.decode(files["mods/portable_encounter_table/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  -- The reference API-1/2 Gold loader requires its legacy compatibility flag.
  manifest.gen2compat = api < 3 and true or nil
  files["mods/portable_encounter_table/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/portable_encounter_table/main.lua"] = files["mods/portable_encounter_table/main.lua"]
      .. '\nerror("intentional encounter preview entry failure")'
  end
  local control = require("src.mods.Merge").deepCopy(manifest)
  control.id, control.name = "preview_control", "Preview control"
  files["mods/preview_control/manifest.json"] = Json.encode(control)
  files["mods/preview_control/main.lua"] = "local m=...; m.exports.api=m"
  if noMod then
    files["mods/portable_encounter_table/manifest.json"], files["mods/portable_encounter_table/main.lua"] =
      nil, nil
  end
  local result = T.sdk.loadMods(
    noMod and { "mods/preview_control" } or { "mods/portable_encounter_table", "mods/preview_control" },
    { data = data, fs = T.sdk.memfs(files), dev = false, generation = gen, version = version }
  )
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local game =
    { data = data, save = { party = {}, flags = {}, options = {}, swarmMaps = {} }, stack = { states = {} } }
  result.loader.game = game
  local restores = {}
  local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function()
      owner[key] = old
    end
    owner[key] = value
  end
  if backend == "gen1" and gen == 3 then
    local E, P = require("src.core.game3.encounters"), require("src.core.game3.pokemon")
    patch(E, "_tables", data.gen3Encounters)
    patch(E, "_loaded", true)
    patch(P, "_names", data.gen3Pokemon._names)
  end
  return {
    T = T,
    e = result.loader.exports.portable_encounter_table,
    game = game,
    result = result,
    generation = gen,
    backend = backend,
    api = api,
    land = land,
    nativeApi = result.loader.exports.preview_control.api,
    setRate = function(value)
      if gen == 2 and backend == "gen1" then
        data.encounters.grass.PROBE.rates.DAY = value
      elseif backend == "gen1" and gen == 3 then
        data.gen3Encounters.PROBE.land.rate = value
      else
        data.encounters.PROBE.grass.rate = value
      end
    end,
    close = function()
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
