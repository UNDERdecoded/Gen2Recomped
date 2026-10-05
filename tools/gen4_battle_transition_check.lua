-- Run:  texlua tools/gen4_battle_transition_check.lua <cache dir>
--
-- PLATINUM'S BATTLE TRANSITIONS. Requested from play: "add in pokemon
-- platinums battle transitions with rom parity". Until now a Platinum battle
-- began behind the Game Boy's spiral. What is checked:
--   1. the choice, per EncEffects_CutInEffect / CutInEffects_ForBattle;
--   2. the interpolators and the flash, against values worked by hand from
--      encounter_effect.c;
--   3. every one of the 31 effects runs to its end in a plausible number of
--      30 Hz ticks and finishes covered (black or white);
--   4. the cartridge's pictures are in the cache, and the wiring exists.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_battle_transition_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

-- ============================ 1. the choice
local C = require('src.world.Gen4EncounterEffect')
local function name(ctx) local _, n = C.cutIn(ctx) return n end
check(name({ species = 396, enemyLevel = 3, leadLevel = 5, terrain = 'grass' }) == 'grass_low',
      'a weaker wild Starly in grass')
check(name({ species = 396, enemyLevel = 5, leadLevel = 5, terrain = 'grass' }) == 'grass_low',
      'an EQUAL level is still the lower-level effect (v0 > 0 is strict)')
check(name({ species = 396, enemyLevel = 6, leadLevel = 5, terrain = 'plain' }) == 'grass_high',
      'plain terrain is the grass pair')
check(name({ species = 129, enemyLevel = 30, leadLevel = 5, terrain = 'water' }) == 'water_high',
      'water, stronger')
check(name({ species = 41, enemyLevel = 3, leadLevel = 5, terrain = 'cave' }) == 'cave_low',
      'cave, weaker')
check(name({ trainer = true, trainerClass = 2, enemyLevel = 5, leadLevel = 5, terrain = 'grass' })
      == 'trainer_grass_low', 'a Youngster: the trainer column')
check(name({ trainer = true, trainerClass = 2, enemyLevel = 9, leadLevel = 5, terrain = 'cave' })
      == 'trainer_cave_high', 'a stronger trainer in a cave')
check(name({ trainer = true, trainerClass = 62, enemyLevel = 14, leadLevel = 5 }) == 'leader_roark',
      'Roark (class 62) has his banner')
check(name({ trainer = true, trainerClass = 79, double = true }) == 'double',
      'Volkner in a double battle is DOUBLE_LEADER, whose cut-in is the double one')
check(name({ trainer = true, trainerClass = 74, double = true }) == 'double',
      'and any other special trainer in a double loses its cut-in (the cartridge bug)')
check(name({ trainer = true, trainerClass = 73, double = true }) == 'galactic_grunt',
      'but Team Galactic keeps theirs even in a double')
check(name({ trainer = true, trainerClass = 87 }) == 'galactic_boss', 'Jupiter is a commander')
check(name({ trainer = true, trainerClass = 86 }) == 'galactic_boss', 'Cyrus')
check(name({ trainer = true, trainerClass = 69 }) == 'champion_cynthia', 'Cynthia')
check(name({ trainer = true, trainerClass = 63, enemyLevel = 9, leadLevel = 5, terrain = 'water' })
      == 'trainer_water_high', 'the rival uses the local effect')
check(name({ species = 483 }) == 'legendary' and name({ species = 487 }) == 'mythical',
      'Dialga is LEGENDARY, Giratina MYTHICAL')
check(name({ species = 481, enemyLevel = 50, leadLevel = 40, terrain = 'cave' }) == 'cave_high',
      'Mesprit, roaming, takes the local effect')
check(name({ species = 144, zone = 251, terrain = 'grass' }) == 'grass_low'
      and name({ species = 144, zone = 10, terrain = 'grass' }) == 'grass_low',
      'Articuno is local everywhere (its pair says USE_LOCAL)')
check(name({ species = 377, zone = 10 }) == 'mythical' and name({ species = 377, zone = 251 }) ~= 'mythical',
      'Regirock is MYTHICAL except in Pal Park')
check(name({ species = 396, double = true }) == 'double', 'a wild double')
local _, _, pair = C.cutIn({ trainer = true, trainerClass = 97, frontier = true })
check(pair == 'frontier_brain', 'a Frontier Brain in the Frontier')

-- ============================ 2. the arithmetic
local T = require('src.render.Gen4BattleTransition')
local q = T.Quad(0, -2, -12, 7)
local xs = {}
for i = 1, 8 do xs[i] = q() end
local want = { 0, -10.3, -17.3, -20.9, -21.2, -18.2, -11.8, -2 }
local ok = true
for i = 1, 8 do if math.abs(xs[i] - want[i]) > 0.06 then ok = false end end
check(ok, 'the grass slice\'s first phase swings to about -21 and back to -2 in 8 calls')
local l = T.Lin(0, 16, 3)
local a, b, c, d = l(), l(), l(), l()
check(a == 0 and b == 5 and c == 10 and d == 16, 'a 3-step brightness ramp is 0, 5, 10, 16')
local sp = T.Quad(0, 255, 1, 8)
local s = {}
for i = 1, 9 do s[i] = math.floor(sp()) end
check(s[2] == 4 and s[5] == 65 and s[9] == 255, 'ScreenSplit X (v0 = 1.0, fx32 floor): 0, 4, .., 65, .., 255')

-- ============================ 3. every effect runs, and ends covered
-- The flash on its own: 2 flashes are 22 ticks, by the C state machine.
local E = T.EFFECTS
local count = 0
for i = 0, #C.CUTINS do
  local n = C.CUTINS[i]
  check(E[n], 'effect ' .. i .. ' (' .. n .. ') has a script')
end
local function run(nm)
  local stack = { pop = function() end }
  local t = setmetatable({}, T)
  t.game, t.ctx = { stack = stack }, { trainerName = 'X' }
  t.name = nm
  t.S = { bright = 0, other = 0, zoom = 1, sprites = {}, rects = {}, tasks = {}, animTick = 0 }
  local S, TT = t.S, t.ctx
  t.main = coroutine.create(function() E[nm](S, TT) end)
  t.frame, t.finished = 0, false
  local n = t:runAll(3000)
  return n, t.S
end
local lengths = {}
for i = 0, #C.CUTINS do
  local nm = C.CUTINS[i]
  if E[nm] then
    local okRun, n, S = pcall(run, nm)
    check(okRun, nm .. ' runs: ' .. tostring(n))
    if okRun then
      lengths[nm] = n
      check(n > 20 and n < 400, nm .. ' takes a plausible time (' .. n .. ' ticks)')
      check(S.cover == 'black' or S.cover == 'white', nm .. ' ends covered, got ' .. tostring(S.cover))
      count = count + 1
    end
  end
end
check(count == 31, 'all 31 ran, got ' .. count)
check(lengths.grass_low and lengths.grass_low < lengths.leader_roark,
      'a leader\'s introduction is longer than a wild flash')
-- the gym leader's: 1-flash (12) + reveal 7 + 11 + VS ~16 + slide 5 + 11
-- + 4 + 4 + 27 + fade 16 -- around 115 ticks, about four seconds
check(lengths.leader_roark and lengths.leader_roark > 100 and lengths.leader_roark < 140,
      'a gym leader\'s cut-in is about 115 ticks, got ' .. tostring(lengths.leader_roark))

-- ============================ 4. the pictures and the wiring
local f = loadfile(cacheDir .. '/gen4_encounter_effects.lua')
local rec = f and f()
check(rec, 'the cache must carry gen4_encounter_effects '
      .. '(run tools/gen4_encounter_effects_extract.lua on an older cache)')
if rec then
  local im = rec.images.trainer_low and rec.images.trainer_low[1]
  check(im and im.w == 64 and im.h == 64 and im.x == -32, 'the small Poke Ball is 64x64, centred')
  local hi = rec.images.trainer_high
  check(hi and #hi == 3 and hi[2].h == 64 and hi[3].y == 0, 'the big one has its two halves')
  local nb = 0
  for _, who in ipairs({ 'roark', 'gardenia', 'wake', 'maylene', 'fantina', 'candice', 'byron', 'volkner' }) do
    if rec.images['leader_' .. who .. '/banner'] and rec.images['leader_' .. who .. '/mugshot']
       and rec.palettes['leader_' .. who .. '/mugshot.NCLR'] then nb = nb + 1 end
  end
  check(nb == 8, 'eight leaders\' banners and mugshots, got ' .. nb)
  check(rec.anims.league_banner and #rec.anims.league_banner >= 2, 'the League banner animates')
  check(rec.images.vs and #rec.images.vs == 2, 'VS: outline and solid')
end
local dsrc = io.open('src/core/Data.lua'):read('a')
check(dsrc:match('local GEN4_PREFIXED = (%b{})'):find('"gen4_encounter_effects"', 1, true),
      'Data.lua must load it')
local bt = io.open('src/render/BattleTransition.lua'):read('a')
check(bt:find('Gen4BattleTransition").new(game, onDone, opts)', 1, true),
      'BattleTransition hands Platinum to it')
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('terrain = GameVersion.isGen4() and', 1, true) and ow:find('species = tonumber(enemySpecies)', 1, true),
      'and the overworld passes what the choice reads')
local rd = io.open('src/render/Renderer.lua'):read('a')
check(rd:find('self.battleWipe.needsSource', 1, true), 'the renderer hands it the frame')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
