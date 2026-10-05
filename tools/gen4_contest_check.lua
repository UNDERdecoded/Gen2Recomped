-- Run:  texlua tools/gen4_contest_check.lua <cache dir>
--
-- PLATINUM'S SUPER CONTEST, STAGE ONE (src/import/Gen4ContestData.lua,
-- src/pokemon/Gen4Contest.lua and the g4_contest_* commands), per contest.c,
-- unk_02094EDC.c and overlay017's visual and final scoring.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_contest')
check(rec, 'the cache must carry gen4_contest (run tools/gen4_contest_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
local text = load('text')
local data = { gen4_contest = rec, text = text, pokemon = load('pokemon'), isGen4Cache = true }
local C = require('src.pokemon.Gen4Contest')
local T = require('src.import.Gen4Text')

-- the data
check(#rec.opponents == 95 and rec.opponents[0].species == 25, '96 contestants; the first a Pikachu')
check(text[T.label(205, rec.opponents[0].nameId)] == 'Sparky', 'named Sparky (bank 205)')
check(#rec.judges == 11 and #rec.dressups == 95, '12 judges, 96 dress-ups')
local themeOK = true
for t = 0, 11 do if not rec.themes[t] or rec.themes[t][0] == nil then themeOK = false end end
check(themeOK, 'twelve theme tables')

-- the LCRNG: 0x41C64E6D, 0x6073, high half
local r = C.rng(0)
check(r.next() == 0 and r.seed == 0x6073, 'LCRNG from 0: seed 0x6073, out 0')
r = C.rng(1)
r.next()
check(r.seed == (0x41C64E6D + 0x6073) % 4294967296, 'LCRNG from 1')

-- every rank and type can field three opponents and three judges
local ok = true
for rank = 0, 3 do for ty = 0, 4 do
  local rng = C.rng(rank * 7 + ty)
  local opp = C.pickOpponents(rec, ty, rank, C.OFFICIAL, false, rng)
  local j = C.pickJudges(rec, ty, rank, rng)
  if not (opp[1] and opp[2] and opp[3] and j[1] and j[2] and j[3]) then ok = false end
  if opp[1] == opp[2] or opp[2] == opp[3] or opp[1] == opp[3] then ok = false end
  for k = 1, 3 do
    local o = rec.opponents[opp[k]]
    if o.rank ~= rank or not o.types[ty + 1] or o.practice == 1 or o.official == 1 or o.postgame >= 2 then ok = false end
  end
end end
check(ok, 'official contests at every rank and type draw three distinct, eligible opponents and three judges')

-- the visual condition score (ov17_0223F374)
local c = C.new({ data = data, rank = 0, type = C.COOL, competition = C.OFFICIAL, seed = 5,
  mon = { species = 25, contest = { cool = 40, tough = 10, beauty = 20, sheen = 6 }, item = 260 },
  playerName = 'LUCAS', partySlot = 0 })
check(C.visualStatScore(c, c.contestants[0].mon) == math.floor((40 + math.floor((10 + 20 + 6) / 2)) * 110 / 100),
      'cool 40 + (tough 10 + beauty 20 + sheen 6)/2, x1.10 with a Red Scarf')
check(C.visualStatScore(c, { contest = { cool = 40, tough = 10, beauty = 20, sheen = 6 }, item = 264 }) == math.floor(58 * 105 / 100),
      'x1.05 with a Yellow Scarf in a Cool contest')
C.scoreVisual(c, data)
check(C.stars(c, 0) == 6, 'Normal rank: 63 is six stars (thresholds 10..80)')
check(c.scores[0].visualDress == 0 and C.hearts(c, 0) == 0, 'the player enters undressed: no hearts')
local anyHearts = false
for id = 1, 3 do if c.scores[id].visualDress > 0 then anyHearts = true end end
check(anyHearts, 'opponents wear their contest_data dress-ups for the drawn theme')

-- final scoring
c.placement = nil
for id = 0, 3 do c.scores[id].dance, c.scores[id].acting = 1, 1 end
C.place(c)
local seen = {}
for id = 0, 3 do seen[c.placement[id]] = true end
check(seen[0] and seen[1] and seen[2] and seen[3], 'four distinct placements')
local best, bestId = -1, nil
for id = 0, 3 do if c.bars[id].total > best then best, bestId = c.bars[id].total, id end end
check(c.placement[bestId] == 0, 'the longest bar places first')
check(c.bars[0][2] == c.bars[1][2] and c.bars[0][2] == math.floor((192 * 3333 + 5000) / 10000), 'level rounds give everyone the full equal bar')

-- the commands
local Cm = require('src.script.Commands')
require('src.script.Gen4Commands')
local save = { gen4Vars = {}, party = { { species = 25, hp = 20, moves = { { id = 84 }, { id = 98 } }, contest = { cool = 200, tough = 100, beauty = 100, sheen = 100 } },
  { species = 1, hp = 20, moves = { { id = 33 } } } }, player = { name = 'LUCAS', gender = 'boy' }, flags = {} }
local game = { data = data, save = save, stringBuffers = {}, stack = { push = function() end, pop = function() end } }
local ctx = { game = game, save = save }
local function var(v) return save.gen4Vars[v] end
local G = require('src.script.Gen4Commands')
check(G.contestEligible(save.party[1], 0, 0) and not G.contestEligible(save.party[2], 0, 0),
      'eligibility: two moves needed')
check(not G.contestEligible(save.party[1], 1, 0), 'Great rank needs the Normal ribbon')
Cm.g4_new_contest(ctx, 0, 0, C.OFFICIAL, 0)
check(game.gen4Contest and game.gen4Contest.contestants[0].mon == save.party[1], 'newcontest builds the contest on the game')
Cm.g4_contest_buffer(ctx, 'rank', 0)
Cm.g4_contest_buffer(ctx, 'type', 1)
check(game.stringBuffers[1] == 'NORMAL RANK' and game.stringBuffers[2] == 'COOL CONTEST', 'rank and type names from bank 204')
Cm.g4_contest_query(ctx, 'entry', 0x800C)
check(var(0x800C) == 3, 'the player is entry 3')
Cm.g4_contest_buffer(ctx, 'trainer', 3, 0)
check(game.stringBuffers[1] == 'LUCAS', 'entry 3 is the player')
C.scoreVisual(game.gen4Contest, data)
for id = 0, 3 do game.gen4Contest.scores[id].dance, game.gen4Contest.scores[id].acting = 1, 1 end
C.place(game.gen4Contest)
local won = game.gen4Contest.placement[0] == 0
Cm.g4_contest_query(ctx, 'skipCeremony', 0x800C)
check(var(0x800C) == (won and 0 or 1), 'the award ceremony is only for a player win')
Cm.g4_contest_query(ctx, 'firstWin', 0x800C)
check(var(0x800C) == (won and 73 or 0xFFFF), 'first win at Normal Cool: the Red Barrette (73)')
Cm.g4_end_contest(ctx)
check(game.gen4Contest == nil, 'endcontest frees it')
check(won == (save.party[1].ribbons and save.party[1].ribbons[33] == true or false), 'a win awards the Cool ribbon (33)')

-- accessories
Cm.g4_add_accessory(ctx, 73, 1)
Cm.g4_can_fit_accessory(ctx, 73, 1, 0x800C)
check(var(0x800C) == 0, 'a unique accessory fits once')
Cm.g4_add_accessory(ctx, 5, 8)
Cm.g4_can_fit_accessory(ctx, 5, 1, 0x800C)
check(var(0x800C) == 1, 'a common one stacks to nine')

-- the Contest Hall lowers
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = text }
local bad, unknown = {}, {}
for label in pairs(sdata.map_scripts.scripts) do
  if label:sub(1, 5) == 'M0212' then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      local n = row[1]
      if n == 'g4_unimplemented' then unknown[tostring(row[2])] = true
      elseif type(n) == 'string' and not Cm[n] then bad[#bad + 1] = n end
    end
  end
end
local left = {}
for k in pairs(unknown) do left[#left + 1] = k end
table.sort(left)
check(#bad == 0, 'no unknown verbs: ' .. table.concat(bad, ','))
local LINK = { endcommunication = true, showlinkcontestrecords = true, startbattleclient = true,
               startbattleserver = true, waitforlinkcontestsetup = true }
local notLink = {}
for _, k in ipairs(left) do if not LINK[k] then notLink[#notLink + 1] = k end end
check(#notLink == 0, 'only the link commands are left unlowered in the hall: ' .. table.concat(notLink, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
