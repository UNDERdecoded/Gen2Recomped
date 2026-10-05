-- Run:  texlua tools/gen4_area_popup_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_area_popup.lua` -- the area-name signs and the per-header label
-- data (src/import/Gen4AreaPopup.lua) -- into an EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_area_popup_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4AreaPopup').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_area_popup.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
local n = 0
for _ in pairs(out.windows) do n = n + 1 end
local h = out.headers
print(('wrote %s/gen4_area_popup.lua: %d signs; Twinleaf (411) text=%s window=%s type=%s; Jubilife (3) window=%s'):format(
  cacheDir, n, h[411] and h[411].text, h[411] and h[411].window, h[411] and h[411].mapType, h[3] and h[3].window))
