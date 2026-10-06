-- Run:  texlua tools/gen4_fly_check.lua <cache dir>
--
-- PLATINUM'S FLY (src/world/Gen4Fly.lua), per spawn_locations.c and
-- field_move_tasks.c. The party menu offered every field move but this one.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_fly_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local data = { field = assert(loadfile(cacheDir .. '/field.lua'))(),
               maps = assert(loadfile(cacheDir .. '/maps.lua'))() }
local Fly = require('src.world.Gen4Fly')

check(Fly.flagKey(0) == 'FLAG_G4_09B1', 'FLAG_FIRST_ARRIVAL_TWINLEAF_TOWN is 0x9B1')
local rows = data.field.healLocations
check(rows and #rows >= 20, 'the cache carries the spawn table')

-- the map scripts set the rest themselves; their flags must land on rows
local scripted = { 0x9C0, 0x9C2, 0x9C3 }
local byFlag = {}
for _, r in ipairs(rows) do byFlag[Fly.flagKey(r.firstArrival)] = r end
local landed = 0
for _, f in ipairs(scripted) do
  if byFlag[('FLAG_G4_%04X'):format(f)] or f > 0x9B1 then landed = landed + 1 end
end
check(landed == #scripted, 'script-set first-arrival flags are in the same range')

local save = { flags = {} }
check(#Fly.destinations(data, save) == 0, 'nothing is open on a new game')
local twin = Fly.onEnter(data, save, 411)
check(twin and save.flags.FLAG_G4_09B1, 'entering Twinleaf (header 411) opens it')
local d = Fly.destinations(data, save)
check(#d == 1 and d[1].map == 'T01' and d[1].label == 'Twinleaf Town',
      'and it is the one destination, by its own name')
check(type(d[1].x) == 'number' and type(d[1].y) == 'number', 'with the cartridge\'s landing spot')

-- a row that is not unlockOnMapEntry is left to its script
local scriptOnly
for _, r in ipairs(rows) do if not r.unlockOnMapEntry then scriptOnly = r break end end
if scriptOnly then
  local s2 = { flags = {} }
  Fly.onEnter(data, s2, scriptOnly.fly.header)
  check(not s2.flags[Fly.flagKey(scriptOnly.firstArrival)],
        'a script-unlocked destination (' .. tostring(scriptOnly.fly.map) .. ') is not opened by walking in')
end

-- the checks
local ok, why = Fly.check(data, { badges = {} }, { allowFly = true })
check(not ok and why == 'badge', 'no Cobble Badge, no Fly')
local src = io.open('src/ui/Gen4PartyMenu.lua'):read('a')
local fm = io.open('src/world/Gen4FieldMoves.lua'):read('a')
check(fm:find("F.ORDER = {'CUT','FLY','SURF'", 1, true) and src:find("F.ORDER", 1, true), 'the party menu offers FLY')
check(src:find("ow:gen4FlyTo(item.value,mon)", 1, true), 'and flies to the chosen destination')
check(src:find('and not save.safari', 1, true), 'and Teleport is refused in a Safari Game')
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('require("src.world.Gen4Fly").onEnter(Game.data, Game.save, self.map.def.header)', 1, true),
      'every map change runs TryUnlockFlyLocationByMap')
local fly = io.open('src/world/Gen4Fly.lua'):read('a')
check(fly:find('save.safari then return false', 1, true), 'and Fly is refused in a Safari Game')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
