-- Run:  python tools/run_lua_check.py tools/gen4_journal_check.lua <platinum cache dir>
--
-- PLATINUM'S JOURNAL (src/pokemon/Gen4Journal.lua, src/ui/Gen4Journal.lua,
-- src/import/Gen4JournalArt.lua) against journal.c, journal_printer.c and
-- journal_controller.c: the pages by day, the rules against repeats, the
-- wording, the open-on-continue test, the key item, and the page turn.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local J = require('src.pokemon.Gen4Journal')
local E = J.EVENT
local d1 = { year = 26, month = 10, day = 10, week = 6 }
local d2 = { year = 26, month = 10, day = 11, week = 0 }
local d4 = { year = 26, month = 10, day = 13, week = 2 }

-- ------------------------------------------------------------- the pages --
local save = {}
check(J.page(save, d1) == nil, 'no page before givejournal')
save.gen4Journal.acquired = true
J.title(save, 411, d1)
local p1 = J.page(save, d1)
check(p1 and p1.title.map == 411 and p1.title.day == 10, 'the title: the date and the map the day began on')
J.title(save, 3, d1)
check(J.page(save, d1).title.map == 411, 'titled once a day')
check(not J.openOnContinue(save, d2), 'a day later: not opened')
check(J.openOnContinue(save, d4), 'three days later: opened (Journal_CheckOpenOnContinue)')
check(J.openOnContinue(save, { year = 27, month = 10, day = 10, week = 0 }), 'a year later: opened')
local dec31 = { acquired = true, pages = { { title = { year = 26, month = 12, day = 31, week = 4 }, events = {}, online = {} } } }
check(not J.openOnContinue({ gen4Journal = dec31 }, { year = 27, month = 1, day = 1, week = 5 }),
  'Dec 31 -> Jan 1 is one day, not a new year')
J.title(save, 3, d2)
check(#save.gen4Journal.pages == 2 and save.gen4Journal.pages[1].title.day == 11
  and save.gen4Journal.pages[2].title.day == 10, 'a new day pushes a new page on top')
local s10 = { gen4Journal = { acquired = true, pages = {} } }
for k = 1, 12 do J.title(s10, 3, { year = 26, month = 1, day = k, week = k % 7 }) end
check(#s10.gen4Journal.pages == 10 and s10.gen4Journal.pages[1].title.day == 12, 'ten pages kept, newest first')

-- ----------------------------------------------------- the location rules --
local s = { gen4Journal = { acquired = true, pages = {} } }
J.title(s, 3, d1)
local ev = function() return J.page(s, d1).events end
J.location(s, { type = E.USED_PC_BOX }, d1)
J.location(s, { type = E.USED_PC_BOX }, d1)
check(#ev() == 1, 'the same misc event twice in a row is written once')
J.location(s, { type = E.GYM_WAS_TOO_TOUGH, location = 0 }, d1)
J.trainer(s, 47, 246, d1)
check(#ev() == 2 and ev()[2].type == E.BEAT_GYM_LEADER, 'beating Roark takes the place of "too tough"')
J.location(s, { type = E.ARRIVED_IN_LOCATION, location = 3 }, d1)
J.location(s, { type = E.ARRIVED_IN_LOCATION, location = 3 }, d1)
check(#ev() == 3, 'arriving twice at one place: once')
J.location(s, { type = E.ITEM_WAS_OBTAINED, item = 1 }, d1)
J.location(s, { type = E.USED_PC_BOX }, d1)
check(#ev() == 4 and ev()[1].type == E.BEAT_GYM_LEADER, 'a fifth event drops the oldest')
J.trainer(s, 3, 1, d1)
check(J.page(s, d1).trainer and J.page(s, d1).trainer.trainer == 1, 'an ordinary trainer is the page\'s trainer')
J.trainer(s, 3, 261, d1); J.trainer(s, 3, 262, d1)
local e4 = 0
for _, e in ipairs(ev()) do if e.type == E.BEAT_ELITE_FOUR_MEMBER then e4 = e4 + 1 end end
check(e4 == 1, 'only the latest Elite Four win is kept')
J.usedMove(s, J.MOVE.TELEPORT, 3)
check(ev()[#ev()].type == E.WARPED_TO_LOCATION, 'Teleport writes WARPED_TO_LOCATION (USED_CUT + 9)')
J.usedMove(s, J.MOVE.SOFTBOILED, 3)
check(ev()[#ev()].type == E.USED_SOFTBOILED, 'Softboiled is USED_CUT + 14')
J.onShopClosed(s, 2, 0)
check(ev()[#ev()].type == E.LOTS_OF_SHOPPING, 'bought twice or more: lots of shopping')
J.onShopClosed(s, 1, 1)
check(ev()[#ev()].type == E.BUSINESS_AT_MART, 'bought and sold: business')
J.mon(s, 'caught', 25, 0, 1, 15, d1)
check(J.page(s, d1).mon.variant == 1, 'caught at :15 -> the second wording')
J.mon(s, 'defeated', 25, 1, 1, 15, d1)
check(J.page(s, d1).mon.variant == 0, 'beaten at :15 -> the first')

-- ---------------------------------------------------------- the wording --
local text = load('text')
local data = { text = text, pokemon = load('pokemon'), items = load('items'), trainers = load('trainers'),
  gen4_area_popup = load('gen4_area_popup'), gen4_journal_art = load('gen4_journal_art'), isGen4Cache = true }
check(text and data.gen4_area_popup, 'the cache has text and gen4_area_popup')
if text and data.gen4_area_popup then
  local game = { data = data, save = { player = { name = 'LUCAS', rival = 'BARRY' } } }
  local page = { title = { year = 26, month = 10, day = 10, week = 6, map = 411 },
    events = { { type = E.RESTED_AT_HOME }, { type = E.ARRIVED_IN_LOCATION, location = 3 },
               { type = E.BEAT_GYM_LEADER, location = 0, trainer = 246 },
               { type = E.LEFT_BUILDING, location = 8 } },
    mon = { result = 'caught', species = 25, gender = 0, time = 0, variant = 0 },
    trainer = { trainer = 1, map = 3 }, online = {} }
  local r = J.render(game, page)
  local LANG = load('gen4_language')
  if LANG then
    -- a non-English cartridge words every row itself: each is a real line of the
    -- bank with this page's names in it, never the English sentence
    local function real(v) return type(v) == 'string' and v ~= '' and not v:find('{', 1, true) end
    check(real(r.date) and r.date:find('10', 1, true) and r.date ~= 'Oct. 10', 'the date: "' .. tostring(r.date) .. '"')
    check(real(r.weekday) and r.weekday ~= 'Saturday', 'the weekday: "' .. tostring(r.weekday) .. '"')
    local english = { 'Started from Twinleaf Town.', 'Rested comfortably at home.', 'Arrived in Jubilife City.' }
    for i = 1, 3 do
      check(real(r.lines[i]) and r.lines[i] ~= english[i], ('row %d is the cartridge\'s own line: "%s"'):format(i, tostring(r.lines[i])))
    end
    check(real(r.lines[4]) and not r.lines[4]:find('Oreburgh', 1, true), 'beat the gym leader: "' .. tostring(r.lines[4]) .. '"')
    check(real(r.lines[5]) and not r.lines[5]:find('Oreburgh', 1, true), 'left a building: "' .. tostring(r.lines[5]) .. '"')
    check(real(r.lines[6]) and (r.lines[6]:find('Pikachu', 1, true) or r.lines[6]:find('PIKACHU', 1, true)), 'caught: "' .. tostring(r.lines[6]) .. '"')
    check(real(r.lines[7]) and not r.lines[7]:find('Jubilife', 1, true), 'the trainer line: "' .. tostring(r.lines[7]) .. '"')
  else
  check(r.date == 'Oct. 10', 'the date: "' .. tostring(r.date) .. '"')
  check(r.weekday == 'Saturday', 'the weekday')
  check(r.lines[1] == 'Started from Twinleaf Town.', 'started from: "' .. tostring(r.lines[1]) .. '"')
  check(r.lines[2] == 'Rested comfortably at home.', 'rested at home')
  check(r.lines[3] == 'Arrived in Jubilife City.', 'arrived: "' .. tostring(r.lines[3]) .. '"')
  check(r.lines[4]:find('Oreburgh Gym', 1, true) and r.lines[4]:find('Roark', 1, true), 'beat Roark: "' .. tostring(r.lines[4]) .. '"')
  check(r.lines[5]:find('Oreburgh City', 1, true), 'left a building: "' .. tostring(r.lines[5]) .. '"')
  check(r.lines[6]:find('Pikachu', 1, true) or r.lines[6]:find('PIKACHU', 1, true), 'caught: "' .. tostring(r.lines[6]) .. '"')
  check(r.lines[7]:find('Jubilife City', 1, true), 'the trainer line: "' .. tostring(r.lines[7]) .. '"')
  end
  check(#r.lines == 9, 'nine rows under the title')
end

-- ----------------------------------------------------------- the screen --
local art = data.gen4_journal_art
local nArt = 0
for _ in pairs(art or {}) do nArt = nArt + 1 end
check(nArt == 20, 'twenty papers: ten pages, boy and girl (love tools/gen4_journal_extract)')
local Screen = require('src.ui.Gen4Journal')
check(#Screen.FOLD == 9 and Screen.FOLD[1][32] == 31 and Screen.FOLD[8][1] == 28 and Screen.FOLD[9][1] == false,
  'the page turn: Unk_ov81_021D33E8\'s nine steps')
local pressed = {}
local popped = 0
local game = { data = data, save = save,
  input = { wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end },
  stack = { pop = function() popped = popped + 1 end } }
local sc = Screen.new(game, {})
for _ = 1, 10 do sc:update() end
pressed.right = true; sc:update()
check(sc.page == 1 and sc.turning, 'RIGHT turns to the older page')
for _ = 1, 10 do sc:update() end
pressed.a = true; sc:update()
check(sc.page == 1 and not sc.turning, 'no page past the last')
pressed.b = true; sc:update()
check(sc.page == 0, 'B goes back a page first')
for _ = 1, 10 do sc:update() end
pressed.b = true; sc:update()
for _ = 1, 10 do sc:update() end
check(popped == 1, 'then B on the first page closes')

-- ---------------------------------------------------------- the wiring --
local IE = require('src.inventory.ItemEffects')
check(src('src/inventory/ItemEffects.lua'):find('fieldUseFunc == 5', 1, true)
  and src('src/ui/BagMenu.lua'):find('result == "journal"', 1, true), 'the Journal key item opens it')
check(src('src/core/Game.lua'):find('J.openOnContinue(loaded)', 1, true), 'Continue opens it after two days')
check(src('src/script/Gen4ScriptVM.lua'):find('g4_give_journal', 1, true)
  and src('src/script/Gen4ScriptVM.lua'):find('g4_journal_event', 1, true), 'givejournal and createjournalevent are lowered')
check(src('src/core/Data.lua'):find('"gen4_journal_art"', 1, true), 'Data loads gen4_journal_art')
local _ = IE

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
