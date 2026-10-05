-- Run:  texlua tools/gen4_daily_slots_check.lua <cache dir>
--
-- THE TROPHY GARDEN'S AND THE GREAT MARSH'S DAILY POKEMON (grass slots 7 and
-- 8), per pokeplatinum's trophy_garden_daily_encounters.c,
-- great_marsh_daily_encounters.c and wild_encounters.c. See
-- src/world/Gen4DailySlots.lua.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_daily_slots_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local function load(name)
  local f = loadfile(cacheDir .. '/' .. name .. '.lua')
  return f and f()
end

local special = load('gen4_special_encounters')
check(special, 'the cache must carry gen4_special_encounters '
      .. '(run tools/gen4_special_encounters_extract.lua on an older cache)')
if not special then
  print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)); os.exit(1)
end
local tg = special.trophyGarden
check(#tg == 16 and tg[1] == 133 and tg[2] == 438 and tg[16] == 298,
      'sixteen garden Pokemon, Eevee first and Azurill last')
check(#special.greatMarsh.natdex == 32 and #special.greatMarsh.regional == 32,
      'two 32-entry marsh lists')
check(special.greatMarsh.natdex[1] == 454 and special.greatMarsh.regional[1] == 194,
      'the National Dex list opens with Toxicroak, the regional one with Wooper')

local data = { gen4_special_encounters = special,
               maps = load('maps'), encounters = load('encounters') }
local D = require('src.world.Gen4DailySlots')

-- ============================ 1. Mr. Backlot's draw
local save = { pokedex = { national = true } }
local seq = { 0, 0, 0, 5 }
local i = 0
local rng = function() i = i + 1; return seq[i] or 0 end
check(D.addTrophyMon(data, save, rng) == 0 and save.gen4TrophyGarden.slot1 == 0,
      'the first one goes in slot 1')
check(D.trophySlot1Species(data, save) == 133, 'and is what Backlot names (Eevee)')
local pick = D.addTrophyMon(data, save, rng)
check(pick == 5 and save.gen4TrophyGarden.slot1 == 5 and save.gen4TrophyGarden.slot2 == 0,
      'a repeat of a species already there is redrawn, then the new one SHIFTS the old down')

-- ============================ 2. the grass slots
local garden, marsh
for id, def in pairs(data.maps or {}) do
  if def.header == 287 then garden = def end
  if def.header == 506 then marsh = def end
end
check(garden and garden.label == 'Trophy Garden', 'header 287 is the Trophy Garden')
local s = garden and D.slotsFor(data, save, garden)
check(s and s[7] == 35 and s[8] == 133, 'slot 7 is the newest (Clefairy), slot 8 the one before (Eevee)')
check(D.slotsFor(data, { pokedex = {}, gen4TrophyGarden = save.gen4TrophyGarden }, garden) == nil,
      'and none of it before the National Dex')

local msave = { pokedex = { national = true }, gen4Swarm = { daily = 7 * 1024 + 3 } }
check(marsh and D.slotsFor(data, msave, marsh) == nil, 'the marsh pair needs a Safari Game')
msave.safari = { balls = 30 }
local m = marsh and D.slotsFor(data, msave, marsh)
-- header 506 is area 2: bits 10..14 of the daily -> 7
check(m and m[7] == special.greatMarsh.natdex[8] and m[8] == m[7],
      'area 2 reads bits 10..14 of the day\'s value, into both slots')
msave.pokedex.national = false
m = marsh and D.slotsFor(data, msave, marsh)
check(m and m[7] == special.greatMarsh.regional[8], 'and the regional list before the National Dex')

-- ============================ 3. the encounter table carries it
local Encounter = require('src.world.Encounter')
if garden and data.encounters then
  local view = Encounter.forMap(data, garden, nil, 12, save)
  local slots = view and view.grass and view.grass.slots
  check(slots and slots[7].species == 35 and slots[8].species == 133,
        'Encounter.forMap puts them in the Trophy Garden\'s grass')
  local before = Encounter.forMap(data, garden, nil, 12, { pokedex = {} })
  local bs = before and before.grass and before.grass.slots
  check(bs and bs[7].species ~= 35, 'and not without the National Dex')
end

-- ============================ 4. the script commands
local vm = io.open('src/script/Gen4ScriptVM.lua'):read('a')
check(vm:find('L.addtrophygardenmon', 1, true) and vm:find('L.gettrophygardenslot1species', 1, true),
      'both opcodes are lowered')
local cmds = io.open('src/script/Gen4Commands.lua'):read('a')
check(cmds:find('function Commands.g4_add_trophy_garden_mon', 1, true)
      and cmds:find('function Commands.g4_trophy_garden_slot1', 1, true), 'and run')
local dsrc = io.open('src/core/Data.lua'):read('a')
check(dsrc:match('local GEN4_PREFIXED = (%b{})'):find('"gen4_special_encounters"', 1, true),
      'Data.lua loads the lists')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
