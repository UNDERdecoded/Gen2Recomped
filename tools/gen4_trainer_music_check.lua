-- Run:  texlua tools/gen4_trainer_music_check.lua <cache dir>
--
-- PLATINUM'S TRAINER EYES-MEET THEMES (src/import/Gen4TrainerMusic.lua and
-- `playtrainerencounterbgm`), per field_bgm.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_trainer_music')
check(rec, 'the cache must carry gen4_trainer_music (run tools/gen4_trainer_music_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end
local audio, trainers = load('audio'), load('trainers')
local data = { gen4_trainer_music = rec, audio = audio, trainers = trainers }
local M = require('src.import.Gen4TrainerMusic')
local function song(name) return audio.songs[name].nds end

check(rec.rows == 79, 'all 79 rows of sTrainerEncounterBGMs')
check(M.forClass(data, 7) == song('SEQ_EYE_LADY'), 'Aroma Lady: SEQ_EYE_LADY')
check(M.forClass(data, 69) == song('SEQ_EYE_CHAMP'), 'Cynthia: SEQ_EYE_CHAMP')
check(M.forClass(data, 73) == song('SEQ_EYE_GINGA'), 'Galactic Grunt: SEQ_EYE_GINGA')
check(M.forClass(data, 98) == song('SEQ_EYE_FUN'), 'Maid: SEQ_EYE_FUN')
check(M.forClass(data, 0) == song('SEQ_EYE_KID'), 'a class the table does not name: SEQ_EYE_KID')

-- every trainer in the cache resolves to an eyes-meet sequence
local bad = 0
for id, t in pairs(trainers) do
  if type(id) == 'number' and type(t) == 'table' then
    local s = M.forTrainer(data, id)
    if not (s and s >= 1100 and s <= 1114) then bad = bad + 1 end
  end
end
check(bad == 0, 'every trainer has an eyes-meet theme (' .. bad .. ' without)')

-- the command plays it
local played
package.loaded['src.core.Music'] = { play = function(_, s) played = s end }
local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local cynthiaId
for id, t in pairs(trainers) do if type(t) == 'table' and t.class == 69 then cynthiaId = id break end end
local save = { gen4Vars = { [0x8004] = cynthiaId } }
C.g4_trainer_encounter_bgm({ game = { data = data }, save = save }, 0x8004)
check(played == song('SEQ_EYE_CHAMP'), 'playtrainerencounterbgm with Cynthia plays her theme')

-- the common encounter script lowers it
local VM = require('src.script.Gen4ScriptVM')
local rows = VM.compile({ constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = load('text') }, 'M1114/S0F02')
check(rows and rows[2] and rows[2][1] == 'g4_trainer_encounter_bgm' or (rows and rows[1] and rows[1][1] == 'g4_trainer_encounter_bgm')
      or (function() for _, r in ipairs(rows or {}) do if r[1] == 'g4_trainer_encounter_bgm' then return true end end end)(),
      'M1114/S0F02 opens with the encounter theme')
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
