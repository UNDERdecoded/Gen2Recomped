-- Run:  texlua tools/gen4_trainer_prize_check.lua <cache dir>
--
-- PLATINUM'S PRIZE MONEY (src/import/Gen4TrainerPrize.lua and BattleState's
-- payout), per battle_script.c BattleScript_CalcPrizeMoney.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_trainer_prize')
check(rec, 'the cache must carry gen4_trainer_prize (run tools/gen4_trainer_prize_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
local trainers = load('trainers')
local data = { gen4_trainer_prize = rec, trainers = trainers }
local P = require('src.import.Gen4TrainerPrize')

check(rec.byClass[0] == 0 and rec.byClass[2] == 4 and rec.byClass[69] == 50, 'player 0, Youngster 4, Cynthia 50')
-- Youngster Logan (trainer 2): one Lv5 Burmy -> 5 x 4 x 4 = 80
local logan = trainers[2]
local last = logan.party[#logan.party]
check(P.prize(data, logan) == last.level * 4 * 4, ('Youngster Logan pays %d (Lv%d x 4 x 4)'):format(P.prize(data, logan), last.level))
check(P.prize(data, logan, { amuletCoin = true }) == 2 * P.prize(data, logan), 'an Amulet Coin doubles it')
check(P.prize(data, logan, { double = true }) == 2 * P.prize(data, logan), 'one trainer\'s double battle doubles it')
check(P.prize(data, logan, { double = true, tag = true }) == P.prize(data, logan), 'a tag battle does not')

-- every trainer of a paying class pays something
local zero = 0
for id, t in pairs(trainers) do
  if type(id) == 'number' and type(t) == 'table' and (rec.byClass[t.class] or 0) > 0 and P.prize(data, t) == 0 then zero = zero + 1 end
end
check(zero == 0, 'every trainer of a paying class pays (' .. zero .. ' do not)')
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
