-- Run:  texlua tools/gen4_hidden_paths_check.lua <cache dir>
--
-- SPRING PATH IS HIDDEN UNTIL IT IS UNLOCKED; SEABREAK PATH APPEARS WHEN IT IS.
--
-- `FieldMapChange_InitTerrainCollisionManager` (pokeplatinum
-- src/field_map_change.c) patches four cells of the overworld matrix on every
-- map change, from the save's hidden-location vars. The port had no patch and
-- lowered `sethiddenlocation` to a no-op, so Spring Path stood open from a new
-- game and Seabreak Path could never appear. See src/world/Gen4HiddenPaths.lua.

package.path = './?.lua;./?/init.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_hidden_paths_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local function load(name)
  return assert(loadfile(cacheDir .. '/' .. name .. '.lua'), name)()
end

local H = require('src.world.Gen4HiddenPaths')

-- ============================ 1. the vars are the cartridge's encoding
local save = {}
check(not H.unlocked(save, H.SPRING_PATH), 'a new save has nothing unlocked')
H.set(save, H.SPRING_PATH, true)
check(save.gen4Vars[0x4038] == 0x0312,
      'Spring Path is VAR 0x4038 = magic 0x0312, got '
      .. tostring(save.gen4Vars[0x4038]))
check(H.unlocked(save, H.SPRING_PATH), 'and that reads back as unlocked')
save.gen4Vars[0x4038] = 1
check(not H.unlocked(save, H.SPRING_PATH),
      'a var that is merely non-zero is NOT unlocked -- the cartridge compares '
      .. 'against the magic number')
H.set(save, H.SEABREAK_PATH, true)
check(save.gen4Vars[0x4039] == 0x1028, 'Seabreak Path is VAR 0x4039 = 0x1028')
H.set(save, H.SEABREAK_PATH, false)
check(save.gen4Vars[0x4039] == 0, 'and clearing writes 0')

-- A save made while the command was a no-op, already past the Spring Path
-- event (progress var 16554 >= 1), must not find the path sealed.
local old = { gen4Vars = { [16554] = 2 } }
check(#H.patches(old) == 0 or H.unlocked(old, H.SPRING_PATH),
      'an older save past the Spring Path event must be migrated to unlocked')
check(H.unlocked(old, H.SPRING_PATH), 'and must read back as unlocked')
check(not H.unlocked({ gen4Vars = { [16554] = 0 } }, H.SPRING_PATH)
      and #H.patches({ gen4Vars = {} }) == 4,
      'while a save before it stays sealed')

-- ============================ 2. the script command reaches it
local VM = require('src.script.Gen4ScriptVM')
local rows = VM.lower({ { name = 'sethiddenlocation', args = { 2, 1 } } })
check(rows[1] and rows[1][1] == 'g4_set_hidden_location',
      'sethiddenlocation must lower to a real command, not a no-op, got '
      .. tostring(rows[1] and rows[1][1]))
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local ctx = { save = {} }
C.g4_set_hidden_location(ctx, 2, 1)
check(H.unlocked(ctx.save, H.SPRING_PATH), 'running it unlocks the location')
-- ...with the location in a VAR, which is how the cartridge's scripts pass it.
ctx = { save = { gen4Vars = { [0x8004] = 3 } } }
C.g4_set_hidden_location(ctx, 0x8004, 1)
check(H.unlocked(ctx.save, H.SEABREAK_PATH), 'a var operand names the location')

-- Every site in the cartridge must lower to it.
local scripts = load('map_scripts')
local sites = 0
local function walk(t, seen)
  if type(t) ~= 'table' or seen[t] then return end
  seen[t] = true
  if t.name == 'sethiddenlocation' then sites = sites + 1 end
  for _, v in pairs(t) do walk(v, seen) end
end
walk(scripts, {})
check(sites >= 4, 'the cartridge sets hidden locations at several sites, got ' .. sites)

-- ============================ 3. the collision follows the save
local maps = load('maps')
local data = { maps = maps, map_layouts = load('map_layouts'),
               gen4_map_permissions = load('gen4_map_permissions') }
local MapLoader = require('src.world.MapLoader')

-- Walkable cells inside the given matrix chunks, read off the def.
local function walkable(def, chunks)
  local n = 0
  for _, c in ipairs(chunks) do
    for ty = 0, 31 do
      for tx = 0, 31 do
        local mx, my = c[1] * 32 + tx - (def.originX or 0), c[2] * 32 + ty - (def.originY or 0)
        if mx >= 0 and my >= 0 and mx < def.width and my < def.height then
          local i = my * def.width + mx
          local lo, hi = def.blocks:byte(i * 2 + 1, i * 2 + 2)
          if lo and (lo + hi * 256) ~= 255 then n = n + 1 end
        end
      end
    end
  end
  return n
end
local SPRING = { { 23, 21 }, { 24, 21 }, { 23, 22 }, { 24, 22 } }
local SEABREAK = { { 28, 15 }, { 27, 16 }, { 28, 16 }, { 27, 17 } }

local spring = maps.L04
check(spring and spring.label == 'Spring Path', 'L04 must be Spring Path')
MapLoader.resolveBlocks(data, spring)
local locked, unlocked = {}, {}
H.applyToDef(data, spring, locked)
local closed = walkable(spring, SPRING)
H.set(unlocked, H.SPRING_PATH, true)
H.applyToDef(data, spring, unlocked)
local open = walkable(spring, SPRING)
print(('Spring Path walkable cells: %d locked, %d unlocked'):format(closed, open))
-- MEASURED on Rev 1: 90 cells open, 0 sealed -- the path is a narrow one.
check(open >= 60, 'unlocked, Spring Path must be walkable, got ' .. open)
check(closed < open / 4, 'locked, it must be (nearly) sealed, got ' .. closed)
-- ...and locking again restores the sealed state, from the pristine snapshot.
H.applyToDef(data, spring, locked)
check(walkable(spring, SPRING) == closed, 're-locking must restore exactly')

local route = maps.R224
MapLoader.resolveBlocks(data, route)
local before = (function() H.applyToDef(data, route, {}); return walkable(route, SEABREAK) end)()
local letter = {}
H.set(letter, H.SEABREAK_PATH, true)
H.applyToDef(data, route, letter)
local after = walkable(route, SEABREAK)
print(('Route 224 Seabreak cells walkable: %d before Oak\'s Letter, %d after'):format(before, after))
check(after ~= before, 'unlocking Seabreak Path must change Route 224\'s collision')
check(route._blockArray == nil, 'and drop Map\'s decoded cache of the blocks')

-- The loader re-applies on a state change rather than serving a stale map.
local loaderSrc = io.open('src/world/MapLoader.lua'):read('a')
check(loaderSrc:find('gen4HiddenKey ~= Gen4HiddenPaths.key', 1, true),
      'MapLoader.load must rebuild a cached overworld map when the state changes')

-- ============================ 4. the ground draws the patched lands
local terrain = load('gen4_terrain')
local mats = load('gen4_map_matrices')
local grid = terrain.matrices[0]
local g2, a2 = H.grid(0, grid, mats[0].altitudes, {})
local i = 21 * grid.width + 23 + 1
check(g2.land[i] == 176 and a2[i] == 2,
      'locked, Spring Path draws land 176 at altitude 2')
check(grid.land[i] ~= 176 and mats[0].altitudes[i] ~= 2 or grid.land[i] ~= 176,
      'and the shared terrain tables are left untouched')
local g3 = H.grid(0, grid, mats[0].altitudes, unlocked)
check(g3.land[i] == grid.land[i], 'unlocked, it draws the shipped land')
local g4 = H.grid(0, grid, mats[0].altitudes, letter)
check(g4.land[15 * grid.width + 28 + 1] == 119, 'with the letter used, Seabreak draws 119')
check(H.grid(5, grid, nil, {}) == grid, 'and no other matrix is touched')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
