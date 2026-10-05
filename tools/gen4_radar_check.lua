-- Run:  texlua tools/gen4_radar_check.lua <cache dir>
--
-- THE POKE RADAR (src/world/Gen4Radar.lua), per pokeplatinum src/pokeradar.c
-- and the radar arms of wild_encounters.c / encounter.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local R = require('src.world.Gen4Radar')

-- the rings: every pick lands on its ring's border, and covers it exactly
for ring = 0, 3 do
  local seen, n, ok = {}, 0, true
  for pick = 0, R.RING_CELLS[ring + 1] - 1 do
    local dx, dy = R.ringCell(ring, pick)
    local r = 4 - ring
    if math.max(math.abs(dx), math.abs(dy)) ~= r then ok = false end
    local k = dx .. ',' .. dy
    if not seen[k] then seen[k] = true n = n + 1 end
  end
  check(ok and n == R.RING_CELLS[ring + 1],
        ('ring %d: %d distinct cells, all on the %dx%d border'):format(ring, n, 9 - 2 * ring, 9 - 2 * ring))
end

-- spawning
local function seq(list) local i = 0 return function() i = i + 1 return list[i] or 0 end end
local chain = R.newChain()
check(not R.spawn(chain, 10, 10, function() return false end, seq({})), 'no tall grass anywhere: no patches')
check(not chain.active, 'and no chain')
chain = R.newChain()
check(R.spawn(chain, 10, 10, function() return true end, seq({ 0, 0, 0, 0 })), 'in grass: patches')
check(#chain.patches == 4 and chain.patches[1].x == 6 and chain.patches[1].y == 6
      and chain.patches[4].x == 9 and chain.patches[4].y == 9, 'pick 0 of each ring is its top-left corner')

-- continuing
R.setup(chain, false, seq({ 87, 88, 0, 0, 99, 99, 0, 0 }))
check(chain.patches[1].continueChain and not chain.patches[2].continueChain,
      'ring 0 continues on a roll under 88, ring 1 breaks on 88 (its rate is 68)')
check(not R.shinyRoll(0, function() return 0 end), 'no shiny at chain 0')
check(R.shinyRoll(5, function(n) return n == 7200 and 0 or 1 end), 'chain 5: 1 in 7200')
check(R.shinyRoll(40, function(n) return n == 200 and 0 or 1 end), 'chain 40 and up: 1 in 200')

-- the chain itself
chain = R.newChain()
R.spawn(chain, 10, 10, function() return true end, seq({ 0, 0, 0, 0 }))
for _, p in ipairs(chain.patches) do p.continueChain = true; p.shakeType = R.SOFT end
local slots = {}
for i = 1, 12 do slots[i] = { species = 396, level = 4, chance = 1 } end
local rolled = 0
local roll = function(t) rolled = rolled + 1 return { species = t[1].species, level = t[1].level } end
local save = {}
local e = R.encounter(chain, chain.patches[1], slots, nil, roll, save)
check(e.species == 396 and chain.count == 1 and chain.species == 396, 'the first patch starts the chain at 1 with what it rolled')
e = R.encounter(chain, chain.patches[1], slots, nil, roll, save)
check(e.species == 396 and e.level == 4 and chain.count == 2 and rolled == 1,
      'a continuing patch gives the SAME Pokemon without a roll, chain 2')
chain.patches[2].continueChain = false
local other = function() return { species = 399, level = 4 } end
R.encounter(chain, chain.patches[2], slots, nil, other, save)
check(not chain.active, 'a breaking patch with a different species ends the chain')
check(save.gen4RadarRecords and save.gen4RadarRecords[1].count == 2, 'the best chain is recorded')

-- hard shakes bring the radar species into slots 5, 6, 11, 12
chain = R.newChain()
R.spawn(chain, 10, 10, function() return true end, seq({ 0, 0, 0, 0 }))
chain.patches[1].shakeType = R.HARD
local seen
R.encounter(chain, chain.patches[1], slots, { 401, 402, 403, 404 }, function(t)
  seen = { t[5].species, t[6].species, t[11].species, t[12].species, t[1].species }
  return { species = 396, level = 4 }
end, {})
check(seen and seen[1] == 401 and seen[2] == 402 and seen[3] == 403 and seen[4] == 404 and seen[5] == 396,
      'a hard shake puts the radar species in slots 5, 6, 11 and 12')

-- after the battle
chain = R.newChain(); chain.active = true; chain.radarBattle = true
check(R.afterBattle(chain, 'caught'), 'a catch keeps the chain')
chain.radarBattle = true
check(not R.afterBattle(chain, 'run'), 'running ends it')
chain = R.newChain(); chain.active = true; chain.radarBattle = false
check(not R.afterBattle(chain, 'win'), 'and any battle that was not a radar battle ends it')

-- the battery
local s = {}
for _ = 1, 60 do R.charge(s, true) end
check(s.gen4RadarCharge == 50, 'the battery fills to 50 steps')
R.charge(s, false)

-- wiring
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('self:gen4RadarEncounter(encDef)', 1, true), 'the step asks the radar first')
check(ow:find('function OverworldState:gen4UseRadar()', 1, true), 'the item switches it on')
local ie = io.open('src/inventory/ItemEffects.lua'):read('a')
check(ie:find('itemDef.fieldUseFunc == 11', 1, true), 'by its use function (ITEM_USE_FUNC_POKE_RADAR)')
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
