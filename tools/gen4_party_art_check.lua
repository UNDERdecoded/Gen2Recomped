-- tools/gen4_party_art_check.lua -- Platinum's party screen, the parts that
-- are not pictures: the cursor's navigation table, the submenu's order and its
-- touch rows, the CANCEL button's rectangle, and (given a cache) that the
-- importer's `gen4_party_art` / `gen4_party_ink` carry every key the screen
-- draws.
--
--   python tools/run_lua_check.py tools/gen4_party_art_check.lua [cache dir]

local cacheDir = arg and arg[1]
package.path = "./?.lua;" .. package.path

package.loaded['src.render.Font'] = {}
package.loaded['src.core.Logger'] = { warn = function() end }
package.loaded['src.core.Strings'] = function(s, ...) if select('#', ...) > 0 then return s:format(...) end return s end
package.loaded['src.render.Renderer'] = { uiPresentation = { x = 0, y = 0, w = 256, h = 192, scaleX = 1, scaleY = 1 } }
package.loaded['src.render.Assets'] = { image = function() return nil end }
package.loaded['src.ui.Theme'] = { cursor = 0 }

local PASS, FAIL = 0, 0
local function check(cond, what)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print("FAIL: " .. what) end
end

local Party = require('src.ui.Gen4PartyMenu')
local function game(n, moves)
  local party = {}
  for i = 1, n do party[i] = { species = 387, level = 5, hp = 10, stats = { hp = 10 }, moves = moves or {} } end
  return { data = { pokemon = { [387] = { name = 'TURTWIG' } } }, save = { party = party },
           stack = { pop = function() end, push = function() end } }
end

-- navigation: the cartridge's Basic table, empty slots skipped
do
  local s = Party.new(game(6))
  local function go(from, dir) s.index = from; s:step(dir); return s.index end
  check(go(1, 'right') == 2 and go(1, 'down') == 3 and go(1, 'up') == 7 and go(1, 'left') == 7, 'lead moves')
  check(go(2, 'left') == 1 and go(2, 'right') == 3 and go(2, 'down') == 4, 'slot 2 moves')
  check(go(5, 'down') == 7 and go(6, 'right') == 7 and go(6, 'down') == 7, 'bottom row reaches CANCEL')
  check(go(7, 'up') == 6 and go(7, 'down') == 2 and go(7, 'right') == 1 and go(7, 'left') == 6, 'CANCEL moves')
  local short = Party.new(game(3))
  short.index = 4; short:step('up')
  check(short.index == 2, 'CANCEL up skips empty slots 6 and 4 to slot 2 (got ' .. short.index .. ')')
  short.index = 3; short:step('right')
  check(short.index == 4, 'an empty slot to the right is passed to CANCEL (index 4 on a party of 3)')
end

-- the submenu: SUMMARY, field moves in move-slot order, SWITCH, ITEM, CANCEL
do
  package.loaded['src.import.Gen4Weather'] = { nameFor = function() return nil end }
  local s = Party.new(game(1, { { id = 91 }, { id = 57 }, { id = 15 }, { id = 33 } }))
  local a = s:actions()
  check(table.concat(a, ',') == 'summary,field:DIG,field:SURF,field:CUT,switch,item,cancel',
        'field moves in move-slot order: ' .. table.concat(a, ','))
  local egg = Party.new(game(1, { { id = 57 } }))
  egg:party()[1].isEgg = true
  check(table.concat(egg:actions(), ',') == 'summary,switch,cancel', 'an egg: SUMMARY, SWITCH, CANCEL')
  -- the touch rows: 16 apart, ending at y 184, frame x 144..255
  s.index = 1; s.submenu = 1
  local m = s:menuRect(#a)
  check(m.firstRow == 184 - 16 * #a and m.x == 144 and m.w == 112, 'submenu rows end at y 184')
  local hit
  s.runAction = function(_, act) hit = act end
  s:touchpressed(1, 200, m.firstRow + 16 + 4)
  check(hit == 'field:DIG', 'the second touch row is the second action')
end

-- CANCEL: the 56 x 32 button around (232, 176)
do
  local s = Party.new(game(2))
  local closed = false
  s.close = function() closed = true end
  s:touchpressed(1, 205, 165)
  check(closed and s.index == 3, 'a touch on the CANCEL button closes')
  closed = false; s.index = 1
  s:touchpressed(1, 190, 170)
  check(not closed, 'x 190 is left of the button')
end

-- the cache
if cacheDir then
  local okA, art = pcall(dofile, cacheDir .. '/gen4_party_art.lua')
  local okI, ink = pcall(dofile, cacheDir .. '/gen4_party_ink.lua')
  check(okA and type(art) == 'table', 'gen4_party_art is in the cache (tools/gen4_art_extract ... party)')
  check(okI and type(ink) == 'table' and ink.text and ink.hpGreen, 'gen4_party_ink is in the cache')
  if okA and type(art) == 'table' then
    local want = { 'panel_none', 'digits', 'ball_0', 'ball_1', 'button_0', 'button_1', 'held_item', 'held_mail', 'held_seal' }
    for _, v in ipairs({ 0, 2, 4, 6, 7 }) do
      for _, k in ipairs({ 'panel_lead_', 'panel_back_', 'panel_lead_egg_', 'panel_back_egg_' }) do want[#want + 1] = k .. v end
    end
    for seq = 0, 3 do for r = 0, 1 do want[#want + 1] = ('cursor_%d_%d'):format(seq, r) end end
    for n = 0, 6 do want[#want + 1] = 'status_' .. n end
    local missing = {}
    for _, k in ipairs(want) do if not art[k] then missing[#missing + 1] = k end end
    check(#missing == 0, 'party art keys missing: ' .. table.concat(missing, ' '))
    local p = art.panel_lead_0
    check(p and p.width == 128 and p.height == 48, 'a panel is 128 x 48')
    check(art.digits and art.digits.width == 104 and art.digits.height == 8, 'the digits strip is 13 glyphs of 8')
    local c = art.cursor_1_0
    check(c and c.width == 128 and c.height == 48 and c.originX == -64 and c.originY == -24, 'the cursor is 128 x 48 from (-64, -24)')
    local b = art.button_0
    check(b and b.width == 56 and b.height == 32, 'the CANCEL button is 56 x 32')
    check(art.subscreen == nil, 'no `subscreen` key (it would overwrite gen4_graphics party/subscreen.png)')
  end
  if okI and type(ink) == 'table' and ink.hpGreen then
    local g = ink.hpGreen[1]
    check(g[1] < 110 and g[2] == 255 and g[3] < 110, 'the HP bar green is menu.NCLR row 3 colour 9')
  end
else
  print('-- no cache dir given: the cache section was skipped')
end

-- EVERY KNOWN FIELD MOVE IS LISTED (GetContextMenuEntriesForPartyMon), badge
-- or weather notwithstanding; the check answers at the press
do
  local s = Party.new(game(1, { { id = 70 }, { id = 249 }, { id = 148 }, { id = 135 } }))
  check(table.concat(s:actions(), ',') == 'summary,field:STRENGTH,field:ROCK_SMASH,field:FLASH,field:SOFTBOILED,switch,item,cancel',
        'Strength, Rock Smash, Flash and Softboiled listed: ' .. table.concat(s:actions(), ','))
end

-- refusals print the party menu's own lines
do
  local pushed = {}
  local g = game(2, { { id = 70 } })
  g.stack.push = function(_, box) pushed[#pushed + 1] = box end
  package.loaded['src.render.TextBox'] = { new = function(_, text) return { text = text } end }
  g.data.text = {}
  local T = require('src.import.Gen4Text')
  g.data.text[T.label(453, 76)] = 'BADGE LINE'
  g.data.text[T.label(453, 104)] = 'HERE LINE'
  g.data.text[T.label(453, 138)] = 'HP LINE'
  g.overworld = { player = { facingCell = function() return 0, 0 end, surfing = false }, npcAtCell = function() return nil end }
  g.save.badges = {}
  local s = Party.new(g)
  s:useFieldMove(g.save.party[1], 'STRENGTH')
  check(pushed[1] and pushed[1].text == 'BADGE LINE', 'Strength without the Mine Badge: the badge line')
  -- Softboiled: a fifth of max HP, refused when HP is no more than that
  local mon = g.save.party[1]
  mon.hp, mon.stats.hp = 2, 10
  s:useFieldMove(mon, 'SOFTBOILED')
  check(pushed[2] and pushed[2].text == 'HP LINE', 'Softboiled at 2/10 HP: "Not enough HP..."')
  mon.hp = 10
  local other = g.save.party[2]
  other.hp = 4
  s.index = 1
  s:useFieldMove(mon, 'SOFTBOILED')
  check(s.hpTransfer and s.hpTransfer.amount == 2, 'Softboiled gives max HP / 5 = 2')
  s.index = 2
  s:choose()
  check(mon.hp == 8 and other.hp == 6 and not s.hpTransfer, 'the transfer moved 2 HP: ' .. mon.hp .. ' / ' .. other.hp)
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
