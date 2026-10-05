-- Run:  texlua tools/gen4_field_queries_check.lua <cache dir>
--
-- PLATINUM'S SMALLER FIELD COMMANDS: the easy-chat word picker and its
-- buffer (Sunyshore's Julia), ribbon names, the Oreburgh Museum's fossils, the
-- Rotom room count, the Pokedex ratings, the Regi ruins' dots and a handful
-- of party queries -- per easy_chat_words.c, scrcmd_fossil.c, unk_0205DFC4.c,
-- ov5_021F6454.c and scrcmd_party.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local text, items = load('text'), load('items')
local data = { text = text, items = items, gen4_dex = load('gen4_dex') }

-- easy chat words
local EC = require('src.pokemon.Gen4EasyChat')
local c = EC.counts(data)
check(c[1] == 496 and c[2] == 468 and c[3] == 18 and c[4] == 124 and c[11] == 23,
      'the eleven banks\' sizes are the ROM\'s (496 species, 468 moves, 18 types, 124 abilities ... 23 union)')
check(EC.toString(data, 25) == 'PIKACHU', 'word 25 is PIKACHU')
check(EC.toString(data, EC.word(data, 2, 1)) == 'POUND', 'the move bank follows the species: POUND')
local w = EC.word(data, 9, 1)
local bi, e = EC.split(data, w)
check(bi == 9 and e == 1 and EC.toString(data, w) == 'DELIGHT', 'feelings entry 1 round-trips: DELIGHT')
check(EC.toString(data, 0xFFFF) == '', 'WORD_NONE prints nothing')
local groups = EC.groups(data, { pokedex = { seen = { [25] = true, ['SPECIES_387'] = true } } })
check(groups[1].label == 'POKéMON' and #groups[1].words == 2, 'POKéMON lists only seen species')
local hasTough = false
for _, g in ipairs(groups) do if g.label == 'TOUGH WORDS' then hasTough = true end end
check(not hasTough, 'locked TOUGH WORDS are not offered')
check(groups[2].words[1].label <= groups[2].words[2].label, 'words are alphabetical')

local C = require('src.script.Commands')
local G = require('src.script.Gen4Commands')
local save = { gen4Vars = {}, party = {}, inventory = {}, flags = {}, player = { gender = 'boy' } }
local game = { data = data, save = save, stringBuffers = {} }
local pushed = {}
game.stack = { push = function(_, s) pushed[#pushed + 1] = s end, pop = function() pushed[#pushed] = nil end }
local resumed = 0
local ctx = { game = game, save = save, runner = { resume = function() resumed = resumed + 1 end, yield = function() end } }
local function var(v) return save.gen4Vars[v] end
save.pokedex = { seen = { [25] = true } }
C.g4_choose_message_word(ctx, 0, 0x800C, 0x8000)
check(#pushed == 1, 'choosecustommessageword opens the groups')
pushed[1].items[1].onSelect()   -- POKéMON
check(#pushed == 2 and pushed[2].items[1].label == 'PIKACHU', '...then the words')
local words = table.remove(pushed)
table.remove(pushed)
words.items[1].onSelect()
check(var(0x800C) == 1 and var(0x8000) == 25 and resumed == 1, 'choosing PIKACHU: result 1, word 25')
C.g4_buffer_message_word(ctx, 0, 0x8000)
check(game.stringBuffers[1] == 'PIKACHU', 'buffercustommessageword')
pushed = {}
C.g4_choose_message_word(ctx, 0, 0x800C, 0x8000)
local top = table.remove(pushed)
top.onCancel()
check(var(0x800C) == 0 and var(0x8000) == 0xFFFF, 'backing out: result 0, word 0xFFFF')

-- ribbons
C.g4_buffer_ribbon_name(ctx, 3, 65)
check(game.stringBuffers[4] == 'Smile Ribbon', 'bufferribbonname 65: Smile Ribbon, got ' .. tostring(game.stringBuffers[4]))

-- fossils: every item id is the ROM's
local names = { [103] = 'Old Amber', [101] = 'Helix Fossil', [102] = 'Dome Fossil', [99] = 'Root Fossil',
                [100] = 'Claw Fossil', [104] = 'Armor Fossil', [105] = 'Skull Fossil' }
local allNamed = true
for _, f in ipairs(G.FOSSILS) do
  local d = items[f.item] or items[('ITEM_%03d'):format(f.item)]
  if not (d and d.name == names[f.item]) then allNamed = false end
end
check(allNamed and #G.FOSSILS == 7, 'the seven fossil items name themselves in the ROM item table')
save.inventory = { [101] = 1, [105] = 2 }
C.g4_fossil_count(ctx, 0x8000)
check(var(0x8000) == 3, 'getfossilcount: 3')
save.gen4Vars[0x8002] = 105
C.g4_species_from_fossil(ctx, 0x8001, 0x8002)
check(var(0x8001) == 408, 'Skull Fossil -> Cranidos')
C.g4_fossil_at_threshold(ctx, 0x8002, 0x8004, 2)
check(var(0x8002) == 105 and var(0x8004) == 6, 'the second fossil in table order is the Skull Fossil (index 6)')

-- Rotom
save.party = { { species = 25 }, { species = 479, form = 0 }, { species = 479, form = 2 }, { species = 479, form = 1 } }
C.g4_party_rotom_forms(ctx, 0x8003, 0x800C)
check(var(0x8003) == 2 and var(0x800C) == 2, 'two changed Rotom, the first in slot 2')

-- ratings
check(G.dexRating(false, 15) == 6 and G.dexRating(false, 16) == 7 and G.dexRating(false, 209) == 17,
      'Rowan: 15 / 16 / 209 seen')
check(G.dexRating(false, 210, false, true) == 4 and G.dexRating(false, 210, false, false) == 5,
      'the complete Sinnoh dex, after and before Eterna')
check(G.dexRating(true, 39) == 22 and G.dexRating(true, 420, true) == 35 and G.dexRating(true, 420, false) == 34
      and G.dexRating(true, 482, true) == 42, 'Oak: under 40, the gendered 410 and the gendered complete line')

-- party queries
save.party = { { species = 25, isEgg = true }, { species = 25, personality = 37 }, { species = 25, isEgg = true } }
C.g4_count_party_eggs(ctx, 0x800C)
check(var(0x800C) == 2, 'countpartyeggs')
C.g4_party_slot_with_nature(ctx, 0x8000, 12)
check(var(0x8000) == 1, 'findpartyslotwithnature 12 (Serious): slot 1')
C.g4_party_slot_with_nature(ctx, 0x8000, 3)
check(var(0x8000) == 0xFF, '...and none for Adamant: 0xFF')

-- Regi dots
save.gen4Vars[0x4069] = 0
local function step(x, z) save.gen4Vars[0x8004], save.gen4Vars[0x8005] = x, z; C.g4_regi_dot(ctx, 0x4069, 588, 0x8004, 0x8005) end
step(4, 7)
check(var(0x4069) == 1, 'the first Iron Ruins dot sets bit 0')
step(6, 6)
check(var(0x4069) == 1, 'off a dot nothing changes')
for _, d in ipairs(G.REGI_DOTS[588]) do step(d[1], d[2]) end
check(var(0x4069) == 260, 'all seven: RUINS_STATE_ACTIVATED_ALL_DOTS (260)')

-- the scripts lower
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = text }
local want = { M0165 = true, M0065 = true, M0411 = true, M0392 = true, M0170 = true }
local bad = {}
for label in pairs(sdata.map_scripts.scripts) do
  if want[label:sub(1, 5)] then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      local n = row[1]
      if type(n) == 'string' and (not C[n] or n == 'g4_unimplemented') then bad[#bad + 1] = label .. ':' .. tostring(row[2]) end
    end
  end
end
check(#bad == 0, 'Julia, the museum, the ratings, the Iron Ruins and the nature NPCs lower fully: ' .. table.concat(bad, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
