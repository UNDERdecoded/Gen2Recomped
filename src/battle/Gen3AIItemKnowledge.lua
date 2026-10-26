-- Native GBA AI item reads and battle-long observed-effect bytes.
local K = {}
local function emerald()
  return require("src.core.GameVersion").get() == "emerald"
end
local EFFECTS = {}
local i = 0
for name in
  ([[RESTORE_HP CURE_PAR CURE_SLP CURE_PSN CURE_BRN CURE_FRZ RESTORE_PP
CURE_CONFUSION CURE_STATUS CONFUSE_SPICY CONFUSE_DRY CONFUSE_SWEET CONFUSE_BITTER
CONFUSE_SOUR ATTACK_UP DEFENSE_UP SPEED_UP SP_ATTACK_UP SP_DEFENSE_UP CRITICAL_UP
RANDOM_STAT_UP EVASION_UP RESTORE_STATS MACHO_BRACE EXP_SHARE QUICK_CLAW FRIENDSHIP_UP
CURE_ATTRACT CHOICE_BAND FLINCH BUG_POWER DOUBLE_PRIZE REPEL SOUL_DEW DEEP_SEA_TOOTH
DEEP_SEA_SCALE CAN_ALWAYS_RUN PREVENT_EVOLVE FOCUS_BAND LUCKY_EGG SCOPE_LENS STEEL_POWER
LEFTOVERS DRAGON_SCALE LIGHT_BALL GROUND_POWER ROCK_POWER GRASS_POWER DARK_POWER
FIGHTING_POWER ELECTRIC_POWER WATER_POWER FLYING_POWER POISON_POWER ICE_POWER GHOST_POWER
PSYCHIC_POWER FIRE_POWER DRAGON_POWER NORMAL_POWER UP_GRADE SHELL_BELL LUCKY_PUNCH
METAL_POWDER THICK_CLUB STICK]]):gmatch("%S+")
do
  i = i + 1
  EFFECTS[name] = i
end
local function defFor(battle, item)
  local defs = battle.data and battle.data.items or {}
  if defs[item] then
    return defs[item]
  end
  local numeric = tonumber(item)
  if not numeric then
    return nil
  end
  for _, def in pairs(defs) do
    if type(def) == "table" and tonumber(def.index) == numeric then
      return def
    end
  end
end
function K.item(battle, b)
  local value = b and b.mon and (b.mon.item or b.mon.heldItem)
  local def = value and defFor(battle, value)
  return tonumber(def and def.index) or tonumber(value) or 0
end
function K.raw(battle, item)
  if item == 0 then
    return 0
  end
  local def = defFor(battle, item)
  if not def then
    return 0
  end
  return tonumber(def.gen3HoldEffect) or tonumber(def.holdEffect) or EFFECTS[def.holdEffect] or 0
end
function K.record(battle, b, effect)
  if not require("src.core.GameVersion").isGen3() then
    return
  end
  local id = b and b.position
  if id == nil then
    return
  end
  if not emerald() then
    if id % 2 ~= 0 then
      return
    end
    id = 0
  end
  battle._aiHistory = battle._aiHistory or {}
  local h = battle._aiHistory
  h.itemEffects = h.itemEffects or {}
  h.itemEffects[id] = effect
end
function K.observed(battle, b)
  local h = battle._aiHistory
  return tonumber(h and h.itemEffects and b and h.itemEffects[b.position]) or 0
end
function K.get(vm, which)
  local b = which == 1 and vm.user or vm.target
  if not b then
    return 0
  end
  if emerald() then
    local item = b.position == vm.user.position and K.item(vm.battle, b) or K.observed(vm.battle, b)
    return K.raw(vm.battle, item)
  end
  if b.position and b.position % 2 == 0 then
    local h = vm.battle._aiHistory
    return tonumber(h and h.itemEffects and h.itemEffects[0]) or 0
  end
  return K.raw(vm.battle, K.item(vm.battle, b))
end
function K.install(ai)
  ai.OPS.get_hold_effect = function(vm, args)
    vm.result = K.get(vm, args[1])
  end
  ai.OPS.if_holds_item = function(vm, args)
    local b = ai.who(vm, args[1])
    local item = 0
    if b and b.position % 2 == vm.user.position % 2 then
      item = K.item(vm.battle, b)
    else
      item = K.observed(vm.battle, b)
    end
    -- Native retail byte OR, retained instead of inventing a corrected word.
    local value = tonumber(args[2]) or 0
    local bit = require("bit")
    if bit.bor(value % 256, math.floor(value / 256) % 256) == item then
      return args[#args]
    end
  end
end
return K
