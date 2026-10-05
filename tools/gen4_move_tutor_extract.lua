-- Run:  texlua tools/gen4_move_tutor_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_move_tutor.lua` -- the shard tutors' move table and per-species
-- masks (src/import/Gen4MoveTutor.lua) -- into an EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_move_tutor_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4MoveTutor').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_move_tutor.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
local T = require('src.import.Gen4MoveTutor')
print(('wrote %s/gen4_move_tutor.lua: %d moves (first %d, last %d); Bulbasaur %s; Route 212 for an empty Gible: %d moves')
  :format(cacheDir, #out.moves, out.moves[1].move, out.moves[#out.moves].move, out.masks[1],
          #T.learnable(out, { species = 443, moves = {} }, 0)))
