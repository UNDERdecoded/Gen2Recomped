-- Run:  python tools/run_lua_check.py tools/gen4_met_location_check.lua [<platinum cache>/data/generated]
--
-- PLATINUM'S MET LOCATION (src/pokemon/Gen4Origin.lua): a Pokemon caught,
-- given or hatched is stamped with the map's label (MapHeader_GetMapLabelTextID,
-- a place-name bank 433 index), which the Hall of Fame and the summary print
-- by name. Before, every Platinum Pokemon was met nowhere (BattleState.metHere
-- is a Gen 3 region-map section, nil on Gen 4 maps): "Met at ." in the Hall
-- of Fame at the end of the story. With a cache, the real labels are read too.

package.path = './?.lua;' .. package.path
local Origin = require('src.pokemon.Gen4Origin')

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local function dataset(family)
  return {
    constants = { gen = 4 },
    gen4_version = family and { family = family } or nil,
    maps = { R201 = { header = 342 }, T01R0202 = { header = 414 } },
    gen4_area_popup = { headers = { [342] = { text = 17 }, [414] = { text = 4 } } },
    text = { TEXT_B0433_00017 = 'Route 201', TEXT_B0433_00004 = 'Twinleaf\nTown' },
  }
end
local today = { year = 2026, month = 11, day = 14 }

local game = { data = dataset(), save = { player = { map = 'R201' } } }
local mon = {}
Origin.stamp(game, mon, 'met', nil, today)
check(mon.metLocation == 17, 'a catch on Route 201 is met at its label (17)')
check(Origin.placeName(game.data, mon.metLocation) == 'Route 201', '...which names Route 201')
check(Origin.placeName(game.data, 4) == 'Twinleaf Town', 'a two-line place name prints on one line')

game.save.player.map = 'T01R0202'
local egg = { isEgg = true }
Origin.stamp(game, egg, 'egg', 'Day-Care Couple', today)
check(egg.eggLocation == 'Day-Care Couple' and egg.metLocation == nil, 'an egg keeps its giver and is not met yet')
Origin.stamp(game, egg, 'hatch', nil, today)
check(egg.metLocation == 4 and egg.hatched, 'it hatches where it hatches (the house, 4)')

local given = {}
Origin.stamp(game, given, 'met', 'Pal Park', today)
check(given.metLocation == 'Pal Park', 'a location the caller names is kept')
Origin.stamp(game, given, 'met', nil, today)
check(given.metLocation == 'Pal Park', 'and a second receipt does not replace it')

local hg = { data = dataset('hgss'), save = { player = { map = 'R201' } } }
local hgMon = {}
Origin.stamp(hg, hgMon, 'met', nil, today)
check(hgMon.metLocation == nil and Origin.placeName(hg.data, 17) == nil,
      'HeartGold / SoulSilver (another place-name bank) are left as they were')
check(Origin.placeName(game.data, 'R201') == nil, 'a map id string is not a place-name index')

-- the map the player is on, not the one the last save names (save.player.map
-- is written by captureSave only): the starter is given on Route 201 with
-- the last save still in the bedroom
local live = { data = dataset(), save = { player = { map = 'T01R0202' } },
               overworld = { map = { id = 'R201' } } }
local starter = {}
Origin.stamp(live, starter, 'met', nil, today)
check(starter.metLocation == 17, 'met where the player stands (Route 201), not where the last save was')

-- the real labels
local dir = arg and arg[1]
if dir and dir ~= '' then
  dir = dir:gsub('[/\\]$', '')
  local popup = assert(loadfile(dir .. '/gen4_area_popup.lua'))()
  local maps = assert(loadfile(dir .. '/maps.lua'))()
  maps = maps.maps or maps
  local text = assert(loadfile(dir .. '/text.lua'))()
  local real = { constants = { gen = 4 }, maps = maps, gen4_area_popup = popup, text = text }
  local function at(map)
    local m = {}
    Origin.stamp({ data = real, save = { player = { map = map } } }, m, 'met', nil, today)
    return m.metLocation, Origin.placeName(real, m.metLocation)
  end
  local _, r201 = at('R201')
  check(r201 == 'Route 201', 'the cache: Route 201 (' .. tostring(r201) .. ')')
  -- the cartridge's language: item 1's name (Master Ball / Meisterball).
  -- The expected place names are per language; English stays exact.
  local items = assert(loadfile(dir .. '/items.lua'))()
  local ball = items[1] and items[1].name
  local lang = (ball == 'Master Ball') and 'en' or 'de'
  local expectBy = {
    en = { verity = 'Verity Lakefront', stark = 'Stark Mountain' },
    de = { verity = 'Wahrheitsufer', stark = 'Kahlberg' },
  }
  local expect = expectBy[lang]
  local _, verity = at('L01')
  check(verity == expect.verity, 'the cache (' .. lang .. '): ' .. expect.verity .. ' (' .. tostring(verity) .. ')')
  local _, stark = at('D16R0103')
  check(stark == expect.stark, 'the cache (' .. lang .. '): ' .. expect.stark .. ' (' .. tostring(stark) .. ')')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
