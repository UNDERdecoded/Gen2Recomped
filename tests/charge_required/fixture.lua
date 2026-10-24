local M = {}
function M.new(root, backend, version, api, format, noMod, failing, consumer, prepare)
  consumer = consumer or "portable_charge_required"
  local T = require("tests.modkit")
  local V = require("src.core.GameVersion")
  assert(V.VERSIONS[version], "unregistered version")
  V.set(version)
  local gen = V.generation()
  local rows = {
    { "SOLARBEAM", 76, 120, "GRASS", "CHARGE_EFFECT", "EFFECT_SOLARBEAM", 151 },
    { "FLY", 19, 70, "FLYING", "FLY_EFFECT", "EFFECT_FLY", 155 },
    { "DIG", 91, 60, "GROUND", "FLY_EFFECT", "EFFECT_FLY", 155 },
    { "RAZOR_WIND", 13, 80, "NORMAL", "CHARGE_EFFECT", "EFFECT_RAZOR_WIND", 39 },
    { "SKULL_BASH", 130, 100, "NORMAL", "CHARGE_EFFECT", "EFFECT_SKULL_BASH", 145 },
    { "SKY_ATTACK", 143, 140, "FLYING", "CHARGE_EFFECT", "EFFECT_SKY_ATTACK", 75 },
    { "TACKLE", 33, 35, "NORMAL", "NO_ADDITIONAL_EFFECT", "EFFECT_NORMAL_HIT", 0 },
  }
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  if backend == "gen1" and gen == 2 then
    data = {
      pokemon = {
        growthRates = {
          GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 },
        },
        CHARMANDER = {
          id = "CHARMANDER",
          index = 4,
          dex = 4,
          name = "CHARMANDER",
          types = { "NORMAL", "NORMAL" },
          baseStats = {
            hp = 80,
            attack = 50,
            defense = 50,
            speed = 50,
            specialAttack = 50,
            specialDefense = 50,
          },
          catchRate = 45,
          baseExp = 64,
          growthRate = "GROWTH_MEDIUM_FAST",
          genderRatio = 127,
          levelMoves = {},
          evolutions = {},
        },
      },
      moves = {},
      items = {},
      maps = {},
      encounters = {},
      audio = {},
      text = require("tests.gen2_battle_text_fixture")(),
      type_chart = { types = {}, matchups = {}, battleRules = require("tests.gen2_battle_rules_fixture")() },
    }
    for name, index in pairs({ NORMAL = 0, FLYING = 2, GROUND = 4, GRASS = 22 }) do
      data.type_chart.types[name] =
        { id = name, index = index, category = name == "GRASS" and "special" or "physical" }
    end
  elseif not (backend == "gen1" and gen == 3) then
    local mon = require("src.mods.Merge").deepCopy(data.pokemon.FIXMON_A)
    mon.id, mon.name, mon.dex, mon.index, mon.evolutions = "CHARMANDER", "CHARMANDER", 4, 4, {}
    mon.types = { "NORMAL" }
    data.pokemon.CHARMANDER = mon
  end
  local ids, rom, names = {}, {}, {}
  for _, row in ipairs(rows) do
    local name, number, power, kind, gbEffect, g2Effect, g3Effect = unpack(row)
    local id = backend == "gen2" and gen == 3 and ("MOVE_%03d"):format(number) or name
    ids[name], names[number] = id, name
    local effect = gen > 1 and name == "SOLARBEAM" and "SOLARBEAM_EFFECT" or gbEffect
    if backend == "gen1" and gen == 2 then
      effect = g2Effect
    end
    if backend == "gen1" and gen == 3 then
      data.gen3Moves._rom[number] = {
        effect = g3Effect,
        power = power,
        type = ({ NORMAL = 0, FLYING = 2, GROUND = 4, GRASS = 12 })[kind],
        accuracy = 100,
        pp = 10,
        secondaryChance = 0,
        target = 0,
        priority = 0,
        flags = 51,
      }
      data.gen3Pokemon._moveNames[number] = name
      rom[number] = data.gen3Moves._rom[number]
    else
      data.moves[id] = {
        id = id,
        index = number,
        name = name,
        power = power,
        type = kind,
        accuracy = 100,
        accuracyRaw = 255,
        pp = 10,
        effect = effect,
        effectChance = name == "SKY_ATTACK" and 30 or 0,
        effectChanceRaw = name == "SKY_ATTACK" and 77 or 0,
      }
    end
  end
  if prepare then prepare(data, gen, backend, rom, names) end
  local files, Json = {}, require("src.link.Json")
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/" .. consumer .. "/" .. name, "rb"))
    files["mods/" .. consumer .. "/" .. name] = f:read("*a")
    f:close()
  end
  local manifest = Json.decode(files["mods/" .. consumer .. "/manifest.json"])
  manifest.api, manifest.callback_format, manifest.gen2compat = api, format, api < 3 and true or nil
  files["mods/" .. consumer .. "/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/" .. consumer .. "/main.lua"] = files["mods/" .. consumer .. "/main.lua"]
      .. '\nerror("intentional charge entry failure")'
  end
  if noMod then
    files = {}
  end
  local result = T.sdk.loadMods(
    noMod and {} or { "mods/" .. consumer },
    { data = data, fs = T.sdk.memfs(files), generation = gen, dev = false }
  )
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local game = {
    data = data,
    save = {
      party = {},
      options = {},
      player = { name = "PROBE" },
      flags = {},
      inventory = {},
      pokedex = { seen = {}, caught = {} },
      defeatedTrainers = {},
    },
    stack = setmetatable({}, { __index = require("src.core.StateStack") }),
    input = {
      wasPressed = function()
        return false
      end,
      isDown = function()
        return false
      end,
    },
  }
  game.stack:init()
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
    require("src.import.gba.versions").select(version)
    local P = require("src.core.game3.pokemon")
    for key, value in pairs(data.gen3Pokemon) do
      patch(P, key, value)
    end
    patch(P, "_romMoveNames", names)
    patch(P, "_battleMoves", rom)
    local Moves = require("src.core.game3.battle.moves")
    patch(Moves, "_rom", rom)
    patch(Moves, "_romLoaded", true)
    patch(Moves, "BY_NUM", names)
    local byName = {}
    for number, name in pairs(names) do
      byName[name] = number
    end
    patch(Moves, "_numByName", byName)
    patch(
      require("src.core.game3.scripting.space"),
      "bundle",
      {
        text = setmetatable({}, {
          __index = function(t, key)
            local ir = { { t = "text", s = tostring(key) } }
            rawset(t, key, ir)
            return ir
          end,
        }),
      }
    )
  elseif not (backend == "gen1" and gen == 2) then
    require("src.render.Font").load(data)
    require("src.battle.TypeChart").load(data)
  end
  local function fresh(name, opts)
    opts = opts or {}
    local id = ids[name]
    local b, user, target, move, use, hp, pp, charging, hidden
    if backend == "gen1" and gen == 3 then
      local State, Adapter = require("src.core.game3.battle.state"), require("src.core.game3.battle.adapter")
      local n = data.gen3Pokemon._moveNames
      local number
      for k, v in pairs(n) do
        if v == name then
          number = k
          break
        end
      end
      local function mon()
        return {
          species = 4,
          nickname = "PROBE",
          level = 30,
          hp = 400,
          maxHp = 400,
          attack = 50,
          defense = 50,
          speed = 50,
          spAtk = 50,
          spDef = 50,
          ability = 0,
          moves = { number },
          pp = { 10 },
          maxPp = { 10 },
          item = 0,
        }
      end
      b = State.new({
        wild = true,
        playerParty = { mon() },
        foeMon = mon(),
        weather = opts.sun and "SUN" or nil,
      })
      b.rng = function(lo)
        return lo or 0
      end
      user, target = opts.enemy and b.enemy or b.player, opts.enemy and b.player or b.enemy
      local ad = Adapter.new(b)
      use = function(called)
        local slot = 1
        if called then
          slot = nil
        end
        return require("src.core.game3.battle.engine").resolveMove(
          user,
          target,
          number,
          slot,
          ad,
          b,
          {},
          { called = called }
        )
      end
      hp = function()
        return ad:hp(target)
      end
      pp = function()
        return user.mon.pp[1]
      end
      charging = function()
        return user.twoTurnMove ~= nil
      end
      hidden = function()
        return user.semiInvulnerable ~= nil
      end
    elseif backend == "gen1" and gen == 2 then
      local Mon = require("src.battle.gen2.Mon")
      local p, e = Mon.new(data, "CHARMANDER", 30), Mon.new(data, "CHARMANDER", 30)
      p.hp, p.stats.hp, e.hp, e.stats.hp = 400, 400, 400, 400
      p.moves, e.moves = { { id = id, pp = 10 } }, { { id = id, pp = 10 } }
      b = require("src.battle.gen2.Battle").new({
        data = data,
        party = { p },
        wild = e,
        random = function(n)
          return math.max(0, (n or 1) - 1)
        end,
      })
      b.weather = opts.sun and "sun" or nil
      user, target = opts.enemy and e or p, opts.enemy and p or e
      move = user.moves[1]
      use = function(called)
        b.copyDepth = called and 1 or 0
        return b:useMove(user, target, id)
      end
      hp = function()
        return target.hp
      end
      pp = function()
        return move.pp
      end
      charging = function()
        return user.volatile.chargeMove ~= nil
      end
      hidden = function()
        return user.volatile.vanished == true
      end
    else
      local P = require("src.pokemon.Pokemon")
      local p = P.new(data, "CHARMANDER", 30, function(lo)
        return lo or 0
      end)
      p.hp, p.stats.hp, p.moves = 400, 400, { { id = id, pp = 10 } }
      game.save.party = { p }
      b = require("src.battle.BattleState").newWild(game, "CHARMANDER", 30)
      b.player.mon.hp, b.player.mon.stats.hp, b.enemy.mon.hp, b.enemy.mon.stats.hp = 400, 400, 400, 400
      b.rng = function(lo)
        return lo or 0
      end
      if opts.sun then
        b.field.weather = "SUN"
      end
      user, target = opts.enemy and b.enemy or b.player, opts.enemy and b.player or b.enemy
      move = { id = id, pp = 10 }
      user.mon.moves, user.curMoves = { move }, { move }
      use = function(called)
        return b:performMove(user, target, move, called)
      end
      hp = function()
        return target.mon.hp
      end
      pp = function()
        return move.pp
      end
      charging = function()
        return user.charging ~= nil
      end
      hidden = function()
        return user.invulnerable == true
      end
    end
    return {
      battle = b,
      user = user,
      target = target,
      move = move,
      use = use,
      hp = hp,
      pp = pp,
      charging = charging,
      hidden = hidden,
    }
  end
  return {
    T = T,
    e = result.loader.exports[consumer],
    result = result,
    data = data,
    game = game,
    gen = gen,
    backend = backend,
    api = api,
    format = format,
    ids = ids,
    fresh = fresh,
    close = function()
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
