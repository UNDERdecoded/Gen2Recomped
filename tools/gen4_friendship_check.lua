-- Run:  texlua tools/gen4_friendship_check.lua <cache dir>
--
-- PLATINUM'S WALKING FRIENDSHIP (src/pokemon/Gen4Friendship.lua), per
-- Field_UpdateFriendship and Pokemon_UpdateFriendship(WALK_CYCLE).

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local data = { maps = load('maps'), items = load('items'), gen4_area_popup = load('gen4_area_popup'),
               pokemon = load('pokemon') }
local F = require('src.pokemon.Gen4Friendship')
local function party(extra)
  local m = { species = 396, happiness = 70 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return { party = { m } }, m
end
local heads = function() return 1 end
local tails = function() return 0 end
local function walk(save, n, rng) for _ = 1, n do F.step(data, save, data.maps.T01, rng) end end

local s, m = party()
walk(s, 127, tails)
check(m.happiness == 70, 'nothing before the 128th step')
walk(s, 1, tails)
check(m.happiness == 71, 'the 128th step: +1')
s, m = party()
walk(s, 128, heads)
check(m.happiness == 70, 'skipped on the coin flip (LCRNG_Next() & 1)')
s, m = party({ ball = 11 })
walk(s, 128, tails)
check(m.happiness == 72, 'a Luxury Ball adds 1')
s, m = party({ eggLocation = 'T01' })
walk(s, 128, tails)
check(m.happiness == 72, 'standing where its egg came from adds 1')
s, m = party({ metLocation = 'T01' })
walk(s, 128, tails)
check(m.happiness == 71, 'the MET location does not -- the cartridge compares the egg location')
s, m = party({ ball = 11, item = 218 })
walk(s, 128, tails)
check(m.happiness == 73, 'Soothe Bell: (1 + 1) * 1.5 = 3')
s, m = party({ happiness = 255, ball = 11 })
walk(s, 128, tails)
check(m.happiness == 255, 'capped at 255')
-- creation and old saves
local mig = { party = { { species = 396 }, { species = 25, happiness = 200 } }, boxes = { { { species = 133 } } } }
local seeded = F.migrate(data, mig)
check(seeded == 2 and mig.party[1].happiness == data.pokemon[396].baseFriendship
      and mig.party[2].happiness == 200 and mig.boxes[1][1].happiness == data.pokemon[133].baseFriendship,
      'an old save gets each species base friendship, once, and keeps what it had')
check(F.migrate(data, mig) == 0, 'and only once')
local pk = io.open('src/pokemon/Pokemon.lua'):read('a')
check(pk:find('and (def.baseFriendship or def.friendship or 70))', 1, true), 'new Platinum Pokemon carry friendship')
local src = io.open('src/world/OverworldController.lua'):read('a')
check(src:find('require("src.pokemon.Gen4Friendship").step(', 1, true), 'the field step uses it')
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
