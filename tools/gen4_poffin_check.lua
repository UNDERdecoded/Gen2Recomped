-- Run:  texlua tools/gen4_poffin_check.lua <cache dir>
--
-- PLATINUM'S POFFINS (src/pokemon/Gen4Poffin.lua, Gen4PoffinStir.lua and the
-- g4_*poffin* commands), per poffin.c, overlay083/ov83_0223F7F4.c and
-- poffin_case/main.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local flavors = load('gen4_berry_flavors')
check(flavors, 'the cache must carry gen4_berry_flavors (run tools/gen4_berry_flavors_extract.lua)')
if not flavors then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
local text, items = load('text'), load('items')
local data = { text = text, items = items, gen4_berry_flavors = flavors }
local P = require('src.pokemon.Gen4Poffin')

-- the berries, against nuts_data.narc
check(table.concat(flavors[149].flavors, ',') == '10,0,0,0,0' and flavors[149].smoothness == 25, 'Cheri: Spicy 10, smooth 25')
check(table.concat(flavors[152].flavors, ',') == '0,0,0,10,0', 'Rawst: Bitter 10')

-- Poffin_MakePoffin
check(P.make({ 10, 0, 0, 0, 0 }, 20).type == 0, 'spicy alone: type 0 (Spicy)')
check(P.make({ 0, 12, 0, 20, 0 }, 20).type == 3 * 5 + 1, 'bitter over dry: Bitter-Dry (16)')
check(P.make({ 10, 10, 10, 0, 0 }, 20).type == P.RICH, 'three flavors: Rich')
check(P.make({ 10, 10, 10, 10, 0 }, 20).type == P.OVERRIPE, 'four: Overripe')
check(P.make({ 60, 30, 30, 30, 30 }, 40).type == P.MILD, 'any flavor >= 50: Mild')
local cycle = 0
local f = P.make({ 5, 0, 0, 0, 0 }, 20, true, function(n) cycle = cycle + 1; return cycle % n end)
local twos, zeros = 0, 0
for i = 1, 5 do if f.flavors[i] == 2 then twos = twos + 1 elseif f.flavors[i] == 0 then zeros = zeros + 1 end end
check(f.type == P.FOUL and twos == 3 and zeros == 2, 'foul: a cleared Poffin with three random flavors at 2')
check(P.name(data, P.make({ 0, 12, 0, 20, 0 }, 20)) == 'Bitter-Dry Poffin', 'names from bank 465')
check(P.level(P.make({ 0, 12, 0, 20, 0 }, 20)) == 20 and P.level(P.make({ 10, 10, 30, 0, 0 }, 20)) == 30,
      'level: the type\'s main flavor, or the highest for Rich')

-- the cooking result, by hand from ov83_0223F7F4
local cheri = { item = 149, flavors = flavors[149].flavors, smoothness = 25 }
local p = P.cook({ cheri }, 1800, 0, 0)
-- d = {10,0,0,0,-10}; one negative -> {9,-1,-1,-1,-11}; one minute = x1.00
check(p.type == 0 and p.flavors[1] == 9 and p.flavors[2] == 0 and p.smoothness == 24,
      'Cheri alone in one minute: Spicy, 9, smooth 24 -- got ' .. table.concat(p.flavors, ',') .. ' / ' .. p.smoothness)
p = P.cook({ cheri }, 900, 0, 0)
check(p.flavors[1] == 18, 'in thirty seconds the flavor doubles: 18')
p = P.cook({ cheri }, 900, 2, 3)
check(p.flavors[1] == 13, 'and five burns and spills take five: 13')
p = P.cook({ cheri, cheri }, 1800, 0, 0)
check(p.type == P.FOUL, 'the same Berry twice in a group is Foul')

-- the case
local save = { gen4Vars = {}, inventory = {}, party = {} }
for _ = 1, 100 do P.add(save, P.make({ 1, 0, 0, 0, 0 }, 20)) end
check(P.count(save) == 100 and not P.add(save, P.make({ 1, 0, 0, 0, 0 }, 20)), 'a hundred Poffins, then full')

-- feeding: a Lonely mon (nature 1) likes spicy and dislikes sour
local mon = { species = 25, personality = 1, happiness = 70 }
local q = P.make({ 20, 0, 0, 0, 10 }, 30)
check(P.preference(q, mon) == 'like', 'Lonely likes a spicy-over-sour Poffin')
P.feed(q, mon)
check(mon.contest.cool == 22 and mon.contest.tough == 9 and mon.contest.sheen == 30 and mon.happiness == 71,
      'x1.1 cool (22), x0.9 tough (9), smoothness to sheen, friendship +1')
mon.contest.sheen = 255
check(not P.canEat(mon), 'a sheen of 255 eats no more')

-- the stirring physics
local Stir = require('src.pokemon.Gen4PoffinStir')
check(Stir.arc(168, 96, 168, 106) > 0 and Stir.arc(168, 96, 168, 86) < 0, 'arc: clockwise on screen is positive')
local s = Stir.new(function() return 0 end)
for _ = 1, 89 do Stir.step(s, 0) end
check(s.burns == 0 and s.event == nil, 'still for 89 frames: nothing yet')
Stir.step(s, 0)
check(s.event == 'warn' and s.burns == 0, 'the 90th: the first slow stretch is only a warning')
for _ = 1, 90 do Stir.step(s, 0) end
check(s.burns == 1, 'the next 90: a burn')
s = Stir.new(function() return 0 end)
for _ = 1, 30 do Stir.step(s, 200000) end
check(s.velocity == 3640 and s.spills == 1, 'pinned at 3640 for 30 frames: one overflow')
s = Stir.new(function() return 0 end)
local frames = 0
while not s.done and frames < 5000 do Stir.step(s, 0); frames = frames + 1 end
check(s.done and s.frames == 1800, 'never stirred: three 600-frame phases, 1800 frames')

-- the commands
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local game = { data = data, save = { gen4Vars = {}, inventory = {}, party = {} } }
local ctx = { game = game, save = game.save }
C.g4_can_cook_poffin(ctx, 0x800C)
check(game.save.gen4Vars[0x800C] == 1, 'checkcancookpoffin: no Berries -> 1')
game.save.inventory[149] = 2
C.g4_can_cook_poffin(ctx, 0x800C)
check(game.save.gen4Vars[0x800C] == 0, '...with a Cheri Berry -> 0')
C.g4_give_poffin(ctx, 0x800C, 60, 30, 30, 30, 30, 40)
check(game.save.gen4Vars[0x800C] == P.MILD and P.count(game.save) == 1, 'givepoffin: the Hotel\'s Mild Poffin')
C.g4_poffin_case_empty_slots(ctx, 0x800C)
check(game.save.gen4Vars[0x800C] == 99, 'getemptypoffincaseslotcount: 99')

-- GROUP COOKING (ov83_0223FCE8 / ov83_0223FFA8)
local Stir = require('src.pokemon.Gen4PoffinStir')
local gs = Stir.new(function() return 0 end)
gs.syncFrames = 60
check(Stir.syncBonus(gs, 4) == 10 and Stir.syncBonus(gs, 3) == 5 and Stir.syncBonus(gs, 2) == 1
      and Stir.syncBonus(gs, 1) == 0, 'sync bonus: (frames / 6) x {0,1,5,10}[cooks] / 10')
gs.syncFrames = 6000
check(Stir.syncBonus(gs, 4) == 10, '...at most 10')
local ss = Stir.new(function() return 0 end)
ss.velocity = 2000
local together = { { x = 100, y = 96, arc = 900, zone = 0 }, { x = 110, y = 100, arc = 900, zone = 0 } }
for _ = 1, 4 do Stir.sync(ss, together) end
check((ss.syncFrames or 0) == 0 and ss.syncStreak == 4, 'sync: four frames together before any counts')
Stir.sync(ss, together)
check(ss.syncFrames == 1 and ss.synced and ss.sparkle, '...then each frame counts and sparkles')
together[2].arc = 100
Stir.sync(ss, together)
check(ss.syncFrames == 1 and ss.syncStreak == 4, 'a cook barely moving pauses the run')
together[2].arc, together[2].x = 900, 160
Stir.sync(ss, together)
check(ss.syncStreak == 0 and not ss.synced, 'a finger 32 px from the first cook\'s breaks it')

local cmdSave = { gen4Vars = {}, inventory = {} }
C.g4_link_club({ game = { stack = {} }, save = cmdSave }, 3, 0x800C)
check(cmdSave.gen4Vars[0x800C] == 3, 'startbattleserver for any other mode: COMM_CLUB_RET_ERROR')

-- a three-cook group, the player stirring the way the pot asks
local Cook = require('src.ui.Gen4PoffinCooking')
local gsave = { gen4Vars = {}, inventory = { [149] = 1 }, player = { name = 'LUCAS' } }
local cook
local ggame = { data = data, save = gsave, stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end,
            isDown = function(_, k) return math.abs(cook.stir.velocity) < 2400 and (k == 'right') == (cook.stir.dir == 0) and (k == 'right' or k == 'left') end } }
cook = Cook.new(ggame, { group = 3 })
cook:start(149)
check(#cook.partners == 2 and cook.partners[1].item ~= 149 and cook.partners[2].item ~= cook.partners[1].item,
      'two local cooks, each with a different Berry')
for _ = 1, 4000 do
  if cook.mode ~= 'stir' then break end
  cook:update(1 / 30)
end
check(cook.mode == 'result' and cook.made == 3 and P.count(gsave) == 3, 'every cook gets one Poffin per cook: 3')
check((cook.stir.syncFrames or 0) > 0, 'the group stirred in sync for ' .. tostring(cook.stir.syncFrames) .. ' frames')
print(('  group: %d frames, %d burns, %d spills, %d synced, %s smooth %d'):format(cook.stir.frames, cook.stir.burns,
  cook.stir.spills, cook.stir.syncFrames or 0, P.name(data, cook.poffin), cook.poffin.smoothness))

-- the scripts lower
local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = text }
local bad = {}
for label in pairs(sdata.map_scripts.scripts) do
  local m = label:sub(1, 5)
  if m == 'M0426' or m == 'M0119' or m == 'M0148' then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      local n = row[1]
      if n == 'g4_unimplemented' then
        bad[#bad + 1] = label .. ':' .. tostring(row[2])
      elseif type(n) == 'string' and not C[n] then bad[#bad + 1] = label .. ':' .. n end
    end
  end
end
check(#bad == 0, 'the Poffin House, the Hotel and the Contest Hall\'s poffin rows lower: ' .. table.concat(bad, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
