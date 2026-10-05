-- Run:  texlua tools/gen4_battle_menu_check.lua <cache dir>
--
-- PLATINUM'S MOVE BUTTONS AND MENU LABELS, on both presentations.
--
-- Requested from play: move the single-screen strip's move tiles to the bottom
-- of the screen with their PP and everything else the real buttons carry, and
-- make the bottom screen's battle menu match the ROM. What the cartridge puts
-- on a move button (`BattleSubscreen_DrawMoveSelectMenu`): its move's TYPE
-- colours from overlay 11's `sMovePaletteTable`, the name, a type icon, "PP"
-- and "cur/max" in a `GetPPTextColor` colour; the action menu's four labels
-- in their own colour trios; CANCEL on the move menu's bar.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_battle_menu_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

-- ============================ 1. the cartridge's data is in the cache
local f = loadfile(cacheDir .. '/gen4_move_buttons.lua')
local rec = f and f()
check(rec, 'the cache must carry gen4_move_buttons '
      .. '(run tools/gen4_move_buttons_extract.lua on an older cache)')
if rec then
  local n = 0
  for t = 0, 17 do if rec.types[t] and #rec.types[t] == 16 then n = n + 1 end end
  check(n == 18, 'eighteen 16-colour type palettes, got ' .. n)
  -- Spot values straight off src/overlay011/move_palettes.c, RGB555 -> 8-bit.
  local function is(c, r, g, b)
    local x = function(v) return math.floor(v * 255 / 31 + 0.5) end
    return c and c[1] == x(r) and c[2] == x(g) and c[3] == x(b)
  end
  check(is(rec.types[10][3], 31, 17, 14), 'Fire entry 2 is RGB(31,17,14)')
  check(is(rec.types[1][3], 31, 22, 14), 'Fighting entry 2 is RGB(31,22,14)')
  check(is(rec.types[2][3], 15, 21, 31), 'Flying entry 2 is RGB(15,21,31) -- '
        .. 'read through the pointer table, the palettes are not in type order')
  for i = 1, 4 do
    local m = rec.masks[i]
    check(m and #m.index == m.w * m.h and m.w == 124 and m.h == 55,
          'button ' .. i .. ' carries a 124x55 mask')
  end
  check(rec.text and #rec.text.pp == 16 and #rec.text.name == 16 and #rec.text.action == 16,
        'and the three text palettes (OBJ 2, 3, 4)')
end
local dsrc = io.open('src/core/Data.lua'):read('a')
check(dsrc:match('local GEN4_PREFIXED = (%b{})'):find('"gen4_move_buttons"', 1, true),
      'Data.lua must load it')

-- ============================ 2. GetPPTextColor
local MB = require('src.import.Gen4MoveButtons')
local function c(cur, max) local a = MB.ppColour(cur, max) return a end
check(c(0, 35) == 7, '0 PP is the empty colour')
check(c(35, 35) == 1, 'full PP the ordinary one')
check(c(8, 35) == 5 and c(17, 35) == 3 and c(18, 35) == 1,
      'a quarter or less, a half or less, and above')
check(c(1, 5) == 5 and c(2, 5) == 3 and c(3, 5) == 1,
      'max 3..7: 1 and 2 are the low colours, by count not by fraction')
check(c(1, 2) == 5, 'max 2: 1 is the lowest')

-- ============================ 3. the strip: on the bottom, clear of the HUD
local B = require('src.battle.Gen4Battle')
check(B.MOVE_STRIP.y == 136 and B.MOVE_STRIP.y + B.MOVE_STRIP.h == 192,
      'the move tiles run from the healthbox plaque\'s end (136) to the bottom')
for i = 1, 4 do
  local x, y, w, h = B.compactMoveRect(i)
  check(y >= 136 and y + h <= 192 and w >= 120, 'tile ' .. i .. ' inside the strip')
end
local bsrc = io.open('src/battle/Gen4Battle.lua'):read('a')
check(bsrc:find('Gen4Battle.drawMoveFace(battle, i, colX, y, y + h - 14, true)', 1, true),
      'each tile carries the face: name, type icon and PP -- the last two shrunk to fit')
check(B.SMALL_INFO_SCALE and B.SMALL_INFO_SCALE < 1, 'the strip draws its info row smaller')
check(select(2, bsrc:gsub('if not moveButtons%(battle%) then Gen4Battle.drawMoveDetail', '')) == 2,
      'and the box no longer repeats TYPE/PP once the buttons carry it')

-- ============================ 4. the bottom screen
check(bsrc:find('Gen4Battle.drawMoveFace(battle, i, col * 128, 38 + row * 64, 54 + row * 64)', 1, true),
      'the bottom screen places the face where the cartridge does')
local spots = B.ACTION_LABEL_SPOTS
check(spots and spots[1].x == 128 and spots[1].y == 84 and spots[2].x == 40
      and spots[3].x == 216 and spots[4].y == 178,
      'the action labels sit at the cartridge\'s font OAM positions')
check(B.CANCEL_LABEL_SPOT and B.CANCEL_LABEL_SPOT.y == 178, 'and CANCEL on its bar')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
