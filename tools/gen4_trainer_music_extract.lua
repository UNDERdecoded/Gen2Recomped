-- Run:  texlua tools/gen4_trainer_music_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_trainer_music.lua` -- the trainer-class eyes-meet themes from
-- ARM9 (src/import/Gen4TrainerMusic.lua) -- into an EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_trainer_music_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4TrainerMusic').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_trainer_music.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
print(('wrote %s/gen4_trainer_music.lua: %d rows; Aroma Lady %s, Cynthia (class 92?) %s')
  :format(cacheDir, out.rows, tostring(out.byClass[7]), tostring(out.byClass[92])))
