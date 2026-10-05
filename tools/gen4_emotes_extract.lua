-- Run:  texlua tools/gen4_emotes_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_emotes.lua` -- the "!" and "!!" bubbles -- into an EXISTING
-- Platinum cache, so a cache made before `RomExtractorGen4:emotes` existed
-- gains them without a re-import. Same decoder, same serialiser; it only adds
-- that one file.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_emotes_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local NdsRom = require('src.import.NdsRom')
local Narc = require('src.import.NarcArchive')
local Gen4Emotes = require('src.import.Gen4Emotes')
local LuaWriter = require('src.import.LuaWriter')

local rom = assert(NdsRom.open(romPath))
local arc = assert(Narc.parse(assert(rom:read(Gen4Emotes.ARCHIVE))))
local out = assert(Gen4Emotes.extract(arc))
local f = assert(io.open(cacheDir .. '/gen4_emotes.lua', 'wb'))
f:write(LuaWriter.encode(out))
f:close()
print(('wrote %s/gen4_emotes.lua: "!" %dx%d (%s), "!!" %s'):format(cacheDir,
  out.exclamation.width, out.exclamation.height, tostring(out.exclamation.texture),
  out.double and tostring(out.double.texture) or 'missing'))
