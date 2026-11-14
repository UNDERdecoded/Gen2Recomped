-- Run:  python tools/run_lua_check.py tools/gen4_battle_text_check.lua <platinum cache>/data/generated
--
-- PLATINUM'S BATTLE LINES FROM THE CARTRIDGE (src/battle/Gen4BattleText.lua).
-- On a non-English cache (`gen4_language` present) the engine's English lines
-- come out as the cartridge's bank 368 / bank 0 lines with the names filled
-- in; on an English cache nothing changes at all.

package.path = './?.lua;' .. package.path
local dir = (arg[1] or ''):gsub('[/\\]*$', '') .. '/'
local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function load_(n) local f = loadfile(dir .. n) return f and f() end

local T = require('src.battle.Gen4BattleText')
local data = { text = load_('text.lua'), moves = load_('moves.lua'), items = load_('items.lua'), constants = { gen = 4 } }
local lang = load_('gen4_language.lua')
local battle = { data = data, trainer = nil }

local tackleName
for id, def in pairs(data.moves) do if id == 33 then tackleName = def.name end end

local function lines(s) return s and s:gsub('\n', ' / ') end

if not lang then
  -- an English cache: the engine's own text, untouched
  data.gen4_language = nil
  for _, s in ipairs({ 'Wild STARLY\nappeared!', 'Go! TURTWIG!', 'Enemy STARLY\nfainted!', "It's super\neffective!",
    "TURTWIG's\nhurt by poison!", 'Enemy STARLY\nwas poisoned!', "TURTWIG's\nATTACK fell!", 'Hail continues to\nfall.',
    "Enemy STARLY's\nSPCL.ATK\ngreatly fell!", 'RED got $120\nfor winning!', 'But, it failed!', 'Nothing happened!',
    "STARLY's\nINTIMIDATE!", 'Enemy STARLY is\npelted by HAIL!', 'RED used\nPotion!',
    'The tailwind blew\nfrom behind\nyour team!', 'A SANDSTORM brewed!' }) do
    check(T.translate(battle, s) == s, 'an English cache keeps "' .. lines(s) .. '"')
  end
else
  data.gen4_language = lang
  local function differs(s, mustHave)
    local out = T.translate(battle, s)
    check(out ~= s and out:find(mustHave, 1, true), ('"%s" -> "%s" (needs %s)'):format(lines(s), lines(out), mustHave))
    check(not out:find('{STRVAR', 1, true) and not out:find('{WAIT', 1, true), 'no raw placeholder left in "' .. lines(out) .. '"')
    return out
  end
  differs('Wild STARLY\nappeared!', 'STARLY')
  differs('Go! TURTWIG!', 'TURTWIG')
  differs('Enemy STARLY\nfainted!', 'STARLY')
  differs('TURTWIG\nfainted!', 'TURTWIG')
  differs("It's super\neffective!", '')
  differs("It's not very\neffective...", '')
  differs('Critical hit!', '')
  differs("Enemy STARLY's\nattack missed!", 'STARLY')
  differs('TURTWIG gained\n64 EXP. Points!', '64')
  differs('TURTWIG grew\nto level 11!', '11')
  differs("TURTWIG's\nATTACK fell!", 'TURTWIG')
  differs("Enemy STARLY's\nSPEED rose!", 'STARLY')
  differs('TURTWIG\nused ' .. tackleName .. '!', 'TURTWIG')
  differs('Enemy STARLY\nused ' .. tackleName .. '!', 'STARLY')
  battle.trainer = { className = 'KLASSE', name = 'NAME' }
  differs('Enemy STARLY\nused ' .. tackleName .. '!', 'STARLY')
  differs('KLASSE NAME wants\nto fight!', 'KLASSE')
  differs('KLASSE NAME sent\nout STARLY!', 'STARLY')
  -- the second pass: status, weather, items, the sides' fields (generated table
  -- + hand rows).  Each must come out in the cartridge's language.
  local function german(s, notThis)
    local out = T.translate(battle, s)
    check(out ~= s, ('"%s" is translated'):format(lines(s)))
    check(not out:find('{STRVAR', 1, true) and not out:find('{WAIT', 1, true) and not out:find('\012', 1, true),
      'no raw control left in "' .. lines(out) .. '"')
    if notThis then check(not out:find(notThis, 1, true), ('"%s" no longer says %s'):format(lines(out), notThis)) end
    return out
  end
  battle.trainer = nil
  german("TURTWIG's\nhurt by poison!", 'poison')
  german('Enemy STARLY\nwas poisoned!', 'poisoned')
  german('TURTWIG\nwas burned!', 'burned')
  german("Enemy STARLY's\nparalyzed! It may\nnot attack!", 'paralyzed')
  german('STARLY\nfell asleep!', 'asleep')
  german('Hail continues to\nfall.', 'Hail')
  german('A SANDSTORM brewed!', 'brewed')
  german('Enemy STARLY is\npelted by HAIL!', 'pelted')
  german('The tailwind blew\nfrom behind\nyour team!', 'tailwind')
  german("Poison spikes were\nscattered all around\nyour team's feet!", 'Poison spikes')
  german('But, it failed!', 'failed')
  german('Nothing happened!', 'Nothing')
  german('RED got $120\nfor winning!', 'winning')
  german("Enemy STARLY's\nSPCL.ATK\ngreatly fell!", 'greatly')
  german("TURTWIG's\nSPEED rose!", 'rose')
  german("TURTWIG's\nACCURACY fell!", 'fell')
  german("STARLY's\nINTIMIDATE!", 'INTIMIDATE')
  local potion = tostring((data.items[17] or {}).name)
  german('TURTWIG restored\nhealth using its\n' .. potion .. '!', 'restored')
  german('RED used\n' .. potion .. '!', ' used')
  -- a stat change names the stat from the battle's own stat bank
  check(not german("TURTWIG's\nATTACK fell!"):find('ATTACK', 1, true), 'the stat is named in the cartridge language')
  -- a wild / foe / ally line each have their own entry
  local ally, wild = T.translate(battle, 'TURTWIG\nwas poisoned!'), T.translate(battle, 'Enemy STARLY\nwas poisoned!')
  battle.trainer = { className = 'KLASSE', name = 'NAME' }
  local foe = T.translate(battle, 'Enemy STARLY\nwas poisoned!')
  check(ally ~= wild and wild ~= foe, 'poison: ally, wild and foe each have their own line')
  battle.trainer = nil
  -- an unknown line is left alone
  check(T.translate(battle, 'Something nobody wrote.') == 'Something nobody wrote.', 'an unknown line is unchanged')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
