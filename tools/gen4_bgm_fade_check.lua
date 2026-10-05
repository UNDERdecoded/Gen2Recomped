-- Run:  texlua tools/gen4_bgm_fade_check.lua <cache dir>
--
-- PLATINUM'S BGM FADES AND FIELD-PLAYER VOLUME (src/core/Music.lua's DS
-- levels and `fadeoutbgm` / `fadeinbgm` / `setplayervolume`), per
-- scrcmd_sound.c, sound_playback.c and field_bgm.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end

local Music = require('src.core.Music')
local data = {}
local function tick(n) for _ = 1, n do Music.update(data) end end

Music.dsFade(0, 10)
check(Music.dsFading(), 'fadeoutbgm 0 10: fading')
tick(5)
local level = Music.dsLevels()
check(math.abs(level - 0.5) < 1e-9, 'halfway after 5 frames: ' .. level)
tick(5)
level = Music.dsLevels()
check(level == 0 and not Music.dsFading(), 'silent and finished after 10')
Music.playMap(data, nil)
check(Music.dsLevels() == 1, 'a map change starts its BGM at full level again')

Music.setPlayerLevel(0)
local _, player = Music.dsLevels()
check(player == 0, 'setplayervolume 0')
Music.dsFade(1, 10, 0)
check(Music.dsLevels() == 0 and Music.dsFading(), 'fadeinbgm starts from zero')
tick(10)
level, player = Music.dsLevels()
check(level == 1 and player == 0, 'the fade-in ends at full; the player volume is separate')
Music.setPlayerLevel(1)

-- the commands wait for the fade, and the scripts lower
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local yielded, check_
local runner = { yield = function(self) yielded = true; check_ = self.waitingCheck end }
C.g4_fade_out_bgm({ runner = runner, save = { gen4Vars = {} } }, 0, 20)
check(yielded and check_ and check_() == false, 'fadeoutbgm waits while the fade runs')
tick(20)
check(check_() == true, '...and resumes when it is done')
C.g4_set_player_volume({ save = { gen4Vars = {} } }, 127)
check(select(2, Music.dsLevels()) == 1, 'setplayervolume 127: full')

local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = load('text') }
local bad, seen = {}, 0
for label in pairs(sdata.map_scripts.scripts) do
  for _, row in ipairs(VM.compile(sdata, label) or {}) do
    if row[1] == 'g4_fade_out_bgm' or row[1] == 'g4_fade_in_bgm' or row[1] == 'g4_set_player_volume' then seen = seen + 1 end
    if row[1] == 'g4_noop' and tostring(row[2]):find('BGM fade') then bad[#bad + 1] = label end
  end
end
check(#bad == 0 and seen > 0, ('every fade lowers for real (%d rows, %d left as no-ops)'):format(seen, #bad))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
