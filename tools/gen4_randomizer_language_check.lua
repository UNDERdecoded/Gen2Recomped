-- Run:  python tools/run_lua_check.py tools/gen4_randomizer_language_check.lua <platinum cache>/data/generated
--
-- THE RANDOMIZER'S PROTECTED LISTS ON A CACHE IN ANY LANGUAGE
-- (src/runmodes/RandomData.lua).  The lists are written as English names;
-- a German cache names its moves and items in German, so they are read through
-- the cartridge ids (Gen4EnglishRef).  The same assertions hold on both caches.

package.path = './?.lua;' .. package.path
if not _G.love then _G.love = require('tests.love_stub') end
local dir = (arg[1] or ''):gsub('[/\\]*$', '') .. '/'
local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function load_(n) return assert(loadfile(dir .. n))() end

local RD = require('src.runmodes.RandomData')
local data = { constants = { gen = 4 }, items = load_('items.lua'), moves = load_('moves.lua'),
               trainers = load_('trainers.lua') }

-- items: Master Ball 1, Fresh Water 30, Soda Pop 31, Lemonade 32, Rare Candy 50
-- are story / protected; a Potion (17) and an Oran Berry are not
for _, id in ipairs({ 1, 30, 31, 32, 50 }) do
  check(RD.protectedItem(data, id), 'item ' .. id .. ' is protected')
end
check(not RD.protectedItem(data, 17), 'a Potion is not protected')
check(not RD.protectedItem(data, 155), 'an Oran Berry is not protected')

-- moves: Selfdestruct 120, Explosion 153, Counter 68, Struggle 165 never come out of the "good" pool
local info = RD.moveInfo(data)
local good = {}
for _, id in ipairs(info.good) do good[id] = true end
for _, id in ipairs({ 120, 153, 68, 243, 90 }) do check(not good[id], 'move ' .. id .. ' is not a good random attack') end
check(good[33] and good[85], 'Tackle and Thunderbolt are good attacks')

-- the item pools
local items = RD.itemInfo(data)
local general = {}
for _, id in ipairs(items.general) do general[id] = true end
check(general[17] and not general[50] and not general[30], 'Potion is in the pool, Rare Candy and Fresh Water are not')

-- trainer names: the Gym Leaders (class ids) keep theirs, a Youngster-type does not need to
local leaderName, leaderId
for id, t in pairs(data.trainers) do
  if type(t) == 'table' and t.class == 62 then leaderId, leaderName = id, t.name break end
end
local before = {}
for id, t in pairs(data.trainers) do if type(t) == 'table' then before[id] = t.name end end
local RandomOptions = require('src.runmodes.RandomOptions')
local rm = { seed = 12345, random = { trainerNames = true } }
local ok, why = pcall(RD.apply, data, rm)
check(ok, 'apply runs (' .. tostring(why) .. ')')
local changed, keptLeaders = 0, true
for id, t in pairs(data.trainers) do
  if type(t) == 'table' and before[id] ~= t.name then
    changed = changed + 1
    if t.class == 62 or t.class == 64 or (t.class and t.class >= 74 and t.class <= 79) or (t.class and t.class >= 65 and t.class <= 69) then
      keptLeaders = false
    end
  end
end
check(keptLeaders, 'Leaders, the Elite Four and the Champion keep their names')
check(changed > 0, 'other trainers were renamed (' .. changed .. ')')
pcall(RD.restore)

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
