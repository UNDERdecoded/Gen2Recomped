-- Run:  texlua tools/gen4_seals_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_seals.lua` -- the seal table and Sunyshore's daily seal stocks
-- from ARM9 (src/import/Gen4Seals.lua) -- into an EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_seals_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4Seals').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_seals.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
local days = {}
for d, list in ipairs(out.stocks) do days[d] = table.concat(list, ',') end
print(('wrote %s/gen4_seals.lua: seal 1 price %d name %d; seal 78 name %d; stocks %s')
  :format(cacheDir, out.seals[1].price, out.seals[1].nameIndex, out.seals[78].nameIndex, table.concat(days, ' | ')))
