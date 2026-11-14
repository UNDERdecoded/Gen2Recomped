-- Run:  texlua tools/gen4_game_corner_check.lua <cache dir>
--
-- THE VEILSTONE GAME CORNER (src/import/Gen4GameCorner.lua and the coin,
-- prize and Hidden Power commands), per scrcmd_coins.c, coins.c,
-- scrcmd_game_corner_prize.c and ov5_021F6454.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
-- A NON-ENGLISH CACHE (gen4_language.lua): the words a lookup returns come from
-- that cartridge's own banks, so they are asserted to be real lines of the bank
-- (and the counts in them), not the English words.  English asserts as ever.
local LANG = load('gen4_language')
local function named(actual, english, label)
  if not LANG then check(actual == english, label) return end
  check(type(actual) == 'string' and actual ~= '' and not actual:find('{', 1, true),
    label .. ' [' .. tostring(LANG.language) .. ': read from the bank]')
end
local rec = load('gen4_game_corner')
check(rec, 'the cache must carry gen4_game_corner (run tools/gen4_game_corner_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end

-- Which cartridge made this cache: the SHA-1 that ends `rom-cache.complete`,
-- two directories above `data/generated`.  Renegade Platinum re-prices and
-- replaces prizes (its first row is item 275, not the Silk Scarf), so the
-- retail asserts below hold for every cache EXCEPT a Renegade one, and the
-- Renegade branch asserts what the hack's ARM9 actually holds.
local RENEGADE_SHA1 = '381f9eef44564602a5f6469ee8c390fbb8ebac3a'
local function cacheSha1()
  local f = io.open(dir .. '/../../rom-cache.complete', 'rb')
  local raw = f and f:read('*a')
  if f then f:close() end
  return raw and raw:match(':(%x+)%s*$')
end
local renegade = cacheSha1() == RENEGADE_SHA1

-- the table, against scrcmd_game_corner_prize.c
check(#rec.prizes == 19, 'nineteen prizes')
local lastPrize = rec.prizes[19]
if not renegade then
  check(rec.prizes[1].item == 251 and rec.prizes[1].price == 1000, 'Silk Scarf for 1000 first')
  check(rec.prizes[5].item == 417 and rec.prizes[5].price == 2000, 'TM90 (Substitute) for 2000')
  check(lastPrize.item == 395 and lastPrize.price == 20000, 'TM68 (Giga Impact) for 20000 last')
else
  -- Renegade's table, as its ARM9 holds it (sGameCornerPrizeData, first row
  -- replaced and the TM rows re-priced): shape plus the rows the hack changed
  local itemsData = load('items')
  for i, row in ipairs(rec.prizes) do
    check(row.item > 0 and row.price > 0 and row.price % 10 == 0 and row.price <= 50000,
          'prize ' .. i .. ' is an item and a price in coins')
    check(itemsData and itemsData[row.item], 'prize ' .. i .. ' names an item the cache knows')
  end
  check(rec.prizes[1].item == 275 and rec.prizes[1].price == 1000,
        'Renegade: item 275 for 1000 replaces the Silk Scarf first')
  check(rec.prizes[2].item == 265 and rec.prizes[3].item == 276,
        'Renegade: rows 2 and 3 follow the replaced first row')
end

-- coins.c
local GC = require('src.import.Gen4GameCorner')
local save = { coins = 49990 }
check(GC.canAdd(save, 10) and not GC.canAdd(save, 11), 'Coins_CanAdd: the sum may reach 50000, not pass it')
check(GC.add(save, 500) and save.coins == 50000, 'Coins_Add clamps at 50000')
check(not GC.add(save, 1), '...and refuses when already full')
check(not GC.subtract(save, 50001) and save.coins == 50000, 'Coins_Subtract is all or nothing')

-- the commands
local C = require('src.script.Commands')
local G = require('src.script.Gen4Commands')
local text = load('text')
local game = { data = { gen4_game_corner = rec, text = text }, stringBuffers = {} }
save = { coins = 100, gen4Vars = {}, party = {} }
game.save = save
local ow = {}
local ctx = { game = game, save = save, overworld = ow }
local function var(v) return save.gen4Vars[v] end
C.g4_can_add_coins(ctx, 0x800C, 50)
check(var(0x800C) == 1, 'checkcanaddcoins: yes')
C.g4_add_coins(ctx, 50)
check(save.coins == 150, 'addcoins 50')
save.gen4Vars[0x8001] = 150
C.g4_has_coins(ctx, 0x800C, 0x8001)
check(var(0x800C) == 1, 'hascoinsfromvar: 150 of 150')
save.gen4Vars[0x8001] = 151
C.g4_has_coins(ctx, 0x800C, 0x8001)
check(var(0x800C) == 0, '...not 151')
save.gen4Vars[0x8001] = 100
C.g4_subtract_coins(ctx, 0x8001)
check(save.coins == 50, 'subtractcoinsfromvar')
C.g4_get_coins(ctx, 0x800C)
check(var(0x800C) == 50, 'getcoinsamount')
save.gen4Vars[0x8008] = 18
C.g4_prize_data(ctx, 0x8008, 0x8000, 0x8001)
check(var(0x8000) == lastPrize.item and var(0x8001) == lastPrize.price,
      'getgamecornerprizedata 18: the last row of the table')
if not renegade then
  check(var(0x8000) == 395 and var(0x8001) == 20000, 'getgamecornerprizedata 18: TM68, 20000')
end

-- the window: "   50 Coins", right-aligned, and buffer 0 left alone
game.stringBuffers[1] = 'KEEP'
C.g4_coin_window(ctx, 'show', 20, 2)
-- bank 361 #197 is "{count} Coins" in English, the cartridge's own word elsewhere
check(ow.gen4CoinWindow and ow.gen4CoinWindow.amount:find(LANG and '50' or '50 Coins', 1, true)
      and not (LANG and ow.gen4CoinWindow.amount:find('{', 1, true)), 'showcoins: the count from bank 361 #197')
check(game.stringBuffers[1] == 'KEEP', 'the window does not eat the script\'s buffer 0')
save.coins = 999
C.g4_coin_window(ctx, 'update')
check(ow.gen4CoinWindow.amount:find(LANG and '999' or '999 Coins', 1, true) and ow.gen4CoinWindow.left == 20, 'updatecoindisplay keeps its place')
C.g4_coin_window(ctx, 'hide')
check(ow.gen4CoinWindow == nil, 'hidecoins')

-- Hidden Power's type
check(G.hiddenPowerType({ hp = 31, attack = 31, defense = 31, speed = 31, spatk = 31, spdef = 31 }) == 17,
      'all odd IVs: Dark (17)')
check(G.hiddenPowerType({ hp = 30, attack = 30, defense = 30, speed = 30, spatk = 30, spdef = 30 }) == 1,
      'all even: Fighting (1)')
check(G.hiddenPowerType({ hp = 30, attack = 31, defense = 30, speed = 30, spatk = 30, spdef = 31 }) == 10,
      'type 8 skips the ??? type to Fire (10)')
save.party = { { species = 129, ivs = {} }, { species = 25, ivs = { hp = 31, attack = 31, defense = 31, speed = 31, spatk = 31, spdef = 31 } } }
C.g4_hidden_power_type(ctx, 0, 0x8004)
check(var(0x8004) == 0xFFFF, 'Magikarp cannot learn it: 0xFFFF')
C.g4_hidden_power_type(ctx, 1, 0x8004)
check(var(0x8004) == 17, 'Pikachu, all odd: Dark')
C.g4_buffer_type_name(ctx, 0, 0x8004)
named(game.stringBuffers[1], 'DARK', 'buffertypename reads bank 624')

-- the Coin Case from the bag: bank 7 #57
local items = load('items')
local IE = require('src.inventory.ItemEffects')
save.coins = 1234
local ok, kind, lines = pcall(IE.use, { items = items, text = text, constants = { gen = 4 }, isGen4Cache = true }, save, 444)
check(ok and kind == 'failed' and lines and lines[1] == 'Your Coins: 1234',
      'the Coin Case says "Your Coins: 1234", got ' .. tostring(ok and lines and lines[1] or kind))

-- every Game Corner script lowers, the slot machine as its real session row
-- (PtSlotMachine.install; it was a named g4_noop gap before the app was built)
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = text }
local bad, slots = {}, 0
for label in pairs(sdata.map_scripts.scripts) do
  if label:sub(1, 5) == 'M0141' or label:sub(1, 5) == 'M0150' then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      local n = row[1]
      if n == 'pt_slot_machine' and C.pt_slot_machine then slots = slots + 1
      elseif n == 'g4_noop' and row[2] == 'the slot machine' then bad[#bad + 1] = label .. ':slot machine is still the named gap'
      elseif type(n) == 'string' and (not C[n] or n == 'g4_unimplemented') then bad[#bad + 1] = label .. ':' .. tostring(row[2]) end
    end
  end
end
check(#bad == 0, 'every Game Corner script lowers: ' .. table.concat(bad, ', '))
if LANG then
  -- the German cartridge's script file 141 is a different script (50 scripts, not
  -- the USA's 44) and carries no slot-machine command at all; whatever it does
  -- carry has to lower, which the check above asserts
  print(('note: this %s cartridge\'s script file 141 holds %d slot machine row(s)'):format(tostring(LANG.language), slots))
else
  check(slots > 0, 'and the slot machine lowers to its session row (pt_slot_machine)')
end
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
