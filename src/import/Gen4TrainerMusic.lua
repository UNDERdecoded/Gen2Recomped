-- PLATINUM'S TRAINER EYES-MEET THEMES (pokeplatinum src/field_bgm.c,
-- sTrainerEncounterBGMs and FieldBGM_GetEyesMeetForTrainer).
--
-- An ARM9 table of { u16 trainer class, u16 sequence } rows, found by content
-- -- Aroma Lady (class 7) -> SEQ_EYE_LADY (1104), Ruin Maniac (48) ->
-- SEQ_EYE_MOUNT (1105) -- and read until a row stops being a class and an
-- eyes-meet sequence. A class the table does not name gets SEQ_EYE_KID.
--
-- The cartridge plays it from `playtrainerencounterbgm <trainer>`, the first
-- row of the common trainer-encounter script (M1114), which every sighted
-- trainer runs.
--
-- Written to the cache module `gen4_trainer_music` as { byClass = {...} }.

local Gen4TrainerMusic = {}

Gen4TrainerMusic.SIGNATURE = string.char(7, 0, 0x50, 4, 48, 0, 0x51, 4)
Gen4TrainerMusic.FIRST_EYE, Gen4TrainerMusic.LAST_EYE = 1100, 1114

function Gen4TrainerMusic.parse(arm9)
  if type(arm9) ~= "string" then return nil, "no arm9" end
  local at = arm9:find(Gen4TrainerMusic.SIGNATURE, 1, true)
  if not at then return nil, "sTrainerEncounterBGMs not found" end
  local byClass, rows = {}, 0
  while true do
    local o = at + rows * 4
    local c1, c2, s1, s2 = arm9:byte(o, o + 3)
    if not s2 then break end
    local class, seq = c1 + c2 * 256, s1 + s2 * 256
    if class > 255 or seq < Gen4TrainerMusic.FIRST_EYE or seq > Gen4TrainerMusic.LAST_EYE then break end
    if byClass[class] == nil then byClass[class] = seq end
    rows = rows + 1
  end
  return { byClass = byClass, rows = rows }
end

function Gen4TrainerMusic.extract(rom)
  return Gen4TrainerMusic.parse(rom and rom:arm9())
end

-- FieldBGM_GetEyesMeetForTrainer: the class's theme, else SEQ_EYE_KID.
function Gen4TrainerMusic.forClass(data, class)
  local rec = data and data.gen4_trainer_music
  local seq = rec and rec.byClass and rec.byClass[tonumber(class)]
  if seq then return seq end
  local songs = data and data.audio and data.audio.songs
  local kid = songs and songs.SEQ_EYE_KID
  return kid and kid.nds or nil
end

function Gen4TrainerMusic.forTrainer(data, trainerId)
  local t = data and data.trainers and data.trainers[tonumber(trainerId)]
  if not t then return Gen4TrainerMusic.forClass(data, nil) end
  return Gen4TrainerMusic.forClass(data, t.class)
end

return Gen4TrainerMusic
