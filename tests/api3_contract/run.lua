-- Shared harness; only fixture construction knows the native engine layout.
local M = {}
local function read(path)
  local f = assert(io.open(path, "rb"))
  local body = f:read("*a")
  f:close()
  return body
end
local function dataFor(backend, generation)
  if backend == "gen1" and generation == 3 then
    local fixture = require("tests.modkit.sdk").gen3Data()
    fixture.maps.PROBE = { id = "PROBE", width = 2, height = 2, tileset = "FIX", blocks = { 1 } }
    return fixture
  end
  local stats = { hp = 100, attack = 100, defense = 100, speed = 100, special = 100 }
  local mon = {
    id = "MEW",
    name = "MEW",
    dex = 151,
    types = { "PSYCHIC" },
    baseStats = stats,
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
  local effect = "NO_ADDITIONAL_EFFECT"
  if generation > 1 then
    stats.spatk, stats.spdef = 100, 100
  end
  if backend == "gen1" and generation == 2 then
    stats.special, stats.spatk, stats.spdef = nil, nil, nil
    stats.specialAttack, stats.specialDefense = 100, 100
    mon.level1Moves, mon.learnset, mon.frontSize = nil, nil, nil
    mon.levelMoves, mon.picSize = { { level = 1, move = "POUND" } }, 5
    effect = "EFFECT_NORMAL_HIT"
  end
  local pokemon = { MEW = mon }
  if backend == "gen1" and generation == 2 then
    pokemon.growthRates =
      { MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
  end
  return {
    pokemon = pokemon,
    moves = {
      POUND = {
        id = "POUND",
        name = "POUND",
        type = "NORMAL",
        power = 40,
        accuracy = 100,
        pp = 35,
        effect = effect,
      },
    },
    items = { POTION = { id = "POTION", name = "POTION", price = 300, tossable = true } },
    maps = { PROBE = { id = "PROBE", width = 2, height = 2, tileset = "FIX", blocks = { 1 } } },
    trainers = {},
    encounters = {},
    audio = {},
    type_chart = { types = { NORMAL = {}, PSYCHIC = {} }, matchups = {} },
    gen2Maps = backend == "gen1" and generation == 2 and {
      PROBE = { id = "PROBE", width = 2, height = 2, tileset = "FIX", blocks = { 1 } },
    } or nil,
  }
end
local function nativeMon(backend, gen)
  local stats = { hp = 40, attack = 21, defense = 22, speed = 23, special = 24 }
  local mon = {
    species = "MEW",
    nickname = "Scout",
    name = "Native name",
    level = 20,
    hp = 30,
    status = "PSN",
    stats = stats,
    moves = { { id = "POUND", pp = 30, ppUps = 0 } },
  }
  if gen > 1 then
    stats.spatk, stats.spdef = 24, 25
  end
  if backend == "gen1" and gen > 1 then
    stats.special, stats.spatk, stats.spdef = nil, nil, nil
    stats.specialAttack, stats.specialDefense = 24, 25
    mon.status = gen == 2 and "poison" or 8
    if gen == 3 then
      mon.species, mon.moves[1].id = 151, 1
    end
  end
  return mon
end
function M.run(root, backend, version, failing, scaffold)
  local Loader = require("src.mods.Loader")
  local Runtime = require("src.mods.Runtime")
  local Version = require("src.core.GameVersion")
  local Json = require("src.link.Json")
  Version.set(version)
  local generation = Version.generation(version)
  local data = dataFor(backend, generation)
  local files = {}
  for _, id in ipairs(failing and { "portable", "rollback" } or { "portable" }) do
    for _, name in ipairs({ "manifest.json", "main.lua" }) do
      files["mods/" .. id .. "/" .. name] = read(root .. "/mods/" .. id .. "/" .. name)
    end
  end
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(assert(files[p]), "@" .. p)
    end,
    getInfo = function(p)
      if files[p] then
        return { type = "file", size = #files[p] }
      end
      for key in pairs(files) do
        if key:sub(1, #p + 1) == p .. "/" then
          return { type = "directory" }
        end
      end
    end,
    getDirectoryItems = function(p)
      if p == "mods" then
        return failing and { "portable", "rollback" } or { "portable" }
      end
      return {}
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false, generation = generation, version = version })
  local game
  loader._game = function(_, loadedOnly)
    if backend == "gen2" then
      assert(loadedOnly, "API 3 must not bootstrap Game")
    end
    return game
  end
  local ok = loader:load(data)
  if scaffold then
    assert(ok, table.concat(loader.errors, "; "))
    assert(loader.mods.portable.manifest.api == 3, "generated manifest selects API 3")
    local power = backend == "gen1" and generation == 3 and data.gen3Moves._rom[1].power
      or data.moves.POUND.power
    assert(power == 45, "generated entry changed the native move")
    local report = { scaffold = true, power = power }
    print("API3_CONTRACT " .. Json.encode(report))
    return report
  end
  local errorCount = #loader.errors
  local exported = assert(loader.exports.portable, table.concat(loader.errors, "; "))
  assert(exported.report, table.concat(loader.errors, "; "))
  if failing then
    assert(not ok and table.concat(loader.errors, "; "):find("intentional API 3 rollback", 1, true))
  else
    assert(ok, table.concat(loader.errors, "; "))
  end
  local nativeHp = backend == "gen1" and generation == 3 and data.gen3Pokemon._stats[151].hp
    or data.pokemon.MEW.baseStats.hp
  assert(nativeHp == 101, "rollback/native merge")
  assert(
    (backend == "gen1" and generation == 2 and data.gen2Maps or data.maps).PROBE.width == 2,
    "passthrough reads remain detached"
  )
  local raw = nativeMon(backend, generation)
  local save = { party = { raw }, flags = {}, modData = {}, money = 0 }
  game = { data = data, save = save, stack = { states = {} } }
  if backend == "gen1" and generation == 3 then
    game.session = save
  end
  exported.exercise()
  Runtime.emit("pokemon.received", { mon = raw })
  assert(raw.hp == 30, "event read did not mutate native Pokemon")
  loader.hooks:call("evolution.check", function(_, mon)
    assert(mon == raw and mon.hp == 27, "native hook forwarding")
    assert(
      mon.status
        == (
          backend == "gen1" and generation == 3 and 16
          or backend == "gen1" and generation == 2 and "burn"
          or "BRN"
        ),
      "native status writeback"
    )
    local attack = mon.stats.spatk or mon.stats.specialAttack or mon.stats.special
    local defense = mon.stats.spdef or mon.stats.specialDefense or mon.stats.special
    assert(attack == 31 and defense == 31, "common Special writes both later stats")
    return "UNCHANGED"
  end, game, raw, {}, {})
  assert(raw.hp == 27)
  exported.late()
  Runtime.emit("mod.portable.probe", { value = 8 })
  assert(exported.report.custom == 8, "custom callback reached live owner")
  assert(#loader.errors == errorCount, "no callback errors or failed-owner subscription leaks")
  if generation == 1 then
    require("src.battle.TypeChart").load(data)
    local player, enemy = nativeMon(backend, generation), nativeMon(backend, generation)
    local function battler(mon)
      return {
        mon = mon,
        species = mon.species,
        name = mon.nickname,
        curStats = mon.stats,
        curTypes = { "PSYCHIC" },
        curMoves = mon.moves,
        stages = {},
      }
    end
    local battle = {
      isBattleState = true,
      game = game,
      data = data,
      kind = "wild",
      phase = "menu",
      queue = {},
      player = battler(player),
      enemy = battler(enemy),
      enemyParty = { enemy },
      ruleset = {},
      turnCount = 0,
      sides = { { battlers = {} }, { battlers = {} } },
    }
    function battle:battleKind()
      return "wild"
    end
    function battle:visibleText()
      return {}
    end
    function battle:effectRecord()
      return { accuracyChecked = true }
    end
    game.save.party, game.save.inventory = { player }, {}
    game.stack.states = { battle }
    exported.snapshot()
    assert(player.hp == 30, "invalid intent never dispatched")
  end
  -- The entry-time world handle must follow a later Game instead of retaining the old save.
  local replacement = nativeMon(backend, generation)
  replacement.hp = 19
  local nextSave = { party = { replacement }, modData = {}, flags = {} }
  game = { data = data, save = nextSave, stack = { states = {} } }
  if backend == "gen1" and generation == 3 then
    game.session = nextSave
  end
  assert(exported.world:party()[1].hp == 19, "captured facade follows current game")
  assert(exported.battle:snapshot() == nil, "no battle")
  local result = exported.report
  assert(result.event and result.hook and result.party and result.custom == 8)
  print("API3_CONTRACT " .. Json.encode(result))
  return result
end
M.dataFor = dataFor
return M
