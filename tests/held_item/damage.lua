-- Shared inputs; execute each engine's actual calculator and public hook chain.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/held_item/fixture.lua").new(root, backend, version, 3, "unified")
  local T, rows = f.T, {}
  local scenarios = {
    { name = "empty" },
    { name = "normal-boost", item = "NORMAL_POWER" },
    { name = "choice-band", item = "CHOICE_BAND" },
    { name = "thick-club", item = "THICK_CLUB", species = 104 },
    { name = "thick-club-wrong-species", item = "THICK_CLUB" },
    { name = "metal-powder", targetItem = "METAL_POWDER", targetSpecies = 132 },
    { name = "metal-powder-wrong-species", targetItem = "METAL_POWDER" },
    { name = "fire-boost", item = "FIRE_POWER", special = true },
    { name = "light-ball", item = "LIGHT_BALL", species = 25, special = true },
    { name = "light-ball-wrong-category", item = "LIGHT_BALL", species = 25 },
    { name = "deep-sea-tooth", item = "DEEP_SEA_TOOTH", species = 373, special = true },
    { name = "deep-sea-scale", targetItem = "DEEP_SEA_SCALE", targetSpecies = 373, special = true },
    {
      name = "soul-dew-both",
      item = "SOUL_DEW",
      targetItem = "SOUL_DEW",
      species = 407,
      targetSpecies = 408,
      special = true,
    },
    { name = "override-empty", effect = "HELD_NORMAL_BOOST", parameter = 13 },
    { name = "override-choice", effect = "HELD_CHOICE_BAND" },
    { name = "suppress-choice", item = "CHOICE_BAND", suppress = true },
    { name = "stateful-read", effect = "HELD_NORMAL_BOOST", parameter = 13, stateful = true },
    { name = "huge-power-club", item = "THICK_CLUB", species = 104, ability = "HUGE_POWER" },
    { name = "pure-power-band", item = "CHOICE_BAND", ability = "PURE_POWER" },
    { name = "hustle-band", item = "CHOICE_BAND", ability = "HUSTLE" },
    { name = "guts-burn-band", item = "CHOICE_BAND", ability = "GUTS", status = "BRN" },
    { name = "burn-band", item = "CHOICE_BAND", status = "BRN" },
    {
      name = "marvel-scale",
      targetItem = "METAL_POWDER",
      targetSpecies = 132,
      targetAbility = "MARVEL_SCALE",
      targetStatus = "BRN",
    },
    { name = "thick-fat-boost", item = "FIRE_POWER", special = true, targetAbility = "THICK_FAT" },
    { name = "blaze-boost", item = "FIRE_POWER", special = true, ability = "BLAZE", pinch = true },
    {
      name = "plus-light-ball",
      item = "LIGHT_BALL",
      species = 25,
      special = true,
      ability = "PLUS",
      targetAbility = "MINUS",
    },
    { name = "rain-fire", item = "FIRE_POWER", special = true, weather = "RAIN" },
    { name = "sun-fire", item = "FIRE_POWER", special = true, weather = "SUN" },
    { name = "water-sport", item = "FIRE_POWER", special = true, sport = true },
    { name = "screen-band", item = "CHOICE_BAND", screen = true },
    { name = "screen-fire", item = "FIRE_POWER", special = true, screen = true },
    {
      name = "blaze-water-sport",
      item = "FIRE_POWER",
      special = true,
      ability = "BLAZE",
      pinch = true,
      sport = true,
    },
    { name = "flash-fire", item = "FIRE_POWER", special = true, ability = "FLASH_FIRE", flash = true },
    { name = "charged-boost", item = "ELECTRIC_POWER", special = true, electric = true, charged = true },
  }
  local function item(effect)
    for _, row in ipairs(f.catalog) do
      if row[3] == effect then
        return row[1]
      end
    end
    assert(effect == nil, "fixture item missing: " .. tostring(effect))
  end
  for _, scenario in ipairs(scenarios) do
    for _, stat in ipairs({ 17, 51, 257 }) do
      for _, stage in ipairs({ -3, -1, 0, 1, 3 }) do
        for _, crit in ipairs({ false, true }) do
          local b = f.reset(item(scenario.item))
          f.hold("enemy", item(scenario.targetItem))
          local user, target = b.player, b.enemy
          user.mon.status, target.mon.status = scenario.status, scenario.targetStatus
          if scenario.pinch then
            user.mon.hp = 100
          end
          if native then
            user.type1, user.type2, target.type1, target.type2 = 0, 0, 0, 0
            user.expTracedAbility, target.expTracedAbility = scenario.ability, scenario.targetAbility
            user.expFlashFire, user.expCharged = scenario.flash, scenario.charged
          else
            user.curTypes, target.curTypes = { "NORMAL" }, { "NORMAL" }
            user.abilityOverride, target.abilityOverride = scenario.ability, scenario.targetAbility
            user.flashFire, user.charged = scenario.flash, scenario.charged
          end
          local attackStat, defenseStat =
            scenario.special and "spAtk" or "attack", scenario.special and "spDef" or "defense"
          if native then
            user.mon[attackStat], target.mon[defenseStat] = stat, 51
            user.stages[attackStat], target.stages[defenseStat] = stage, -stage
          else
            attackStat, defenseStat = attackStat:lower(), defenseStat:lower()
            user.curStats[attackStat], target.curStats[defenseStat] = stat, 51
            user.stages[attackStat], target.stages[defenseStat] = stage, -stage
          end
          user.species, target.species = scenario.species or 4, scenario.targetSpecies or 4
          local trace, reads, draws = {}, 0, {}
          local off = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
            trace[#trace + 1] = {
              holder = ctx.mon.nickname,
              item = ctx.item,
              effect = ctx.effect,
              parameter = ctx.parameter,
              trigger = ctx.trigger,
              definition = ctx.def and ctx.def.id,
              actualBattle = ctx.battle == b,
            }
            if ctx.mon.nickname == "PLAYER" then
              reads = reads + 1
              if scenario.suppress then
                return nil, 0
              end
              if scenario.effect then
                if scenario.stateful and reads % 2 == 0 then
                  return "HELD_CHOICE_BAND", 0
                end
                return scenario.effect, scenario.parameter or 0
              end
            end
            return nextRead(ctx)
          end)
          local function rng(lo, hi)
            draws[#draws + 1] = { lo, hi, hi }
            return hi
          end
          local function calculate()
            if native then
              return require("src.core.game3.battle.damage").calc(user, target, {
                id = "TACKLE",
                numId = 33,
                power = 35,
                type = scenario.electric and 13 or scenario.special and 10 or 0,
                effect = 0,
              }, {
                forceCrit = crit,
                rng = rng,
                adapter = require("src.core.game3.battle.adapter").new(b),
                st = b,
                weather = scenario.weather,
                waterSport = scenario.sport,
                reflect = scenario.screen,
                lightScreen = scenario.screen,
              })
            else
              return b:computeDamage(user, target, {
                id = f.ids.TACKLE,
                index = 33,
                power = 35,
                type = scenario.electric and "ELECTRIC" or scenario.special and "FIRE" or "NORMAL",
                effect = "NO_ADDITIONAL_EFFECT",
                gen3Effect = 0,
              }, {
                forceCrit = crit,
                rng = rng,
                weather = scenario.weather,
                sports = scenario.sport and { "FIRE" } or nil,
                screens = scenario.screen and { reflect = true, lightScreen = true } or nil,
              })
            end
          end
          local damage = calculate()
          local repeated = scenario.stateful and calculate() or nil
          off()
          if scenario.name == "blaze-water-sport" and stat == 257 and stage == 0 and not crit then
            T.eq(damage, 42, "unchanged reference anchor: sport floors before pinch ability")
          end
          T.eq(#trace, scenario.stateful and 4 or 2, "one held read per actor in each GBA base command")
          T.eq(reads, scenario.stateful and 2 or 1, "answers expire before the next native command")
          T.eq(trace[1] and trace[1].holder, "PLAYER", "attacker held read first")
          T.eq(trace[2] and trace[2].holder, "ENEMY", "defender held read second")
          T.eq(#f.result.errors, 0, "public callback errors remain empty")
          rows[#rows + 1] = {
            case = scenario.name,
            stat = stat,
            stage = stage,
            crit = crit,
            damage = damage,
            repeated = repeated,
            trace = trace,
            draws = draws,
            userHp = user.mon.hp,
            targetHp = target.mon.hp,
          }
        end
      end
    end
  end
  f.close()
  return rows
end
return M
