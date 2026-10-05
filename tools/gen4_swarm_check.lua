-- Run:  texlua tools/gen4_swarm_check.lua <cache dir>
--
-- PLATINUM'S DAILY SWARMS. See src/world/Gen4Swarms.lua for the cartridge
-- functions each piece follows. Before this, `enableswarms` was a no-op and
-- `getswarmmapandspecies` answered 0, so no swarm ever happened in Sinnoh.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_swarm_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local data = {
  maps = assert(loadfile(cacheDir .. '/maps.lua'))(),
  encounters = assert(loadfile(cacheDir .. '/encounters.lua'))(),
}

local S = require('src.world.Gen4Swarms')

-- ============================ 1. ARNG_Next, exactly
-- Reference: 16-bit limbs, every partial product far below 2^53.
local function exact(seed)
  local a = 1812433253
  local s0, s1 = seed % 65536, math.floor(seed / 65536)
  local a0, a1 = a % 65536, math.floor(a / 65536)
  local p = s0 * a0 + ((s0 * a1 + s1 * a0) % 65536) * 65536
  return (p + 1) % 4294967296
end
local seed, bad = 0x12345678, 0
for _ = 1, 50000 do
  local e = exact(seed)
  if S.arngNext(seed) ~= e then bad = bad + 1 end
  seed = e
end
check(bad == 0, 'ARNG_Next must be exact over 50,000 steps, got ' .. bad .. ' wrong')
check(S.arngNext(0) == 1, 'ARNG_Next(0) is 1')

-- ============================ 2. the day turns the swarm over
local save = {}
check(not S.enabled(save), 'a new save has swarms off')
check(S.header(save) == 342, 'and before the first day turns over, swarmDaily is 0 -- Route 201')
local before = save.gen4Swarm.rand
S.onDays(save, 3)
check(save.gen4Swarm.daily == exact(exact(exact(before))),
      'each elapsed day advances the RNG once, and the daily takes its value')
check(S.header(save) == S.HEADERS[(save.gen4Swarm.daily % 22) + 1],
      'the swarm map is sSwarmMapIdTable[daily % 22]')
-- ...driven by the port's daily handler.
local Daily = require('src.script.Gen4Daily')
local r0 = save.gen4Swarm.rand
Daily.onDays(save, 1)
check(save.gen4Swarm.daily == exact(r0),
      'Gen4Daily.onDays must advance the swarm by exactly one day')

-- ============================ 3. every table entry is a real swarm map
local headers = {}
for id, def in pairs(data.maps) do headers[def.header] = { id = id, def = def } end
local found = 0
for _, h in ipairs(S.HEADERS) do
  local hit = headers[h]
  local area = hit and data.encounters[hit.def.encounters or hit.id]
  if area and area.swarm and (tonumber(area.swarm[1]) or 0) > 0 then found = found + 1 end
end
check(found == 22, 'all 22 swarm headers must be maps with a swarm species, got ' .. found)

-- ============================ 4. the scripts
local VM = require('src.script.Gen4ScriptVM')
local rows = VM.lower({ { name = 'enableswarms', args = {} } })
check(rows[1] and rows[1][1] == 'g4_enable_swarms', 'enableswarms must not be a no-op')
rows = VM.lower({ { name = 'getswarmmapandspecies', args = { 0x8000, 0x8001 } } })
check(rows[1] and rows[1][1] == 'g4_swarm_map_species', 'getswarmmapandspecies must answer')
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local ss = { gen4Vars = {}, gen4Swarm = { enabled = false, daily = 1, rand = 1 } }
local ctx = { save = ss, game = { data = data, save = ss } }
C.g4_enable_swarms(ctx)
check(S.enabled(ss), 'and enableswarms turns them on')
C.g4_swarm_map_species(ctx, 0x8000, 0x8001)
check(ss.gen4Vars[0x8000] == 343 and ss.gen4Vars[0x8001] == 263,
      'daily 1 is Route 202 and Zigzagoon -- got ' .. tostring(ss.gen4Vars[0x8000])
      .. ', ' .. tostring(ss.gen4Vars[0x8001]))

-- ============================ 5. the grass table on the swarm's map
local Encounter = require('src.world.Encounter')
local r202 = data.maps.R202
local view = Encounter.forMap(data, r202, 'R202', 12, ss)
local slots = view and view.swarmGrass
check(slots and slots[1].species == 263 and slots[2].species == 263,
      'on Route 202 the first two grass slots are Zigzagoon')
local plain = Encounter.forMap(data, r202, 'R202', 12, { gen4Swarm = { enabled = false, daily = 1 } })
check(plain and plain.swarmGrass == nil, 'with swarms off, the table is untouched')
local r201 = data.maps.R201
local other = Encounter.forMap(data, r201, 'R201', 12, ss)
check(other and other.swarmGrass == nil, 'and no other map swarms')
-- The day's swarm moving on must not leave a stale table cached.
ss.gen4Swarm.daily = 0
local moved = Encounter.forMap(data, r202, 'R202', 12, ss)
check(moved and moved.swarmGrass == nil, 'a new day\'s swarm elsewhere clears Route 202')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
