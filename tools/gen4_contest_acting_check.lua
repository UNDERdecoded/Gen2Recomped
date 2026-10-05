-- Run:  texlua tools/gen4_contest_acting_check.lua <cache dir>
--
-- PLATINUM'S ACTING COMPETITION (src/pokemon/Gen4ContestActing.lua) against
-- turns worked by hand from overlay017.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_contest')
check(rec and rec.effects and rec.actingAI, 'gen4_contest must carry effects and actingAI (run tools/gen4_contest_extract.lua)')
if not (rec and rec.effects and rec.actingAI) then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end

local C = require('src.pokemon.Gen4Contest')
local A = require('src.pokemon.Gen4ContestActing')
local E = A.EFFECT

-- the tables
local appeal = {}
for e = 0, 23 do appeal[e] = rec.effects[e].appeal end
check(appeal[E.BASIC] == 30 and appeal[E.FIRST_NEXT_TURN] == 20 and appeal[E.DOUBLED_JUDGE] == 0
  and appeal[E.UNIQUE_JUDGE] == 10 and appeal[E.PITY] == 10 and appeal[E.TWO_VOLTAGE_IN_A_ROW] == 10
  and appeal[E.MAX_VOLTAGE_ADV] == 20, 'base appeal per effect (Unk_020F568C)')
check(#rec.actingAI == 165 and rec.actingAI[1].cond == 20 and rec.actingAI[1].target == 240
  and rec.actingAI[1].weights[0] == 70 and rec.actingAI[1].weights[3] == -20, 'AI row 1 is {1, 0x14, 0xF0, 1, {70,20,20,-20}}')
check(rec.actingAI[165].position == 4 and rec.actingAI[165].cond == 13 and rec.actingAI[165].weights[2] == -20, 'AI row 165')
check(rec.effects[E.FIRST_NEXT_TURN].msgs[0] == 0 and rec.effects[E.FIRST_NEXT_TURN].msgs[1] == 1, 'Perform First lines are bank 211 #0 / #1')

-- synthetic moves: id = 100 + effect * 10 + contest type
local moves = {}
for e = 0, 23 do for t = 0, 4 do moves[100 + e * 10 + t] = { contestEffect = e, contestType = t } end end
local function mv(e, t) return 100 + e * 10 + t end
local data = { gen4_contest = rec, moves = moves }
local function contest(seed) return { type = C.COOL, rank = 0, competition = C.ACTING, rng = C.rng(seed or 1) } end

-- A: four basic acts
local s = A.new(contest(), data)
check(table.concat(s.order, ',') == '0,1,2,3', 'an official Acting round starts in id order')
check(table.concat(A.new({ type = 0, rank = 0, competition = C.PRACTICE_ACTING, rng = C.rng(1) }, data).order, ',') == '3,2,1,0',
  'a practice starts reversed')
A.playTurn(s, {
  [0] = { move = mv(E.BASIC, 0), judge = 0 }, [1] = { move = mv(E.BASIC, 0), judge = 0 },
  [2] = { move = mv(E.BASIC, 1), judge = 1 }, [3] = { move = mv(E.BASIC, 2), judge = 2 },
})
check(s.totals[0] == 50 and s.totals[1] == 50 and s.totals[2] == 60 and s.totals[3] == 60,
  ('basic 30 + judge share 20/30: %d %d %d %d'):format(s.totals[0], s.totals[1], s.totals[2], s.totals[3]))
check(s.voltage[0] == 20 and s.voltage[1] == 0 and s.voltage[2] == 0, 'two Cool moves raised judge 0 to 20; a Cute one cannot lower 0')
check(table.concat(s.order, ',') == '1,0,3,2', 'lowest first, ties to whoever went later: ' .. table.concat(s.order, ','))

-- B: max Voltage at the head judge, Steal, Max Voltage Advantage, Pity
s = A.new(contest(), data)
s.voltage[1] = 40
local ev = A.playTurn(s, {
  [0] = { move = mv(E.BASIC, 0), judge = 1 }, [1] = { move = mv(E.STEAL_VOLTAGE, 1), judge = 2 },
  [2] = { move = mv(E.MAX_VOLTAGE_ADV, 1), judge = 0 }, [3] = { move = mv(E.PITY, 1), judge = 0 },
})
check(s.totals[0] == 140, 'head judge at 50 pays 80: 30 + 80 + 30 = ' .. s.totals[0])
check(s.totals[1] == 110, 'Steal Voltage takes the 80 from the one ahead: 0 + 80 + 30 = ' .. s.totals[1])
check(s.totals[2] == 40, 'Max Voltage Advantage needs the one ahead to have hit max: 20 + 20 = ' .. s.totals[2])
check(s.totals[3] == 60, 'Pity Points for the lowest: 10 + 20 + 30 = ' .. s.totals[3])
check(s.voltage[1] == 0, 'the judge resets after paying')
check(table.concat(s.order, ',') == '2,3,1,0', 'next order ' .. table.concat(s.order, ','))
local wild = false
for _, e in ipairs(ev) do if e.kind == 'voltage' and e.level == 50 and e.bonus == 80 then wild = true end end
check(wild, 'the Voltage event reports the max and its bonus')

-- C: Perform First beats the score order; Double Next Turn carries
s = A.new(contest(), data)
A.playTurn(s, {
  [0] = { move = mv(E.BASIC, 0), judge = 0 }, [1] = { move = mv(E.DOUBLE_NEXT_TURN, 1), judge = 1 },
  [2] = { move = mv(E.BASIC, 1), judge = 2 }, [3] = { move = mv(E.FIRST_NEXT_TURN, 1), judge = 2 },
})
check(s.order[1] == 3, 'Perform First goes first next turn: ' .. table.concat(s.order, ','))
check(s.saved.carry[1] == E.DOUBLE_NEXT_TURN, 'Double Next Turn is carried')
local before = s.totals[1]
A.playTurn(s, {
  [0] = { move = mv(E.BASIC, 1), judge = 0 }, [1] = { move = mv(E.BASIC, 1), judge = 1 },
  [2] = { move = mv(E.BASIC, 3), judge = 2 }, [3] = { move = mv(E.BASIC, 3), judge = 0 },
})
check(s.totals[1] - before == 30 + 30 + 30, 'doubled: basic 30, + 30 carried, + 30 share = ' .. (s.totals[1] - before))

-- D: a move twice in a row only after Consecutive Use
s = A.new(contest(), data)
A.playTurn(s, {
  [0] = { move = mv(E.CONSECUTIVE_USE, 0), judge = 0 }, [1] = { move = mv(E.BASIC, 0), judge = 1 },
  [2] = { move = mv(E.BASIC, 1), judge = 2 }, [3] = { move = mv(E.BASIC, 2), judge = 2 },
})
check(A.canUse(s, 0, mv(E.CONSECUTIVE_USE, 0)), 'Consecutive Use may repeat')
check(not A.canUse(s, 1, mv(E.BASIC, 0)), 'a basic move may not')
check(A.canUse(s, 1, mv(E.BASIC, 1)), 'another move may')

-- E: Low Voltage, Suppress, Lowers Voltage, High Score Later
s = A.new(contest(), data)
s.voltage = { [0] = 30, 30, 0 }
A.playTurn(s, {
  [0] = { move = mv(E.SUPPRESS_VOLTAGE, 0), judge = 0 },   -- 20, no rise for anyone from here
  [1] = { move = mv(E.LOW_VOLTAGE_ADV, 0), judge = 1 },     -- 0 + (30 -> +10)
  [2] = { move = mv(E.LOWERS_VOLTAGE, 1), judge = 2 },      -- 20, judges 0 and 1 go 30 -> 20
  [3] = { move = mv(E.HIGH_SCORE_LATER, 3), judge = 2 },    -- 0 + 40 (fourth); Smart lowers... judge 2 is 0
})
check(s.totals[0] == 20 + 30, 'Suppress 20 + share 30: ' .. s.totals[0])
check(s.totals[1] == 10 + 30, 'Low Voltage at 30 is +10: ' .. s.totals[1])
check(s.totals[2] == 20 + 20 and s.totals[3] == 40 + 20, 'Lowers Voltage 20, High Score Later +40 last')
check(s.voltage[0] == 20 and s.voltage[1] == 20 and s.voltage[2] == 0, 'suppressed rises, lowered judges')

-- F: judge-dependent effects
s = A.new(contest(), data)
A.playTurn(s, {
  [0] = { move = mv(E.ALL_SAME_JUDGE, 1), judge = 0 }, [1] = { move = mv(E.DOUBLED_JUDGE, 1), judge = 0 },
  [2] = { move = mv(E.UNIQUE_JUDGE, 1), judge = 0 }, [3] = { move = mv(E.BASIC, 1), judge = 0 },
})
check(s.totals[0] == 0 + 0 + 150, 'All Same Judge +150 when all four chose it: ' .. s.totals[0])
check(s.totals[1] == 0 + 0 + 60, 'Doubled Judge +20 per other: ' .. s.totals[1])
check(s.totals[2] == 10, 'Unique Judge earns nothing shared: ' .. s.totals[2])

-- G: the NPCs choose a usable move and a judge, reproducibly
s = A.new(contest(7), data)
local m1, j1 = A.chooseNpc(s, 1, { mv(E.BASIC, 0), mv(E.BASIC, 1), 0, 0 }, 0, 0)
check((m1 == mv(E.BASIC, 0) or m1 == mv(E.BASIC, 1)) and j1 >= 0 and j1 <= 2, 'an NPC picks one of its moves and a judge')
s.lastMove[1] = mv(E.BASIC, 0)
local m2 = A.chooseNpc(s, 1, { mv(E.BASIC, 0), mv(E.BASIC, 1), 0, 0 }, 0, 0)
check(m2 == mv(E.BASIC, 1), 'and never last turn\'s move')
-- row 1 (position 1, a judge at 40, the contest's type): the Cool move, to that judge
s = A.new(contest(3), data)
s.voltage = { [0] = 0, 40, 0 }
local m3, j3 = A.chooseNpc(s, 0, { mv(E.BASIC, 1), mv(E.BASIC, 0), 0, 0 }, 0, 2)
check(m3 == mv(E.BASIC, 0) and j3 == 1, ('at 40 Voltage the first performer goes for it: move %d judge %d'):format(m3, j3))

-- a whole round with NPCs plays four turns and totals feed the final scoring
s = A.new(contest(11), data)
local npc = {}
for id = 1, 3 do npc[id] = { moves = { mv(E.BASIC, 0), mv(E.UNIQUE_JUDGE, 1), mv(E.FIRST_PERF_ADV, 2), mv(E.PITY, 4) }, level = id % 4 } end
local playerMoves = { mv(E.BASIC, 0), mv(E.HIGH_SCORE_LATER, 0) }
for turn = 1, 4 do
  A.playTurn(s, { [0] = { move = playerMoves[turn % 2 + 1], judge = turn % 3 } }, npc)
end
check(A.done(s) and s.turn == 4, 'four turns')
local sum = 0
for id = 0, 3 do sum = sum + s.totals[id] end
check(sum > 0, 'points were scored (' .. sum .. ')')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
