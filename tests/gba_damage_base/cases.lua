-- Compare the actual ordinary GBA damage calculators with equal session inputs.
local C = {}
function C.run(backend, version)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local native = backend == "gen1"
  local D = require(native and "src.core.game3.battle.damage" or "src.battle.Damage")
  local rules = not native and require("src.battle.rulesets.gen3_emerald")
  local ids = { NORMAL = 0, GHOST = 7, STEEL = 8, FIRE = 10, WATER = 11, GRASS = 12 }
  local data = {
    items = {},
    constants = { generation = 3 },
    type_chart = {
      types = {},
      matchups = {
        { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
        { attacker = "NORMAL", defender = "STEEL", multiplier = 5 },
      },
    },
  }
  for name, id in pairs(ids) do
    data.type_chart.types[name] = { id = name, index = id, category = id <= 8 and "physical" or "special" }
  end
  if not native then
    require("src.battle.TypeChart").load(data)
  end
  local contexts = {
    { name = "normal-stab" },
    { name = "no-stab", userType = "FIRE" },
    { name = "burn", status = "BRN" },
    { name = "reflect", reflect = true },
    { name = "double-reflect", reflect = true, double = true },
    { name = "spread", spread = true },
    { name = "spread-reflect", spread = true, reflect = true, double = true },
    { name = "resistance", targetType = "STEEL" },
    { name = "immunity", targetType = "GHOST" },
    { name = "rain-fire", moveType = "FIRE", weather = "RAIN" },
    { name = "sun-fire", moveType = "FIRE", weather = "SUN" },
    { name = "rain-water", moveType = "WATER", weather = "RAIN" },
    { name = "sun-water", moveType = "WATER", weather = "SUN" },
    { name = "light-screen", moveType = "FIRE", lightScreen = true },
    { name = "double-light-screen", moveType = "FIRE", lightScreen = true, double = true },
    { name = "rain-solarbeam", moveType = "GRASS", weather = "RAIN", solar = true },
    { name = "sand-solarbeam", moveType = "GRASS", weather = "SAND", solar = true },
    { name = "hail-solarbeam", moveType = "GRASS", weather = "HAIL", solar = true },
  }
  local function battler(level, attack, defense, kind, status)
    if native then
      return {
        mon = {
          level = level,
          hp = 6000,
          maxHp = 6000,
          attack = attack,
          defense = defense,
          spAtk = attack,
          spDef = defense,
          speed = 50,
          ability = 0,
          status = status,
        },
        type1 = ids[kind],
        type2 = ids[kind],
        ability = 0,
        stages = { attack = 0, defense = 0, spAtk = 0, spDef = 0 },
      }
    end
    return {
      mon = { level = level, hp = 6000, status = status },
      curStats = { attack = attack, defense = defense, spatk = attack, spdef = defense, special = attack },
      curTypes = { kind },
      stages = { attack = 0, defense = 0, spatk = 0, spdef = 0 },
    }
  end
  local rows = {}
  for _, ctx in ipairs(contexts) do
    for _, level in ipairs({ 1, 5, 29, 30, 50, 100 }) do
      for _, power in ipairs({ 2, 35, 120, 250 }) do
        for _, stats in ipairs({ { 50, 50 }, { 255, 257 }, { 300, 50 }, { 500, 10 } }) do
          for _, roll in ipairs({ 85, 100 }) do
            local kind = ctx.moveType or "NORMAL"
            local user = battler(level, stats[1], 50, ctx.userType or kind, ctx.status)
            local target = battler(level, 50, stats[2], ctx.targetType or "NORMAL")
            local result
            if native then
              result = D.calc(user, target, {
                id = "PORTABLE_BASE",
                numId = 33,
                power = power,
                type = ids[kind],
                effect = ctx.solar and 151 or 0,
              }, {
                forceCrit = false,
                forceRoll = roll,
                weather = ctx.weather,
                spread = ctx.spread,
                reflect = ctx.reflect,
                lightScreen = ctx.lightScreen,
                doubleScreens = ctx.double,
              })
            else
              result = D.compute(rules, user, target, {
                id = "PORTABLE_BASE",
                power = power,
                type = kind,
                effect = ctx.solar and "SOLARBEAM_EFFECT" or "NO_ADDITIONAL_EFFECT",
                gen3Effect = ctx.solar and 151 or 0,
              }, {
                forceCrit = false,
                data = data,
                rng = function()
                  return roll
                end,
                weather = ctx.weather,
                spread = ctx.spread,
                screens = { reflect = ctx.reflect, lightScreen = ctx.lightScreen },
                doublesScreens = ctx.double,
              })
            end
            T.check(type(result) == "number" and result >= 0, "ordinary damage is nonnegative")
            T.eq(user.mon.hp, 6000, "calculation cannot spend attacker HP")
            T.eq(target.mon.hp, 6000, "calculation cannot spend target HP")
            rows[#rows + 1] = {
              context = ctx.name,
              level = level,
              power = power,
              attack = stats[1],
              defense = stats[2],
              roll = roll,
              damage = result,
            }
          end
        end
      end
    end
  end
  return rows
end
return C
