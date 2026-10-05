-- Run:  texlua tools/gen4_emote_check.lua <cache dir>
--
-- THE "!" OVER A TRAINER WHO HAS SEEN YOU. Reported from play: *"were missing
-- the proper exclamation point above trainers when they see you for battle and
-- its not above their heads"*. Platinum fell through to a hand-drawn box placed
-- with flat 2D arithmetic. See src/import/Gen4Emotes.lua for the cartridge.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_emote_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

-- ============================ 1. the cartridge's art is in the cache
local f = loadfile(cacheDir .. '/gen4_emotes.lua')
local emotes = f and f()
check(emotes and emotes.exclamation, 'the cache must carry gen4_emotes '
      .. '(run tools/gen4_emotes_extract.lua on an older cache)')
if emotes and emotes.exclamation then
  local e = emotes.exclamation
  check(e.texture == 'sisen_ef' and e.width == 16 and e.height == 16
        and #e.rgba == 16 * 16 * 4, '"!" is fldeff 85\'s 16x16 sisen_ef')
  check(emotes.double and emotes.double.texture == 'saisen_ef', '"!!" is saisen_ef')
  -- The mark is red on white: count the red texels down the centre columns.
  local red = 0
  for y = 0, 15 do for x = 7, 8 do
    local i = (y * 16 + x) * 4
    local r, g, b, a = e.rgba:byte(i + 1, i + 4)
    if a > 0 and r > 180 and g < 120 and b < 120 then red = red + 1 end
  end end
  check(red >= 8, 'and its centre carries the red mark, got ' .. red .. ' red texels')
end
local dsrc = io.open('src/core/Data.lua'):read('a')
check(dsrc:match('local GEN4_PREFIXED = (%b{})'):find('"gen4_emotes"', 1, true),
      'Data.lua must load gen4_emotes')

-- ============================ 2. the cartridge's motion
local E = require('src.import.Gen4Emotes')
local seq = {}
for age = 1, 8 do seq[#seq + 1] = E.bounce(age) end
check(table.concat(seq, ',') == '6,10,12,12,10,6,0,0',
      'the bounce is velocity 6 less 2 a frame: got ' .. table.concat(seq, ','))
check(E.FRAMES == 37, 'seven frames of bounce and thirty of hold')

-- ============================ 3. on top of the head, centred
local OW = require('src.world.OverworldController')
local ground = { scale = function() return 0.858 end,
                 rise = function(_, x, y) return 10 end }
local sprite = { tileW = 16, tileH = 32, offsetX = 0, offsetY = 16, cellYBias = -4 }
local npc = { sprite = sprite, px = 96, py = 208, shiftPx = 0 }
local cam = { x = 0, y = 100 }
local record = { width = 16, height = 16 }
local bx, by, rise = OW.gen4EmoteSpot(ground, npc, cam, record, 20)
-- The sprite's own top, by SpriteRenderer:draw's arithmetic.
local top = math.floor(npc.py - (cam.y + rise)) + sprite.cellYBias - sprite.offsetY
local left = math.floor(npc.px - cam.x) - sprite.offsetX
check(by + 16 == top, ('the bubble\'s bottom must be the sprite\'s top: %d vs %d')
      :format(by + 16, top))
check(bx == left, 'and centred on a 16-wide sprite')
local _, high = OW.gen4EmoteSpot(ground, npc, cam, record, 3)
check(by - high == 12, 'rising 12 at the top of the bounce')
check(rise == 10 + (npc.py - cam.y) * (1 - 0.858),
      'with the same terrain rise the sprite is drawn with')

-- ============================ 4. "!!" and the scripted emote
local cmd = io.open('src/script/Gen4Commands.lua'):read('a')
check(cmd:find('(action.emote == "double_exclamation") and "double"', 1, true),
      'EMOTE_DOUBLE_EXCLAMATION_MARK must draw the "!!"')
check(cmd:find('frames = Gen4Emotes.FRAMES', 1, true), 'on the cartridge\'s timing')

-- ============================ 5. the free-camera modes
--
-- Reported from play: *"in tilted camera modes, first and third person mode im
-- not seeing the ! icon appear"*. Two faults, both measured in a render of
-- Route 202: the bubble was drawn after the 3D pass had been closed, and once
-- moved inside it, it was depth-tested at its trainer's FEET and lost to the
-- treetops behind him.
local ow = io.open('src/world/OverworldController.lua'):read('a')
local early = ow:find('if freeGround then\n      self:eachEmote(fxEmote)', 1, true)
  or ow:find('if freeGround then\r\n      self:eachEmote(fxEmote)', 1, true)
local canopy = ow:find('self.map.renderer:drawAbove(cam.x, bgY, vw, vh)', 1, true)
check(early and canopy and early < canopy,
      'with a free camera the "!" must be drawn before drawAbove closes the 3D pass')
check(ow:find('if not emoteEarly then self:eachEmote(fxEmote) end', 1, true),
      'and not drawn a second time after it')
check(ow:find('Gen4Emotes.LIFT + 8)', 1, true),
      'and depth-tested at the bubble\'s own height, not its trainer\'s feet')
local gsrc = io.open('src/render/Gen4Ground.lua'):read('a')
check(gsrc:find('function Gen4Ground:freeEntity(mapX, mapY, camX, camY, rise, draw, depthLift)', 1, true),
      'freeEntity must take that depth lift')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
