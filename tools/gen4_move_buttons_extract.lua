-- Run:  texlua tools/gen4_move_buttons_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_move_buttons.lua` -- the per-type move-button palettes, their
-- masks and the PP text palette (src/import/Gen4MoveButtons.lua) -- into an
-- EXISTING Platinum cache, so it gains them without a re-import. Same
-- extractor, same serialiser; it only adds that one file.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_move_buttons_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local NdsRom = require('src.import.NdsRom')
local Narc = require('src.import.NarcArchive')
local Gen4Graphics = require('src.import.Gen4Graphics')
local Gen4Subscreen = require('src.import.Gen4Subscreen')
local Gen4MoveButtons = require('src.import.Gen4MoveButtons')
local LuaWriter = require('src.import.LuaWriter')

local rom = assert(NdsRom.open(romPath))
local arc = assert(Narc.parse(assert(rom:read(Gen4Subscreen.PATH))))
local out = assert(Gen4MoveButtons.extract(rom, arc, Gen4Graphics, Gen4Subscreen))
local f = assert(io.open(cacheDir .. '/gen4_move_buttons.lua', 'wb'))
f:write(LuaWriter.encode(out))
f:close()
local painted = 0
for _, m in ipairs(out.masks) do
  for i = 1, #m.index do if m.index:byte(i) > 0 then painted = painted + 1 end end
end
local fire = out.types[10] and out.types[10][3]
print(('wrote %s/gen4_move_buttons.lua: 18 type palettes (Fire entry 2 = %d,%d,%d), '
       .. '%d slot-palette pixels over 4 buttons'):format(cacheDir,
       fire and fire[1] or -1, fire and fire[2] or -1, fire and fire[3] or -1, painted))
