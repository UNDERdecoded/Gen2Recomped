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
local data = { text = load_('text.lua'), moves = load_('moves.lua'), constants = { gen = 4 } }
local lang = load_('gen4_language.lua')
local battle = { data = data, trainer = nil }

local tackleName
for id, def in pairs(data.moves) do if id == 33 then tackleName = def.name end end

local function lines(s) return s and s:gsub('\n', ' / ') end

if not lang then
  -- an English cache: the engine's own text, untouched
  data.gen4_language = nil
  for _, s in ipairs({ 'Wild STARLY\nappeared!', 'Go! TURTWIG!', 'Enemy STARLY\nfainted!', "It's super\neffective!" }) do
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
  -- an unknown line is left alone
  check(T.translate(battle, 'Something nobody wrote.') == 'Something nobody wrote.', 'an unknown line is unchanged')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
