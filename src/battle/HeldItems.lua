-- Generation II held-item mechanics shared by battle and field seams.
--
-- The Gen2 ROM extractor stamps ItemAttributes' held-effect byte and signed
-- parameter onto each item record.  Most mechanics can therefore follow the
-- cartridge's data rather than maintain a second item-name table.  The few
-- species-specific items whose ItemAttributes effect is HELD_NONE (Thick Club,
-- Light Ball, Lucky Punch, Lucky Egg and Berserk Gene) are identified by key.

local ItemEffects = require("src.inventory.ItemEffects")
local Strings = require("src.core.Strings")

local HeldItems = {}

HeldItems.EFFECT = {
  NONE = 0,
  BERRY = 1,
  LEFTOVERS = 3,
  RESTORE_PP = 6,
  CLEANSE_TAG = 8,
  HEAL_POISON = 10,
  HEAL_FREEZE = 11,
  HEAL_BURN = 12,
  HEAL_SLEEP = 13,
  HEAL_PARALYZE = 14,
  HEAL_STATUS = 15,
  HEAL_CONFUSION = 16,
  METAL_POWDER = 42,
  NORMAL_BOOST = 50,
  FIGHTING_BOOST = 51,
  FLYING_BOOST = 52,
  POISON_BOOST = 53,
  GROUND_BOOST = 54,
  ROCK_BOOST = 55,
  BUG_BOOST = 56,
  GHOST_BOOST = 57,
  FIRE_BOOST = 58,
  WATER_BOOST = 59,
  GRASS_BOOST = 60,
  ELECTRIC_BOOST = 61,
  PSYCHIC_BOOST = 62,
  ICE_BOOST = 63,
  DRAGON_BOOST = 64,
  DARK_BOOST = 65,
  STEEL_BOOST = 66,
  ESCAPE = 72,
  CRITICAL_UP = 73,
  QUICK_CLAW = 74,
  FLINCH = 75,
  AMULET_COIN = 76,
  BRIGHTPOWDER = 77,
  FOCUS_BAND = 79,
}

local TYPE_BY_EFFECT = {
  [50] = "NORMAL", [51] = "FIGHTING", [52] = "FLYING",
  [53] = "POISON", [54] = "GROUND", [55] = "ROCK", [56] = "BUG",
  [57] = "GHOST", [58] = "FIRE", [59] = "WATER", [60] = "GRASS",
  [61] = "ELECTRIC", [62] = "PSYCHIC", [63] = "ICE", [64] = "DRAGON",
  [65] = "DARK", [66] = "STEEL",
}

local STATUS_BY_EFFECT = {
  [HeldItems.EFFECT.HEAL_POISON] = "PSN",
  [HeldItems.EFFECT.HEAL_FREEZE] = "FRZ",
  [HeldItems.EFFECT.HEAL_BURN] = "BRN",
  [HeldItems.EFFECT.HEAL_SLEEP] = "SLP",
  [HeldItems.EFFECT.HEAL_PARALYZE] = "PAR",
}

local function norm(value)
  if value == nil then return nil end
  local key = tostring(value):upper():gsub("[%.']", "")
  key = key:gsub("[^A-Z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  local aliases = {
    KING_S_ROCK = "KINGS_ROCK",
    MYSTERYBERRY = "MYSTERY_BERRY",
    MIRACLEBERRY = "MIRACLE_BERRY",
    SILVERPOWDER = "SILVER_POWDER",
    TWISTEDSPOON = "TWISTED_SPOON",
    NEVERMELTICE = "NEVER_MELT_ICE",
    BLACKGLASSES = "BLACK_GLASSES",
    FARFETCH_D = "FARFETCHD",
  }
  return aliases[key] or key
end
HeldItems.norm = norm

local function monOf(holder)
  return holder and (holder.mon or holder) or nil
end

local function itemDef(data, holder)
  local mon = monOf(holder)
  local id = mon and (mon.item or mon.heldItem)
  if not (id and data and data.items) then return nil, id end
  return data.items[id], id
end

function HeldItems.itemKey(data, holder)
  local def, id = itemDef(data, holder)
  if not id then return nil end
  local key = ItemEffects.alias(id, def)
  return norm(key or (def and (def.key or def.name)) or id)
end

function HeldItems.effect(data, holder)
  local def, id = itemDef(data, holder)
  if type(def) ~= "table" then return HeldItems.EFFECT.NONE, 0 end

  -- Intentional Gen II cleanup approved for the recomp ruleset: retail
  -- Crystal accidentally assigns HELD_DRAGON_BOOST to Dragon Scale and leaves
  -- Dragon Fang with HELD_NONE.  Treat Dragon Fang as the Dragon-type booster
  -- and Dragon Scale as a normal held item instead of reproducing that bug.
  local key = norm(ItemEffects.alias(id, def) or def.key or def.name or id)
  if key == "DRAGON_FANG" then
    return HeldItems.EFFECT.DRAGON_BOOST, 10
  elseif key == "DRAGON_SCALE" then
    return HeldItems.EFFECT.NONE, 0
  end

  return tonumber(def.heldEffect) or HeldItems.EFFECT.NONE,
         tonumber(def.heldParam) or 0
end

local function speciesKey(holder)
  local mon = monOf(holder)
  return norm(mon and mon.species)
end

local function consume(holder)
  local mon = monOf(holder)
  if not mon then return end
  mon.item, mon.heldItem = nil, nil
end
HeldItems.consume = consume

-- LoadEnemyMon .WildItem (Gen II): normal wild encounters first have a
-- 75% no-item branch, then use a second byte to choose Item2 for 8% of the
-- remaining 25%. BATTLETYPE_FORCEITEM bypasses both rolls and uses Item1.
function HeldItems.rollWild(data, species, rng, forceCommon)
  local def = data and data.pokemon and data.pokemon[species]
  local common = def and def.heldItemCommon or nil
  local rare = def and def.heldItemRare or nil
  if forceCommon then return common end

  rng = rng or love.math.random
  if rng(0, 255) < 192 then return nil end
  if rng(0, 255) < 20 then return rare end
  return common
end

local function isAlive(holder)
  local mon = monOf(holder)
  return mon and (tonumber(mon.hp) or 0) > 0
end

local function heal(holder, amount)
  local mon = monOf(holder)
  local maxHP = mon and mon.stats and tonumber(mon.stats.hp)
  if not (mon and maxHP and tonumber(mon.hp)) or mon.hp <= 0 or mon.hp >= maxHP then
    return 0
  end
  local before = mon.hp
  mon.hp = math.min(maxHP, mon.hp + math.max(1, math.floor(amount or 0)))
  return mon.hp - before
end

local function displayName(holder)
  if not holder then return "POKéMON" end
  if holder.name then return holder.isPlayer == false and ("Enemy " .. holder.name) or holder.name end
  local mon = monOf(holder)
  return mon and (mon.nickname or mon.species) or "POKéMON"
end

local function queueHeal(battle, holder, text)
  if text then battle:sayNext(Strings(text, displayName(holder))) end
  local mon = monOf(holder)
  if battle.drainNext and mon then battle:drainNext(holder, mon.hp) end
end

-- -------------------------------------------------------------------------
-- Turn order / hit chance / critical chance
-- -------------------------------------------------------------------------

function HeldItems.quickClaw(data, holder, rng)
  local effect, param = HeldItems.effect(data, holder)
  if effect ~= HeldItems.EFFECT.QUICK_CLAW then return false end
  rng = rng or love.math.random
  return rng(0, 255) < param
end

function HeldItems.accuracyPenalty(data, holder)
  local effect, param = HeldItems.effect(data, holder)
  return effect == HeldItems.EFFECT.BRIGHTPOWDER and param or 0
end

function HeldItems.criticalStageBonus(data, holder)
  local effect = HeldItems.effect(data, holder)
  if effect == HeldItems.EFFECT.CRITICAL_UP then return 1 end
  local key, species = HeldItems.itemKey(data, holder), speciesKey(holder)
  if key == "STICK" and species == "FARFETCHD" then return 2 end
  if key == "LUCKY_PUNCH" and species == "CHANSEY" then return 2 end
  return 0
end

-- -------------------------------------------------------------------------
-- Damage/stat held items
-- -------------------------------------------------------------------------

function HeldItems.modifyBattleStats(data, attacker, defender, atkStat, defStat, atk, dfn)
  local aKey, aSpecies = HeldItems.itemKey(data, attacker), speciesKey(attacker)
  local dEffect = HeldItems.effect(data, defender)
  local dSpecies = speciesKey(defender)

  if aKey == "THICK_CLUB" and (aSpecies == "CUBONE" or aSpecies == "MAROWAK")
     and atkStat == "attack" then
    atk = atk * 2
  elseif aKey == "LIGHT_BALL" and aSpecies == "PIKACHU"
     and (atkStat == "spatk" or atkStat == "special") then
    atk = atk * 2
  end

  -- A transformed Ditto keeps mon.species = DITTO while battler.species is the
  -- copied species.  Metal Powder only works before Transform.
  local untransformedDitto = dSpecies == "DITTO"
    and (defender.species == nil or norm(defender.species) == "DITTO")
  if dEffect == HeldItems.EFFECT.METAL_POWDER and untransformedDitto
     and (defStat == "defense" or defStat == "spdef" or defStat == "special") then
    dfn = math.floor(dfn * 3 / 2)
  end
  return atk, dfn
end

function HeldItems.applyTypeBoost(data, attacker, moveType, damage)
  local effect, param = HeldItems.effect(data, attacker)
  if TYPE_BY_EFFECT[effect] ~= moveType then return damage end
  -- ItemAttributes stores 10 for the retail type boosters: x1.10, with the
  -- floor occurring here inside the damage pipeline.
  return math.max(1, math.floor(damage * (100 + param) / 100))
end

function HeldItems.limitDirectDamage(data, target, damage, rng)
  if not isAlive(target) or damage <= 0 then return damage end
  local effect, param = HeldItems.effect(data, target)
  if effect ~= HeldItems.EFFECT.FOCUS_BAND then return damage end
  local hp = tonumber(monOf(target).hp) or 0
  if hp <= 1 or damage < hp then return damage end
  rng = rng or love.math.random
  if rng(0, 255) < param then return hp - 1 end
  return damage
end

-- Crystal does not run BattleCommand_KingsRock after every damaging move.
-- It is an explicit command in selected move-effect scripts (NormalHit,
-- LeechHit, MultiHit, RecoilHit, SkyAttack, Snore, etc.).  Keep that script
-- boundary here instead of approximating it from power or from whether a move
-- already has a native flinch chance.  In particular Sky Attack and Snore
-- really execute BOTH flinchtarget and kingsrock on cartridge.
local KINGS_ROCK_EFFECTS = {
  NO_ADDITIONAL_EFFECT = true,
  SWIFT_EFFECT = true,
  DRAIN_HP_EFFECT = true,
  EXPLODE_EFFECT = true,
  PAY_DAY_EFFECT = true,
  BIDE_EFFECT = true,
  THRASH_PETAL_DANCE_EFFECT = true,
  TWO_TO_FIVE_ATTACKS_EFFECT = true,
  ATTACK_TWICE_EFFECT = true,
  JUMP_KICK_EFFECT = true,
  TWINEEDLE_EFFECT = true,
  RECOIL_EFFECT = true,
  CHARGE_EFFECT = true,
  RAGE_EFFECT = true,
  FLY_EFFECT = true,
  SUPER_FANG_EFFECT = true,
  SPECIAL_DAMAGE_EFFECT = true,
  REVERSAL_EFFECT = true,
  COUNTER_EFFECT = true,
  SNORE_EFFECT = true,
  FALSE_SWIPE_EFFECT = true,
  THIEF_EFFECT = true,
  ROLLOUT_EFFECT = true,
  FURY_CUTTER_EFFECT = true,
  RETURN_EFFECT = true,
  PRESENT_EFFECT = true,
  FRUSTRATION_EFFECT = true,
  MAGNITUDE_EFFECT = true,
  PURSUIT_EFFECT = true,
  RAPID_SPIN_EFFECT = true,
  HIDDEN_POWER_EFFECT = true,
  MIRROR_COAT_EFFECT = true,
  SOLARBEAM_EFFECT = true,
  BEAT_UP_EFFECT = true,
}

function HeldItems.supportsKingsRock(move)
  if not move then return false end
  -- Triple Kick has its own Crystal effect byte, but the importer represents
  -- its three-hit semantics through move.multiHit instead of a separate effect
  -- name.  Its script ends in `kingsrock` just like the other eligible moves.
  if norm(move.id) == "TRIPLE_KICK" or tonumber(move.multiHit) == 3 then
    return true
  end
  return KINGS_ROCK_EFFECTS[norm(move.effect)] == true
end

function HeldItems.tryKingsRock(data, user, target, move, rng, blockedBySubstitute)
  if blockedBySubstitute or not isAlive(target) or not HeldItems.supportsKingsRock(move) then
    return false
  end
  local effect, param = HeldItems.effect(data, user)
  if effect ~= HeldItems.EFFECT.FLINCH then return false end
  rng = rng or love.math.random
  if rng(0, 255) < param then
    target.flinched = true
    return true
  end
  return false
end

-- -------------------------------------------------------------------------
-- Automatic consumables
-- -------------------------------------------------------------------------

-- Gen II keeps one confusion counter per battle side, separate from the
-- active party struct.  Switching therefore leaves the previous counter
-- behind.  Ordinary confusion effects initialize this counter explicitly;
-- Berserk Gene does the same here as an intentional correction of Crystal's
-- retail 256-turn/stale-counter bug.
local function confusionSide(holder)
  return holder and holder.isPlayer and "player" or "enemy"
end

function HeldItems.setConfusionCounter(battle, holder, turns)
  if not (battle and holder) then return end
  battle.heldConfusionCounters = battle.heldConfusionCounters or {}
  battle.heldConfusionCounters[confusionSide(holder)] = math.max(0, tonumber(turns) or 0)
end

function HeldItems.confusionCounter(battle, holder)
  local counters = battle and battle.heldConfusionCounters
  return counters and (tonumber(counters[confusionSide(holder)]) or 0) or 0
end

local function curePersistent(holder, wanted)
  local mon = monOf(holder)
  local status = mon and mon.status
  if not status then return false end
  if wanted and norm(status) ~= wanted then return false end
  mon.status = nil
  holder.sleepTurns, holder.toxicCounter = nil, nil
  return true
end

function HeldItems.onStatus(battle, holder)
  if not (battle and isAlive(holder)) then return {} end
  local effect = HeldItems.effect(battle.data, holder)
  local wanted = STATUS_BY_EFFECT[effect]
  local changed = false
  if wanted then
    changed = curePersistent(holder, wanted)
  elseif effect == HeldItems.EFFECT.HEAL_STATUS then
    changed = curePersistent(holder)
    -- MiracleBerry cures every major status at once, including confusion.
    -- If a primary status triggered it while confusion is also active, clear
    -- both before consuming the item rather than leaving confusion behind.
    if changed then
      holder.confusedTurns = nil
      HeldItems.setConfusionCounter(battle, holder, 0)
    end
  end
  if not changed then return {} end
  consume(holder)
  holder.shownStatus = holder.mon.status
  return { Strings("%s's held item\ncured its status!", displayName(holder)) }
end

function HeldItems.onConfusion(battle, holder)
  if not (battle and isAlive(holder)) or not holder.confusedTurns then return {} end
  local effect = HeldItems.effect(battle.data, holder)
  local key = HeldItems.itemKey(battle.data, holder)
  if effect ~= HeldItems.EFFECT.HEAL_CONFUSION
     and effect ~= HeldItems.EFFECT.HEAL_STATUS
     and key ~= "BITTER_BERRY" and key ~= "MIRACLE_BERRY" then
    return {}
  end
  holder.confusedTurns = nil
  HeldItems.setConfusionCounter(battle, holder, 0)
  consume(holder)
  return { Strings("%s snapped out\nwith its held item!", displayName(holder)) }
end

local function restorePP(data, holder)
  local mon = monOf(holder)
  for i, move in ipairs(mon and mon.moves or {}) do
    if (tonumber(move.pp) or 0) <= 0 then
      local def = data.moves and data.moves[move.id]
      local base = def and tonumber(def.pp)
      local maxPP = base
      if base then maxPP = base + (tonumber(move.ppUps) or 0) * math.floor(base / 5) end
      local amount = norm(move.id) == "SKETCH" and 1 or 5
      move.pp = maxPP and math.min(maxPP, amount) or amount
      if holder.curMoves and holder.curMoves ~= mon.moves and holder.curMoves[i] then
        holder.curMoves[i].pp = move.pp
      end
      return true
    end
  end
  return false
end

local function processLeftovers(battle, holder)
  if not isAlive(holder) then return end
  local effect = HeldItems.effect(battle.data, holder)
  if effect ~= HeldItems.EFFECT.LEFTOVERS then return end
  local mon = monOf(holder)
  local maxHP = mon.stats and tonumber(mon.stats.hp)
  if not maxHP then return end
  local got = heal(holder, math.max(1, math.floor(maxHP / 16)))
  if got > 0 then
    queueHeal(battle, holder, "%s restored HP\nwith LEFTOVERS!")
  end
end

local function processRestorePP(battle, holder)
  if not isAlive(holder) then return end
  local effect = HeldItems.effect(battle.data, holder)
  if effect == HeldItems.EFFECT.RESTORE_PP and restorePP(battle.data, holder) then
    consume(holder)
    battle:sayNext(Strings("%s's held item\nrestored PP!", displayName(holder)))
  end
end

local function processHealingItem(battle, holder)
  if not isAlive(holder) then return end
  local effect, param = HeldItems.effect(battle.data, holder)
  local mon = monOf(holder)
  if effect == HeldItems.EFFECT.BERRY then
    local maxHP = mon.stats and tonumber(mon.stats.hp)
    if maxHP and mon.hp * 2 <= maxHP then
      local got = heal(holder, param)
      if got > 0 then
        consume(holder)
        queueHeal(battle, holder, "%s restored HP\nwith its held item!")
      end
    end
    return
  end

  -- Status berries normally fire as soon as the condition is inflicted.  This
  -- fallback mirrors HandleHealingItems for a status that entered through an
  -- older/non-standard seam.
  local msgs = HeldItems.onStatus(battle, holder)
  if #msgs == 0 then msgs = HeldItems.onConfusion(battle, holder) end
  for _, msg in ipairs(msgs) do battle:sayNext(msg) end
end

-- HandleBetweenTurnEffects reaches held items only after weather and its faint
-- checks.  Keep the item phases grouped rather than processing every item on
-- one battler at once: cartridge order is Leftovers, MysteryBerry, then the
-- healing/status-item family.
function HeldItems.endTurn(battle)
  if not battle or battle.result then return end
  local battlers = { battle.player, battle.enemy }
  for _, b in ipairs(battlers) do processLeftovers(battle, b) end
  for _, b in ipairs(battlers) do processRestorePP(battle, b) end
  for _, b in ipairs(battlers) do processHealingItem(battle, b) end
end

-- Berserk Gene is HELD_NONE in ItemAttributes and is detected by key.
-- Crystal retail leaves the side confusion counter uninitialized, causing a
-- stale-counter/256-turn bug.  This implementation intentionally corrects
-- that legacy bug by initializing a normal Gen II confusion duration.
function HeldItems.onEntry(battle, holder)
  if not (battle and isAlive(holder)) then return false end
  if HeldItems.itemKey(battle.data, holder) ~= "BERSERK_GENE" then return false end
  consume(holder)
  holder.stages = holder.stages or {}
  holder.stages.attack = math.min(6, (tonumber(holder.stages.attack) or 0) + 2)
  holder.confusedTurns = battle.rng(2, 5)
  HeldItems.setConfusionCounter(battle, holder, holder.confusedTurns)
  battle:sayNext(Strings("%s's BERSERK GENE\nsharply raised ATTACK!", displayName(holder)))
  return true
end

-- -------------------------------------------------------------------------
-- EXP / prize money / escape / encounter rate
-- -------------------------------------------------------------------------

function HeldItems.modifyExperience(data, mon, gained)
  if HeldItems.itemKey(data, mon) == "LUCKY_EGG" then
    return math.max(1, math.floor(gained * 3 / 2))
  end
  return gained
end

function HeldItems.observeParticipant(battle, holder)
  if battle and holder and holder.isPlayer then
    local effect = HeldItems.effect(battle.data, holder)
    if effect == HeldItems.EFFECT.AMULET_COIN then battle.amuletCoin = true end
  end
end

function HeldItems.modifyPrize(battle, prize)
  return battle and battle.amuletCoin and prize * 2 or prize
end

function HeldItems.canEscape(data, holder)
  local effect = HeldItems.effect(data, holder)
  return effect == HeldItems.EFFECT.ESCAPE
end

-- Crystal scans the whole party for Cleanse Tag, then halves the encounter
-- rate byte before the first encounter RNG draw.  The holder does not need to
-- be in slot one (ApplyCleanseTagEffectOnEncounterRate loops wPartyCount).
function HeldItems.cleanseTagRate(data, party, rate)
  for _, mon in ipairs(party or {}) do
    local effect = HeldItems.effect(data, mon)
    if effect == HeldItems.EFFECT.CLEANSE_TAG then
      return math.floor((tonumber(rate) or 0) / 2)
    end
  end
  return rate
end

return HeldItems
