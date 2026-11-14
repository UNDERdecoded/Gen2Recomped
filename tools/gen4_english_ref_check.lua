-- Run:  python tools/run_lua_check.py tools/gen4_english_ref_check.lua <platinum cache>/data/generated
--
-- ENGLISH NAMES ONTO A GEN IV CACHE OF ANY LANGUAGE (src/pokemon/Gen4EnglishRef.lua):
-- Pal Park's held items, the Walker's prizes and moves, and Poke Transfer's
-- items reach the right id on the German cache as on the English one.
-- On an English cache the table is also checked against the cache's own names.

package.path = './?.lua;' .. package.path
local dir = (arg[1] or ''):gsub('[/\\]*$', '') .. '/'
local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function load_(n) return assert(loadfile(dir .. n))() end

local items, moves = load_('items.lua'), load_('moves.lua')
local data = { constants = { gen = 4 }, items = items, moves = moves }
local english = items[1] and items[1].name == 'Master Ball'
local Ref = require('src.pokemon.Gen4EnglishRef')
local CG = require('src.pokemon.CrossGen')
local N = require('src.pokemon.Gen4EnglishNames')

if english then
  local bad = 0
  for kind, tbl in pairs({ items = items, moves = moves }) do
    for name, id in pairs(N[kind]) do
      if Ref.norm(tbl[id] and tbl[id].name) ~= name then bad = bad + 1 end
    end
  end
  check(bad == 0, 'every English name in the table is that id\'s name in the English cache (' .. bad .. ' differ)')
end

-- held items of a Gen III cartridge (keyed by slug, named in English)
local src = { items = { ORANBERRY = { name = 'ORAN BERRY' }, KINGSROCK = { name = "KING'S ROCK" },
                        MASTERBALL = { name = 'MASTER BALL' } },
              moves = { THUNDERBOLT = { name = 'THUNDERBOLT', index = 85 }, TACKLE = { name = 'TACKLE', index = 33 } } }
check(CG.itemId(data, src, 'KINGSROCK') == 221, 'King\'s Rock holds on as item 221')
check(CG.itemId(data, src, 'ORANBERRY') == 155, 'Oran Berry holds on as item 155')
check(CG.itemId(data, src, 'MASTERBALL') == 1, 'a Master Ball stays a Master Ball')
check(CG.moveId(data, src, 'THUNDERBOLT') == 85 and CG.moveId(data, src, 'TACKLE') == 33, 'moves come across by index')
check(CG.itemByName(data, 'POKE BALL') == 4, 'the default ball is a Poke Ball (id 4)')

-- the Walker: a prize name and a catch's moves
check(CG.itemByName(data, 'Potion') == 17, 'the Walker prize "Potion" is item 17')
check(CG.moveByName(data, 'Sand-attack') == 28, 'Sand-attack is move 28')
check(CG.moveByName(data, 'Poisonpowder') == 77, 'Poisonpowder is move 77')

-- a Gen IV cartridge as the source (Poke Transfer): a German name does not matter
local srcPl = { gen4 = true, items = { [155] = { name = 'Nicht-Englisch' } } }
local bw = { constants = { gen = 5 }, items = { [900] = { name = 'Oran Berry' } }, moves = {} }
check(CG.itemId(bw, srcPl, 155) == 900, 'a German Platinum item reaches Black/White by its id')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
