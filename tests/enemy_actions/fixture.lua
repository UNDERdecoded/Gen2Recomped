local M = {}
function M.new(root, backend, version, api, format)
  local consumer = "portable_enemy_action"
  local T = require("tests.modkit")
  local V = require("src.core.GameVersion")
  assert(V.VERSIONS[version], "unregistered version")
  V.set(version)
  local gen = V.generation()
  local rows = {
    { "STRUGGLE", 165, 50, "NORMAL", "RECOIL_EFFECT", "EFFECT_RECOIL_HIT", 48 },
    { "MIMIC", 102, 0, "NORMAL", "MIMIC_EFFECT", "EFFECT_MIMIC", 82 },
    { "SCRATCH", 10, 40, "NORMAL", "NO_ADDITIONAL_EFFECT", "EFFECT_NORMAL_HIT", 0 },
    { "FLY", 19, 70, "FLYING", "FLY_EFFECT", "EFFECT_FLY", 155 },
    { "TACKLE", 33, 35, "NORMAL", "NO_ADDITIONAL_EFFECT", "EFFECT_NORMAL_HIT", 0 },
  }
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  assert(gen == 3, "enemy action fixture requires GBA")
  if backend ~= "gen1" then
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
  if backend == "gen2" then
    data.moves.STRUGGLE = data.moves[ids.STRUGGLE]
  end
  local files, Json = {}, require("src.link.Json")
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/" .. consumer .. "/" .. name, "rb"))
    files["mods/" .. consumer .. "/" .. name] = f:read("*a")
    f:close()
  end
  local manifest = Json.decode(files["mods/" .. consumer .. "/manifest.json"])
  manifest.api, manifest.callback_format, manifest.gen2compat = api, format, api < 3 and true or nil
  files["mods/" .. consumer .. "/manifest.json"] = Json.encode(manifest)
  local result = T.sdk.loadMods(
    { "mods/" .. consumer },
    { data = data, fs = T.sdk.memfs(files), generation = gen, dev = false }
  )
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
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
    patch(require("src.core.game3.scripting.space"), "bundle", {
      text = setmetatable({}, {
        __index = function(t, key)
          local ir = { { t = "text", s = tostring(key) } }
          rawset(t, key, ir)
          return ir
        end,
      }),
    })
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
