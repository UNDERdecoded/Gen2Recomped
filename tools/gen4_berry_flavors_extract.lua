-- Run:  texlua tools/gen4_berry_flavors_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_berry_flavors.lua` -- each berry's five flavors and smoothness
-- from /itemtool/itemdata/nuts_data.narc (Gen4BerryData.flavors) -- into an
-- EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_berry_flavors_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local B = require('src.import.Gen4BerryData')
local rom = assert(require('src.import.NdsRom').open(romPath))
local arc = assert(require('src.import.NarcArchive').parse(assert(rom:read(B.PATH))))
local out = assert(B.flavors(arc))
local f = assert(io.open(cacheDir .. '/gen4_berry_flavors.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
local c = out[149]
print(('wrote %s/gen4_berry_flavors.lua: Cheri %s smooth %d; Pecha %s; Rawst %s')
  :format(cacheDir, table.concat(c.flavors, ','), c.smoothness,
          table.concat(out[151].flavors, ','), table.concat(out[152].flavors, ',')))
