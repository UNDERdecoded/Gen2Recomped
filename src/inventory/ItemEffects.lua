-- Item use effects, ported from engine/items/item_effects.asm.
-- Heal amounts and behaviors match Gen 1; TMs/HMs teach their machine
-- move when the species' tmhm list allows it.
--
-- ItemEffects.use returns:
--   "consumed", messages            item used up
--   "kept", messages                used but not consumed (TM kept? no --
--                                   HMs and key items)
--   "failed", messages              no effect ("It won't have any effect.")
--   "ball"                          caller must throw it (battle only)
--   "learn", moveId                 caller must run the learn-move flow

local Flags = require("src.script.Flags")
local Strings = require("src.core.Strings")

local ItemEffects = {}

local HEAL_AMOUNT = {
  POTION = 20, SUPER_POTION = 50, HYPER_POTION = 200,
  FRESH_WATER = 50, SODA_POP = 60, LEMONADE = 80,
  -- Gen2 additions (data/items/attributes.asm): the two healing berries and
  -- the Moomoo Milk / Berry Juice drinks.
  BERRY = 10, GOLD_BERRY = 30, BERRY_JUICE = 20, MOOMOO_MILK = 100,
  RAGECANDYBAR = 20,
}

local STATUS_HEAL = {
  ANTIDOTE = { PSN = true }, BURN_HEAL = { BRN = true },
  ICE_HEAL = { FRZ = true }, AWAKENING = { SLP = true },
  PARLYZ_HEAL = { PAR = true },
  FULL_HEAL = { PSN = true, BRN = true, FRZ = true, SLP = true, PAR = true },
  -- Gen2 status berries.  BITTER BERRY cures confusion, which is a volatile
  -- rather than a status byte, so it is handled alongside FULL HEAL below.
  PSNCUREBERRY = { PSN = true }, BURNT_BERRY = { FRZ = true },
  ICE_BERRY = { BRN = true }, MINT_BERRY = { SLP = true },
  PRZCUREBERRY = { PAR = true },
  BITTER_BERRY = {},
  MIRACLEBERRY = { PSN = true, BRN = true, FRZ = true, SLP = true,
                   PAR = true },
}

-- Items that also clear the confusion volatile (FULL HEAL, MIRACLEBERRY and
-- BITTER BERRY -- item_effects.asm .curestatus / .bitterberry).
local CURES_CONFUSION = {
  FULL_HEAL = true, MIRACLEBERRY = true, BITTER_BERRY = true,
}

local BALLS = {
  POKE_BALL = true, GREAT_BALL = true, ULTRA_BALL = true,
  MASTER_BALL = true, SAFARI_BALL = true,
  -- Gen2 balls
  LEVEL_BALL = true, LURE_BALL = true, MOON_BALL = true,
  FRIEND_BALL = true, FAST_BALL = true, HEAVY_BALL = true,
  LOVE_BALL = true, PARK_BALL = true,
}

local STONES = {
  FIRE_STONE = true, WATER_STONE = true, THUNDER_STONE = true,
  LEAF_STONE = true, MOON_STONE = true,
  -- Gen2 spells Thunderstone as one word and adds the Sun Stone
  THUNDERSTONE = true, SUN_STONE = true,
}

-- vitamins: stat-exp boosters (ItemUseVitamin)
local VITAMINS = { HP_UP = "hp", PROTEIN = "attack", IRON = "defense",
                   CARBOS = "speed", CALCIUM = "special" }

ItemEffects.BALLS = BALLS

-- Gen2 items are ITEM_nnn; every table in this file is keyed by Gen1's
-- name-derived ids, which the Gen2 extractor stamps on as `key`.
local function alias(id, itemDef)
  if itemDef and itemDef.key then return itemDef.key end
  local Data = require("src.core.Data")
  local def = Data.items and Data.items[id]
  return (def and def.key) or id
end
ItemEffects.alias = alias

-- IS THIS A BALL?  The name list above is Gen 1's and Gen 2's, and Hoenn has
-- seven balls that are not on it -- DIVE, LUXURY, NEST, NET, PREMIER, REPEAT
-- and TIMER.  Reported as items that simply did nothing when thrown, which is
-- what an unrecognised ball does: `use` falls past the ball branch and ends
-- at the refusal.
--
-- The dataset already knows.  Every ball on the cartridge is in the BALL
-- POCKET and has no field-use function at all -- you cannot use one from the
-- bag, only throw it -- so the pocket is the cartridge's own answer and a
-- Gen 4 ball added by a mod gets it for free.  The name list stays as the
-- answer for Gen 1 and Gen 2, whose items carry no pocket.
function ItemEffects.isBall(id, itemDef)
  if BALLS[alias(id, itemDef)] then return true end
  local def = itemDef
  if def == nil then
    local Data = require("src.core.Data")
    def = Data.items and Data.items[id]
  end
  return (type(def) == "table" and def.pocket == "BALL") or false
end
function ItemEffects.isStone(id) return STONES[alias(id)] or false end

-- Does using this item take item_effects.asm's .healHP path, the one that
-- plays SFX_HEAL_HP and lengthens the party HP bar with UpdateHPBar2 before
-- the message (item_effects.asm .doneHealing)?  The status-only cures branch
-- to .playStatusAilmentCuringSound instead and never touch the bar.  BagMenu
-- keeps the party picker open for these so the fill has something to draw
-- on (#252).
-- The Gen 3 record, reachable from the two predicates below -- which run
-- before `use` and decide whether a party picker opens at all.  Declared here
-- rather than beside gen3Use because a `local function` is only in scope
-- below its own declaration, and these two are above it.
function ItemEffects.gen3RecordFor(id, data)
  local Data = data
  if Data == nil then
    local ok, mod = pcall(require, "src.core.Data")
    Data = ok and mod or nil
  end
  local c = Data and Data.constants
  local all = c and c.gen3ItemEffects
  return type(all) == "table" and all[id] or nil
end

function ItemEffects.healsHP(id)
  local r = ItemEffects.gen3RecordFor(id)
  if r then return (r.heal or r.revive) and true or false end
  id = alias(id)
  return HEAL_AMOUNT[id] ~= nil or id == "MAX_POTION" or id == "FULL_RESTORE"
      or id == "REVIVE" or id == "MAX_REVIVE"
end

-- Does this item need a party-member target?
function ItemEffects.needsTarget(id, itemDef)
  -- HOENN ASKS FIRST, and this is what opens the party picker.
  --
  -- The list below is Gen 1's and Gen 2's, so an ORAN BERRY answered "no
  -- target needed" and was then used on nobody -- which is a medicine that
  -- silently does nothing however correct the effect behind it is.  A SACRED
  -- ASH is the one that really does not want one: it revives the whole party.
  local r = ItemEffects.gen3RecordFor(id)
  if r then
    if r.sacredAsh then return false end
    if r.heal or r.revive or r.cures or r.cureAll or r.pp or r.ev
       or r.ppUp or r.ppMax then
      return true
    end
  end
  id = alias(id, itemDef)
  return HEAL_AMOUNT[id] or STATUS_HEAL[id] or id == "MAX_POTION"
      or id == "FULL_RESTORE" or id == "REVIVE" or id == "MAX_REVIVE"
      or id == "RARE_CANDY" or STONES[id]
      or (itemDef and itemDef.machine) or id == "ETHER"
      or id == "MAX_ETHER" or id == "ELIXER" or id == "MAX_ELIXER"
      or id == "MYSTERYBERRY"
      or VITAMINS[id] or id == "PP_UP"
end

local function monName(data, mon)
  return mon.nickname or data.pokemon[mon.species].name
end

-- Curing the ACTIVE battler clears its Toxic escalation flag
-- (.cureStatusAilment / trainer_ai.asm AICureStatus both do
-- `res BADLY_POISONED`); the raw w*ToxicCounter is NOT reset by item
-- cures in Gen 1, so battle.sideToxic is deliberately left alone.
local function cureActiveToxic(battle, target)
  if not battle then return end
  for _, b in ipairs({ battle.player, battle.enemy }) do
    if b and b.mon == target then b.toxicCounter = nil end
  end
end

-- battle-only stat boosters (engine/items/item_effects.asm ItemUseXStat)
local X_ITEMS = {
  X_ATTACK = "attack", X_DEFEND = "defense", X_SPEED = "speed",
  X_SPECIAL = "special", X_ACCURACY = "accuracy",
}

-- The two static Snorlax encounters (scripts/Route12.asm, Route16.asm).
-- ItemUsePokeFlute only wakes one when the player is on its route, hasn't
-- beaten it yet, and is standing in one of the four cells orthogonally
-- adjacent to it (Route12SnorlaxFluteCoords/Route16SnorlaxFluteCoords are
-- exactly Snorlax's four neighbors, so a Manhattan distance of 1 from the
-- NPC matches them without hand-listing map coordinates here).
local SNORLAX_ROUTES = {
  ROUTE_12 = { obj = "ROUTE12_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE12_SNORLAX" },
  ROUTE_16 = { obj = "ROUTE16_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE16_SNORLAX" },
}

-- Is the player adjacent to a not-yet-beaten Snorlax on the current map?
-- Returns the map id and NPC to wake it, or nil.
local function adjacentSleepingSnorlax(save, ow)
  local route = ow and ow.map and SNORLAX_ROUTES[ow.map.id]
  if not route or Flags.get(save, route.beatFlag) then return nil end
  local p = ow.player
  if not p then return nil end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.name == route.obj then
      if math.abs(p.cellX - npc.cellX) + math.abs(p.cellY - npc.cellY) == 1 then
        return ow.map.id, npc
      end
      return nil
    end
  end
  return nil
end

-- Use an item on a target party mon (target may be nil for targetless
-- items).  data = generated data tables; battle = BattleState when used
-- mid-battle; ow = the overworld (OverworldState), needed only to check
-- Snorlax adjacency for a field-used POKé FLUTE.
-- ---------------------------------------------------------------------------
-- WHAT AN ITEM DOES IN HOENN, off the cartridge rather than off a name
--
-- Every table in this file is Gen 1's and Gen 2's, keyed by a name-derived
-- id.  Emerald's items carry no such key, so they matched by ACCIDENT
-- wherever the slug happened to agree: POTION worked, and ORAN BERRY, SITRUS
-- BERRY, the five status berries, ENERGY POWDER, ENERGY ROOT, HEAL POWDER,
-- REVIVAL HERB, LAVA COOKIE and ZINC did nothing at all.  CALCIUM was worse
-- than nothing -- the Gen 1 table sends it to "special", a stat a Gen 3
-- Pokemon does not have.
--
-- extractItemEffects reads gItemEffectTable into a record a line of code can
-- act on: what it heals, what it cures, which EV it moves and by how much,
-- and what it does to friendship.  This runs that record.
--
-- WHAT IT DELIBERATELY DOES NOT TAKE: an item whose record says only `stone`
-- or only `battle` falls through to the branches below, because the stones
-- already work by name and the X items belong to the battle side.  A RARE
-- CANDY falls through too.  The point is to add Hoenn's items, not to take
-- Johto's away.
-- ---------------------------------------------------------------------------
local GEN3_EV_MAX = 255            -- per stat
local GEN3_EV_TOTAL = 510          -- across the six
local GEN3_EV_ORDER = { "hp", "attack", "defense", "speed", "spatk", "spdef" }

local function gen3Record(data, itemId)
  local c = data and data.constants
  local all = c and c.gen3ItemEffects
  return type(all) == "table" and all[itemId] or nil
end

-- The friendship a medicine moves, which is a third of the record the port
-- had no way to know about.  Three deltas, chosen by how much the Pokemon
-- already likes you, and the bitter herbs are why they can be negative.
local function gen3Friendship(target, deltas)
  if not (target and type(deltas) == "table" and #deltas > 0) then return end
  local now = math.floor(tonumber(target.happiness) or 0)
  local band = (now < 100) and 1 or ((now < 200) and 2 or 3)
  local delta = deltas[math.min(band, #deltas)]
  if not delta then return end
  target.happiness = math.max(0, math.min(255, now + delta))
end

local function gen3EvTotal(evs)
  local total = 0
  for _, key in ipairs(GEN3_EV_ORDER) do
    total = total + math.floor(tonumber(evs[key]) or 0)
  end
  return total
end

local function gen3Use(data, save, itemId, target, battle, moveIndex)
  local r = gen3Record(data, itemId)
  if not r then return nil end
  -- a stone, an X item or a rare candy is somebody else's branch
  if not (r.heal or r.revive or r.cures or r.cureAll or r.pp or r.ev
          or r.ppUp or r.ppMax or r.sacredAsh) then
    return nil
  end
  if r.levelUp then return nil end
  local fail = { Strings("It won't have\nany effect.") }

  -- ---- SACRED ASH: the whole party, not one of them ----------------------
  if r.sacredAsh then
    local woke = false
    for _, mon in ipairs((save and save.party) or {}) do
      if mon and mon.species and (tonumber(mon.hp) or 0) <= 0 then
        mon.hp = (mon.stats and mon.stats.hp) or 1
        mon.status = nil
        woke = true
      end
    end
    if not woke then return "failed", fail end
    return "consumed", { Strings("All of your POKeMON\nwere revived!") }
  end

  if not target then return "failed", fail end
  local fainted = (tonumber(target.hp) or 0) <= 0
  local maxHP = (target.stats and tonumber(target.stats.hp)) or 1

  -- ---- reviving, and the rule that keeps a REVIVE off a healthy one ------
  if r.revive then
    if not fainted then return "failed", fail end
    local before = target.hp or 0
    target.hp = (r.amount == "half") and math.max(1, math.floor(maxHP / 2))
                or maxHP
    target.status = nil
    gen3Friendship(target, r.friendship)
    require("src.core.Sound").play(data, "Heal_HP")
    return "consumed",
           { Strings("%s is\nrevitalized!", monName(data, target)) },
           { healedFrom = before }
  end

  -- ---- healing ------------------------------------------------------------
  if r.heal then
    -- a cure-all that also heals (FULL RESTORE) still works on a Pokemon at
    -- full health, as long as it is carrying something
    local full = target.hp >= maxHP
    if fainted or (full and not ((r.cureAll or r.cures) and target.status)) then
      return "failed", fail
    end
    local before = target.hp
    if not full then
      local by = r.amount
      if by == "all" then
        target.hp = maxHP
      elseif by == "half" then
        target.hp = math.min(maxHP, target.hp + math.floor(maxHP / 2))
      else
        target.hp = math.min(maxHP, target.hp + (tonumber(by) or 0))
      end
    end
    local msgs = { Strings("%s's HP\nwas restored!", monName(data, target)) }
    if r.cureAll or r.cures then
      target.status = nil
      cureActiveToxic(battle, target)
    end
    gen3Friendship(target, r.friendship)
    require("src.core.Sound").play(data, "Heal_HP")
    return "consumed", msgs, { healedFrom = before }
  end

  -- ---- curing, and nothing else -------------------------------------------
  if r.cureAll or r.cures then
    local status = target.status
    local confused = nil
    if battle then
      for _, b in ipairs({ battle.player, battle.enemy }) do
        if b and b.mon == target and b.confusedTurns then confused = b end
      end
    end
    local wanted = r.cureAll and status ~= nil
    if not wanted and status then
      for _, name in ipairs(r.cures or {}) do
        if name == status then wanted = true end
      end
    end
    local clearsConfusion = r.cureAll
    if not clearsConfusion then
      for _, name in ipairs(r.cures or {}) do
        if name == "CONFUSION" then clearsConfusion = true end
      end
    end
    if not (wanted or (clearsConfusion and confused)) then
      return "failed", fail
    end
    if wanted then target.status = nil end
    cureActiveToxic(battle, target)
    if clearsConfusion and confused then confused.confusedTurns = nil end
    gen3Friendship(target, r.friendship)
    require("src.core.Sound").play(data, "Heal_Ailment")
    return "consumed",
           { Strings("%s's\nstatus returned\nto normal!",
                     monName(data, target)) }
  end

  -- ---- PP, on one move or on all of them ----------------------------------
  if r.pp then
    local moves = target.moves or {}
    local list = {}
    if r.pp == "one" then
      list[1] = moves[moveIndex or 1]
    else
      for _, mv in ipairs(moves) do list[#list + 1] = mv end
    end
    local moved = false
    for _, mv in ipairs(list) do
      local def = mv and data.moves and data.moves[mv.id]
      local max = def and tonumber(def.pp)
      if max then
        max = max + math.floor(max / 5) * (tonumber(mv.ppUps) or 0)
        if (tonumber(mv.pp) or 0) < max then
          mv.pp = (r.amount == "all") and max
                  or math.min(max, (tonumber(mv.pp) or 0)
                                   + (tonumber(r.amount) or 0))
          moved = true
        end
      end
    end
    if not moved then return "failed", fail end
    gen3Friendship(target, r.friendship)
    return "consumed",
           { Strings("%s's PP\nwas restored!", monName(data, target)) }
  end

  -- ---- PP UP and PP MAX ---------------------------------------------------
  if r.ppUp or r.ppMax then
    local mv = (target.moves or {})[moveIndex or 1]
    local def = mv and data.moves and data.moves[mv.id]
    if not (def and tonumber(def.pp)) then return "failed", fail end
    local ups = math.floor(tonumber(mv.ppUps) or 0)
    if ups >= 3 then return "failed", fail end
    local step = math.floor(tonumber(def.pp) / 5)
    if r.ppMax then
      mv.pp = (tonumber(mv.pp) or 0) + step * (3 - ups)
      mv.ppUps = 3
    else
      mv.pp = (tonumber(mv.pp) or 0) + step
      mv.ppUps = ups + 1
    end
    gen3Friendship(target, r.friendship)
    return "consumed", { Strings("%s's PP\nincreased!", def.name) }
  end

  -- ---- and the effort values, which is where CALCIUM was going wrong ------
  if r.ev then
    target.evs = target.evs or {}
    local now = math.floor(tonumber(target.evs[r.ev]) or 0)
    local by = math.floor(tonumber(r.amount) or 0)
    local want
    if by >= 0 then
      -- the two ceilings: 255 in one stat and 510 across the six
      local room = math.min(GEN3_EV_MAX - now,
                            GEN3_EV_TOTAL - gen3EvTotal(target.evs))
      want = now + math.max(0, math.min(by, room))
    else
      want = math.max(0, now + by)
    end
    if want == now then return "failed", fail end
    target.evs[r.ev] = want
    local okStats, Stats = pcall(require, "src.pokemon.Stats")
    if okStats and data.pokemon and data.pokemon[target.species] then
      pcall(function()
        target.stats = Stats.calc(data.pokemon[target.species], target.level,
                                  target.ivs, target.evs, target.nature)
        target.hp = math.min(target.hp, target.stats.hp)
      end)
    end
    gen3Friendship(target, r.friendship)
    local label = (r.ev == "hp" and "HP")
                  or (r.ev == "spatk" and "SP. ATK")
                  or (r.ev == "spdef" and "SP. DEF")
                  or r.ev:upper()
    return "consumed",
           { Strings("%s's %s\n%s!", monName(data, target), label,
                     by >= 0 and "rose" or "fell") }
  end

  return nil
end

ItemEffects.gen3Use = gen3Use

function ItemEffects.use(data, save, itemId, target, battle, moveIndex, ow)
  local itemDef = data.items[itemId]
  local name = itemDef and itemDef.name or itemId
  local rawItemId = itemId
  itemId = alias(itemId, itemDef)

  -- ItemUseVitamin / ItemUsePPUp / ItemUseEvoStone / ItemUseCoinCase /
  -- ItemUseTMHM all refuse mid-battle (jp nz, ItemUseNotTime)
  if battle and (VITAMINS[itemId] or STONES[itemId] or itemId == "PP_UP"
                 or itemId == "RARE_CANDY" or itemId == "COIN_CASE"
                 or (itemDef and itemDef.machine)) then
    return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!",
                               save.player.name) }
  end

  if ItemEffects.isBall(itemId, itemDef) or ItemEffects.isBall(rawItemId, itemDef) then
    return "ball"
  end

  -- HOENN'S OWN ANSWER FIRST, when the cartridge gave one.  Everything below
  -- is Gen 1's and Gen 2's, keyed by a name Emerald's items do not carry.
  do
    local kind, msgs, extra = gen3Use(data, save, rawItemId, target, battle,
                                      moveIndex)
    if kind then return kind, msgs, extra end
  end


  -- The POKé FLUTE wakes every sleeping Pokémon on both sides
  -- (ItemUsePokeFlute, engine/items/item_effects.asm); never consumed.
  if itemId == "POKE_FLUTE" then
    if not battle then
      -- standing next to a not-yet-beaten Snorlax: this is the ONLY way
      -- Snorlax wakes -- using the flute from the item-use menu, never
      -- just talking to it with the flute in the bag (see
      -- data/scripts/story.lua's snorlaxWake)
      local mapId, npc = adjacentSleepingSnorlax(save, ow)
      if npc then
        return "flute_wake", { data.text._PlayedFluteHadEffectText
          or Strings("{PLAYER} played the\nPOKé FLUTE.") },
          { mapId = mapId, npc = npc }
      end
      -- otherwise: play the tune, nothing happens (ItemUsePokeFlute's
      -- PlayedFluteNoEffectText branch)
      return "flute_field", { Strings("Played the POKé\nFLUTE.\fNow, that's a\ncatchy tune!") }
    end
    local woke = false
    local function wake(mon)
      if mon and mon.status == "SLP" then
        mon.status = nil
        woke = true
      end
    end
    for _, mon in ipairs(save.party) do wake(mon) end
    wake(battle.player and battle.player.mon)
    wake(battle.enemy and battle.enemy.mon)
    -- WakeUpEntireParty runs on the enemy's bench too
    for _, mon in ipairs(battle.enemyParty or {}) do wake(mon) end
    if not woke then
      return "failed", { Strings("Played the POKé\nFLUTE.\fNow, that's a\ncatchy tune!") }
    end
    return "flute", { Strings("%s played the\nPOKé FLUTE.", save.player.name),
                      Strings("All sleeping\nPOKéMON woke up!") }
  end

  -- battle-only items
  if X_ITEMS[itemId] or itemId == "DIRE_HIT" or itemId == "GUARD_SPEC"
     or itemId == "POKE_DOLL" then
    if not battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    local b = battle.player
    -- PIKAHAPPY_USEDXITEM (item_effects.asm ItemUseXAccuracy /
    -- GuardSpec / DireHit / XStat) on the active companion
    if itemId ~= "POKE_DOLL" then
      require("src.world.PikachuFollower")
        .modifyHappiness(save, "USEDXITEM", b and b.mon)
    end
    if itemId == "X_ACCURACY" then
      -- ItemUseXAccuracy sets USING_X_ACCURACY: moves never miss
      -- (not an accuracy stage)
      b.xAccuracy = true
      return "consumed", { Strings("%s's\nhits will never\nmiss!", b.name) }
    end
    if X_ITEMS[itemId] then
      local stat = X_ITEMS[itemId]
      local cur = b.stages[stat] or 0
      -- ItemUseXStat removes the item BEFORE running the stat-up
      -- effect, so at +6 it is still consumed and StatModifierUpEffect
      -- just prints "Nothing happened!"
      if cur >= 6 then
        return "consumed", { Strings("Nothing happened!") }
      end
      b.stages[stat] = cur + 1
      return "consumed", { Strings("%s's\n%s rose!", b.name, stat:upper()) }
    end
    -- ItemUseDireHit/ItemUseGuardSpec always set the bit and consume
    -- the item, even when it is already active
    if itemId == "DIRE_HIT" then
      b.focusEnergy = true
      return "consumed", { Strings("%s's\ngetting pumped!", b.name) }
    end
    if itemId == "GUARD_SPEC" then
      b.mist = true
      return "consumed", { Strings("%s's\nprotected against\nstat changes!", b.name) }
    end
    if itemId == "POKE_DOLL" then
      if battle.kind ~= "wild" then
        -- ItemUsePokeDoll jumps to ItemUseNotTime in trainer battles
        return "failed", { Strings(
          "OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
      end
      return "consumed_escape", { Strings("The wild POKéMON\nran away!") }
    end
  end

  -- PP restores.  The ETHERs restore the move the player picked
  -- (moveIndex, from the ItemUsePPRestore move menu); the ELIXERs
  -- restore every move with no menu.
  if itemId == "ETHER" or itemId == "MAX_ETHER"
     or itemId == "ELIXER" or itemId == "MAX_ELIXER"
     or itemId == "MYSTERYBERRY" then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    local restored = false
    local full = itemId == "MAX_ETHER" or itemId == "MAX_ELIXER"
    local allMoves = itemId == "ELIXER" or itemId == "MAX_ELIXER"
    -- MYSTERYBERRY is a 5 PP single-move restore (data/items/attributes.asm)
    local amount = itemId == "MYSTERYBERRY" and 5 or 10
    local function restore(mv)
      local mdef = data.moves[mv.id]
      local maxPP = mdef and (mdef.pp + (mv.ppUps or 0) * math.floor(mdef.pp / 5))
      if maxPP and mv.pp < maxPP then
        mv.pp = full and maxPP or math.min(maxPP, mv.pp + amount)
        return true
      end
      return false
    end
    if allMoves then
      for _, mv in ipairs(target.moves) do
        restored = restore(mv) or restored
      end
    else
      local mv = target.moves[moveIndex or 1]
      restored = mv and restore(mv) or false
    end
    if not restored then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    return "consumed", { Strings("%s's PP\nwas restored!", monName(data, target)) }
  end

  -- PIKAHAPPY_USEDITEM (item_effects.asm ItemUseMedicine, item id up to
  -- CALCIUM): fires once a medicine has a target, before the effect
  -- resolves -- potions, status cures, revives and vitamins all count,
  -- RARE_CANDY does not (its success is a LEVELUP bump instead)
  if target and (HEAL_AMOUNT[itemId] or STATUS_HEAL[itemId]
                 or itemId == "MAX_POTION" or itemId == "FULL_RESTORE"
                 or itemId == "REVIVE" or itemId == "MAX_REVIVE"
                 or VITAMINS[itemId]) then
    require("src.world.PikachuFollower")
      .modifyHappiness(save, "USEDITEM", target)
  end

  local heal = HEAL_AMOUNT[itemId]
  if heal or itemId == "MAX_POTION" or itemId == "FULL_RESTORE" then
    -- a FULL RESTORE on a statused mon already at full HP acts as a
    -- Full Heal: cured, consumed, ailment sound (item_effects.asm
    -- swaps wCurItem to FULL_HEAL and jumps to .cureStatusAilment)
    if itemId == "FULL_RESTORE" and target and target.hp > 0
       and target.hp >= target.stats.hp and target.status then
      target.status = nil
      cureActiveToxic(battle, target)
      require("src.core.Sound").play(data, "Heal_Ailment")
      return "consumed", { Strings("%s's\nstatus returned\nto normal!", monName(data, target)) }
    end
    if not target or target.hp <= 0 or target.hp >= target.stats.hp then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    -- wHPBarOldHP: the bar animation starts from the HP the mon had BEFORE
    -- the item landed (item_effects.asm latches it with the party menu still
    -- up), so latch it here and hand it back as extra.healedFrom for the
    -- party-menu fill (#252)
    local before = target.hp
    if itemId == "MAX_POTION" or itemId == "FULL_RESTORE" then
      target.hp = target.stats.hp
    else
      target.hp = math.min(target.stats.hp, target.hp + heal)
    end
    local msgs = { Strings("%s's HP\nwas restored!", monName(data, target)) }
    if itemId == "FULL_RESTORE" then
      target.status = nil
      cureActiveToxic(battle, target)
    end
    require("src.core.Sound").play(data, "Heal_HP")
    return "consumed", msgs, { healedFrom = before }
  end

  local cures = STATUS_HEAL[itemId]
  if cures then
    -- BITTER BERRY / MIRACLEBERRY / FULL HEAL also clear the confusion
    -- volatile, which lives on the battler rather than the party mon.
    local confused = nil
    if battle and CURES_CONFUSION[itemId] then
      for _, b in ipairs({ battle.player, battle.enemy }) do
        if b and b.mon == target and b.confusedTurns then confused = b end
      end
    end
    if not target or ((not target.status or not cures[target.status])
                      and not confused) then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    if confused then confused.confusedTurns = nil end
    target.status = nil
    cureActiveToxic(battle, target)
    require("src.core.Sound").play(data, "Heal_Ailment")
    return "consumed", { Strings("%s's\nstatus returned\nto normal!", monName(data, target)) }
  end

  if itemId == "REVIVE" or itemId == "MAX_REVIVE" then
    if not target or target.hp > 0 then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    target.status = nil
    target.hp = itemId == "REVIVE" and math.floor(target.stats.hp / 2) or target.stats.hp
    require("src.core.Sound").play(data, "Heal_HP")
    -- a revive takes the same .healHP -> .doneHealing route, animating up
    -- from the fainted mon's 0 HP (#252)
    return "consumed", { Strings("%s\nis revitalized!", monName(data, target)) },
           { healedFrom = 0 }
  end

  if itemId == "RARE_CANDY" then
    if not target or target.level >= 100 then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    local Growth = require("src.pokemon.Growth")
    local Stats = require("src.pokemon.Stats")
    local speciesDef = data.pokemon[target.species]
    target.level = target.level + 1
    target.exp = Growth.expForLevel(speciesDef.growthRate, target.level)
    local old = target.stats
    target.stats = Stats.calc(speciesDef, target.level, target.dvs, target.statExp)
    target.hp = math.min(target.stats.hp, target.hp + (target.stats.hp - old.hp))
    -- PIKAHAPPY_LEVELUP on a candy level (item_effects.asm:1540)
    require("src.world.PikachuFollower")
      .modifyHappiness(save, "LEVELUP", target)
    return "consumed", { Strings("%s grew\nto level %d!", monName(data, target), target.level) },
           { leveledTo = target.level }
  end

  if STONES[itemId] then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    -- Yellow's starter Pikachu never evolves: ItemUseEvoStone runs
    -- IsThisPartyMonStarterPikachu (OT identity match) before
    -- TryEvolvingMon and bails with the voiced cry + RefusingText.
    -- The stone is NOT consumed on the refuse path.
    if target.species == "PIKACHU"
       and require("src.core.GameVersion").isYellow()
       and target.ot == save.player.name
       and target.otId == save.player.id then
      require("src.core.Sound").playCry(data, "PIKACHU")
      local raw = data.text and data.text._RefusingText
      local line = raw and raw:gsub("{RAM:[^}]*}", monName(data, target))
        or Strings("%s\nis refusing!", monName(data, target))
      return "failed", { line }
    end
    local speciesDef = data.pokemon[target.species]
    for _, evo in ipairs(speciesDef.evolutions) do
      if evo.method == "ITEM" and (evo.item == itemId or evo.item == rawItemId) then
        return "consumed", nil, { evolveTo = evo.species }
      end
    end
    return "failed", { Strings("It won't have\nany effect.") }
  end

  -- vitamins: +2560 stat exp, refused at 25600+ (ItemUseVitamin,
  -- engine/items/item_effects.asm)
  local vitaminStat = VITAMINS[itemId]
  if vitaminStat then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    target.statExp = target.statExp or {}
    local cur = target.statExp[vitaminStat] or 0
    if cur >= 25600 then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    target.statExp[vitaminStat] = math.min(65535, cur + 2560)
    local Stats = require("src.pokemon.Stats")
    target.stats = Stats.calc(data.pokemon[target.species], target.level,
                              target.dvs, target.statExp)
    target.hp = math.min(target.hp, target.stats.hp)
    return "consumed", { Strings("%s's %s\nrose!", monName(data, target),
      vitaminStat == "hp" and "HP" or vitaminStat:upper()) }
  end

  -- PP UP boosts the move the player picked (ItemUsePPUp's move menu)
  if itemId == "PP_UP" then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    local mv = target.moves[moveIndex or 1]
    local mdef = mv and data.moves[mv.id]
    if mdef and (mv.ppUps or 0) < 3 then
      mv.ppUps = (mv.ppUps or 0) + 1
      -- each PP UP adds maxPP/5 uses on top of the base maximum
      mv.pp = mv.pp + math.floor(mdef.pp / 5)
      return "consumed", { Strings("%s's PP\nincreased!", mdef.name) }
    end
    return "failed", { Strings("It won't have\nany effect.") }
  end

  if itemDef and itemDef.machine then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    local speciesDef = data.pokemon[target.species]
    local ok = false
    for _, m in ipairs(speciesDef.tmhm) do
      if m == itemDef.machine.move then ok = true break end
    end
    if not ok then
      -- the only item-use refusal with a sound in pokered: item_effects.asm
      -- plays SFX_DENIED before MonCannotLearnMachineMoveText (the generic
      -- ItemUseNotTime/NoCyclingAllowedHere paths are silent)
      require("src.core.Sound").play(data, "Denied")
      return "failed", { Strings("%s can't\nlearn that move!", monName(data, target)) }
    end
    for _, mv in ipairs(target.moves) do
      if mv.id == itemDef.machine.move then
        return "failed", { Strings("It knows that\nmove already!") }
      end
    end
    -- HMs are never consumed; TMs are single-use
    return (itemDef.machine.kind == "HM" and "learnkept" or "learn"), itemDef.machine.move
  end

  if itemId == "OLD_ROD" or itemId == "GOOD_ROD" or itemId == "SUPER_ROD" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    -- FishingInit (engine/items/item_effects.asm): cp wWalkBikeSurfState, 2
    -- (surfing) sets carry, and every ItemUseXRod does jp c, ItemUseNotTime
    -- on that carry -- surfing refuses the rod with the same OAK text as
    -- the mid-battle case above, no rod-specific message (#533)
    if ow and ow.player and ow.player.surfing then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "fish", itemId
  end

  -- HOENN HAS TWO BIKES, AND THE BAG KNEW NEITHER.
  --
  -- Everything the Acro Bike needs was already written -- Collision's five
  -- obstacle behaviours, acroTrickPasses, the extractor's bikeBehaviours --
  -- and that rule's own comment said it was "already here and already
  -- tested, instead of a `return false` nobody remembers to revisit".  What
  -- was missing was smaller and further out: this line knew only the Game
  -- Boy's item id, so the two bikes Rydel gives you did nothing when used.
  --
  -- With no Acro Bike, Jagged Pass's bumpy-slope cells are a wall, and past
  -- them are Mt. Chimney and the Magma Hideout.
  if itemId == "BICYCLE" or itemId == "MACH_BIKE" or itemId == "ACRO_BIKE" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    -- WHICH one, so the overworld can set the rider's own rules: the Mach
    -- Bike climbs muddy slopes at speed, and the Acro Bike hops and
    -- wheelies over what stops everyone else
    return "bicycle", (itemId == "ACRO_BIKE" and "acro")
                      or (itemId == "MACH_BIKE" and "mach") or nil
  end

  if itemId == "ESCAPE_ROPE" then
    return "escape_rope"
  end
  -- THE POKeBLOCK CASE, which is the only way into the condition system from
  -- the bag.  It is a key item like the bike and the map, and it opens a
  -- screen rather than doing anything to the world.
  if itemId == "POKEBLOCK_CASE" then
    if battle then
      return "failed", { Strings("This isn't the time to use that!") }
    end
    return "pokeblock_case"
  end
  if itemId == "TOWN_MAP" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "townmap"
  end
  if itemId == "ITEMFINDER" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "itemfinder"
  end
  if itemId == "COIN_CASE" then
    return "failed", { Strings("Coin count:\n%d", save.coins or 0) }
  end
  if itemId == "REPEL" or itemId == "SUPER_REPEL" or itemId == "MAX_REPEL" then
    local steps = itemId == "REPEL" and 100 or itemId == "SUPER_REPEL" and 200 or 250
    save.repelSteps = steps
    return "consumed", { Strings("%s used\n%s!", save.player.name, name) }
  end

  return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
end

return ItemEffects
