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
local rec = load('gen4_game_corner')
check(rec, 'the cache must carry gen4_game_corner (run tools/gen4_game_corner_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end

-- the table, against scrcmd_game_corner_prize.c
check(#rec.prizes == 19, 'nineteen prizes')
check(rec.prizes[1].item == 251 and rec.prizes[1].price == 1000, 'Silk Scarf for 1000 first')
check(rec.prizes[5].item == 417 and rec.prizes[5].price == 2000, 'TM90 (Substitute) for 2000')
check(rec.prizes[19].item == 395 and rec.prizes[19].price == 20000, 'TM68 (Giga Impact) for 20000 last')

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
check(var(0x8000) == 395 and var(0x8001) == 20000, 'getgamecornerprizedata 18: TM68, 20000')

-- the window: "   50 Coins", right-aligned, and buffer 0 left alone
game.stringBuffers[1] = 'KEEP'
C.g4_coin_window(ctx, 'show', 20, 2)
check(ow.gen4CoinWindow and ow.gen4CoinWindow.amount:find('50 Coins', 1, true), 'showcoins: the count from bank 361 #197')
check(game.stringBuffers[1] == 'KEEP', 'the window does not eat the script\'s buffer 0')
save.coins = 999
C.g4_coin_window(ctx, 'update')
check(ow.gen4CoinWindow.amount:find('999 Coins', 1, true) and ow.gen4CoinWindow.left == 20, 'updatecoindisplay keeps its place')
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
check(game.stringBuffers[1] == 'DARK', 'buffertypename reads bank 624')

-- the Coin Case from the bag: bank 7 #57
local items = load('items')
local IE = require('src.inventory.ItemEffects')
save.coins = 1234
local ok, kind, lines = pcall(IE.use, { items = items, text = text, constants = { gen = 4 } }, save, 444)
check(ok and kind == 'failed' and lines and lines[1] == 'Your Coins: 1234',
      'the Coin Case says "Your Coins: 1234", got ' .. tostring(ok and lines and lines[1] or kind))

-- every Game Corner script lowers, the slot machine as its named gap
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = text }
local bad, slots = {}, 0
for label in pairs(sdata.map_scripts.scripts) do
  if label:sub(1, 5) == 'M0141' or label:sub(1, 5) == 'M0150' then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      local n = row[1]
      if n == 'g4_noop' and row[2] == 'the slot machine' then slots = slots + 1
      elseif type(n) == 'string' and (not C[n] or n == 'g4_unimplemented') then bad[#bad + 1] = label .. ':' .. tostring(row[2]) end
    end
  end
end
check(#bad == 0, 'every Game Corner script lowers: ' .. table.concat(bad, ', '))
check(slots > 0, 'and the slot machine is a named gap, not an unknown')
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
