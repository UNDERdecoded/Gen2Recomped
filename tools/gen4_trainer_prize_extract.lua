-- Run:  texlua tools/gen4_trainer_prize_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_trainer_prize.lua` -- each trainer class's prize multiplier from
-- overlay 16 (src/import/Gen4TrainerPrize.lua) -- into an EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_trainer_prize_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4TrainerPrize').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_trainer_prize.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
print(('wrote %s/gen4_trainer_prize.lua: Youngster %d, Ace Trainer %d, Cynthia (69) %d, Gym Leader? class 63 %d')
  :format(cacheDir, out.byClass[2], out.byClass[26], out.byClass[69], out.byClass[63]))
