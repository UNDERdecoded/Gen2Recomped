-- Run:  texlua tools/gen4_wild_lead_check.lua <cache dir>
--
-- THE LEAD POKEMON'S EFFECT ON A WILD ENCOUNTER, per `TryGenerateWildMon`
-- (pokeplatinum src/overlay006/wild_encounters.c). See
-- src/world/Gen4WildLead.lua. None of it existed for Platinum.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_wild_lead_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local data = { pokemon = assert(loadfile(cacheDir .. '/pokemon.lua'))(),
               constants = assert(loadfile(cacheDir .. '/constants.lua'))() }
data.constants.gen = 4
for _, def in pairs(data.pokemon) do      -- Data's load-time normalisation
  local bs = type(def) == 'table' and def.baseStats
  if type(bs) == 'table' and bs.spatk == nil and bs.spAttack ~= nil then
    bs.spatk, bs.spdef = bs.spAttack, bs.spDefense
  end
  if type(def) == 'table' and def.evYield == nil and type(def.evYields) == 'table' then
    def.evYield = def.evYields
  end
end

local L = require('src.world.Gen4WildLead')

-- A lead with a given ability: the species is picked so `abilities[1]` IS it.
local function leadWith(ability, level, extra)
  for id, def in pairs(data.pokemon) do
    if type(def) == 'table' and def.abilities and def.abilities[1] == ability then
      local mon = { species = id, level = level or 50, abilitySlot = 1,
                    personality = 7 }
      for k, v in pairs(extra or {}) do mon[k] = v end
      return { party = { mon } }
    end
  end
  error('no species with ' .. ability)
end
-- A scripted rng: answers in order, then the low bound.
local function rngOf(list)
  local i = 0
  return function(a, b) i = i + 1; local x = list[i]; if x == nil then return a end; return x end
end

-- Real species: 81 Magnemite (Electric/Steel), 25 Pikachu (Electric),
-- 16 Pidgey (Normal/Flying), 396 Starly.
local grass = {}
for i = 1, 12 do grass[i] = { species = 396, level = 3 } end
grass[11] = { species = 81, level = 20 }

-- ============================ 1. slot odds without a lead ability
local none = { party = { { species = 1, level = 50, abilitySlot = 1 } } }   -- Overgrow: no field effect
check(L.choose(data, none, grass, 'grass', nil, rngOf({ 98 })).slot == 11,
      'grass roll 98 is slot 11 (the cartridge\'s 1% slot)')
check(L.choose(data, none, grass, 'grass', nil, rngOf({ 19 })).slot == 1
      and L.choose(data, none, grass, 'grass', nil, rngOf({ 20 })).slot == 2,
      'and 0..19 / 20..39 are slots 1 and 2')
local rod = {}
for i = 1, 5 do rod[i] = { species = 129, minLevel = 10, maxLevel = 10 } end
check(L.choose(data, none, rod, 'rod', 'good', rngOf({ 45 })).slot == 2,
      'Good Rod roll 45 is slot 2 -- 40/40/15/4/1, not the data\'s 60/30')
check(L.choose(data, none, rod, 'rod', 'old', rngOf({ 45 })).slot == 1,
      'while the Old Rod\'s 45 is slot 1')

-- ============================ 2. Magnet Pull / Static
local mp = leadWith('MAGNET_PULL')
local e = L.choose(data, mp, grass, 'grass', nil, rngOf({ 0, 1 }))
check(e.species == 81, 'Magnet Pull forces the one Steel slot on grass')
local st = leadWith('STATIC')
e = L.choose(data, st, grass, 'grass', nil, rngOf({ 0, 1 }))
check(e.species == 81, 'Static forces the Electric slot')
e = L.choose(data, st, grass, 'grass', nil, rngOf({ 1, 0 }))
check(e.species == 396, 'but only on its 50%')
local allElectric = {}
for i = 1, 12 do allElectric[i] = { species = 25, level = 5 } end
e = L.choose(data, st, allElectric, 'grass', nil, rngOf({ 0, 30 }))
check(e.slot == 2, 'and not when every slot already is Electric')
local water = {}
for i = 1, 5 do water[i] = { species = 129, minLevel = 20, maxLevel = 30 } end
water[5] = { species = 81, minLevel = 20, maxLevel = 20 }
e = L.choose(data, mp, water, 'water', nil, rngOf({ 0, 1, 10 }))
check(e.species ~= 81, 'on water Magnet Pull is lost to the Static check (cartridge bug)')

-- ============================ 3. Hustle / Vital Spirit / Pressure
local hu = leadWith('HUSTLE')
local mixed = {}
for i = 1, 12 do mixed[i] = { species = 396, level = 3 } end
mixed[5] = { species = 396, level = 9 }
e = L.choose(data, hu, mixed, 'grass', nil, rngOf({ 0, 1 }))
check(e.level == 9, 'Hustle moves to the same species\' highest-level slot')
e = L.choose(data, hu, water, 'water', nil, rngOf({ 0, 22, 1 }))
check(e.level == 30, 'and on water takes the slot\'s max level on its 50%')

-- ============================ 4. Keen Eye / Intimidate
local ke = leadWith('KEEN_EYE', 30)
local weak = {}
for i = 1, 12 do weak[i] = { species = 396, level = 5 } end
check(L.choose(data, ke, weak, 'grass', nil, rngOf({ 0, 0 })) == nil,
      'Keen Eye turns away an encounter 5+ levels below the lead, half the time')
check(L.choose(data, ke, weak, 'grass', nil, rngOf({ 0, 1 })) ~= nil, 'only half')
local low = leadWith('KEEN_EYE', 5)
check(L.choose(data, low, weak, 'grass', nil, rngOf({ 0, 0 })) ~= nil,
      'and never for a lead of level 5 or below')

-- ============================ 5. Synchronize and Cute Charm
local sy = leadWith('SYNCHRONIZE', 50, { personality = 25 * 1000 + 13 })
e = L.choose(data, sy, grass, 'grass', nil, rngOf({ 0, 0 }))
check(e.nature == 13, 'Synchronize hands over the lead\'s nature on its 50%')
local Stats = require('src.pokemon.Stats')
local Forms = require('src.pokemon.Gen4Forms')
local wild = { species = 396, level = 5, ivs = Stats.randomIVs(math.random), evs = {} }
L.apply(data, wild, 13, 'female')
check(wild.personality % 25 == 13, 'and the wild personality is re-drawn to carry it')
check(require('src.pokemon.DayCare').gender(data, wild) == 'female', 'with the gender asked for')
local cc = leadWith('CUTE_CHARM', 50, { personality = 255 })
local leadG = require('src.pokemon.Pokemon').genderOf(data, cc.party[1])
e = L.choose(data, cc, grass, 'grass', nil, rngOf({ 0, 3, 1 }))
check(leadG and e.gender and e.gender ~= leadG,
      'Cute Charm asks for the opposite gender ('
      .. tostring(leadG) .. ' -> ' .. tostring(e.gender) .. ')')

-- ============================ 6. wild held items (and Compound Eyes)
--
-- Platinum stores them as `heldItems = { common, rare }`; the port read only
-- Hoenn's field names, so no wild Pokemon in Sinnoh ever held an item.
local BS = require('src.battle.BattleState')
local withItems, sameItems
for id, def in pairs(data.pokemon) do
  local h = type(def) == 'table' and def.heldItems
  if h and (h.common or 0) ~= 0 and (h.rare or 0) ~= 0 then
    if h.common ~= h.rare and not withItems then withItems = id end
    if h.common == h.rare and not sameItems then sameItems = id end
  end
end
check(withItems, 'the cache must carry species with two different held items')
if withItems then
  local h = data.pokemon[withItems].heldItems
  local function roll(r, eyes)
    local m = { species = withItems }
    BS.giveWildHeldItem(data, m, function() return r end, eyes)
    return m.item
  end
  check(roll(44) == nil and roll(45) == h.common and roll(94) == h.common
        and roll(95) == h.rare, '45% nothing, 50% common, 5% rare')
  check(roll(19, true) == nil and roll(20, true) == h.common
        and roll(79, true) == h.common and roll(80, true) == h.rare,
        'and 20/60/20 behind a Compound Eyes lead')
end
if sameItems then
  local m = { species = sameItems }
  BS.giveWildHeldItem(data, m, function() return 0 end)
  check(m.item == data.pokemon[sameItems].heldItems.common,
        'a species whose two items match always holds it')
end

-- ============================ 7. wired into every Gen 4 creation path
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(select(2, ow:gsub('src.world.Gen4WildLead', '')) >= 2,
      'the step and Sweet Scent rolls must use it')
local fish = io.open('src/world/Gen4Fishing.lua'):read('a')
check(fish:find('Gen4WildLead").choose', 1, true), 'and fishing')
local bs = io.open('src/battle/BattleState.lua'):read('a')
check(bs:find('Gen4WildLead").apply(game.data, wild, opts.nature, opts.gender)', 1, true),
      'and newWild must apply the nature and gender')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
