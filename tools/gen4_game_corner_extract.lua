-- Run:  texlua tools/gen4_game_corner_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_game_corner.lua` -- the prize counter's table from ARM9
-- (src/import/Gen4GameCorner.lua) -- into an EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_game_corner_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4GameCorner').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_game_corner.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
local rows = {}
for _, p in ipairs(out.prizes) do rows[#rows + 1] = p.item .. ':' .. p.price end
print(('wrote %s/gen4_game_corner.lua: %d prizes %s'):format(cacheDir, #out.prizes, table.concat(rows, ' ')))
