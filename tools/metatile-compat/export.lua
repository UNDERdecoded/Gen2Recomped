-- Export public interface metadata only; run in the pinned reference checkout.
package.path='./?.lua;./?/init.lua;'..package.path
local MB=require('src.core.game3.mb')
local function quote(s)return string.format('%q',s)end
local function keys(t)local out={}for k in pairs(t)do out[#out+1]=k end;table.sort(out);return out end
print('return {')
print('  ids = {')
for _,name in ipairs(keys(MB.all()))do print('    ['..quote(name)..'] = '..MB.id(name)..',')end
print('  },\n  names = {')
for id=0,767 do local name=MB.nameOf(id);if name then print('    ['..id..'] = '..quote(name)..',')end end
print('  },\n  translations = {')
for _,game in ipairs({'emerald','ruby','sapphire'})do
 local t=MB.translator(game)
 print('    '..game..' = {')
 for first=0,255,16 do local line={}for raw=first,first+15 do line[#line+1]=t.canon(raw)end;print('      '..table.concat(line,',')..',')end
 print('    },')
end
print('  },\n  sourceNames = {')
for _,game in ipairs({'ruby','sapphire'})do
 local t=MB.translator(game);print('    '..game..' = {')
 for raw=0,255 do local name=t.sourceName(t.canon(raw));if name then print('      ['..raw..'] = '..quote(name)..',')end end
 print('    },')
end
print('  },\n}')
