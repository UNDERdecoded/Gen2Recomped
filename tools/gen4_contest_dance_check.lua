-- Run:  texlua tools/gen4_contest_dance_check.lua <cache dir>
--
-- PLATINUM'S DANCE COMPETITION (src/pokemon/Gen4ContestDance.lua and
-- src/ui/Gen4ContestDance.lua), per overlay017's ov17_0223DAD0.c,
-- ov17_0224CFB8.c and ov17_0224E930.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
package.loaded['src.core.Music'] = { play = function() end, stop = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_contest')
check(rec, 'the cache must carry gen4_contest')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
local text = load('text')
local data = { gen4_contest = rec, text = text, pokemon = load('pokemon'), isGen4Cache = true }
local C = require('src.pokemon.Gen4Contest')
local D = require('src.pokemon.Gen4ContestDance')
local T = require('src.import.Gen4Text')

-- the song table and its choice
check(D.SONGS[0].bpm == 120 and D.SONGS[0].moves == 3 and D.SONGS[3].bpm == 60, 'the songs: 120 BPM / 3 moves for Normal; 60 BPM')
local function pick(rank, ty) local s, l = D.pick(rank, ty) return s .. ',' .. l end
check(pick(C.NORMAL, C.CUTE) == '0,0' and pick(C.GREAT, C.COOL) == '1,0', 'Normal plays song 0, Great song 1')
check(pick(C.ULTRA, C.COOL) == '2,1' and pick(C.MASTER, C.BEAUTY) == '3,1' and pick(C.MASTER, C.TOUGH) == '6,0',
      'Ultra / Master by type: Cool {2,1}, Beauty {3,1}, Tough {6,0}')
check(text[T.label(206, 0)] == 'JUMP' and text[T.label(206, 5)] ~= nil, 'bank 206: the pad\'s JUMP, the verdicts')

local c = C.new({ data = data, rank = C.NORMAL, type = C.COOL, competition = C.OFFICIAL, seed = 11,
  mon = { species = 25, contest = { cool = 40 } }, playerName = 'LUCAS', partySlot = 0 })
local d = D.new(c)
check(d.step == 15 and d.steps == 16 and d.measure == 240, '120 BPM: a 15-frame step, a 240-frame measure')
check(D.roundStart(d, 0) == 60 and D.roundStart(d, 1) == 2 * 240 + (4 + 8) * 15, 'round starts: 4 intro steps, then 2 measures + 8 steps each')
check(table.concat(D.order(0), ',') == '3,2,1,0' and table.concat(D.order(3), ',') == '0,3,2,1' and D.leader(3) == 0,
      'leads 3, 2, 1, then the player; the others step forward')

-- the judge: half-step grid (7.5 frames), thresholds 2 / 3
local g, q = D.judge(d, 30) check(g == 4 and q == D.EXCELLENT, 'on the beat: Excellent')
g, q = D.judge(d, 32) check(g == 4 and q == D.EXCELLENT, '2 frames off: Excellent')
g, q = D.judge(d, 33) check(g == 4 and q == D.GOOD, '3 frames off: Good')
g, q = D.judge(d, 33.75) check(g == 4 and q == D.GOOD, 'a tie between half steps goes to the earlier: Good (Normal cannot miss on time)')
local cu = C.new({ data = data, rank = C.ULTRA, type = C.COOL, competition = C.OFFICIAL, seed = 3,
  mon = { species = 25, contest = {} }, playerName = 'LUCAS', partySlot = 0 })
local du = D.new(cu)
g, q = D.judge(du, 9 * 4 + 4)
check(du.step == 18 and g == 4 and q == D.MISS, 'Ultra Cool, 100 BPM: 4 frames off a half step is a Miss')
g, q = D.judge(du, 9 * 4 + 2)
check(q == D.GOOD, '...2 frames off is Good')

-- the windows
check(D.canLead(d, 100, 0) and not D.canLead(d, 117, 0) and not D.canLead(d, 50, 3), 'lead: before half - step/4, up to 3 moves')
check(not D.canCopy(d, 119, 0) and D.canCopy(d, 120, 0) and not D.canCopy(d, 237, 0), 'copy: the second half, up to measure - step/4')
check(D.cooldown(d) == 13, 'after a move, step - 2 frames before the next')

-- leading and copying
local ms = D.newMeasure(d, 0, 0)
D.leadMove(d, ms, 30, D.JUMP)
D.leadMove(d, ms, 60, D.LEFT)
check(d.points[3] == 4, 'the lead\'s two Excellents: 4 points')
local hit = D.copyMove(d, ms, 2, 150, D.JUMP)
check(hit.quality == D.EXCELLENT and d.points[2] == 2, 'copied half a measure later, same move: Excellent')
local wrong = D.copyMove(d, ms, 1, 180, D.RIGHT)
check(wrong.quality == D.MISS and wrong.wrong, 'the wrong direction: a miss, a wrong move')
local nothing = D.copyMove(d, ms, 1, 165, D.JUMP)
check(nothing.quality == D.MISS and not nothing.wrong, 'nothing to copy there: a miss')

-- the computer lead and back dancers
local okLead, okCopy = true, true
for seed = 1, 20 do
  local cc = C.new({ data = data, rank = (seed % 4), type = seed % 5, competition = C.OFFICIAL, seed = seed,
    mon = { species = 25, contest = {} }, playerName = 'LUCAS', partySlot = 0 })
  local dd = D.new(cc)
  local moves = D.npcLead(dd, 3)
  if #moves ~= dd.moves then okLead = false end
  local m2 = D.newMeasure(dd, 0, 0)
  for _, mv in ipairs(moves) do
    if not D.canLead(dd, mv.t, m2.counts[3]) then okLead = false end
    D.leadMove(dd, m2, mv.t, mv.dir)
  end
  local copies = D.npcCopy(dd, 2, m2.leadMoves)
  if #copies ~= #moves then okCopy = false end
  for i, cp in ipairs(copies) do
    if math.abs(cp.t - (m2.leadMoves[i].grid + dd.steps) * dd.hs) > 12 then okCopy = false end
  end
end
check(okLead, 'a computer lead makes the song\'s moves, all inside the lead\'s window')
check(okCopy, 'a computer copies each move half a measure on, a few frames off at most')

-- the whole round, the player pressing nothing: three leads, no points of their own
local game = { data = data, input = { wasPressed = function() return false end, isDown = function() return false end } }
local UI = require('src.ui.Gen4ContestDance')
local done = false
local ui = UI.new(game, c, { onDone = function() done = true end })
local pressed = { a = true }
game.input.wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end
for _ = 1, 20000 do
  ui:update(1 / 60)
  if (ui.mode == 'end' and ui.message) or ui.mode == 'intro' then pressed.a = true end
  if done then break end
end
check(done, 'the round runs to its end and the leader\'s announcement')
check(c.scores[0].dance == 0 and (c.scores[1].dance + c.scores[2].dance + c.scores[3].dance) > 0,
      'scores: the idle player 0, the others ' .. c.scores[1].dance .. '/' .. c.scores[2].dance .. '/' .. c.scores[3].dance)

-- a player who copies every lead move on the beat
local c2 = C.new({ data = data, rank = C.NORMAL, type = C.COOL, competition = C.OFFICIAL, seed = 12,
  mon = { species = 25, contest = {} }, playerName = 'LUCAS', partySlot = 0 })
done = false
local ui2 = UI.new(game, c2, { onDone = function() done = true end })
pressed = { a = true }
local KEY = { [1] = 'up', [2] = 'down', [3] = 'left', [4] = 'right' }
for _ = 1, 20000 do
  local ms2 = ui2.ms
  if ui2.mode == 'dance' and ms2 then
    local t = ui2.frame + 1 - ms2.start
    if ms2.lead ~= 0 then
      for _, l in ipairs(ms2.leadMoves) do
        if math.floor((l.grid + ui2.d.steps) * ui2.d.hs) == math.floor(t) then pressed[KEY[l.dir]] = true end
      end
    elseif t == 30 or t == 60 or t == 90 then
      pressed.up = true
    end
  end
  ui2:update(1 / 60)
  if (ui2.mode == 'end' and ui2.message) or ui2.mode == 'intro' then pressed.a = true end
  if done then break end
end
check(done and c2.scores[0].dance >= 20, 'a player who keeps time and copies scores well: ' .. tostring(c2.scores[0].dance))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
