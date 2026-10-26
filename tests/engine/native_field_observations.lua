-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local G=require('src.core.Game3')
local Collision=require('src.core.game3.collision')
local Weather=require('src.core.game3.field_weather')
local Warp=require('src.world.Warp')
local Host=require('src.mods.Runtime')
local Identity=require('src.compat.gen1.MapIdentity')
local previousHooks=Host.hooks
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 G.release()
 local f=require('tools.session-runtime.fixture').new(edition);local g,w=f.game,f.world
 f.map.def.warps={{x=3,y=4},{x=5,y=6}}
 g.data.constants.gen3WeatherNames={[0]='NONE',[3]='RAIN',[5]='RAIN_THUNDERSTORM',[13]='DOWNPOUR',[20]='ROUTE119_CYCLE'}
 local calls=0
 Host.hooks={chains={['warp.destination']={{}}},call=function()calls=calls+1;error('forecast invoked committing hook')end}
 local before=require('src.link.Json').encode(g.save)
 local id,x,y=Collision.resolveWarpDestination(g,{destMap=f.canonical,destWarp=2})
 T.eq(id,f.canonical);T.eq(x,5);T.eq(y,6)
 local raw=Warp.peekDestination(g.data,{destMap='TEST',destWarp=2},nil,nil,g.save)
 T.eq(raw,'TEST');T.eq(calls,0)
 T.eq(Collision.resolveWarpDestination(g,{destMap='UNIMPORTED'}),nil)
 T.eq(Collision.resolveWarpDestination(g,{destMap=f.canonical,destWarp=-1}),nil)
 local canon,xx,yy=Collision.resolveWarpDestination(g,{destMap='TEST',destWarp=1})
 T.eq(canon,f.canonical);T.eq(xx,3);T.eq(yy,4)
 T.eq(Collision.resolveWarpDestination(g,{mapGroup=f.map.def.group,mapNum=f.map.def.number,destWarp=2}),f.canonical)
 T.eq(Warp.peekDestination(g.data,{destMap='LAST_MAP',destWarp=1}),nil)
 T.eq(require('src.link.Json').encode(g.save),before,'ordinary forecasts never write native state')
 g.save.gen3DynamicWarp={map='TEST',warp=1,x=17,y=18}
 canon,xx,yy=Collision.resolveWarpDestination(g,{nativeDestination='MAP_G127_N127',mapGroup=127,mapNum=127})
 T.eq(canon,f.canonical);T.eq(xx,5);T.eq(yy,6,'dynamic warp uses native zero-based landing index')
 g.save.gen3DynamicWarp.warp=255
 canon,xx,yy=Collision.resolveWarpDestination(g,{mapGroup=127,mapNum=127})
 T.eq(xx,17);T.eq(yy,18,'native coordinate sentinel is preserved')
 g.save.gen3WeatherActive=3;T.eq(Weather.getWeather(),3)
 g.save.gen3WeatherActive=20;g.save.gen3WeatherStage=2;w.weatherFrame=91
 T.eq(Weather.getWeather(),5,'weather uses the native resolved cycle stage')
 T.eq(w.weatherFrame,91,'weather observation cannot advance native clock')
 g.save.gen3WeatherStage=3;T.eq(Weather.getWeather(),3)
 g.save.gen3WeatherActive=99;T.eq(Weather.getWeather(),nil,'unknown weather is not invented')
 local SourceWeather=require('src.core.game3.weather')
 T.eq(SourceWeather.SUNNY,2);T.eq(SourceWeather.RAIN,3)
 g.data.constants.gen3WeatherNames=nil;g.save.gen3WeatherActive=0
 T.eq(SourceWeather.get(),0,'editions without extracted cycle records share native enum')
 T.eq(SourceWeather.isActive(),false)
 g.save.gen3WeatherActive=5;T.eq(SourceWeather.get(),5);T.eq(SourceWeather.isActive(),true)
 g.stack.states={};g.stack.worldState=nil;T.eq(Weather.getWeather(),nil,'retired world has no active weather')
 T.eq(Collision.resolveWarpDestination(g,{destMap='TEST'}),nil,'retired world cannot forecast a warp')
 Collision.release();G.release()
end
Host.hooks=previousHooks
T.finish('native read-only warp forecasts and resolved weather observations')
