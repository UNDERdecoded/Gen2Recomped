-- Run:  texlua tools/gen4_daycare_check.lua <cache dir>
--
-- PLATINUM'S SOLACEON DAY CARE (src/pokemon/Gen4DayCare.lua and the
-- g4_daycare_* commands), per overlay005/daycare.c and scrcmd_daycare.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local data = { pokemon = load('pokemon'), moves = load('moves'), constants = load('constants'),
               items = load('items'), gen4_egg_moves = load('gen4_egg_moves') }
check(data.gen4_egg_moves, 'the cache must carry gen4_egg_moves (run tools/gen4_egg_moves_extract.lua)')
if not (data.pokemon and data.gen4_egg_moves) then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
package.loaded['src.core.Data'] = data
package.loaded['src.core.GameVersion'] = { isGen4 = function() return true end, isGen2 = function() return false end,
  isGen3 = function() return false end, isYellow = function() return false end, get = function() return 'platinum' end }
-- the field normalization Data:seedDefaults applies to every personal row
local growth = { 'MEDIUM_FAST', 'ERRATIC', 'FLUCTUATING', 'MEDIUM_SLOW', 'FAST', 'SLOW' }
for _, def in pairs(data.pokemon) do
  local b = def.baseStats; b.spatk = b.spAttack; b.spdef = b.spDefense; b.special = b.spAttack
  def.evYield = def.evYields; def.evYield.spatk = def.evYield.spAttack; def.evYield.spdef = def.evYield.spDefense
  def.growthRate = growth[def.expRate + 1]; def.level1Moves = {}
  for _, row in ipairs(def.learnset or {}) do if row.level <= 1 then table.insert(def.level1Moves, row.move) end end
  def.spriteFront, def.spriteBack, def.forms, def.picAnim = nil, nil, nil, nil
end

local E = require('src.import.Gen4EggMoves')
local turtwigEgg = E.of(data.gen4_egg_moves, 387)
check(#turtwigEgg == 10 and turtwigEgg[1] == 388 and turtwigEgg[10] == 276, 'Turtwig\'s ten egg moves, Worry Seed first')
check(#E.of(data.gen4_egg_moves, 1) == 12, 'Bulbasaur twelve')

local DC = require('src.pokemon.Gen4DayCare')
local Pokemon = require('src.pokemon.Pokemon')
local function mon(species, level, personality, extra)
  local m = Pokemon.new(data, species, level)
  Pokemon.applySeed(data, m, { personality = personality })
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
-- personalities: Turtwig is 87.5% male, so a low byte of 0 is female, 255 male
local female = mon(387, 20, 0x00000100, { otId = 1 })
local male = mon(387, 20, 0x000001FF, { otId = 2, moves = { { id = 388, pp = 10 }, { id = 92, pp = 10 }, { id = 33, pp = 35 } } })
female.moves = { { id = 33, pp = 35 }, { id = 110, pp = 40 } }
male.moves[#male.moves + 1] = { id = 110, pp = 40 }
check(DC.gender(data, female) == 'female' and DC.gender(data, male) == 'male', 'gender from the personality\'s low byte')

local save = { party = { female, male, mon(25, 10, 5) }, player = { id = 1, name = 'LUCAS' }, money = 5000 }
check(DC.state(save) == DC.NO_MONS, 'empty: DAYCARE_NO_MONS (0)')
DC.deposit(data, save, 0)
check(#save.party == 2 and DC.state(save) == DC.ONE_MON, 'one in: DAYCARE_ONE_MON (2)')
DC.deposit(data, save, 0)
check(#save.party == 1 and DC.state(save) == DC.TWO_MONS, 'two in: DAYCARE_TWO_MONS (3)')
check(DC.compatibility(data, save) == DC.MAX and DC.compatibilityLevel(data, save) == 0,
      'same species, different OT: 70, "very well"')
save.player.id = 2; male.otId = nil
female.otId = 2
check(DC.compatibility(data, save) == DC.MED, 'same species, same OT: 50')
female.otId = 1; save.player.id = 1

-- 255 steps on the second mon: the roll (forced to succeed)
local realRandom = love.math and love.math.random
love.math = love.math or {}
love.math.random = function(a, b) return a end
for _ = 1, 254 do DC.update(data, save, { month = 6, day = 1 }) end
check(not DC.hasEgg(save), 'no egg before the 255th step')
DC.update(data, save, { month = 6, day = 1 })
check(DC.hasEgg(save) and DC.state(save) == DC.EGG_WAITING, 'the 255th step lays it: DAYCARE_EGG_WAITING (1)')
love.math.random = realRandom or math.random

-- the egg: Turtwig, with the father's egg move (Worry Seed), his TM
-- (Toxic) and the level-up move both know (Withdraw)
local game = { data = data, save = save }
local egg = DC.giveEgg(game, save)
check(egg and DC.speciesOf(egg) == 387 and egg.isEgg and egg.level == 1, 'a level 1 Turtwig egg')
local ids = {}
for _, mv in ipairs(egg.moves) do ids[#ids + 1] = mv.id end
local has = {}
for _, id in ipairs(ids) do has[id] = true end
check(has[388] and has[92] and has[110], 'Worry Seed, Toxic and Withdraw inherited: ' .. table.concat(ids, ','))
check(egg.eggCycles == data.pokemon[387].hatchCycles, 'its cycles are the species\' hatchCycles')
check(not DC.hasEgg(save), 'handing it over clears the personality')
check(save.party[#save.party] == egg, 'and it joins the party')

-- egg cycles: one every 255 steps, two with Flame Body in the party
egg.eggCycles = 1
local hatched
for _ = 1, 255 do hatched = DC.update(data, save, { month = 6, day = 1 }) or hatched end
check(egg.eggCycles == 0 and not hatched, 'cycle 255 takes the last cycle off')
for _ = 1, 255 do hatched = DC.update(data, save, { month = 6, day = 1 }) or hatched end
check(hatched == egg, 'the next cycle at zero hatches it')
check(DC.cycleLength({ month = 2, day = 14 }) == 230 and DC.cycleLength({ month = 2, day = 15 }) == 255,
      'Valentine\'s Day cycles at 230')

-- incense babies
save.gen4DayCare.mons[1].mon.species = 183 -- a Marill pair
save.gen4DayCare.mons[2].mon.species = 183
save.gen4DayCare.personality = 1
check(DC.eggSpecies(data, save) == 183, 'Marill without a Sea Incense: Marill')
save.gen4DayCare.mons[1].mon.item = 254
check(DC.eggSpecies(data, save) == 298, 'with one: Azurill')
save.gen4DayCare.mons[1].mon.item = nil
save.gen4DayCare.mons[1].mon.species = 387
save.gen4DayCare.mons[2].mon.species = 387
save.gen4DayCare.personality = 0

-- price and withdrawal: 100 + 100 a level, the banked EXP cashed in
local slot1 = save.gen4DayCare.mons[1]
slot1.steps = 5000
local gained = DC.gainedLevels(data, save, 0)
check(gained > 0 and DC.price(data, save, 0) == 100 + 100 * gained, 'price 100 + 100 per level (' .. gained .. ')')
local before = slot1.mon.level
check(DC.withdraw(data, save, 0) == 387 and save.party[#save.party].level == before + gained,
      'withdrawing cashes in the EXP')
check(DC.state(save) == DC.ONE_MON and save.gen4DayCare.mons[1] and not save.gen4DayCare.mons[2],
      'the second mon shifts down into slot 0')

-- the scripts lower fully
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = load('text') }
local bad = {}
for label in pairs(sdata.map_scripts.scripts) do
  if label:sub(1, 5) == 'M0501' then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      local n = row[1]
      if type(n) == 'string' and (not C[n] or n == 'g4_unimplemented') then bad[#bad + 1] = label .. ':' .. tostring(row[2]) end
    end
  end
end
check(#bad == 0, 'every Day Care script lowers: ' .. table.concat(bad, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
