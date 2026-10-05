-- Run:  texlua tools/gen4_encounter_effects_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_encounter_effects.lua` -- the battle transitions' pictures
-- (src/import/Gen4EncounterEffects.lua) -- into an EXISTING Platinum cache,
-- so it gains them without a re-import.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_encounter_effects_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local NdsRom = require('src.import.NdsRom')
local E = require('src.import.Gen4EncounterEffects')
local LuaWriter = require('src.import.LuaWriter')

local rom = assert(NdsRom.open(romPath))
local out = assert(E.extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_encounter_effects.lua', 'wb'))
f:write(LuaWriter.encode(out))
f:close()
local n, p = 0, 0
for k, list in pairs(out.images) do
  for i, im in pairs(list) do
    n = n + 1
    local maxi = 0
    for h in im.idx:gmatch('..') do local v = tonumber(h, 16) if v > maxi then maxi = v end end
    print(('%-28s cell %d  %dx%d at %d,%d  max index %d'):format(k, i - 1, im.w, im.h, im.x, im.y, maxi))
  end
end
for _ in pairs(out.palettes) do p = p + 1 end
print(('wrote %s/gen4_encounter_effects.lua: %d images, %d palettes'):format(cacheDir, n, p))
