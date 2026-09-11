-- HELD ITEMS IN BATTLE, which is the other half of what Hoenn added and
-- Kanto did not have.
--
-- gItems[i].holdEffect and holdEffectParam have been extracted correctly
-- since the item stage landed and were read by NOTHING: a LEFTOVERS healed
-- no one, a CHOICE BAND hit no harder, a QUICK CLAW never moved first, every
-- berry sat in its slot for the whole battle, and the eight type-boosting
-- trinkets a gym leader hands out did nothing at all.  70 of the cartridge's
-- 377 items carry one.
--
-- THE SHAPE IS ABILITIES' SHAPE, deliberately.  Everything here returns a
-- plain DESCRIPTION -- what should happen, and to whom -- and BattleState
-- spends it on the message queue, the HP bars and the stat stages.  Nothing
-- in this file touches the queue, which is what lets the whole of it be
-- tested without a battle.
--
-- HOW AN ITEM IS FOUND.  A battler carries `items` (the merged item table,
-- put there by makeBattler beside `statuses`) and `mon.item` is the id.  The
-- lookup is deliberately per-call rather than resolved once at construction:
-- a berry is EATEN mid-battle, and a battler holding a stale def would go on
-- healing from a berry it swallowed three turns ago.
--
-- A Gen 1 or Gen 2 battler has no `items` view, and every entry point here
-- answers nil for it, so none of this reaches an older cartridge.

local HoldItems = {}

-- gTypeNames' short spellings; the same normalizer Abilities keeps, and for
-- the same reason -- a table written against ELECTRIC matches nothing here.
local function normalizeType(name)
  return require("src.battle.Abilities").normalizeType(name)
end

-- The item def a battler is holding, or nil.  `mon.item` is the field the
-- bag and every menu use; `mon.heldItem` is what one script path (giveegg)
-- writes, and both are accepted here the way awardExp already accepts both.
function HoldItems.defOf(battler)
  if type(battler) ~= "table" then return nil end
  local mon = battler.mon
  local id = mon and (mon.item or mon.heldItem)
  if not id then return nil end
  local items = battler.items
  local def = items and items[id]
  if type(def) ~= "table" then return nil end
  return def, id
end

-- The named effect and its parameter, or nil.  An effect the extractor had
-- no name for comes back as a number and matches no rule below, which is
-- the same silence an unknown ability gets.
function HoldItems.effectOf(battler)
  local def = HoldItems.defOf(battler)
  if not def then return nil end
  local effect = def.holdEffect
  if type(effect) ~= "string" then return nil end
  return effect, tonumber(def.holdEffectParam) or 0, def
end

HoldItems.effect = HoldItems.effectOf

local function speciesOf(battler)
  local mon = battler and battler.mon
  return mon and mon.species
end

local function maxHpOf(battler)
  local mon = battler and battler.mon
  if not mon then return 1 end
  return (mon.stats and mon.stats.hp) or mon.maxHp or 1
end

-- ---------------------------------------------------------------------
-- THE STAT MULTIPLIERS
-- ---------------------------------------------------------------------
--
-- Six of the seven are species-locked, which is the whole point of them: a
-- THICK CLUB in anybody else's hands is a rock.  The species list is part of
-- the rule, so it lives with the rule.
local SPECIES_STAT = {
  THICK_CLUB   = { species = { CUBONE = true, MAROWAK = true },
                   stat = "attack", num = 2, den = 1 },
  LIGHT_BALL   = { species = { PIKACHU = true },
                   stat = "spatk", num = 2, den = 1 },
  DEEP_SEA_TOOTH = { species = { CLAMPERL = true },
                     stat = "spatk", num = 2, den = 1 },
  DEEP_SEA_SCALE = { species = { CLAMPERL = true },
                     stat = "spdef", num = 2, den = 1 },
  METAL_POWDER = { species = { DITTO = true },
                   stat = "defense", num = 2, den = 1 },
}

-- SOUL DEW raises BOTH special halves, so it does not fit the one-stat row
-- above and gets its own line below.
local SOUL_DEW_SPECIES = { LATIAS = true, LATIOS = true }

-- The attacker's item, as a numerator/denominator pair so the caller keeps
-- the cartridge's integer arithmetic.  `special` says which attacking stat
-- is being multiplied, because a CHOICE BAND is physical and a LIGHT BALL is
-- not.
function HoldItems.attackMultiplier(attacker, move, special)
  local effect = HoldItems.effectOf(attacker)
  if not effect then return 1, 1 end
  -- CHOICE BAND: half again as much, physical only
  if effect == "CHOICE_BAND" and not special then return 3, 2 end
  local row = SPECIES_STAT[effect]
  if row and row.species[speciesOf(attacker)] then
    if row.stat == "attack" and not special then return row.num, row.den end
    if row.stat == "spatk" and special then return row.num, row.den end
  end
  if effect == "SOUL_DEW" and special
     and SOUL_DEW_SPECIES[speciesOf(attacker)] then
    return 3, 2
  end
  return 1, 1
end

-- ...and the defender's, on the defending stat
function HoldItems.defenceMultiplier(defender, move, special)
  local effect = HoldItems.effectOf(defender)
  if not effect then return 1, 1 end
  local row = SPECIES_STAT[effect]
  if row and row.species[speciesOf(defender)] then
    if row.stat == "defense" and not special then return row.num, row.den end
    if row.stat == "spdef" and special then return row.num, row.den end
  end
  if effect == "SOUL_DEW" and special
     and SOUL_DEW_SPECIES[speciesOf(defender)] then
    return 3, 2
  end
  return 1, 1
end

-- ---------------------------------------------------------------------
-- THE TYPE BOOSTERS
-- ---------------------------------------------------------------------
--
-- Sixteen trinkets, one per type, and each raises a move of its type by its
-- own parameter -- 10 percent for the plain ones (CHARCOAL, MAGNET, the
-- badge-shop family) and 5 for the two INCENSEs, which is why the number
-- comes off the item and is not assumed.
local TYPE_POWER = {
  BUG_POWER = "BUG", STEEL_POWER = "STEEL", GROUND_POWER = "GROUND",
  ROCK_POWER = "ROCK", GRASS_POWER = "GRASS", DARK_POWER = "DARK",
  FIGHTING_POWER = "FIGHTING", ELECTRIC_POWER = "ELECTRIC",
  WATER_POWER = "WATER", FLYING_POWER = "FLYING", POISON_POWER = "POISON",
  ICE_POWER = "ICE", GHOST_POWER = "GHOST", PSYCHIC_POWER = "PSYCHIC",
  FIRE_POWER = "FIRE", DRAGON_POWER = "DRAGON", NORMAL_POWER = "NORMAL",
}

HoldItems.TYPE_POWER = TYPE_POWER

-- Applied to the FINISHED damage, the way the cartridge applies it: as
-- damage * (100 + param) / 100.
function HoldItems.damageMultiplier(attacker, move)
  local effect, param = HoldItems.effectOf(attacker)
  if not (effect and move) then return 1, 1 end
  local boostedType = TYPE_POWER[effect]
  if boostedType and boostedType == normalizeType(move.type) then
    return 100 + (param or 0), 100
  end
  return 1, 1
end

-- ---------------------------------------------------------------------
-- ACCURACY, CRITICALS AND TURN ORDER
-- ---------------------------------------------------------------------

-- BRIGHTPOWDER and LAX INCENSE, on the DEFENDER: the attacker's accuracy
-- falls by the item's own parameter (10 and 5).  Returned as a percentage
-- multiplier so it composes with COMPOUNDEYES and HUSTLE.
function HoldItems.accuracyMultiplier(attacker, defender)
  local effect, param = HoldItems.effectOf(defender)
  if effect == "EVASION_UP" then return 100 - (param or 0) end
  return 100
end

-- SCOPE LENS is +1 crit stage for anybody; LUCKY PUNCH and STICK are +2 and
-- species-locked, and are dead weight on anything else.
local CRIT_SPECIES = {
  LUCKY_PUNCH = { CHANSEY = true },
  STICK = { FARFETCH_D = true, FARFETCHD = true },
}

function HoldItems.critStages(battler)
  local effect = HoldItems.effectOf(battler)
  if not effect then return 0 end
  if effect == "SCOPE_LENS" then return 1 end
  local list = CRIT_SPECIES[effect]
  if list and list[speciesOf(battler)] then return 2 end
  return 0
end

-- QUICK CLAW: a `param` percent chance to move first regardless of speed.
-- Rolled once per turn per holder, before the speed comparison.
function HoldItems.quickClawChance(battler)
  local effect, param = HoldItems.effectOf(battler)
  if effect ~= "QUICK_CLAW" then return 0 end
  return param or 0
end

-- KING'S ROCK: a `param` percent chance to flinch the target, and only on a
-- move the cartridge marks KING'S ROCK affected -- which is the second thing
-- the flags byte had to be extracted for.
function HoldItems.flinchChance(attacker, move)
  local effect, param = HoldItems.effectOf(attacker)
  if effect ~= "FLINCH" then return 0 end
  if move and move.kingsRockAffected == false then return 0 end
  return param or 0
end

-- FOCUS BAND: a `param` percent chance to be left standing on one HP by a
-- hit that would otherwise knock the holder out.
function HoldItems.focusBandChance(battler)
  local effect, param = HoldItems.effectOf(battler)
  if effect ~= "FOCUS_BAND" then return 0 end
  return param or 0
end

-- SHELL BELL: the attacker takes back a `param`th of the damage it dealt.
function HoldItems.shellBellShare(attacker)
  local effect, param = HoldItems.effectOf(attacker)
  if effect ~= "SHELL_BELL" then return nil end
  if not param or param <= 0 then return nil end
  return param
end

-- ---------------------------------------------------------------------
-- THE BERRIES, AND LEFTOVERS
-- ---------------------------------------------------------------------
--
-- Everything below is checked at the end of a turn (and, for the HP ones,
-- again the moment a hit lands, which is what makes a SITRUS BERRY worth
-- holding).  Each returns a description carrying `consume = true` when the
-- item is eaten, which almost all of them are -- LEFTOVERS is the exception
-- and is why the flag is not simply assumed.

local CURE_STATUS = {
  CURE_PAR = "PAR", CURE_SLP = "SLP", CURE_PSN = "PSN",
  CURE_BRN = "BRN", CURE_FRZ = "FRZ",
}

HoldItems.CURE_STATUS = CURE_STATUS

-- The stat each pinch berry raises, and the flavour each confusing berry
-- carries.  A CONFUSE_* berry heals and then confuses the holder if its
-- NATURE dislikes the flavour -- and the flavour maps onto the stat the
-- nature LOWERS, which the extractor already writes on every nature record.
-- Deriving it that way rather than listing twenty natures by hand means a
-- dataset whose nature table says otherwise is believed.
local PINCH_STAT = {
  ATTACK_UP = "attack", DEFENSE_UP = "defense", SPEED_UP = "speed",
  SP_ATTACK_UP = "spatk", SP_DEFENSE_UP = "spdef",
}
local FLAVOUR_STAT = {
  CONFUSE_SPICY = "attack", CONFUSE_DRY = "spatk", CONFUSE_SWEET = "speed",
  CONFUSE_BITTER = "spdef", CONFUSE_SOUR = "defense",
}

HoldItems.PINCH_STAT = PINCH_STAT
HoldItems.FLAVOUR_STAT = FLAVOUR_STAT

-- Does this battler's nature dislike the flavour that maps onto `stat`?
-- The nature record's `lowers` is the whole answer.
function HoldItems.dislikesFlavour(battler, stat)
  local mon = battler and battler.mon
  local natures = battler and battler.natures
  local record = natures and mon and natures[mon.nature]
  if type(record) ~= "table" then return false end
  return record.lowers == stat
end

-- ONE PLACE THAT ASKS "should this item go off now".  `when` is "hit" (a
-- move has just landed on the holder) or "turn" (end of turn); the HP
-- berries answer to both, the status ones only to the end of a turn, which
-- is the cartridge's own split.
--
-- Descriptions returned:
--   { kind = "heal", amount = n }                     RESTORE_HP, LEFTOVERS
--   { kind = "heal", amount = n, confuse = true }     the five flavours
--   { kind = "cure", status = "PAR" }                 the five cures
--   { kind = "cure", status = "ALL" }                 LUM BERRY
--   { kind = "cureConfusion" }                        PERSIM BERRY
--   { kind = "statUp", stat = "attack", delta = 1 }   the five pinch berries
--   { kind = "statUp", stat = nil, delta = 2 }        STARF (caller rolls)
--   { kind = "critUp", delta = 2 }                    LANSAT BERRY
--   { kind = "restoreStats" }                         WHITE HERB
function HoldItems.trigger(battler, when)
  local effect, param = HoldItems.effectOf(battler)
  if not effect then return nil end
  local mon = battler.mon
  if not mon or (mon.hp or 0) <= 0 then return nil end
  local max = maxHpOf(battler)

  -- LEFTOVERS, the one that is never eaten.  Its parameter is 10 and it is
  -- NOT a percentage: ItemBattleEffects' LEFTOVERS arm reads maxHP / 16 and
  -- never looks at the param at all (the byte is shared machinery and is
  -- dead weight for this effect).  Trusting it would have healed a tenth
  -- instead of a sixteenth, which is a difference nothing would ever have
  -- flagged as a bug.
  if effect == "LEFTOVERS" then
    if when ~= "turn" then return nil end
    if mon.hp >= max then return nil end
    return { kind = "heal", effect = effect,
             amount = math.max(1, math.floor(max / 16)), consume = false }
  end

  -- ORAN / SITRUS / BERRY JUICE: a flat number of HP at half health or less
  if effect == "RESTORE_HP" then
    if mon.hp * 2 > max then return nil end
    if mon.hp >= max then return nil end
    return { kind = "heal", effect = effect, amount = math.max(1, param),
             consume = true }
  end

  -- FIGY and the other four: a fraction at half health, and confusion after
  -- it if the holder's nature dislikes the flavour
  local flavourStat = FLAVOUR_STAT[effect]
  if flavourStat then
    if mon.hp * 2 > max then return nil end
    if mon.hp >= max then return nil end
    return { kind = "heal", effect = effect,
             amount = math.max(1, math.floor(max / (param > 0 and param or 8))),
             confuse = HoldItems.dislikesFlavour(battler, flavourStat),
             consume = true }
  end

  if effect == "RESTORE_PP" then
    if when ~= "turn" then return nil end
    -- the caller finds the empty move; nil here means every move has PP
    local slot
    for i, m in ipairs(battler.curMoves or mon.moves or {}) do
      if (m.pp or 1) <= 0 then slot = i break end
    end
    if not slot then return nil end
    return { kind = "restorePP", effect = effect, slot = slot,
             amount = math.max(1, param), consume = true }
  end

  if when ~= "turn" then return nil end

  local cured = CURE_STATUS[effect]
  if cured then
    if mon.status ~= cured then return nil end
    return { kind = "cure", effect = effect, status = cured, consume = true }
  end
  if effect == "CURE_STATUS" then
    if not (mon.status or battler.confusedTurns) then return nil end
    return { kind = "cure", effect = effect, status = "ALL", consume = true }
  end
  if effect == "CURE_CONFUSION" then
    if not battler.confusedTurns then return nil end
    return { kind = "cureConfusion", effect = effect, consume = true }
  end
  if effect == "CURE_ATTRACT" then
    if not battler.infatuated then return nil end
    return { kind = "cureAttract", effect = effect, consume = true }
  end

  -- WHITE HERB: any stat below its starting stage comes back
  if effect == "RESTORE_STATS" then
    local lowered = false
    for _, v in pairs(battler.stages or {}) do
      if v < 0 then lowered = true break end
    end
    if not lowered then return nil end
    return { kind = "restoreStats", effect = effect, consume = true }
  end

  -- the pinch berries, at a quarter of maximum HP or less
  local pinchStat = PINCH_STAT[effect]
  local divisor = (param and param > 0) and param or 4
  if pinchStat then
    if mon.hp * divisor > max then return nil end
    return { kind = "statUp", effect = effect, stat = pinchStat, delta = 1,
             consume = true }
  end
  if effect == "RANDOM_STAT_UP" then
    if mon.hp * divisor > max then return nil end
    return { kind = "statUp", effect = effect, stat = nil, delta = 2,
             consume = true }
  end
  if effect == "CRITICAL_UP" then
    if mon.hp * divisor > max then return nil end
    return { kind = "critUp", effect = effect, delta = 2, consume = true }
  end
  return nil
end

-- The stats STARF BERRY chooses between, in the cartridge's own order.
HoldItems.RANDOM_STATS = { "attack", "defense", "speed", "spatk", "spdef" }

-- EVERSTONE, out of battle.  Evolution.lua already refuses to evolve a mon
-- holding Gen 1's own EVERSTONE by id; this is the same question asked of
-- the hold effect, so a Hoenn dataset answers it without a name match.
function HoldItems.preventsEvolution(mon, items)
  local id = mon and (mon.item or mon.heldItem)
  local def = id and items and items[id]
  return type(def) == "table" and def.holdEffect == "PREVENT_EVOLVE"
end

return HoldItems
