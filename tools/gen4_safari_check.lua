-- Run:  texlua tools/gen4_safari_check.lua <cache dir>
--
-- PLATINUM'S CATCH FORMULA AND THE GREAT MARSH SAFARI GAME.
--
--   1. Gen4Catching: `BattleScript_CalcCatchShakes`, worked by hand. Until
--      this, every ball thrown in Sinnoh used Gen 1's ItemUseBall.
--   2. Gen4Safari: the BAIT / MUD stage counters and the flee check.
--   3. The wiring: the script commands, the field's step and after-battle
--      handling, the start menu, the battle's menu and healthbox.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_safari_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

-- ============================ 1. the catch formula
local C = require('src.battle.Gen4Catching')
local base = { catchRate = 45, maxHP = 100, hp = 100, level = 20,
               targetDef = { types = { 'WATER' } } }
local function with(t)
  local c = {}
  for k, v in pairs(base) do c[k] = v end
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end
check(C.rate(C.POKE, base) == 15, 'catch rate 45 at full HP in a Poke Ball is 15, got ' .. C.rate(C.POKE, base))
check(C.rate(C.ULTRA, base) == 30 and C.rate(C.GREAT, base) == 22 and C.rate(C.SAFARI, base) == 22,
      'Ultra x2, Great and Safari x1.5 (sBasicBallMod)')
check(C.rate(C.NET, base) == 45 and C.rate(C.NET, with({ targetDef = { types = { 'FIRE' } } })) == 15,
      'the Net Ball is x3 on Water or Bug, else x1')
check(C.rate(C.QUICK, with({ turns = 0 })) == 60 and C.rate(C.QUICK, with({ turns = 1 })) == 15,
      'the Quick Ball is x4 before the first turn ends')
check(C.rate(C.TIMER, with({ turns = 10 })) == 30 and C.rate(C.TIMER, with({ turns = 99 })) == 60,
      'the Timer Ball is 10 + turns tenths, to 40')
check(C.rate(C.NEST, with({ level = 5 })) == 52 and C.rate(C.NEST, with({ level = 45 })) == 15,
      'the Nest Ball is 40 - level below 40')
check(C.rate(C.DUSK, with({ hour = 22 })) == 52 and C.rate(C.DUSK, with({ hour = 12 })) == 15
      and C.rate(C.DUSK, with({ hour = 12, terrain = 'cave' })) == 52,
      'the Dusk Ball x3.5 from 20:00 to 03:59, or in a cave')
check(C.rate(C.DIVE, with({ terrain = 'water' })) == 52, 'the Dive Ball on water terrain')
check(C.rate(C.REPEAT, with({ alreadyCaught = true })) == 45, 'the Repeat Ball on an owned species')
check(C.rate(C.POKE, with({ hp = 1 })) == 44, 'at 1 HP: 45 * 298 / 300')
check(C.rate(C.POKE, with({ status = 'SLP' })) == 30 and C.rate(C.POKE, with({ status = 'PAR' })) == 22,
      'asleep x2, paralysed x1.5')
local ok = C.attempt(C.MASTER, base, function() return 65535 end)
check(ok, 'the Master Ball never misses')
local always0 = function() return 0 end
check(select(1, C.attempt(C.POKE, base, always0)), 'four low rolls catch')
local caught, shakes = C.attempt(C.POKE, base, function() return 65535 end)
check(not caught and shakes == 0, 'a first roll at the top breaks out with no shake')
-- 1048560 / sqrt(sqrt(16711680 / 15)) = 1048560 / 32 = 32767
local n = 0
local seq = { 32766, 32766, 32767 }
local i = 0
caught, shakes = C.attempt(C.POKE, base, function() i = i + 1 return seq[i] or 0 end)
check(not caught and shakes == 2, 'the shake threshold is 32767 for rate 15: two pass, the third breaks')
-- safari stages
check(C.rate(C.SAFARI, with({ safariStage = 6 })) == 22
      and C.rate(C.SAFARI, with({ safariStage = 12 })) == 90
      and C.rate(C.SAFARI, with({ safariStage = 0 })) == 5,
      'Safari: 45 x 10/10, x 40/10 and x 10/40, then x1.5')

-- ============================ 2. the Safari stages
local S = require('src.battle.Gen4Safari')
local st = S.init()
check(st.catchStage == 6 and st.escapeCount == 6, 'both counters start at 6')
check(S.bait(st, 3) == 'eating' and st.catchStage == 7 and st.escapeCount == 7,
      'Bait: catch +1 and, 9 in 10, escape +1 ("is eating!")')
check(S.bait(st, 0) == 'busyEating' and st.catchStage == 8 and st.escapeCount == 7,
      '...and 1 in 10 not ("is busy eating!")')
check(S.mud(st, 5) == 'angry' and st.escapeCount == 6 and st.catchStage == 7,
      'Mud: escape -1 and, 9 in 10, catch -1 ("is angry!")')
check(S.mud(st, 0) == 'besideItself' and st.escapeCount == 5 and st.catchStage == 7,
      '...and 1 in 10 not ("is beside itself with anger!")')
for _ = 1, 20 do S.mud(st, 1) end
check(st.escapeCount == 0 and st.catchStage == 0, 'and neither goes below 0')
local s6 = S.init()
check(S.flees(s6, 120, 120) and not S.flees(s6, 120, 121), 'flee rate 120 at stage 6 flees on a roll <= 120')
s6.escapeCount = 0
check(S.flees(s6, 120, 30) and not S.flees(s6, 120, 31), 'and at stage 0 it is 120 x 10/40 = 30')

local data = { text = assert(loadfile(cacheDir .. '/text.lua'))() }
check(S.text(data, S.TEXT.bait, 'LUCAS', 'Bidoof') == 'LUCAS threw some Bait\nat the Bidoof!',
      'the cartridge\'s own line, slots filled')
check(S.text(data, S.TEXT.labelMud) == 'MUD' and S.text(data, S.TEXT.labelBall) == 'BALL',
      'and its menu words')

-- ============================ 3. the wiring
local function src(p) return io.open(p):read('a') end
local vm = src('src/script/Gen4ScriptVM.lua')
check(vm:find('emit(s, { "g4_safari_game", ins.args[1] })', 1, true)
      and vm:find('emit(s, { "g4_safari_caught", ins.args[1] })', 1, true),
      'startendsafarigame and getcurrentsafarigamecaughtnum are lowered')
require('src.script.Gen4Commands')
local Commands = require('src.script.Commands')
check(Commands.g4_safari_game, 'and run')
local save = {}
local ctx = { save = save }
Commands.g4_safari_game(ctx, 0)
check(save.safari and save.safari.balls == 30 and save.safari.steps == 0, 'a game starts with 30 balls')
Commands.g4_safari_game(ctx, 1)
check(save.safari == nil, 'and ends')
local ow = src('src/world/OverworldController.lua')
check(ow:find('function OverworldState:gen4SafariStep', 1, true)
      and ow:find('if st.steps >= 500 then entry = 1 end', 1, true),
      'the field counts steps to 500')
check(ow:find('self:gen4SafariAfterBattle(result, battle)', 1, true), 'and handles the end of a battle')
check(ow:find('not GameVersion.isGen3() and not GameVersion.isGen4()', 1, true),
      'and walking between the marsh\'s areas does not end the game')
local bs = src('src/battle/BattleState.lua')
check(bs:find('self.gen4Safari = require("src.battle.Gen4Safari").init()', 1, true)
      and bs:find('function BattleState:gen4SafariAction', 1, true), 'the battle uses the marsh\'s rules')
check(bs:find('balls[tostring(ball)]', 1, true), 'and Platinum\'s balls find their records')
local menu = src('src/ui/Gen4StartMenu.lua')
check(menu:find('hidden = (row.id == "save" or row.id == "chat")', 1, true)
      and menu:find('"safari_game", 21', 1, true), 'the start menu shows RETIRE and hides SAVE')
local gb = src('src/battle/Gen4Battle.lua')
check(gb:find('healthboxImage(battle, "healthbox_safari")', 1, true), 'the Safari healthbox is drawn')
local cat = src('src/battle/Catching.lua')
check(cat:find('require("src.battle.Gen4Catching").registerInto(registry, owner)', 1, true),
      'the formula is registered for a Gen 4 dataset')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
