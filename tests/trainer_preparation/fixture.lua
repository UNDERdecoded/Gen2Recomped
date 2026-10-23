local M = {}
function M.new(root, backend, version, api, format, noMod, failing, consumer)
  consumer = consumer or "portable_trainer_preparation"
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local gen = Version.generation()
  local Json, files = require("src.link.Json"), {}
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/" .. consumer .. "/" .. name, "rb"))
    files["mods/" .. consumer .. "/" .. name] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/" .. consumer .. "/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  files["mods/" .. consumer .. "/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/" .. consumer .. "/main.lua"] = files["mods/" .. consumer .. "/main.lua"]
      .. '\nerror("intentional entry failure")'
  end
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  if backend == "gen1" and gen == 2 then
    data = {
      version = version,
      pokemon = {
        growthRates = {
          GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 },
        },
        MAGIKARP = {
          id = "MAGIKARP",
          name = "MAGIKARP",
          index = 129,
          dex = 129,
          types = { "WATER", "WATER" },
          genderRatio = 127,
          catchRate = 255,
          baseExp = 20,
          growthRate = "GROWTH_MEDIUM_FAST",
          baseStats = {
            hp = 80,
            attack = 10,
            defense = 55,
            speed = 80,
            specialAttack = 15,
            specialDefense = 20,
          },
          levelMoves = { { level = 1, move = "SPLASH" } },
          evolutions = {},
        },
      },
      moves = {
        SPLASH = {
          id = "SPLASH",
          name = "SPLASH",
          type = "NORMAL",
          power = 0,
          accuracy = 100,
          pp = 40,
          effect = "EFFECT_SPLASH",
        },
      },
      type_chart = {
        types = {
          NORMAL = { id = "NORMAL", index = 0, category = "physical" },
          WATER = { id = "WATER", index = 21, category = "special" },
        },
        matchups = {},
      },
      items = {},
    }
  end
  local result = T.sdk.loadMods(noMod and {} or { "mods/" .. consumer }, {
    data = data,
    generation = gen,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local restores = {}
  local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function()
      owner[key] = old
    end
    owner[key] = value
  end
  local stack = setmetatable({}, { __index = require("src.core.StateStack") })
  stack:init()
  local input = setmetatable({}, { __index = require("src.core.Input") })
  input:init()
  local game = {
    data = data,
    stack = stack,
    input = input,
    sessionStartedAt = 1,
    save = {
      version = version,
      party = {},
      player = { name = "PROBE" },
      options = {},
      flags = {},
      defeatedTrainers = {},
      engineFlags = {},
      inventory = {},
      money = 1000,
      pokedex = { seen = {}, caught = {} },
    },
  }
  local context =
    { trainerClass = "OPP_FIX_YOUNGSTER", partyIndex = 1, mapId = "FIX_ROUTE", npcId = "TRAINER_1" }
  local battle, starts, cancels, start, closeNative = nil, 0, 0
  if backend == "gen1" and gen == 3 then
    require("src.import.gba.versions").select(version)
    local P = require("src.core.game3.pokemon")
    for key, value in pairs(data.gen3Pokemon) do
      patch(P, key, value)
    end
    patch(P, "_front", {})
    patch(P, "_back", {})
    patch(P, "_national", { toNational = { [4] = 4, [16] = 16 } })
    patch(P, "_battleMoves", data.gen3Moves._rom)
    patch(P, "_romMoveNames", data.gen3Pokemon._moveNames)
    local function mon(species, nickname)
      return {
        species = species,
        nickname = nickname,
        level = 20,
        hp = 60,
        maxHp = 60,
        attack = 30,
        defense = 30,
        speed = 30,
        spAtk = 30,
        spDef = 30,
        moves = { 33 },
        pp = { 35 },
        maxPp = { 35 },
        ability = 0,
        personality = 1,
        growthRate = 0,
        exp = 8000,
        item = 0,
        otId = 1,
        otSecretId = 2,
      }
    end
    local session = {
      version = version,
      party = { mon(4, "ONE"), mon(4, "TWO"), mon(4, "THREE") },
      name = "RED",
      trainerId = 1,
      secretId = 2,
      flags = {},
      vars = {},
      options = {},
    }
    game.session = session
    game.save.party = session.party
    local R = require("src.core.game3.runtime")
    patch(R, "active", true)
    patch(R, "session", session)
    patch(R, "_game", game)
    local Field = require("src.core.game3.field")
    patch(Field, "running", false)
    patch(Field, "_session", session)
    patch(Field, "_game", game)
    patch(Field, "_locks", {})
    patch(require("src.core.game3.map"), "current", nil)
    local Space = require("src.core.game3.scripting.space")
    patch(Space, "vm", nil)
    patch(Space, "bundle", {
      text = setmetatable({}, {
        __index = function(t, key)
          local ir = { { t = "text", s = tostring(key), v = tostring(key), text = tostring(key) } }
          rawset(t, key, ir)
          return ir
        end,
      }),
      maps = {},
      events = {},
    })
    local B = require("src.core.game3.battle")
    local Bridge = require("src.core.game3.battle_bridge")
    B.reset()
    Bridge.reset()
    local foe = mon(16, "FOE")
    foe.party = { mon(16, "FOE") }
    foe.trainerClass, foe.trainerId = 1, 1
    patch(require("src.core.game3.scripting.trainers"), "_pack", {
      classNames = { [0] = "TRAINER", [1] = "PROBE" },
      trainers = {
        [0] = {
          class = 0,
          name = "TRAINER",
          pic = 0,
          party = { { species = 16, level = 5, moves = { 33 } } },
        },
        [1] = { class = 1, name = "PROBE", pic = 0, party = { { species = 16, level = 5, moves = { 33 } } } },
      },
    })
    local cache = require("src.core.game3.dataset").cache()
    local read = cache.read
    patch(cache, "read", function(self, path, ...)
      if path:match("/battle_moves%.lua$") then
        return "return {moves={[33]={effect=0,power=35,type=0,accuracy=100,pp=35,target=0,priority=0}}}"
      end
      return read(self, path, ...)
    end)
    result.loader.events:on("battle.started", function()
      starts = starts + 1
      battle = B.getState()
    end)
    start = function()
      return Bridge.start(nil, game, foe, {
        headless = true,
        fade = false,
        autoFight = false,
        cache = cache,
        song = 1,
        mapBehavior = 0,
        noWhiteout = true,
        cancel = function()
          cancels = cancels + 1
        end,
        failed = function(reason)
          error("native trainer start: " .. tostring(reason))
        end,
      })
    end
    closeNative = function()
      B.reset()
      Bridge.reset()
      R.drainDeferred()
    end
  elseif backend == "gen1" and gen == 2 then
    local Mon = require("src.battle.gen2.Mon")
    for i, name in ipairs({ "ONE", "TWO", "THREE" }) do
      local m = Mon.new(data, "MAGIKARP", 20)
      m.nickname = name
      game.save.party[i] = m
    end
    local World = require("src.world.gen2.World")
    local world = World.new(game)
    game.world = world
    local record = {
      class = 1,
      member = 1,
      event = 700,
      name = "PROBE",
      className = "YOUNGSTER",
      roster = { { species = "MAGIKARP", level = 5 } },
    }
    world.vm = require("src.script.gen2.Vm").new({}, {}, world.events)
    result.loader.events:on("battle.started", function(payload)
      local native = payload.battle.battle or payload.battle
      if native ~= battle then
        battle = native
        starts = starts + 1
      end
    end)
    start = function()
      return world:startScriptedBattle(record, nil, function()
        cancels = cancels + 1
      end)
    end
  else
    local Save = require("src.core.SaveData")
    game.save = Save.newGame()
    local P = require("src.pokemon.Pokemon")
    for i, name in ipairs({ "ONE", "TWO", "THREE" }) do
      game.save.party[i] = P.new(data, "FIXMON_A", 20)
      game.save.party[i].nickname = name
    end
    local World = require("src.world.OverworldController")
    start = function()
      return World.prepareTrainerBattle(game, context, function(options)
        battle = require("src.battle.BattleState").newTrainer(game, "OPP_FIX_YOUNGSTER", 1, options)
        starts = starts + 1
      end, function()
        cancels = cancels + 1
      end)
    end
  end
  result.loader.game = game
  return {
    T = T,
    api = api,
    backend = backend,
    generation = gen,
    result = result,
    game = game,
    exports = result.loader.exports[consumer],
    patch = patch,
    start = start,
    starts = function()
      return starts
    end,
    cancels = function()
      return cancels
    end,
    party = function()
      local b = battle
      return b and (b.playerParty or b.party or (b.player and b.player.party) or game.save.party) or nil
    end,
    battle = function()
      return battle
    end,
    close = function()
      if closeNative then
        closeNative()
      end
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
