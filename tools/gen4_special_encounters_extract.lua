-- Run:  texlua tools/gen4_special_encounters_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_special_encounters.lua` -- the Trophy Garden and Great Marsh
-- daily lists (src/import/Gen4SpecialEncounters.lua) -- into an EXISTING
-- Platinum cache, so it gains them without a re-import.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_special_encounters_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4SpecialEncounters').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_special_encounters.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
print(('wrote %s/gen4_special_encounters.lua: trophy garden %s; marsh %d/%d; %d lookout spots')
  :format(cacheDir, table.concat(out.trophyGarden, ','), #out.greatMarsh.natdex,
          #out.greatMarsh.regional, #out.lookoutCoords))
