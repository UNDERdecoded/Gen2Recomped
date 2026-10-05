-- Run:  texlua tools/gen4_contest_art_check.lua <platinum .nds> [<cache dir>]
--
-- THE SUPER CONTEST'S ART (src/import/Gen4ContestArt.lua), composed from the
-- ROM: every picture is there at the cartridge's size, the backdrops are
-- solid, the podiums take their explicit palette rows, the move buttons take
-- their types' colours. With a cache dir, the index must name them all too.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end

local rom = assert(require('src.import.NdsRom').open(arg[1]))
local Art = require('src.import.Gen4ContestArt')
local out = assert(Art.images(rom))

local SIZES = {
  acting_stage = { 512, 256 }, acting_stage_alt = { 512, 256 }, acting_window = { 256, 256 },
  acting_panel_6 = { 80, 48 }, acting_panel_7 = { 80, 48 }, acting_panel_10 = { 80, 48 }, acting_panel_11 = { 80, 48 },
  sub_hearts = { 256, 256 }, sub_judges = { 256, 256 }, sub_moves_off = { 256, 256 },
  visual_stage = { 256, 256 }, visual_curtain = { 256, 256 }, audience = { 256, 256 },
  results_bg = { 256, 256 }, results_bars = { 256, 256 },
  judge_0 = { 32, 32 }, judge_1 = { 32, 32 }, judge_2 = { 32, 32 },
  podium_0 = { 32, 64 }, podium_1 = { 32, 64 }, podium_2 = { 32, 64 },
  voltage_star = { 8, 8 }, head_heart = { 16, 16 }, sub_heart = { 8, 8 }, sub_head_mark = { 32, 32 },
}
for t = 0, 4 do SIZES['sub_logo_' .. t] = { 256, 256 }; SIZES['sub_moves_' .. t] = { 256, 256 } end
for n = 1, 4 do SIZES['next_' .. n] = { 32, 16 } end
for n = 0, 3 do SIZES['reaction_' .. n] = { 16, 16 }; SIZES['small_heart_' .. n] = { 8, 8 } end
local count = 0
for key, size in pairs(SIZES) do
  local pic = out[key]
  count = count + 1
  check(pic and pic.width == size[1] and pic.height == size[2],
    ('%s is %dx%d (%s)'):format(key, size[1], size[2], pic and (pic.width .. 'x' .. pic.height) or 'missing'))
end

local function pixel(pic, x, y)
  local at = (y * pic.width + x) * 4
  return pic.rgba:byte(at + 1), pic.rgba:byte(at + 2), pic.rgba:byte(at + 3), pic.rgba:byte(at + 4)
end
local function transparent(pic)
  local n = 0
  for p = 0, pic.width * pic.height - 1 do if pic.rgba:byte(p * 4 + 4) == 0 then n = n + 1 end end
  return n
end
local function colours(pic)
  local seen, n = {}, 0
  for p = 0, pic.width * pic.height - 1 do
    local at = p * 4
    if pic.rgba:byte(at + 4) ~= 0 then
      local k = pic.rgba:sub(at + 1, at + 3)
      if not seen[k] then seen[k] = true; n = n + 1 end
    end
  end
  return n, seen
end

-- the backdrop (BG palette entry 0) fills what no layer covers
for _, key in ipairs({ 'acting_stage', 'sub_hearts', 'visual_stage', 'audience', 'results_bg', 'sub_logo_0' }) do
  check(out[key] and transparent(out[key]) == 0, key .. ' has no transparent pixel once its backdrop is under it')
end
-- explicit sprite palettes: podiums 1 and 2 are rows 4 and 5, not black
for k = 0, 2 do
  local n = colours(out['podium_' .. k])
  check(n >= 6, ('podium_%d is drawn in colour (%d colours)'):format(k, n))
end
-- the move buttons in their types' colours (Unk_ov17_022534B8), the greyed one apart
local function centre(key) return string.char(pixel(out[key], 64, 48)) end
local seen = {}
for t = 0, 4 do seen[centre('sub_moves_' .. t)] = true end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
check(distinct == 5, 'five types, five button colours (' .. distinct .. ')')
check(not seen[centre('sub_moves_off')], 'the unusable button is none of them')
local r, g, b = pixel(out.sub_moves_0, 64, 48)
check(r > 200 and g < 100 and b < 100, ('Cool buttons are red (%d,%d,%d)'):format(r, g, b))
r, g, b = pixel(out.sub_moves_4, 64, 48)
check(r > 200 and g > 180 and b < 120, ('Tough buttons are yellow (%d,%d,%d)'):format(r, g, b))
-- results board: the bar track is 192 pixels from x 48, rows every 32 from y 8
local dark = 0
for x = 0, 255 do
  local rr, gg, bb = pixel(out.results_bg, x, 30)
  if rr == 41 and gg == 41 and bb == 41 then dark = dark + 1 end
end
check(dark == 192, 'the results board\'s first bar track is 192 pixels (' .. dark .. ')')

local dir = arg[2] and arg[2]:gsub('[/\\]$', '')
if dir then
  local f = loadfile(dir .. '/gen4_contest_art.lua')
  local index = f and f()
  check(index, 'the cache carries gen4_contest_art (run tools/gen4_contest_art_extract)')
  if index then
    for key in pairs(SIZES) do check(index[key] and index[key].path, 'the index names ' .. key) end
    check(index.podium_0 and index.podium_0.originX == -16 and index.podium_0.originY == -32, 'sprites keep their origin')
  end
end

print(('%d checks, %d failed (%d pictures)'):format(PASS + FAIL, FAIL, count))
if FAIL > 0 then os.exit(1) end
