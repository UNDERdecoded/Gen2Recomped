-- Real native flourish sampler and cache marker, independent RS C task oracle.
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local raw=read('src/battle/Gen3MoveAnim.lua');local a=assert(raw:find('function Gen3MoveAnim:flourishLayer(battler)',1,true))
local z=assert(raw:find('-- THE POKEMON THAT SHRINKS',a,true));local source=raw:sub(a,z-1)
local Class={};assert(loadstring('local Gen3MoveAnim=...\n'..source))(Class)
local player,enemy={},{};function Class:matchesBattler(b)return b==player end
local anim=setmetatable({flourish={image='native-rs',life=64,drift=4,lap=128,laps=2,alpha=8/16,centreX=96,centreY=32,width=256,height=256}}, {__index=Class})
local shift,counter,laps=0,0,0
for frame=0,63 do
 if frame>0 then counter=counter+4;shift=shift-4;if counter==128 then counter=0;shift=shift+128;laps=laps+1 end end
 anim.frame=frame;local layer=assert(anim:flourishLayer(player));assert(layer.x==shift and layer.alpha==.5 and layer.centreX==96 and layer.centreY==32)
 assert(anim:flourishLayer(enemy)==nil,'Flourish leaked to the defender')
end
anim.frame=64;assert(anim:flourishLayer(player)==nil,'RS retained the third lap')
anim.flourish.life=96;anim.frame=64;assert(anim:flourishLayer(player),'Existing three-lap sampler changed')
local importer=read('src/import/RomImporter.lua');a=assert(importer:find('local function markerFor(version)',1,true));z=assert(importer:find('-- AND WHAT THAT IMPORT',a,true))
local marker=assert(loadstring('local GameVersion,CACHE_FORMAT=...\n'..importer:sub(a,z-1)..'\nreturn markerFor'))({info=function(v)return{sha1=v..'-sha'}end,isFRLG=function(v)return v=='firered'or v=='leafgreen'end},'format:')
assert(marker('ruby')=='format:rs-stat-flourish-v6:ruby-sha')
assert(marker('sapphire')=='format:rs-stat-flourish-v6:sapphire-sha')
assert(marker('firered')=='format:firered-trade-scene-v1:firered-sha'and marker('emerald')=='format:emerald-trade-scene-v3:emerald-sha','Unrelated cache invalidated')
print('PASS_RS_STAT_FLOURISH 64 C-model frames, exact owner, stop at two laps, existing three-lap sampler, only RS cache v6')
