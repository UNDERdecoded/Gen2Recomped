-- Native GBA speed arithmetic and GetWhoStrikesFirst result codes.
local C = {}
local bit = require("bit")
local ratios = {
  { 10, 40 },
  { 10, 35 },
  { 10, 30 },
  { 10, 25 },
  { 10, 20 },
  { 10, 15 },
  { 10, 10 },
  { 15, 10 },
  { 20, 10 },
  { 25, 10 },
  { 30, 10 },
  { 35, 10 },
  { 40, 10 },
}
C.effectNames, C.effectIds = {}, {}
for name in
  ([[RESTORE_HP CURE_PAR CURE_SLP CURE_PSN CURE_BRN CURE_FRZ RESTORE_PP CURE_CONFUSION CURE_STATUS CONFUSE_SPICY CONFUSE_DRY CONFUSE_SWEET CONFUSE_BITTER CONFUSE_SOUR ATTACK_UP DEFENSE_UP SPEED_UP SP_ATTACK_UP SP_DEFENSE_UP CRITICAL_UP RANDOM_STAT_UP EVASION_UP RESTORE_STATS MACHO_BRACE EXP_SHARE QUICK_CLAW FRIENDSHIP_UP CURE_ATTRACT CHOICE_BAND FLINCH BUG_POWER DOUBLE_PRIZE REPEL SOUL_DEW DEEP_SEA_TOOTH DEEP_SEA_SCALE CAN_ALWAYS_RUN PREVENT_EVOLVE FOCUS_BAND LUCKY_EGG SCOPE_LENS STEEL_POWER LEFTOVERS DRAGON_SCALE LIGHT_BALL GROUND_POWER ROCK_POWER GRASS_POWER DARK_POWER FIGHTING_POWER ELECTRIC_POWER WATER_POWER FLYING_POWER POISON_POWER ICE_POWER GHOST_POWER PSYCHIC_POWER FIRE_POWER DRAGON_POWER NORMAL_POWER UP_GRADE SHELL_BELL LUCKY_PUNCH METAL_POWDER THICK_CLUB STICK]]):gmatch(
    "%S+"
  )
do
  C.effectNames[#C.effectNames + 1] = name
  C.effectIds[name] = #C.effectNames
end
function C.weather(value)
  if type(value) == "number" then
    return value
  end
  value = tostring(value or ""):upper()
  if value == "RAIN" or value == "RAINY" or value == "DOWNPOUR" then
    return 7
  end
  if value == "SUN" or value == "SUNNY" or value == "HARSH_SUN" then
    return 0x60
  end
  return 0
end
function C.paralysed(value)
  if type(value) == "number" then
    return bit.band(value, 64) ~= 0
  end
  return value == "PAR" or value == "PARALYSIS"
end
function C.speed(v, field, adjust)
  local mul = field.weatherActive
      and ((v.ability == 33 and bit.band(field.weather, 7) ~= 0) or (v.ability == 34 and bit.band(
        field.weather,
        0x60
      ) ~= 0))
      and 2
    or 1
  local ratio = ratios[math.max(1, math.min(13, math.floor(v.stage or 0) + 7))]
  local value = math.floor((math.floor(v.speed or 0) % 65536) * mul * ratio[1] / ratio[2])
  local noBadge = field.link or field.emerald and (field.frontier or field.recordedLink)
  if v.player and field.badge and not noBadge then
    value = math.floor(value * 110 / 100)
  end
  if v.effect == 24 then
    value = math.floor(value / 2)
  end
  if C.paralysed(v.status) then
    value = math.floor(value / 4)
  end
  if adjust then
    value = adjust(value)
  end
  if v.effect == 26 and field.turnWord < math.floor(65535 * (v.parameter or 0) / 100) then
    value = 4294967295
  end
  return value
end
function C.result(a, b, draw)
  if a < b then
    return 1
  end
  if a > b then
    return 0
  end
  return math.floor(draw()) % 2 == 1 and 2 or 0
end
return C
