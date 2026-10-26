-- Exercise the real native accuracy command and the public API-3 hook.
local M = {}
local STAGE = {
  [-6] = 33,
  [-5] = 36,
  [-4] = 43,
  [-3] = 50,
  [-2] = 60,
  [-1] = 75,
  [0] = 100,
  133,
  166,
  200,
  233,
  266,
  300,
}
function M.run(root, backend, version, execution)
  local native = backend == "gen1"
  local function configure(data, engine, ids, rom, names)
    for _, row in ipairs({ { 129, "SWIFT" }, { 87, "THUNDER" }, { 327, "SKY_UPPERCUT" } }) do
      local number, name = unpack(row)
      local id = engine == "gen1" and name or ("MOVE_%03d"):format(number)
      ids[name], names[number] = id, name
      if engine == "gen1" then
        local d = require("src.mods.Merge").deepCopy(data.gen3Moves._rom[33])
        data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = d, d, name
      else
        local d = require("src.mods.Merge").deepCopy(data.moves[ids.TACKLE])
        d.id, d.name, d.index = id, name, number
        data.moves[id] = d
      end
    end
    if engine == "gen2" then
      data.items.BRIGHTPOWDER =
        { index = 179, name = "BRIGHTPOWDER", holdEffect = "EVASION_UP", holdEffectParam = 10 }
      data.items.LAX_INCENSE =
        { index = 221, name = "LAX INCENSE", holdEffect = "EVASION_UP", holdEffectParam = 5 }
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  local T, rows, calls, draws, policy = f.T, {}, {}, {}, "delegate"
  local stop
  local damageCalls = 0
  local stopCrit, stopDamage
  if execution then
    stopCrit = f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    stopDamage = f.e.api.hooks:wrap("battle.damage", function(nextDamage, ...)
      damageCalls = damageCalls + 1
      return nextDamage(...)
    end)
  end
  local function hook(nextAccuracy, c)
    calls[#calls + 1] = {
      move = c.moveId,
      number = c.moveNum,
      accuracy = c.accuracy,
      user = c.user.mon.nickname,
      target = c.target.mon.nickname,
      battle = c.battle ~= nil,
    }
    if policy == "force" then
      return true
    end
    if policy == "suppress" then
      return false
    end
    if policy == "threshold" then
      c.accuracy = 37
    end
    if policy == "rng" then
      c.rng = function(lo, hi)
        T.eq(lo, 1, "replacement accuracy RNG lower bound")
        T.eq(hi, 100, "replacement accuracy RNG upper bound")
        return 1
      end
    end
    return nextAccuracy(c)
  end
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local abilities = {
    NONE = 0,
    COMPOUND_EYES = 14,
    HUSTLE = 55,
    SAND_VEIL = 8,
    CLOUD_NINE = 13,
    VOLT_ABSORB = 10,
    WATER_ABSORB = 11,
    FLASH_FIRE = 18,
  }
  local cases = {}
  for acc = -6, 6 do
    for eva = -6, 6 do
      for _, word in ipairs({ 0, 49, 82, 83, 99 }) do
        cases[#cases + 1] =
          { name = "stages", accuracy = 83, acc = acc, eva = eva, word = word, user = (acc - eva) % 4 }
      end
    end
  end
  for _, spec in ipairs({
    { name = "swift", accuracy = 1, move = "SWIFT", number = 129, effect = 17 },
    { name = "swift-air", accuracy = 1, move = "SWIFT", number = 129, effect = 17, semi = "ON_AIR" },
    { name = "thunder-rain", accuracy = 70, move = "THUNDER", number = 87, effect = 152, sky = "RAIN" },
    { name = "thunder-sun", accuracy = 70, move = "THUNDER", number = 87, effect = 152, sky = "SUN" },
    {
      name = "thunder-air",
      accuracy = 70,
      move = "THUNDER",
      number = 87,
      effect = 152,
      semi = "ON_AIR",
      executionOnly = true,
    },
    {
      name = "sky-uppercut-air",
      accuracy = 90,
      move = "SKY_UPPERCUT",
      number = 327,
      effect = 207,
      semi = "ON_AIR",
      executionOnly = true,
    },
    { name = "full-accuracy", accuracy = 100 },
    { name = "zero-accuracy", accuracy = 0 },
    { name = "compound-eyes", mine = "COMPOUND_EYES", accuracy = 73, acc = 1 },
    { name = "hustle", mine = "HUSTLE", accuracy = 83, acc = -1 },
    { name = "hustle-special", mine = "HUSTLE", kind = 13, accuracy = 83 },
    { name = "sand-veil", theirs = "SAND_VEIL", sky = "SAND", accuracy = 83, acc = 1 },
    { name = "sand-veil-suppressed", theirs = "SAND_VEIL", sky = "SAND", suppressSky = true, accuracy = 83 },
    { name = "brightpowder", item = "BRIGHTPOWDER", accuracy = 83, acc = 1 },
    { name = "lax-incense", item = "LAX_INCENSE", accuracy = 83, acc = 1 },
    {
      name = "composed-modifiers",
      mine = "COMPOUND_EYES",
      theirs = "SAND_VEIL",
      sky = "SAND",
      item = "LAX_INCENSE",
      accuracy = 73,
      acc = 1,
    },
    { name = "identified", identified = true, accuracy = 83, acc = -1, eva = 6 },
    { name = "locked-on", locked = true, accuracy = 1 },
    { name = "semi-air", semi = "ON_AIR", accuracy = 100 },
    { name = "semi-ground", semi = "UNDERGROUND", accuracy = 100 },
    { name = "semi-water", semi = "UNDERWATER", accuracy = 100 },
    { name = "protected", protect = true, accuracy = 1 },
    { name = "unaffected-by-protect", protect = true, noProtect = true, accuracy = 83 },
    { name = "pokedude", demo = true, accuracy = 1 },
    { name = "pokedude-air", demo = true, semi = "ON_AIR", accuracy = 1 },
    { name = "pokedude-protect", demo = true, protect = true, accuracy = 1 },
    { name = "oak-damage-pending", oak = true, flags = 0, accuracy = 1 },
    { name = "oak-damage-done", oak = true, flags = 1, accuracy = 1 },
    { name = "oak-stat-pending", oak = true, flags = 1, power = 0, accuracy = 1 },
    { name = "oak-stat-done", oak = true, flags = 2, power = 0, accuracy = 1 },
    { name = "oak-separate-flags", oak = true, flags = 2, accuracy = 1 },
    { name = "oak-protected", oak = true, flags = 0, protect = true, accuracy = 1 },
    { name = "absorb-electric", theirs = "VOLT_ABSORB", kind = 13, accuracy = 83 },
    { name = "absorb-water", theirs = "WATER_ABSORB", kind = 11, accuracy = 83 },
    { name = "absorb-fire", theirs = "FLASH_FIRE", kind = 10, accuracy = 83 },
    { name = "pokedude-absorb", demo = true, theirs = "VOLT_ABSORB", kind = 13, accuracy = 1 },
  }) do
    for id = 0, 3 do
      local copy = require("src.mods.Merge").deepCopy(spec)
      copy.user = id
      copy.word = 49
      cases[#cases + 1] = copy
    end
  end
  for _, mode in ipairs({ "none", "delegate", "force", "suppress", "threshold", "rng" }) do
    policy = mode
    if mode ~= "none" then
      stop = f.e.api.hooks:wrap("battle.accuracy", hook)
    end
    for _, spec in ipairs(cases) do
      if
        (spec.name ~= "stages" or not execution and (mode == "none" or mode == "delegate"))
        and (execution or not spec.executionOnly)
      then
        calls, draws, damageCalls = {}, {}, 0
        local b = f.fresh("TACKLE", { enemy = true }).battle
        b.double = true
        if native then
          local S = require("src.core.game3.battle.state")
          b.battlers[2] =
            S.makeBattler(require("src.mods.Merge").deepCopy(b.player.mon), "player", { id = 2 })
          b.battlers[3] = S.makeBattler(require("src.mods.Merge").deepCopy(b.enemy.mon), "enemy", { id = 3 })
        else
          local S = require("src.battle.BattleState")
          b:syncSides()
          b:placeBattler(2, S.makeBattler(f.data, require("src.mods.Merge").deepCopy(b.player.mon), true))
          b:placeBattler(3, S.makeBattler(f.data, require("src.mods.Merge").deepCopy(b.enemy.mon), false))
          b:syncSides()
        end
        for id = 0, 3 do
          local a = at(b, id)
          a.mon.nickname, a.mon.hp = "P" .. id, 100
          if native then
            a.ability, a.mon.ability, a.mon.maxHp, a.type1, a.type2 = 0, 0, 400, 0, 0
            for _, key in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
              a.mon[key] = 50
            end
          else
            a.abilityOverride, a.mon.stats.hp, a.curTypes = false, 400, { "NORMAL" }
            for _, key in ipairs({ "attack", "defense", "speed", "spatk", "spdef" }) do
              a.curStats[key] = 50
            end
          end
        end
        local user, target = at(b, spec.user), at(b, spec.user % 2 == 0 and 1 or 0)
        local function ability(a, name)
          if native then
            a.ability, a.mon.ability = abilities[name or "NONE"], abilities[name or "NONE"]
          else
            a.abilityOverride = name and name:gsub("COMPOUND_EYES", "COMPOUNDEYES") or false
          end
        end
        ability(user, spec.mine)
        ability(target, spec.theirs)
        if spec.suppressSky then
          ability(at(b, 3 - spec.user % 2), "CLOUD_NINE")
        end
        user.stages, target.stages = { accuracy = spec.acc or 0 }, { evasion = spec.eva or 0 }
        b.firstBattle, b.oakMsgFlags = spec.oak, spec.flags or 0
        local move
        local number, moveName = spec.number or 33, spec.move or "TACKLE"
        if native then
          user.mon.moves = { number }
        else
          user.curMoves = { { id = f.ids[moveName], pp = 10 } }
          user.mon.moves = user.curMoves
        end
        if native then
          b.pokedude, b.weather = spec.demo, spec.sky
          target.expProtected, target.expIdentified, target.semiInvulnerable =
            spec.protect, spec.identified, spec.semi
          target.expLockedOn = spec.locked and 2 or nil
          target.expLockedOnById = spec.locked and spec.user or nil
          target.item = spec.item == "BRIGHTPOWDER" and 179 or spec.item == "LAX_INCENSE" and 221 or 0
          move = require("src.core.game3.battle.moves")._rom[number]
          move.effect = spec.effect or (spec.power == 0 and 19 or 0)
          move.accuracy, move.power, move.type, move.flags =
            spec.accuracy, spec.power or 35, spec.kind or 0, spec.noProtect and 0 or 2
        else
          b.pokedudeDemo, b.field.weather = spec.demo and {}, spec.sky == "SAND" and "SANDSTORM" or spec.sky
          target.protecting, target.identified, target.invulnerable =
            spec.protect, spec.identified, spec.semi ~= nil
          target.hiddenAs = ({ ON_AIR = "air", UNDERGROUND = "underground", UNDERWATER = "underwater" })[spec.semi]
          user.lockedOn = spec.locked and target or nil
          target.mon.item = spec.item
          move = f.data.moves[f.ids[moveName]]
          move.effect = ({ [17] = "SWIFT_EFFECT", [152] = "THUNDER_EFFECT", [207] = "SKY_UPPERCUT_EFFECT" })[spec.effect]
            or (spec.power == 0 and "DEFENSE_DOWN1_EFFECT" or "NO_ADDITIONAL_EFFECT")
          move.gen3Effect = spec.effect or (spec.power == 0 and 19 or 0)
          move.accuracy, move.power, move.type, move.protectAffected =
            spec.accuracy,
            spec.power or 35,
            ({ [0] = "NORMAL", [13] = "ELECTRIC", [11] = "WATER", [10] = "FIRE" })[spec.kind or 0],
            not spec.noProtect
        end
        b.rng = function(lo, hi)
          local value = lo + spec.word % (hi - lo + 1)
          draws[#draws + 1] = { lo = lo, hi = hi, word = spec.word, value = value }
          return value
        end
        local result
        if execution then
          if native then
            require("src.core.game3.battle.engine").resolveMove(
              user,
              target,
              number,
              1,
              require("src.core.game3.battle.adapter").new(b),
              b,
              {}
            )
          else
            b:executeAction(user, target, user.curMoves[1])
          end
          result = "execution"
        elseif native then
          local context = require("src.core.game3.battle.engine").newContext(
            user,
            target,
            number,
            1,
            require("src.core.game3.battle.adapter").new(b),
            b,
            {},
            {}
          )
          result = context:accuracyCheck("normal", false)
        else
          result = b:accuracyRoll(move, user, target)
        end
        local buff = math.max(-6, math.min(6, (spec.acc or 0) - (spec.identified and 0 or spec.eva or 0)))
        local threshold =
          math.floor(STAGE[buff] * (spec.effect == 152 and spec.sky == "SUN" and 50 or spec.accuracy) / 100)
        if spec.mine == "COMPOUND_EYES" then
          threshold = math.floor(threshold * 130 / 100)
        end
        if spec.theirs == "SAND_VEIL" and spec.sky == "SAND" and not spec.suppressSky then
          threshold = math.floor(threshold * 80 / 100)
        end
        if spec.mine == "HUSTLE" and not spec.kind then
          threshold = math.floor(threshold * 80 / 100)
        end
        if spec.item then
          threshold = math.floor(threshold * (spec.item == "BRIGHTPOWDER" and 90 or 95) / 100)
        end
        local guaranteed = spec.demo
          or spec.locked
          or spec.oak
            and spec.user % 2 == 0
            and math.floor((spec.flags or 0) / (spec.power == 0 and 2 or 1)) % 2 == 0
        local specialAir = execution and (spec.effect == 152 or spec.effect == 207) and spec.semi == "ON_AIR"
        local guard = spec.protect and not spec.noProtect or spec.semi and not guaranteed and not specialAir
        guaranteed = guaranteed
          or spec.effect == 17
          or spec.effect == 78
          or spec.effect == 152 and spec.sky == "RAIN"
        local callback = not guard and not guaranteed and mode ~= "none"
        T.eq(#calls, callback and 1 or 0, spec.name .. " native callback boundary")
        if not execution then
          T.eq(
            #draws,
            not guard and not guaranteed and not (mode == "force" or mode == "suppress") and 1 or 0,
            spec.name .. " exact native accuracy draw count"
          )
        end
        if callback then
          T.eq(calls[1] and calls[1].accuracy, threshold, "public accuracy threshold uses native arithmetic")
        end
        rows[#rows + 1] = {
          case = spec.name,
          mode = mode,
          user = spec.user,
          acc = spec.acc,
          eva = spec.eva,
          word = spec.word,
          result = result,
          calls = calls,
          draws = draws,
          damageCalls = execution and damageCalls or nil,
          pp = execution and (native and user.mon.pp[1] or user.curMoves[1].pp) or nil,
          defense = target.stages.defense or 0,
          hp = target.mon.hp,
          flashFire = (native and target.expFlashFire or target.flashFire) or false,
        }
      end
    end
    if stop then
      stop()
      stop = nil
    end
  end
  if stopCrit then
    stopCrit()
    stopDamage()
  end
  f.close()
  return rows
end
return M
