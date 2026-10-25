-- Native held-effect reads share names; native consumers keep their own enums.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local M = {}
local battles = setmetatable({}, { __mode = "kv" })
local definitions = setmetatable({}, { __mode = "kv" })

function M.bind(battler, battle)
  if battler and battle then
    battles[battler] = battle
  end
  return battler
end

local gold = {
  [0] = "NONE",
  [1] = "BERRY",
  [3] = "LEFTOVERS",
  [6] = "RESTORE_PP",
  [8] = "CLEANSE_TAG",
  [10] = "HEAL_POISON",
  [11] = "HEAL_FREEZE",
  [12] = "HEAL_BURN",
  [13] = "HEAL_SLEEP",
  [14] = "HEAL_PARALYZE",
  [15] = "HEAL_STATUS",
  [16] = "HEAL_CONFUSION",
  [42] = "METAL_POWDER",
  [50] = "NORMAL_BOOST",
  [51] = "FIGHTING_BOOST",
  [52] = "FLYING_BOOST",
  [53] = "POISON_BOOST",
  [54] = "GROUND_BOOST",
  [55] = "ROCK_BOOST",
  [56] = "BUG_BOOST",
  [57] = "GHOST_BOOST",
  [58] = "FIRE_BOOST",
  [59] = "WATER_BOOST",
  [60] = "GRASS_BOOST",
  [61] = "ELECTRIC_BOOST",
  [62] = "PSYCHIC_BOOST",
  [63] = "ICE_BOOST",
  [64] = "DRAGON_BOOST",
  [65] = "DARK_BOOST",
  [66] = "STEEL_BOOST",
  [72] = "ESCAPE",
  [73] = "CRITICAL_UP",
  [74] = "QUICK_CLAW",
  [75] = "FLINCH",
  [76] = "AMULET_COIN",
  [77] = "BRIGHTPOWDER",
  [79] = "FOCUS_BAND",
  -- A public substitution, not a fabricated cartridge enum or saved item ID.
  PREVENT_CONFUSE = "PREVENT_CONFUSE",
}
local goldIds = {}
for id, name in pairs(gold) do
  gold[id] = "HELD_" .. name
  goldIds[gold[id]] = id
end
function M.goldNative(name)
  return goldIds[name] or name
end
function M.writeDefinition(view, key, value)
  view[key] = value
  local def = definitions[view]
  if not def then
    return
  end
  if key == "heldEffect" then
    def.heldEffect = M.goldNative(value)
  elseif key == "heldParameter" then
    def.heldParam = value
  else
    def[key] = value
  end
end

local gba = {
  RESTORE_HP = "BERRY",
  CURE_PAR = "HEAL_PARALYZE",
  CURE_SLP = "HEAL_SLEEP",
  CURE_PSN = "HEAL_POISON",
  CURE_BRN = "HEAL_BURN",
  CURE_FRZ = "HEAL_FREEZE",
  CURE_CONFUSION = "HEAL_CONFUSION",
  CURE_STATUS = "HEAL_STATUS",
  CRITICAL_UP = "PINCH_CRITICAL_UP",
  SCOPE_LENS = "CRITICAL_UP",
  EVASION_UP = "BRIGHTPOWDER",
  DOUBLE_PRIZE = "AMULET_COIN",
  REPEL = "CLEANSE_TAG",
  CAN_ALWAYS_RUN = "ESCAPE",
}
local gbaNames = [[
RESTORE_HP CURE_PAR CURE_SLP CURE_PSN CURE_BRN CURE_FRZ RESTORE_PP CURE_CONFUSION CURE_STATUS
CONFUSE_SPICY CONFUSE_DRY CONFUSE_SWEET CONFUSE_BITTER CONFUSE_SOUR ATTACK_UP DEFENSE_UP
SPEED_UP SP_ATTACK_UP SP_DEFENSE_UP CRITICAL_UP RANDOM_STAT_UP EVASION_UP RESTORE_STATS
MACHO_BRACE EXP_SHARE QUICK_CLAW FRIENDSHIP_UP CURE_ATTRACT CHOICE_BAND FLINCH BUG_POWER
DOUBLE_PRIZE REPEL SOUL_DEW DEEP_SEA_TOOTH DEEP_SEA_SCALE CAN_ALWAYS_RUN PREVENT_EVOLVE
FOCUS_BAND LUCKY_EGG SCOPE_LENS STEEL_POWER LEFTOVERS DRAGON_SCALE LIGHT_BALL GROUND_POWER
ROCK_POWER GRASS_POWER DARK_POWER FIGHTING_POWER ELECTRIC_POWER WATER_POWER FLYING_POWER
POISON_POWER ICE_POWER GHOST_POWER PSYCHIC_POWER FIRE_POWER DRAGON_POWER NORMAL_POWER
UP_GRADE SHELL_BELL LUCKY_PUNCH METAL_POWDER THICK_CLUB STICK
]]
local gbaIds = {}
for name in gbaNames:gmatch("%S+") do
  local public = "HELD_" .. (gba[name] or name:gsub("_POWER$", "_BOOST"))
  gba[name], gbaIds[public] = public, name
end
local byteChance = { QUICK_CLAW = true, EVASION_UP = true, FOCUS_BAND = true, FLINCH = true }

function M.read(holder, def, effect, parameter, trigger, generation)
  -- Field/party item scans and other generations do not acquire a battle hook.
  if
    not (holder and holder.mon)
    or Version.generation() ~= generation
    or not Runtime.wantsHook("held_item.trigger")
  then
    return effect, parameter
  end
  local names = generation == 2 and gold or gba
  local ids = generation == 2 and goldIds or gbaIds
  local public = names[effect]
  if generation == 2 then
    if not def then
      public = nil
    elseif type(effect) == "string" and not public then
      public = effect
    end
  end
  local value = parameter
  if generation == 3 and byteChance[effect] then
    value = math.floor(value * 256 / 100)
  end
  local item = holder.mon.item or holder.mon.heldItem
  if generation == 3 and item == nil then item = 0 end
  local view
  if def then
    view = {}
    for k, v in pairs(def) do
      view[k] = v
    end
    view.id, view.heldEffect, view.heldParameter = item, public, value
    if generation == 2 then
      definitions[view] = def
    end
  end
  local before = {}
  for k, v in pairs(view or {}) do
    before[k] = v
  end
  local chosen, amount = Runtime.call("held_item.trigger", function(ctx)
    return ctx.effect, ctx.parameter
  end, {
    battle = battles[holder],
    mon = holder.mon,
    item = item,
    def = view,
    effect = public,
    parameter = value,
    trigger = trigger or "check",
  })
  -- API-3 commits write at next/return boundaries. Legacy native callbacks
  -- write the temporary view directly; settle their scalar metadata here.
  if view then
    local keys = {}
    for k in pairs(before) do
      keys[k] = true
    end
    for k in pairs(view) do
      keys[k] = true
    end
    for k in pairs(keys) do
      if view[k] ~= before[k] and type(view[k]) ~= "function" and type(view[k]) ~= "table" then
        M.writeDefinition(view, k, view[k])
      end
    end
  end
  if type(chosen) ~= "string" then
    return generation == 2 and 0 or nil, 0, true
  end
  amount = tonumber(amount) or value
  if chosen == public and amount == value then
    return effect, parameter, false
  end
  local native = ids[chosen] or (generation == 2 and chosen or nil)
  if not native then
    return generation == 2 and 0 or nil, amount, true
  end
  if generation == 3 and byteChance[native] then
    amount = math.max(0, math.min(256, amount)) * 100 / 256
  end
  return native, amount, true
end
return M
