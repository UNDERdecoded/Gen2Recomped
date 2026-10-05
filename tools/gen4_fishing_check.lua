-- Run:  texlua tools/gen4_fishing_check.lua <cache dir>
--
-- FISHING IN SINNOH. Before this every Platinum rod answered "This isn't the
-- time to use that!", and every Platinum surf/rod encounter rolled with no
-- level. See src/world/Gen4Fishing.lua.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_fishing_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local function load(name)
  local f = loadfile(cacheDir .. '/' .. name .. '.lua')
  return f and f() or nil
end
local data = { maps = load('maps'), encounters = load('encounters'),
               items = load('items'), constants = load('constants') or {},
               gen4_feebas = load('gen4_feebas') }
data.constants.gen = 4

local F = require('src.world.Gen4Fishing')
local Encounter = require('src.world.Encounter')

-- ============================ 1. the rods are rods
local IE = require('src.inventory.ItemEffects')
local save = { player = { name = 'LUCAS' }, party = {}, inventory = {} }
local land = { player = { surfing = false }, map = { def = { header = 354 } } }
local surf = { player = { surfing = true }, map = { def = { header = 354 } } }
local dw = { player = { surfing = false }, map = { def = { header = 573 } } }
for _, id in ipairs({ 445, 446, 447 }) do
  check(IE.use(data, save, id, nil, nil, nil, land) == 'fish',
        'item ' .. id .. ' must be a rod')
  check(IE.use(data, save, id, nil, nil, nil, surf) == 'fish',
        'and usable while surfing, as `CanUseFishingRod` allows')
  check(IE.use(data, save, id, nil, nil, nil, dw) == 'failed',
        'but not in the Distortion World')
end

-- ...and `goFishing` must find the rod from whatever the bag row hands it.
-- The first version looked it up through `ItemEffects.recordFor`, which is the
-- PARTY-USE record and answers nil for a rod -- so the cast never reached
-- Sinnoh's tables even though the item check above passed.
for _, id in ipairs({ 445, '445', 'ITEM_445' }) do
  check(F.rodOf(data, id) == 'old', 'rodOf(' .. tostring(id) .. ') must be the Old Rod')
end
check(F.rodOf(data, 447) == 'super' and F.rodOf(data, 1) == nil, 'and only rods are rods')
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('require("src.world.Gen4Fishing").rodOf(Game.data, rod)', 1, true),
      'goFishing must resolve the rod by its item definition')

-- ============================ 2. levels for ranged slots
local lv = {}
for _ = 1, 400 do
  local e = Encounter.fromSlot({ species = 1, minLevel = 20, maxLevel = 30 })
  lv[e.level] = true
end
local lo, hi = math.huge, -math.huge
for l in pairs(lv) do lo = math.min(lo, l); hi = math.max(hi, l) end
check(lo == 20 and hi == 30, ('a 20..30 slot rolls 20..30 inclusive, got %s..%s')
      :format(tostring(lo), tostring(hi)))
check(Encounter.fromSlot({ species = 1, minLevel = 9, maxLevel = 5 }).level >= 5,
      'a reversed pair is swapped, as GetWildMonLevel does')
local v = Encounter.forMap(data, data.maps.R205A, 'R205A', 12, {})
local s = Encounter.chooseTable(v.water)
check(s and type(s.level) == 'number', 'a Platinum surf encounter has a level')

-- ============================ 3. the rod roll
-- A scripted rng: queue of answers, then 0.
local function rngOf(list)
  local i = 0
  return function(a, b) i = i + 1; local x = list[i]; if x == nil then return a end; return x end
end
local r208 = data.maps.R208
local miss = F.roll(data, {}, r208, 'R208', 'old', 0, 0, rngOf({ 99 }))
check(miss == nil, 'a roll of 99 against the Old Rod\'s rate is no bite')
local hit = F.roll(data, {}, r208, 'R208', 'old', 0, 0, rngOf({ 0, 0, 4 }))
check(hit and hit.species and hit.level, 'a roll under the rate bites, from the rod\'s own table')

-- ============================ 4. Feebas
local fb = data.gen4_feebas
check(fb and fb.species == 349 and #fb.tiles == 528,
      'the cache must carry the Feebas tiles (run tools/gen4_feebas_extract.lua)')
if fb then
  -- Independent re-reading of PlayerAvatar_IsFacingFeebasTile's grouping.
  local function expected(rand)
    local b = { math.floor(rand / 16777216) % 256, math.floor(rand / 65536) % 256,
                math.floor(rand / 256) % 256, rand % 256 }
    local n = #fb.tiles
    local g, ex, over, out = math.floor(n / 4), n % 4, 0, {}
    for i = 1, 4 do
      out[#out + 1] = fb.tiles[g * (i - 1) + (b[i] % g) + over + 1]
      if ex ~= 0 then over = over + 1; ex = ex - 1 end
    end
    table.sort(out)
    return out
  end
  local fsave = { gen4Swarm = { enabled = false, daily = 0, rand = 0xA1B2C3D4 } }
  local got = F.feebasTiles(fb, fsave)
  table.sort(got)
  local want = expected(0xA1B2C3D4)
  check(#got == 4 and table.concat(got, ',') == table.concat(want, ','),
        'four Feebas tiles a day, one per group -- got ' .. table.concat(got, ',')
        .. ' want ' .. table.concat(want, ','))
  local b1f = data.maps.D05R0113
  check(b1f and b1f.header == fb.header, 'D05R0113 must be Mt. Coronet B1F')
  local t = got[1]
  local tx, tz = t % 32, math.floor(t / 32)
  -- rate pass (0), coin pass (1), level roll
  local feebas = F.roll(data, fsave, b1f, 'D05R0113', 'old', tx, tz, rngOf({ 0, 1, 15 }))
  check(feebas and feebas.species == 349 and feebas.level >= 10 and feebas.level <= 20,
        'facing a Feebas tile, the bite is Feebas at 10..20')
  local coin = F.roll(data, fsave, b1f, 'D05R0113', 'old', tx, tz, rngOf({ 0, 0, 0, 0 }))
  check(coin and coin.species ~= 349, 'but only past the 50% coin')
  -- A tile that is not one of today's four.
  local other
  for _, c in ipairs(fb.tiles) do
    local hitT = false
    for _, gT in ipairs(got) do if gT == c then hitT = true end end
    if not hitT then other = c; break end
  end
  local plain = F.roll(data, fsave, b1f, 'D05R0113', 'old', other % 32, math.floor(other / 32),
                       rngOf({ 0, 1, 0, 0 }))
  check(plain and plain.species ~= 349, 'and only on today\'s four tiles')
  -- The day turning over moves them.
  require('src.world.Gen4Swarms').onDays(fsave, 1)
  local moved = F.feebasTiles(fb, fsave)
  table.sort(moved)
  check(table.concat(moved, ',') ~= table.concat(got, ','), 'a new day, new tiles')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
