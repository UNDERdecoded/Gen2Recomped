-- PLATINUM'S DAY CARE (pokeplatinum src/overlay005/daycare.c,
-- src/scrcmd_daycare.c, src/daycare_save.c).
--
-- Sinnoh's day care is not the Johto or Hoenn one with a new coat of paint,
-- and src/pokemon/DayCare.lua -- which models those -- is left alone:
--
--   * ONE PAIR, TWO SLOTS, SHIFTED. Withdrawing slot 0 moves slot 1 down
--     (Daycare_ShiftMonSlots). Each slot banks one EXP per step.
--   * THE EGG IS A PERSONALITY, not a Pokemon. Every 256th step of the
--     second mon (its step count's low byte reaching 0xFF) the pair's
--     compatibility -- 0, 20, 50 or 70 -- is rolled against 0..99, and a
--     success stores the offspring's personality (Daycare_SetInheritedNature,
--     with the Everstone's coin flip). `Daycare_HasEgg` is "that personality
--     is non-zero". The egg itself is built when the man outside hands it
--     over (Daycare_GiveEggFromDaycare): species from the mother, incense
--     babies, form, three inherited IVs, the father's egg and TM moves, the
--     moves both parents share, Volt Tackle for a Light Ball Pichu.
--   * EGGS COUNT CYCLES, not steps, in the friendship byte: a shared counter
--     ticks every step and at 255 (230 on twelve special dates) takes one
--     cycle off every egg -- two with Flame Body or Magma Armor in the party.
--     An egg already at zero cycles hatches (Daycare_Update).
--
-- State lives in save.gen4DayCare = { mons = { {mon, steps}, {mon, steps} },
-- personality = 0, counter = 0 }.

local Gen4DayCare = {}

Gen4DayCare.NO_MONS, Gen4DayCare.EGG_WAITING = 0, 1
Gen4DayCare.ONE_MON, Gen4DayCare.TWO_MONS = 2, 3
Gen4DayCare.INCOMPATIBLE, Gen4DayCare.LOW, Gen4DayCare.MED, Gen4DayCare.MAX = 0, 20, 50, 70

local DITTO, NIDORAN_F, NIDORAN_M = 132, 29, 32
local ILLUMISE, VOLBEAT, MANAPHY, PHIONE, PICHU = 314, 313, 490, 489, 172
local EGG_GROUP_DITTO, EGG_GROUP_UNDISCOVERED = 13, 15
local ITEM_EVERSTONE, ITEM_LIGHT_BALL = 229, 236
local MOVE_VOLT_TACKLE = 344
local EGG_GENDER_MALE = 0x8000

-- sIncenseBabyTable: { baby, incense, what hatches without it }
Gen4DayCare.INCENSE = {
  { 360, 255, 202 },   -- Wynaut, Lax Incense, Wobbuffet
  { 298, 254, 183 },   -- Azurill, Sea Incense, Marill
  { 439, 314, 122 },   -- Mime Jr., Odd Incense, Mr. Mime
  { 438, 315, 185 },   -- Bonsly, Rock Incense, Sudowoodo
  { 446, 316, 143 },   -- Munchlax, Full Incense, Snorlax
  { 458, 317, 226 },   -- Mantyke, Wave Incense, Mantine
  { 406, 318, 315 },   -- Budew, Rose Incense, Roselia
  { 440, 319, 113 },   -- Happiny, Luck Incense, Chansey
  { 433, 320, 358 },   -- Chingling, Pure Incense, Chimecho
}

-- sEggCycleSpecialDates (month * 100 + day): a 230-step cycle on these.
Gen4DayCare.SPECIAL_DATES = { [112] = true, [214] = true, [303] = true, [401] = true,
  [501] = true, [611] = true, [707] = true, [821] = true, [907] = true, [928] = true,
  [1121] = true, [1214] = true }

local function rand(lo, hi) return (love and love.math and love.math.random or math.random)(lo, hi) end
local function rand32() return rand(0, 65535) * 65536 + rand(0, 65535) end

local function speciesOf(mon)
  local id = mon and mon.species
  return tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$")) or 0
end
Gen4DayCare.speciesOf = speciesOf

local function defOf(data, mon)
  local reg = data and data.pokemon or {}
  return reg[mon.species] or reg[speciesOf(mon)]
end

function Gen4DayCare.store(save, create)
  if not save then return nil end
  local dc = save.gen4DayCare
  if not dc and create then
    dc = { mons = {}, personality = 0, counter = 0 }
    save.gen4DayCare = dc
  end
  if dc then dc.mons = dc.mons or {} end
  return dc
end

function Gen4DayCare.slot(save, i)
  local dc = Gen4DayCare.store(save, false)
  return dc and dc.mons[i + 1] or nil
end

function Gen4DayCare.count(save)
  local dc = Gen4DayCare.store(save, false)
  if not dc then return 0 end
  local n = 0
  for i = 1, 2 do if dc.mons[i] and dc.mons[i].mon then n = n + 1 end end
  return n
end

function Gen4DayCare.hasEgg(save)
  local dc = Gen4DayCare.store(save, false)
  return dc ~= nil and (tonumber(dc.personality) or 0) ~= 0
end

-- Daycare_GetState
function Gen4DayCare.state(save)
  if Gen4DayCare.hasEgg(save) then return Gen4DayCare.EGG_WAITING end
  local n = Gen4DayCare.count(save)
  if n > 0 then return n + 1 end
  return Gen4DayCare.NO_MONS
end

-- Pokemon_GetGenderOf: the ratio against the personality's low byte.
function Gen4DayCare.gender(data, mon)
  local def = defOf(data, mon)
  local ratio = def and def.genderRatio
  if ratio == nil or ratio == 255 then return "none" end
  if ratio == 0 then return "male" end
  if ratio == 254 then return "female" end
  return ratio > ((tonumber(mon.personality) or 0) % 256) and "female" or "male"
end

local function otIdOf(save, mon)
  return mon.otId or (save and save.player and save.player.id) or 0
end

-- BoxMon_GetPairDaycareCompatibilityScore
function Gen4DayCare.compatibility(data, save)
  local a, b = Gen4DayCare.slot(save, 0), Gen4DayCare.slot(save, 1)
  if not (a and a.mon and b and b.mon) then return Gen4DayCare.INCOMPATIBLE end
  a, b = a.mon, b.mon
  local da, db = defOf(data, a), defOf(data, b)
  local ga, gb = (da and da.eggGroups) or {}, (db and db.eggGroups) or {}
  if ga[1] == EGG_GROUP_UNDISCOVERED or gb[1] == EGG_GROUP_UNDISCOVERED then return Gen4DayCare.INCOMPATIBLE end
  if ga[1] == EGG_GROUP_DITTO and gb[1] == EGG_GROUP_DITTO then return Gen4DayCare.INCOMPATIBLE end
  local sameOT = otIdOf(save, a) == otIdOf(save, b)
  if ga[1] == EGG_GROUP_DITTO or gb[1] == EGG_GROUP_DITTO then
    return sameOT and Gen4DayCare.LOW or Gen4DayCare.MED
  end
  local sa, sb = Gen4DayCare.gender(data, a), Gen4DayCare.gender(data, b)
  if sa == sb or sa == "none" or sb == "none" then return Gen4DayCare.INCOMPATIBLE end
  local shared = false
  for i = 1, 2 do for j = 1, 2 do
    if ga[i] ~= nil and ga[i] == gb[j] then shared = true end
  end end
  if not shared then return Gen4DayCare.INCOMPATIBLE end
  if speciesOf(a) == speciesOf(b) then
    return sameOT and Gen4DayCare.MED or Gen4DayCare.MAX
  end
  return sameOT and Gen4DayCare.LOW or Gen4DayCare.MED
end

-- DaycareCompatibilityScoreToLevel: the man's four answers, best first.
function Gen4DayCare.compatibilityLevel(data, save)
  local s = Gen4DayCare.compatibility(data, save)
  if s == Gen4DayCare.MAX then return 0 elseif s == Gen4DayCare.MED then return 1
  elseif s == Gen4DayCare.LOW then return 2 end
  return 3
end

-- ------------------------------------------------------------ depositing --

-- Daycare_MoveToEmptySlotFromParty. Shaymin goes back to Land Forme.
function Gen4DayCare.deposit(data, save, partySlot)
  local party = save and save.party or {}
  local mon = party[partySlot + 1]
  if not mon then return nil end
  local dc = Gen4DayCare.store(save, true)
  local i = (not (dc.mons[1] and dc.mons[1].mon)) and 1 or 2
  if speciesOf(mon) == 492 and (tonumber(mon.form) or 0) ~= 0 then
    require("src.pokemon.Gen4Forms").setForm(data, mon, 0)
  end
  table.remove(party, partySlot + 1)
  dc.mons[i] = { mon = mon, steps = 0 }
  return mon
end

-- The level a slot's mon would be at with its banked EXP (BoxPokemon_GiveExperience).
function Gen4DayCare.levelWithSteps(data, slot)
  local mon = slot and slot.mon
  if not mon then return 0 end
  local def = require("src.pokemon.Gen4Forms").definition(data, mon)
  local level = require("src.pokemon.Growth").levelForExp(def and def.growthRate,
    (tonumber(mon.exp) or 0) + (tonumber(slot.steps) or 0))
  return math.min(100, level)
end

function Gen4DayCare.gainedLevels(data, save, i)
  local slot = Gen4DayCare.slot(save, i)
  if not (slot and slot.mon) then return 0 end
  return Gen4DayCare.levelWithSteps(data, slot) - (tonumber(slot.mon.level) or 1)
end

-- DaycareMon_BufferDaycarePrice: 100 plus 100 a level.
function Gen4DayCare.price(data, save, i)
  return Gen4DayCare.gainedLevels(data, save, i) * 100 + 100
end

-- Daycare_MoveToPartyFromDaycareSlot: the banked EXP, the levels it buys
-- and every move learned on the way (a full set loses its first move,
-- ov5_021E63E0), then the slots shift down. Returns the species.
function Gen4DayCare.withdraw(data, save, i)
  local dc = Gen4DayCare.store(save, false)
  local slot = dc and dc.mons[i + 1]
  if not (slot and slot.mon) then return 0 end
  local mon = slot.mon
  local level = tonumber(mon.level) or 1
  if level < 100 then
    local def = require("src.pokemon.Gen4Forms").definition(data, mon)
    mon.exp = (tonumber(mon.exp) or 0) + (tonumber(slot.steps) or 0)
    local newLevel = Gen4DayCare.levelWithSteps(data, { mon = mon, steps = 0 })
    if newLevel > level then
      require("src.pokemon.Pokemon").learnMovesFromDayCare(data, mon, def, level, newLevel)
      mon.level = newLevel
      require("src.pokemon.Pokemon").applySeed(data, mon, {})
    end
  end
  save.party = save.party or {}
  save.party[#save.party + 1] = mon
  dc.mons[i + 1] = nil
  if not dc.mons[1] and dc.mons[2] then dc.mons[1], dc.mons[2] = dc.mons[2], nil end
  return speciesOf(mon)
end

-- --------------------------------------------------------------- the egg --

local function heldItem(mon) return tonumber(mon and (mon.item or mon.heldItem)) or 0 end
local function natureOf(p) return (tonumber(p) or 0) % 25 end

-- Daycare_GetParentToInheritNature / Daycare_SetInheritedNature
function Gen4DayCare.rollPersonality(data, save)
  local dc = Gen4DayCare.store(save, true)
  local mons = { dc.mons[1] and dc.mons[1].mon, dc.mons[2] and dc.mons[2].mon }
  local slot
  for i = 1, 2 do if mons[i] and Gen4DayCare.gender(data, mons[i]) == "female" then slot = i end end
  local dittos = 0
  for i = 1, 2 do if mons[i] and speciesOf(mons[i]) == DITTO then dittos = dittos + 1; slot = i end end
  if dittos == 2 then slot = rand(0, 65535) >= 0x7FFF and 1 or 2 end
  local inherit = slot and heldItem(mons[slot]) == ITEM_EVERSTONE and rand(0, 65535) < 0x7FFF
  local p
  if inherit then
    local nature = natureOf(mons[slot].personality)
    for _ = 1, 2401 do
      p = rand32()
      if natureOf(p) == nature and p ~= 0 then break end
    end
  else
    p = rand32()
  end
  dc.personality = (p ~= 0) and p or 1
  return dc.personality
end

-- Egg_DetermineEggSpeciesAndParentSlots: mother first, then father.
function Gen4DayCare.parents(data, save)
  local a, b = Gen4DayCare.slot(save, 0), Gen4DayCare.slot(save, 1)
  if not (a and a.mon and b and b.mon) then return nil end
  local mons = { a.mon, b.mon }
  local mother, father = 1, 2
  for i = 1, 2 do
    if speciesOf(mons[i]) == DITTO then mother, father = 3 - i, i
    elseif Gen4DayCare.gender(data, mons[i]) == "female" then mother, father = i, 3 - i end
  end
  local motherMon, fatherMon = mons[mother], mons[father]
  -- with Ditto beside a male, Ditto is the "mother" for the moves
  local speciesParent = motherMon
  if speciesOf(fatherMon) == DITTO and Gen4DayCare.gender(data, motherMon) ~= "female" then
    motherMon, fatherMon = fatherMon, motherMon
  end
  return motherMon, fatherMon, speciesParent
end

function Gen4DayCare.eggSpecies(data, save)
  local _, _, speciesParent = Gen4DayCare.parents(data, save)
  if not speciesParent then return nil end
  local dc = Gen4DayCare.store(save, false)
  local species = tonumber(require("src.pokemon.DayCare").baseForm(data, speciesOf(speciesParent)))
    or speciesOf(speciesParent)
  local male = math.floor((tonumber(dc and dc.personality) or 0) / EGG_GENDER_MALE) % 2 == 1
  if species == NIDORAN_F then species = male and NIDORAN_M or NIDORAN_F end
  if species == ILLUMISE then species = male and VOLBEAT or ILLUMISE end
  if species == MANAPHY then species = PHIONE end
  -- Daycare_AlterEggSpeciesWithIncenseItem
  local a, b = Gen4DayCare.slot(save, 0).mon, Gen4DayCare.slot(save, 1).mon
  for _, row in ipairs(Gen4DayCare.INCENSE) do
    if species == row[1] then
      if heldItem(a) ~= row[2] and heldItem(b) ~= row[2] then species = row[3] end
      break
    end
  end
  return species
end

local function moveId(mv) return tonumber(mv) or tonumber(mv and mv.id) or 0 end

-- Pokemon_AddMove, then Pokemon_ReplaceMove when all four are full.
local function addMove(data, egg, id)
  egg.moves = egg.moves or {}
  for _, mv in ipairs(egg.moves) do if moveId(mv) == id then return end end
  local def = data.moves and data.moves[id]
  local slot = { id = id, pp = def and def.pp or 0 }
  if #egg.moves >= 4 then table.remove(egg.moves, 1) end
  egg.moves[#egg.moves + 1] = slot
end

-- Egg_BuildMoveset
function Gen4DayCare.buildMoves(data, egg, father, mother)
  local def = require("src.pokemon.Gen4Forms").definition(data, egg)
  local fatherMoves, motherMoves = {}, {}
  for i = 1, 4 do
    fatherMoves[i] = moveId((father.moves or {})[i])
    motherMoves[i] = moveId((mother.moves or {})[i])
  end
  local eggMoves = require("src.import.Gen4EggMoves").of(data.gen4_egg_moves, speciesOf(egg))
  for i = 1, 4 do
    local m = fatherMoves[i]
    if m == 0 then break end
    for _, e in ipairs(eggMoves) do
      if m == e then addMove(data, egg, m) break end
    end
  end
  local machine = {}
  for _, id in ipairs((def and def.tmhm) or {}) do machine[tonumber(id)] = true end
  for i = 1, 4 do
    local m = fatherMoves[i]
    if m ~= 0 and machine[m] then addMove(data, egg, m) end
  end
  local shared = {}
  for i = 1, 4 do
    if fatherMoves[i] == 0 then break end
    for j = 1, 4 do
      if fatherMoves[i] == motherMoves[j] then shared[#shared + 1] = fatherMoves[i] end
    end
  end
  local byLevel = {}
  for _, e in ipairs((def and def.learnset) or {}) do byLevel[e.move] = true end
  for _, m in ipairs(shared) do
    if byLevel[m] then addMove(data, egg, m) end
  end
end

-- Daycare_GiveEggFromDaycare. Returns the egg, now last in the party.
function Gen4DayCare.giveEgg(game, save)
  local data = game.data
  local dc = Gen4DayCare.store(save, false)
  if not dc then return nil end
  local mother, father = Gen4DayCare.parents(data, save)
  local species = Gen4DayCare.eggSpecies(data, save)
  if not (mother and species) then return nil end
  -- the form is read from parentSlots[0] AFTER the Ditto swap
  local form = tonumber(mother.form) or 0
  local Pokemon = require("src.pokemon.Pokemon")
  local reg = data.pokemon or {}
  local key = reg[species] and species or ("SPECIES_%03d"):format(species)
  local ok, egg = pcall(Pokemon.new, data, key, 1, nil, form ~= 0 and form or nil)
  if not ok then egg = Pokemon.new(data, key, 1) end
  Pokemon.applySeed(data, egg, { personality = dc.personality })
  -- Egg_InheritIVs: three different stats, each from either parent
  local stats = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
  local parents = { Gen4DayCare.slot(save, 0).mon, Gen4DayCare.slot(save, 1).mon }
  local pool = { 1, 2, 3, 4, 5, 6 }
  local picked = {}
  for i = 1, 3 do picked[i] = table.remove(pool, rand(0, 65535) % (6 - i + 1) + 1) end
  egg.ivs = egg.ivs or {}
  for i = 1, 3 do
    local from = parents[rand(0, 65535) % 2 + 1]
    local key2 = stats[picked[i]]
    local iv = from and from.ivs and from.ivs[key2]
    if iv then egg.ivs[key2] = iv end
  end
  Pokemon.applySeed(data, egg, {})
  Gen4DayCare.buildMoves(data, egg, father, mother)
  if species == PICHU and (heldItem(parents[1]) == ITEM_LIGHT_BALL or heldItem(parents[2]) == ITEM_LIGHT_BALL) then
    addMove(data, egg, MOVE_VOLT_TACKLE)
  end
  local def = reg[key] or {}
  egg.isEgg = true
  egg.nickname = "EGG"
  egg.eggCycles = tonumber(def.hatchCycles) or 20
  egg.eggSteps = egg.eggCycles * 256
  egg.otId = save.player and save.player.id or egg.otId
  egg.otName = save.player and save.player.name or egg.otName
  require("src.pokemon.Gen4Origin").stamp(game, egg, "egg", "Day-Care Couple")
  save.party = save.party or {}
  save.party[#save.party + 1] = egg
  dc.personality, dc.counter = 0, 0
  return egg
end

-- ----------------------------------------------------------------- steps --

-- An egg's remaining cycles. Older saves carry steps; a cycle is 256 of
-- them there, and the species' own hatchCycles caps what that reads as.
function Gen4DayCare.cyclesOf(data, mon)
  if mon.eggCycles ~= nil then return tonumber(mon.eggCycles) or 0 end
  local def = defOf(data, mon) or {}
  local cap = tonumber(def.hatchCycles) or 20
  local steps = tonumber(mon.eggSteps)
  local c = steps and math.ceil(steps / 256) or cap
  return math.min(c, cap)
end

-- Party_GetEggCyclesToSubtract
function Gen4DayCare.cyclesToSubtract(data, party)
  for _, mon in ipairs(party or {}) do
    if not require("src.pokemon.Party").isEgg(mon) then
      local def = defOf(data, mon)
      local ok, ability = pcall(function()
        return require("src.battle.Abilities").of({ mon = mon, def = def })
      end)
      if ok and (ability == "FLAME_BODY" or ability == "MAGMA_ARMOR") then return 2 end
    end
  end
  return 1
end

function Gen4DayCare.cycleLength(now)
  local t = now or os.date("*t")
  return Gen4DayCare.SPECIAL_DATES[t.month * 100 + t.day] and 230 or 255
end

-- Daycare_Update, once a step. Returns the egg that hatches, if one does.
function Gen4DayCare.update(data, save, now)
  local dc = Gen4DayCare.store(save, true)
  local n = 0
  for i = 1, 2 do
    local slot = dc.mons[i]
    if slot and slot.mon then slot.steps = (tonumber(slot.steps) or 0) + 1; n = n + 1 end
  end
  if not Gen4DayCare.hasEgg(save) and n == 2 and (dc.mons[2].steps % 256) == 255 then
    local score = Gen4DayCare.compatibility(data, save)
    local roll = math.floor(rand(0, 65535) * 100 / 0xFFFF)
    if score > roll then Gen4DayCare.rollPersonality(data, save) end
  end
  dc.counter = (tonumber(dc.counter) or 0) + 1
  if dc.counter ~= Gen4DayCare.cycleLength(now) then return nil end
  dc.counter = 0
  local party = save.party or {}
  local subtract = Gen4DayCare.cyclesToSubtract(data, party)
  for _, mon in ipairs(party) do
    if mon.isEgg and not (mon.isBadEgg or mon.badEgg) then
      local cycles = Gen4DayCare.cyclesOf(data, mon)
      if cycles == 0 then return mon end
      cycles = cycles >= subtract and cycles - subtract or cycles - 1
      mon.eggCycles = cycles
      mon.eggSteps = math.max(1, cycles * 256)
    end
  end
  return nil
end

return Gen4DayCare
