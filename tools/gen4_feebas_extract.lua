-- Run:  texlua tools/gen4_feebas_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_feebas.lua` into an EXISTING Platinum cache, so Feebas can be
-- fished without re-importing the whole ROM. A fresh import writes the same
-- file through `RomExtractorGen4:feebas`; this is the same parser and the same
-- serialiser, for a cache made before that stage existed. It only ever adds
-- that one file.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_feebas_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local NdsRom = require('src.import.NdsRom')
local Narc = require('src.import.NarcArchive')
local Gen4Feebas = require('src.import.Gen4Feebas')
local LuaWriter = require('src.import.LuaWriter')

local rom = assert(NdsRom.open(romPath))
local arc = assert(Narc.parse(assert(rom:read(Gen4Feebas.PATH))))
local out = assert(Gen4Feebas.parse(arc:get(0), arc:get(1)))
local f = assert(io.open(cacheDir .. '/gen4_feebas.lua', 'wb'))
f:write(LuaWriter.encode(out))
f:close()
print(('wrote %s/gen4_feebas.lua: species %d, %d tiles'):format(cacheDir, out.species, #out.tiles))
