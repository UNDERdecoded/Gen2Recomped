-- Run:  texlua tools/gen4_egg_moves_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_egg_moves.lua` -- Platinum's `sEggMoves` from overlay 5
-- (src/import/Gen4EggMoves.lua) -- into an EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_egg_moves_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local E = require('src.import.Gen4EggMoves')
local out, count = E.parse(rom:overlay(E.OVERLAY))
assert(out, count)
local f = assert(io.open(cacheDir .. '/gen4_egg_moves.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
print(('wrote %s/gen4_egg_moves.lua: %d species; Bulbasaur %s; Turtwig %s; Pichu %s')
  :format(cacheDir, count, table.concat(out[1] or {}, ','), table.concat(out[387] or {}, ','),
          table.concat(out[172] or {}, ',')))
