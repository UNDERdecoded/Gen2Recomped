-- Run:  texlua tools/gen4_contest_extract.lua <platinum .nds> <cache dir>
--
-- Writes `gen4_contest.lua` -- contest_data.narc's contestants, judges,
-- dress-ups and theme tables (src/import/Gen4ContestData.lua) -- into an
-- EXISTING Platinum cache.

package.path = './?.lua;./?/init.lua;' .. package.path

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  print('usage: texlua tools/gen4_contest_extract.lua <platinum .nds> <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/]$', '')

local rom = assert(require('src.import.NdsRom').open(romPath))
local out = assert(require('src.import.Gen4ContestData').extract(rom))
local f = assert(io.open(cacheDir .. '/gen4_contest.lua', 'wb'))
f:write(require('src.import.LuaWriter').encode(out))
f:close()
local o = out.opponents[0]
print(('wrote %s/gen4_contest.lua: opponent 0 species %d gfx %d rank %d moves %s stats %d/%d/%d/%d/%d/%d fame %d; judge 0 name %d types %s rank %d; dressup 0 %d items')
  :format(cacheDir, o.species, o.gfx, o.rank, table.concat(o.moves, ','), o.cool, o.beauty, o.cute, o.smart, o.tough, o.sheen, o.fame,
    out.judges[0].nameId, table.concat(out.judges[0].types, ','), out.judges[0].rank, #out.dressups[0].items))
print(('acting: %d effects (Basic appeal %d, msgs %d/%d), %d AI rows (last: pos %d cond %d target %d)')
  :format(out.effects and 24 or 0, out.effects and out.effects[5].appeal or -1,
    out.effects and out.effects[1].msgs[0] or -1, out.effects and out.effects[1].msgs[1] or -1,
    out.actingAI and #out.actingAI or 0, out.actingAI and out.actingAI[165].position or -1,
    out.actingAI and out.actingAI[165].cond or -1, out.actingAI and out.actingAI[165].target or -1))
