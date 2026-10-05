-- Run:  texlua tools/gen4_town_map_check.lua <cache dir>
--
-- PLATINUM'S TOWN MAP (src/ui/Gen4TownMap.lua, src/import/Gen4TownMap.lua),
-- per pokeplatinum src/applications/town_map.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_town_map_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local function load(n) local f = loadfile(cacheDir .. '/' .. n .. '.lua') return f and f() end

local rec = load('gen4_town_map')
check(rec, 'the cache must carry gen4_town_map (run tools/gen4_town_map_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
check(#rec.blocks == 182, 'tmap_block.dat: 182 named cells')
check(#rec.flyLocations == 20 and #rec.firstArrival == 20, 'twenty fly locations')
check(rec.images.flyBlocks and #rec.images.flyBlocks == 7, 'seven block shapes')
check(rec.images.player and #rec.images.player == 2, 'two player icons')
check(rec.spritePalette and #rec.spritePalette >= 160, 'the sprite palettes (blocks use slots 5..9)')

local data = { gen4_town_map = rec, gen4_map_matrices = load('gen4_map_matrices'),
               maps = load('maps'), field = load('field'), text = {} }
local T = require('src.ui.Gen4TownMap')
local game = { data = data, save = { flags = {} }, stack = { pop = function() end } }

-- the grid lines up with the matrix: Twinleaf's block is on Twinleaf's cell
check(T.headerAt(game, 3, 27) == 411, 'matrix cell (3, 27) is Twinleaf (header 411)')
local tw = rec.flyLocations[1]
check(tw.x == 3 * 7 and tw.y == 27 * 7, 'and its block is at 7x, 7z before the grid offset')
local s = T.new(game, {})
check(s:nameAt(3, 27) == 'Twinleaf Town', 'the bar names it')
check(s:nameAt(11, 20) and s:nameAt(11, 20):find('Coronet'), 'off-matrix cells name Mt. Coronet')
check(s:blockAt(3, 27) ~= nil, 'and it has a name block')

-- unlocking
local rows = s:locations()
check(not rows[1].unlocked, 'Twinleaf locked on a new save')
game.save.flags.FLAG_G4_09B1 = true
rows = s:locations()
check(rows[1].unlocked, 'and open once its first-arrival flag is set')
check(s:flyLocationAt(411, 3, 27).loc == rows[1].loc, 'the cell finds its fly location')
check(s:flyLocationAt(172, 26, 17).loc.special == 'league'
      and s:flyLocationAt(172, 26, 18).loc.special == 'victoryRoad',
      'the League and outside Victory Road are told apart by cell')

-- the landing: by first-arrival id
local Fly = require('src.world.Gen4Fly')
local d = Fly.destinationFor(data, 68)
check(d and d.map, 'the Pokemon League (first arrival 68) has a landing spot')
local d16 = Fly.destinationFor(data, 16)
check(d16 and (d16.x ~= d.x or d16.y ~= d.y), 'and outside Victory Road (16) a different one')

-- wiring
local pm = io.open('src/ui/Gen4PartyMenu.lua'):read('a')
check(pm:find("require('src.ui.Gen4TownMap').new(game,{mode='fly'", 1, true), 'Fly opens the town map')
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('require("src.ui.Gen4TownMap").new(Game, opts or {})', 1, true), 'and so does the Town Map item')
local ie = io.open('src/inventory/ItemEffects.lua'):read('a')
check(ie:find('itemDef.fieldUseFunc == 2', 1, true), 'which is item 442 by its use function')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
