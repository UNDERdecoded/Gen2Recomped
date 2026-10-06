-- Run:  texlua tools/gen4_screen_art_check.lua <cache dir> [<asset root>]
--
-- THE CARTRIDGE'S ART FOR THE OPTIONS SCREEN, GROUP COOKING, THE DANCE PAD AND
-- THE CREDITS' 3D: each picture the screens ask for is in the cache's index,
-- and (with the asset root) on disk.
--
--   options   config_gra: the backdrop (tile 1) and the cursor bar
--   poffin    nutmixer: the four cooks' plates (player_name.NSCR)
--   contest   contest_bg 18 + 16: the pad, and each button's three press frames
--   ending    ending.narc: the seven props' models, every shape's texture

package.path = './?.lua;./?/init.lua;' .. package.path
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local root = arg and arg[2] and arg[2]:gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function onDisk(path)
  if not root then return true end
  local f = io.open(root .. '/' .. path, 'rb')
  if f then f:close() return true end
  return false
end

local options = load('gen4_options_art')
check(options and options.options_bg and options.options_cursor, 'gen4_options_art: options_bg and options_cursor')
if options and options.options_cursor then
  check(options.options_cursor.width == 256 and options.options_cursor.height == 16, 'the cursor is 32 x 2 tiles')
  check(onDisk(options.options_cursor.path), 'the cursor picture is on disk')
end

local poffin = load('gen4_poffin_art') or {}
local plates = true
for col = 0, 1 do for row = 0, 1 do
  local p = poffin[('cook_plate_%d_%d'):format(col, row)]
  if not (p and p.width == 80 and p.height == 32 and onDisk(p.path)) then plates = false end
end end
check(plates, 'four 10 x 4-tile cook plates')
check(poffin.cook_top_multi ~= nil, 'the group\'s top screen')

local contest = load('gen4_contest_art') or {}
local press = true
for move = 1, 4 do for f = 0, 2 do
  local p = contest[('dance_pad_%d_%d'):format(move, f)]
  if not (p and onDisk(p.path)) then press = false end
end end
check(contest.dance_pad and press, 'the dance pad and its twelve press frames')

local ending = load('gen4_ending') or {}
local models = ending.models or {}
local names = { 'background_morning_tree_1', 'background_morning_tree_2', 'background_day_lamppost',
  'background_night_tree_1_normal', 'background_night_tree_1_snowy', 'background_night_tree_2',
  'background_night_lamppost' }
local all, textured = true, true
for _, n in ipairs(names) do
  local m = models[n]
  if not (m and m.shapes and #m.shapes > 0) then all = false
  else
    for _, s in ipairs(m.shapes) do
      if s.texture and not (s.image and onDisk(s.image)) then textured = false end
    end
  end
end
check(all, 'the credits\' seven prop models')
check(textured, 'every textured shape has its picture')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
