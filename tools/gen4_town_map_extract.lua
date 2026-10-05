-- Run:  texlua tools/gen4_town_map_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_town_map.lua` -- the town map's sprites, palettes, name blocks
-- and fly-location table (src/import/Gen4TownMap.lua) -- into an EXISTING
-- Platinum cache, so it gains them without a re-import.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_town_map_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4TownMap').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_town_map.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
for k, list in pairs(out.images) do
  for i, im in pairs(list) do print(('%-10s cell %d  %dx%d at %d,%d'):format(k, i - 1, im.w, im.h, im.x, im.y)) end
end
print(('wrote %s/gen4_town_map.lua: %d blocks, %d palette colours'):format(cacheDir,
  #(out.blocks or {}), #(out.spritePalette or {})))
