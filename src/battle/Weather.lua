-- Gen 2 battle weather: Rain Dance, Sunny Day and Sandstorm -- the state
-- they set, the damage modifiers they apply, and the end-of-turn upkeep.
--
-- Ported from engine/battle/move_effects/{rain_dance,sunny_day,sandstorm}.asm,
-- engine/battle/core.asm HandleWeather (:1685-1782), engine/battle/misc.asm
-- DoWeatherModifiers (:52-142) and data/battle/weather_modifiers.asm.  Gold,
-- Silver and Crystal are identical here: both trees carry the same four
-- WeatherTypeModifiers rows, the same single WeatherMoveModifiers row, the
-- same 5-turn count and the same message tables.
--
-- Gen 1 has no weather at all, and this file needs no version test to say so:
-- RAIN_DANCE_EFFECT / SUNNY_DAY_EFFECT / SANDSTORM_EFFECT are effect names
-- only the Gen 2 extractor emits, so on a Gen 1 cache nothing ever calls
-- Weather.start and every other entry point is a nil check on
-- battle.field.weather.

local Strings = require("src.core.Strings")

local Weather = {}

-- wBattleWeather values (constants/battle_constants.asm: WEATHER_NONE 0,
-- WEATHER_RAIN 1, WEATHER_SUN 2, WEATHER_SANDSTORM 3).  The port stores the
-- name rather than the byte because battle.field.weather is the documented
-- mod-facing slot.
Weather.RAIN = "RAIN"
Weather.SUN = "SUN"
Weather.SANDSTORM = "SANDSTORM"

-- `ld a, 5 / ld [wWeatherCount], a`.  HandleWeather decrements at the end of
-- the SAME turn the move landed, so five upkeeps run in total and the first
-- "Rain continues to fall." prints on the turn Rain Dance was used -- that is
-- the cartridge's behaviour, not a double-tick.
Weather.TURNS = 5

-- MORE_EFFECTIVE = 15, NOT_VERY_EFFECTIVE = 5 (constants/battle_constants.asm),
-- applied as damage * modifier / 10 (.ApplyModifier sets hDivisor = 10).
local MORE, LESS = 15, 5

-- WeatherTypeModifiers: (weather, move type) -> modifier
local TYPE_MODIFIERS = {
  RAIN = { WATER = MORE, FIRE = LESS },
  SUN  = { FIRE = MORE, WATER = LESS },
}

-- WeatherMoveModifiers: (weather, move effect) -> modifier.  Exactly one row
-- ships in the retail games -- Solar Beam is halved in rain.  Sandstorm does
-- NOT halve it; that is a later generation's rule.
local MOVE_MODIFIERS = {
  RAIN = { SOLARBEAM_EFFECT = LESS },
}

-- .WeatherMessages / .WeatherEndedMessages (core.asm:1770-1782), wording from
-- data/text/battle.asm BattleText_*.
local CONTINUE_TEXT = {
  RAIN = "Rain continues to\nfall.",
  SUN = "The sunlight is\nstrong.",
  SANDSTORM = "The SANDSTORM\nrages.",
}
local ENDED_TEXT = {
  RAIN = "The rain stopped.",
  SUN = "The sunlight\nfaded.",
  SANDSTORM = "The SANDSTORM\nsubsided.",
}

-- the text each move prints when it lands (DownpourText / SunGotBrightText /
-- SandstormBrewedText)
Weather.STARTED_TEXT = {
  RAIN = "A downpour\nstarted!",
  SUN = "The sunlight got\nbright!",
  SANDSTORM = "A SANDSTORM\nbrewed!",
}

-- ---------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------

-- battle.field.weather is the slot newBattle already allocates; weatherTurns
-- is wWeatherCount alongside it.
function Weather.current(battle)
  local field = battle and battle.field
  return field and field.weather or nil
end

function Weather.turnsLeft(battle)
  local field = battle and battle.field
  return field and field.weatherTurns or 0
end

function Weather.start(battle, id)
  local field = battle and battle.field
  if not field then return false end
  field.weather = id
  field.weatherTurns = Weather.TURNS
  return true
end

function Weather.clear(battle)
  local field = battle and battle.field
  if not field then return end
  field.weather, field.weatherTurns = nil, nil
end

-- ---------------------------------------------------------------------
-- damage modifiers
-- ---------------------------------------------------------------------

-- DoWeatherModifiers walks WeatherTypeModifiers first and jumps straight to
-- .ApplyModifier on a hit, which falls through to `ret` -- so the FIRST
-- matching row wins and a type match is never compounded with a move match.
function Weather.modifier(weather, moveType, moveEffect)
  if not weather then return nil end
  local byType = TYPE_MODIFIERS[weather]
  if byType and moveType and byType[moveType] then
    return byType[moveType]
  end
  local byMove = MOVE_MODIFIERS[weather]
  if byMove and moveEffect and byMove[moveEffect] then
    return byMove[moveEffect]
  end
  return nil
end

-- .ApplyModifier: wCurDamage * modifier / 10, clamped to $ffff when the
-- 16-bit quotient overflows and floored at 1 -- a weather modifier can never
-- zero a hit that had damage.
function Weather.applyModifier(damage, weather, moveType, moveEffect)
  local m = Weather.modifier(weather, moveType, moveEffect)
  if not m then return damage end
  local out = math.floor(damage * m / 10)
  if out > 0xFFFF then return 0xFFFF end
  if out < 1 then return 1 end
  return out
end

-- ---------------------------------------------------------------------
-- move interactions outside the damage formula
-- ---------------------------------------------------------------------

-- BattleCommand_SkipSunCharge (effect_commands.asm:6535): in sun, Solar Beam
-- skips straight past `charge` and fires the turn it is selected.
function Weather.skipsCharge(battle, record)
  local charge = record and record.charge
  if not (charge and charge.skipInSun) then return false end
  return Weather.current(battle) == Weather.SUN
end

-- CheckHit .ThunderRain (effect_commands.asm:1741-1749): Thunder always hits
-- in rain.
function Weather.alwaysHits(battle, moveEffect)
  return moveEffect == "THUNDER_EFFECT"
     and Weather.current(battle) == Weather.RAIN
end

-- BattleCommand_ThunderAccuracy (move_effects/thunder.asm) overwrites the
-- move's accuracy BYTE, so the port returns the raw 0-255 threshold rather
-- than a percentage: `50 percent + 1` is 128, not floor(50 * 255 / 100) = 127.
function Weather.thunderAccuracyRaw(battle)
  local weather = Weather.current(battle)
  if weather == Weather.RAIN then return 255 end   -- 100 percent
  if weather == Weather.SUN then return 128 end    -- 50 percent + 1
  return nil                                       -- the move's own accuracy
end

-- BattleCommand_TimeBasedHealContinue (effect_commands.asm:6419-6499).
-- .Multipliers is indexed 0..3 = eighth / quarter / half / max, starting at 2
-- (half).  A time of day that does not match the move drops the index by one;
-- then sun raises it by one and rain or sandstorm lowers it by one.  Link
-- battles skip the time-of-day step entirely.
local HEAL_TIME = {
  MORNING_SUN_EFFECT = "MORNING",
  SYNTHESIS_EFFECT = "DAY",
  MOONLIGHT_EFFECT = "NITE",
}
local HEAL_DIVISOR = { [0] = 8, [1] = 4, [2] = 2, [3] = 1 }

-- the port's clock says MORNING / DAY / NITE; a mod's world.tod hook may say
-- NIGHT, so both spellings map onto the ROM's NITE row.
local TOD_ALIAS = { NIGHT = "NITE", MORN = "MORNING" }

function Weather.healDivisor(battle, moveEffect)
  local want = HEAL_TIME[moveEffect]
  local index = 2
  if want then
    local tod
    local game = battle and battle.game
    local ow = game and game.overworld
    if battle and battle.kind ~= "link" and ow and ow.timeOfDay then
      local ok, value = pcall(ow.timeOfDay, ow)
      if ok then tod = value end
    end
    -- with no clock to read (or a link battle) the ROM's `jr z, .Weather`
    -- path is the one taken: treat the time as matching
    if tod then
      tod = TOD_ALIAS[tod] or tod
      if tod ~= want then index = index - 1 end
    end
  end
  local weather = Weather.current(battle)
  if weather == Weather.SUN then
    index = index + 1
  elseif weather then
    index = index - 1
  end
  if index < 0 then index = 0 elseif index > 3 then index = 3 end
  return HEAL_DIVISOR[index]
end

-- ---------------------------------------------------------------------
-- end-of-turn upkeep
-- ---------------------------------------------------------------------

local SANDSTORM_IMMUNE = { ROCK = true, GROUND = true, STEEL = true }

-- .SandstormDamage checks SUBSTATUS_UNDERGROUND, which only Dig sets -- a mon
-- part-way through Fly still eats the sandstorm.  performMove parks the
-- charging move instance on the battler, so its id is the test.
local function underground(battler)
  local charging = battler.charging
  return charging ~= nil and charging.id == "DIG"
end

-- pokered/pokecrystal's <USER> macro prints "Enemy " before the foe's nickname
local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end

local function maxHpOf(battler)
  local mon = battler.mon
  return (mon.stats and mon.stats.hp) or mon.maxHp or 8
end

local function sandstormDamage(battle, battler)
  if not (battler and battler.mon) or battler.mon.hp <= 0 then return end
  if underground(battler) then return end
  for _, t in ipairs(battler.curTypes or {}) do
    if SANDSTORM_IMMUNE[t] then return end
  end
  battle:animNext("inSandstorm", battler.isPlayer)
  -- GetEighthMaxHP is GetQuarterMaxHP followed by one more shift, each step
  -- floored at 1: floor(floor(maxHP / 4) / 2), minimum 1
  local eighth = math.max(1, math.floor(math.floor(maxHpOf(battler) / 4) / 2))
  battle:applyDamage(battler, eighth)
  battle:sayNext(Strings("The SANDSTORM hits\n%s!", displayName(battler)))
  battle:drainNext()
  if battler.mon.hp <= 0 then battle:onFaint(battler) end
end

-- HandleWeather, called once per turn from HandleBetweenTurnEffects after
-- HandleFutureSight and before HandleWrap.  The count is decremented first:
-- on zero the "ended" line prints and NO sandstorm damage is dealt.
function Weather.upkeep(battle)
  local field = battle and battle.field
  local weather = field and field.weather
  if not weather then return end

  local count = (field.weatherTurns or 1) - 1
  field.weatherTurns = count
  if count <= 0 then
    battle:sayNext(Strings(ENDED_TEXT[weather] or "The weather cleared."))
    field.weather, field.weatherTurns = nil, nil
    return
  end

  local line = CONTINUE_TEXT[weather]
  if line then battle:sayNext(Strings(line)) end
  if weather ~= Weather.SANDSTORM then return end

  -- HandleWeather damages the player's side first and the enemy's second.
  -- That order is the serial-connection one (hSerialConnectionStatus), not a
  -- speed check, so a single-player battle is always player-then-enemy.
  sandstormDamage(battle, battle.player)
  sandstormDamage(battle, battle.enemy)
end

return Weather
