-- Run:  texlua tools/gen4_move_tutor_check.lua <cache dir>
--
-- PLATINUM'S SHARD MOVE TUTORS (src/import/Gen4MoveTutor.lua and the
-- g4_tutor_* commands), per src/overlay005/scrcmd_move_tutor.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_move_tutor')
check(rec, 'the cache must carry gen4_move_tutor (run tools/gen4_move_tutor_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
local T = require('src.import.Gen4MoveTutor')

-- the table, against res/pokemon/move_tutors.json
check(#rec.moves == 38, '38 tutor moves')
local dive = rec.moves[1]
check(dive.move == 291 and dive.red == 2 and dive.blue == 4 and dive.yellow == 2 and dive.green == 0
      and dive.location == 0, 'Dive: 2 red, 4 blue, 2 yellow, Route 212')
check(rec.moves[2].move == 189 and rec.moves[2].location == 1, 'Mud-Slap at the Survival Area')
check(rec.moves[38].move == 253 and rec.moves[38].location == 2, 'Uproar, last, in Snowpoint')
local n = { [0] = 0, 0, 0 }
for _, m in ipairs(rec.moves) do n[m.location] = n[m.location] + 1 end
check(n[0] == 13 and n[1] == 17 and n[2] == 8, 'thirteen on Route 212, seventeen at the Survival Area, eight in Snowpoint')
check(#rec.masks == 505, 'a mask for each of the 505 movesets')

-- learnable: Gible (443) on Route 212 knows only Fury Cutter's chance there
local gible = { species = 443, moves = {} }
local here = T.learnable(rec, gible, 0)
check(#here == 1 and here[1] == 210, 'Gible can learn Fury Cutter on Route 212, got ' .. table.concat(here, ','))
gible.moves = { { id = 210, pp = 20 } }
check(#T.learnable(rec, gible, 0) == 0, 'and not once it knows it')
check(#T.learnable(rec, nil, 2) == 8, 'with no Pokemon, the location\'s whole list')
check(T.moveset({ species = 479, form = 1 }) == 501 and T.moveset({ species = 386, form = 3 }) == 496,
      'Heat Rotom and Speed Deoxys read their own movesets')

-- the commands
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local pushed
local save = { party = { { species = 443, level = 30, moves = { { id = 33, pp = 35 } } } },
               inventory = { [72] = 0, [73] = 8 }, gen4Vars = {} }
local game = { data = { gen4_move_tutor = rec, moves = { [210] = { name = 'Fury Cutter', pp = 20 } } },
               save = save, stack = { push = function(_, s) pushed = s end, pop = function() end } }
local resumed = 0
local ctx = { game = game, save = save, runner = { resume = function() resumed = resumed + 1 end, yield = function() end } }
local function var(v) return save.gen4Vars[v] end
C.g4_tutor_has_moves(ctx, 0, 0, 0x800C)
check(var(0x800C) == 1, 'checkhaslearnabletutormoves: yes for Gible on Route 212')
C.g4_tutor_menu(ctx, 0, 0, 0x800C)
check(pushed and pushed.items and #pushed.items == 2 and pushed.items[1].label == 'Fury Cutter',
      'the menu is Fury Cutter then EXIT')
pushed.items[1].onSelect()
check(var(0x800C) == 210 and resumed == 1, 'choosing it writes the move id and resumes the script')
pushed.onCancel()
check(var(0x800C) == 65534, 'B is MENU_CANCEL (65534)')
C.g4_tutor_can_afford(ctx, 210, 0x800C)
check(var(0x800C) == 1, 'Fury Cutter costs 8 blue: affordable with 8')
save.inventory[73] = 7
C.g4_tutor_can_afford(ctx, 210, 0x800C)
check(var(0x800C) == 0, 'and not with 7')
save.inventory[73] = 8
C.g4_tutor_pay(ctx, 210)
check((save.inventory[73] or 0) == 0, 'paying takes the 8 blue shards')
C.g4_tutor_set_move(ctx, 0, 210, 1)
check(save.party[1].moves[2].id == 210 and save.party[1].moves[2].pp == 20, 'resetmoveslot writes the move with full PP')
C.g4_tutor_forget_menu(ctx, 0, 210)
pushed.onCancel()
C.g4_tutor_forget_slot(ctx, 0x8002)
check(var(0x8002) == 4, 'keeping every move answers 4 (LEARNED_MOVES_MAX)')

-- every tutor script lowers without an unknown command
local VM = require('src.script.Gen4ScriptVM')
local data = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = load('text') }
local unknown = {}
for _, label in ipairs({ 'M0181/S00B1', 'M0211/S1673', 'M0458/S007F', 'M1103/S004D' }) do
  local rows = VM.compile(data, label)
  check(rows and #rows > 0, label .. ' compiles')
  for _, r in ipairs(rows or {}) do
    if type(r[1]) == 'string' and not C[r[1]] then unknown[r[1]] = true end
    if r[1] == 'g4_noop' and tostring(r[2]):find('tutor') then unknown['noop:' .. r[2]] = true end
  end
end
local list = {}
for k in pairs(unknown) do list[#list + 1] = k end
check(#list == 0, 'and nothing in them is unlowered or a tutor no-op: ' .. table.concat(list, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
