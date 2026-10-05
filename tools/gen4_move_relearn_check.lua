-- Run:  texlua tools/gen4_move_relearn_check.lua <cache dir>
--
-- PLATINUM'S TEACH SCREEN OUTSIDE BATTLE: the Move Reminder (Pastoria),
-- Grandma Wilma's Draco Meteor (Route 210) and the Move Deleter (Canalave),
-- per scrcmd_party_mon_moves.c and move_reminder_data.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local pokemon, moves, constants = load('pokemon'), load('moves'), load('constants')
check(pokemon and moves and constants, 'the cache carries pokemon, moves and constants')
if not (pokemon and moves and constants) then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end

local C = require('src.script.Commands')
local G = require('src.script.Gen4Commands')
local data = { constants = constants, pokemon = pokemon, moves = moves }

-- Item_IsHMMove
check(G.isHMMove(data, 57) and G.isHMMove(data, 431) and G.isHMMove(data, 432), 'Surf, Rock Climb and Defog are HMs')
check(not G.isHMMove(data, 89), 'Earthquake (a TM) is not')

-- MoveReminderData_GetMoves: Turtwig at 20 knowing Tackle and Withdraw --
-- Absorb (9), Razor Leaf (13) and Curse (17), not Bite (21)
local turtwig = { species = 387, level = 20, moves = { { id = 33, pp = 35 }, { id = 110, pp = 40 } } }
local r = G.reminderMoves(data, turtwig)
check(#r == 3 and r[1] == 71 and r[2] == 75 and r[3] == 174,
      'Turtwig 20 can relearn Absorb, Razor Leaf, Curse; got ' .. table.concat(r, ','))

-- the commands, driven through the menus they push
local stack = {}
local save = { party = { turtwig }, gen4Vars = {} }
local game = { data = data, save = save, input = {},
               stack = { push = function(_, s) stack[#stack + 1] = s end,
                         pop = function() stack[#stack] = nil end } }
local resumed = 0
local ctx = { game = game, save = save, runner = { resume = function() resumed = resumed + 1 end, yield = function() end } }
local function var(v) return save.gen4Vars[v] end
local function choose(i)
  local m = stack[#stack]
  local item = m.items[i]
  if not item.keepOpen then stack[#stack] = nil end
  if item.onSelect then item.onSelect() end
end
local function cancel()
  local m = stack[#stack]
  stack[#stack] = nil
  m.onCancel()
end

C.g4_has_reminder_moves(ctx, 0x800C, 0)
check(var(0x800C) == 1, 'checkhaslearnableremindermoves: yes')

-- a free slot: Razor Leaf goes straight in
C.g4_open_move_reminder_menu(ctx, 0)
check(#stack == 1 and #stack[1].items == 3 and stack[1].items[2].label == moves[75].name, 'the reminder lists the three')
choose(2)
check(#stack == 0 and resumed == 1 and turtwig.moves[3].id == 75 and turtwig.moves[3].pp == moves[75].pp,
      'Razor Leaf fills slot three with full PP')
C.g4_learned_move(ctx, 0x800C)
check(var(0x800C) == 0, 'checklearnedremindermove: 0, learned')

-- B on the list keeps the old moves
C.g4_open_move_reminder_menu(ctx, 0)
cancel()
C.g4_learned_move(ctx, 0x800C)
check(var(0x800C) == 0xFF, 'giving up answers 0xFF')

-- four known: Draco Meteor (Route 210) replaces the chosen one; an HM cannot go
turtwig.moves = { { id = 33, pp = 35 }, { id = 57, pp = 15 }, { id = 75, pp = 25 }, { id = 71, pp = 25 } }
C.g4_open_move_tutor_menu(ctx, 0, 434)
check(#stack == 1 and #stack[1].items == 1 and stack[1].items[1].label == moves[434].name, 'the tutor offers just Draco Meteor')
choose(1)
check(#stack == 1 and #stack[1].items == 4, 'four known: the forget list')
choose(2)
check(#stack == 1 and turtwig.moves[2].id == 57, 'Surf, an HM, cannot be forgotten here')
cancel()
check(#stack == 1 and #stack[1].items == 1, 'B on the forget list goes back to the move')
choose(1)
choose(1)
check(turtwig.moves[1].id == 434 and turtwig.moves[1].pp == moves[434].pp and turtwig.moves[1].ppUps == 0,
      'Draco Meteor replaces Tackle')
C.g4_learned_move(ctx, 0x800C)
check(var(0x800C) == 0, 'checklearnedtutormove: 0')

-- the deleter: any move, HMs too; B is MOVE_NOT_SELECTED
C.g4_select_party_mon_move(ctx, 0)
choose(2)
C.g4_selected_party_mon_move(ctx, 0x8001)
check(var(0x8001) == 1, 'getselectedpartymonmove: slot 1 (Surf)')
C.g4_buffer_party_move(ctx, 0, 0, 0x8001)
check(game.stringBuffers and game.stringBuffers[1] == moves[57].name, 'bufferpartymovename buffers Surf')
C.g4_clear_move_slot(ctx, 0, 0x8001)
check(#turtwig.moves == 3 and turtwig.moves[2].id == 75 and turtwig.moves[3].id == 71, 'clearing slot 1 shifts the rest up')
C.g4_select_party_mon_move(ctx, 0)
cancel()
C.g4_selected_party_mon_move(ctx, 0x8001)
check(var(0x8001) == 0xFF, 'B answers 0xFF')

-- the scripts lower with nothing missing
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = load('text') }
local bad = {}
for _, label in ipairs({ 'M0133/S006B', 'M0046/S004A', 'M0046/S0106', 'M0450/S00A3' }) do
  for _, row in ipairs(VM.compile(sdata, label) or {}) do
    local n = row[1]
    if type(n) == 'string' and (not C[n] or n == 'g4_unimplemented' or n == 'g4_no_feature'
        or (n == 'g4_noop' and tostring(row[2]):find('tutor'))) then
      bad[#bad + 1] = label .. ':' .. n .. ':' .. tostring(row[2])
    end
  end
end
check(#bad == 0, 'reminder, deleter and Route 210 tutor scripts lower fully: ' .. table.concat(bad, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
