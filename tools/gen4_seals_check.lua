-- Run:  texlua tools/gen4_seals_check.lua <cache dir>
--
-- PLATINUM'S BALL SEALS (src/import/Gen4Seals.lua, the g4_*seal* commands and
-- Sunyshore Market's seal counter), per ball_seal_info.c,
-- capsule_menu/main.c (sealTypeValues) and mart_items.h.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
package.loaded['src.core.GameVersion'] = { isGen4 = function() return true end, isGen2 = function() return false end,
  isGen3 = function() return false end, isYellow = function() return false end, get = function() return 'platinum' end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_seals')
check(rec, 'the cache must carry gen4_seals (run tools/gen4_seals_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
local text, items = load('text'), load('items')
local data = { gen4_seals = rec, text = text, items = items, isGen4Cache = true }
local S = require('src.import.Gen4Seals')

-- the tables, against sealTypeValues and SunyshoreMarketDailyStocks
check(rec.seals[0].price == 999 and rec.seals[1].price == 50 and rec.seals[5].price == 100,
      'prices: the dummy 999, Heart Seal A 50, Heart Seal E 100')
check(rec.seals[16].nameIndex == 77 and rec.seals[17].nameIndex == 16 and rec.seals[29].nameIndex == 28,
      "name indices are the table's own (seal 16 names entry 77, seal 29 entry 28)")
check(rec.seals[50].alphabet and not rec.seals[49].alphabet and rec.seals[50].price == 0,
      'the Unown A-Z seals (50..) are the alphabet seals and are not for sale')
check(#rec.stocks == 7, 'seven days')
check(table.concat(rec.stocks[1], ',') == '1,8,29,43,15,22,36', 'Monday: Heart A, Star B, Fire A, Song A, Line C, Ele B, Party D')
check(table.concat(rec.stocks[7], ',') == '7,49,28,42,14,21,35', 'Sunday: Star A, Song G, Foamy D ...')
check(S.name(data, 1) == 'Heart Seal A' and S.name(data, 1, true) == 'Heart Seal As', 'names from banks 12 / 13')
check(S.name(data, 29) == 'Fire Seal A', 'seal 29 is Fire Seal A by its name index')

-- GiveOrTakeSeal
local save = { gen4Vars = {}, money = 10000, party = {} }
check(S.change(save, 1, 99) and S.count(save, 1) == 99, '99 of a kind fit')
check(not S.change(save, 1, 1) and S.count(save, 1) == 99, 'the 100th is refused, not clamped')
check(not S.change(save, 2, -1) and S.count(save, 2) == 0, 'taking what is not there is refused')
check(S.unique(save) == 1 and S.total(save) == 99, 'unique 1, total 99')

-- the commands
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local game = { data = data, save = save, stringBuffers = {} }
local pushed
game.stack = { push = function(_, s) pushed = s end, pop = function() end }
local ctx = { game = game, save = save, runner = { resume = function() end, yield = function() end } }
local function var(v) return save.gen4Vars[v] end
save.gen4Vars[0x8007] = 51  -- an Unown seal
save.gen4Vars[0x8000] = 3
C.g4_give_or_take_seal(ctx, 0x8007, 0x8000)
C.g4_count_seal(ctx, 0x8007, 0x800C)
check(var(0x800C) == 3, 'giveortakeseal 3, countsealoccurence 3')
save.gen4Vars[0x8000] = 0xFFFF
C.g4_give_or_take_seal(ctx, 0x8007, 0x8000)
C.g4_count_seal(ctx, 0x8007, 0x800C)
check(var(0x800C) == 2, 'a var holding 0xFFFF takes one (the quantity is an s16)')
C.g4_count_unique_seals(ctx, 0x800C)
check(var(0x800C) == 2, 'countuniquesealsinsealcase')
C.g4_buffer_seal_name(ctx, 0, 0x8007, true)
check(game.stringBuffers[1] == S.name(data, 51, true), 'bufferballsealnameplural')

-- the counter: Monday's stock, priced from the table, into the case
C.g4_seal_mart(ctx, 0)
check(pushed and pushed.goods and #pushed.stock == 7, 'pokemartseal 0 opens Monday\'s seven')
check(#pushed:rows() == 2, 'BUY / SEE YA! only')
pushed.cursor = 1; pushed:choose()          -- BUY
pushed.cursor = 3; pushed:choose()          -- Fire Seal A
check(pushed.mode == 'quantity' and pushed.unit == 50, 'Fire Seal A at 50')
pushed.qty = 4; pushed:choose(); pushed:choose()
check(S.count(save, 29) == 4 and save.money == 10000 - 200, 'four bought, 200 paid')
pushed.mode = 'buy'; pushed.cursor = 1; pushed:choose()   -- Heart Seal A, already 99
pushed:choose(); pushed:choose()
check(S.count(save, 1) == 99 and save.money == 9800 and pushed.message and pushed.message:find('Seal Case is full'),
      'a full kind: the ROM\'s "The Seal Case is full." and no charge')

-- the Seal Case from the bag
local IE = require('src.inventory.ItemEffects')
local ok, kind, lines = pcall(IE.use, data, save, 434)
check(ok and kind == 'failed' and lines and lines[1] == 'Seals: ' .. S.total(save), 'the Seal Case says "Seals: n"')

-- the Unown-seal girl and the shop lower fully
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = text }
local bad = {}
for label in pairs(sdata.map_scripts.scripts) do
  if label:sub(1, 5) == 'M1085' then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      local n = row[1]
      if type(n) == 'string' and (not C[n] or n == 'g4_unimplemented') then bad[#bad + 1] = label .. ':' .. tostring(row[2]) end
    end
  end
end
check(#bad == 0, 'the seal scripts lower fully: ' .. table.concat(bad, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
