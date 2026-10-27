package.path='./?.lua;./?/init.lua;'..package.path
local Version=require('src.core.GameVersion')
local Catalog=require('src.import.gba.map_catalog')
local Family=require('src.import.gba.family')
print('return {')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Version.set(edition)
 local family=Family.active()
 print((' [%q]={'):format(edition))
 local groups=family:groups().groups
 for g=0,255 do
  local group=groups[g]
  if group then for n,pret in ipairs(group.maps)do
   local canonical=assert(Catalog.mapIdFor(g,n-1))
   local constant=family:mapConstAt(g,n-1)
   print(('  {%d,%d,%q,%q,%s},'):format(g,n-1,canonical,pret,constant and ('%q'):format(constant)or'nil'))
  end end
 end
 print(' },')
end
print('}')
