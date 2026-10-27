-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Map=require('src.core.game3.map')
local C=require('src.core.game3.collision')
local original=package.loaded['src.core.Game']
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.map-runtime.fixture').new(edition)
 local g,w=f.game,f.world;package.loaded['src.core.Game']=g
 w.player={};g.save={flags={}}
 local def=assert(Map.currentDef());local warp=assert(def.warps[1])
 local before=require('src.link.Json').encode(g.save)
 local runtime=require('src.mods.Runtime');local call=runtime.call
 runtime.call=function(name,...)assert(name~='warp.destination','read cannot execute warp decision');return call(name,...)end
 local id,x,y=C.resolveWarpDestination(g,warp)
 T.eq(id,warp.destMap);T.check(type(x)=='number');T.check(type(y)=='number')
 T.eq(require('src.link.Json').encode(g.save),before);T.eq(w.transitioning,nil)
 T.eq(C.resolveWarpDestination(g,{destMap=warp.destMap,destWarp=warp.destWarp}),nil,'foreign copied records have no native provenance')
 Map.release();T.eq(C.resolveWarpDestination(g,warp),nil,'retired source records cannot resolve')
 runtime.call=call;f.views:release();C.clear()
end
package.loaded['src.core.Game']=original
T.finish('native companion destination reads preserve gameplay hooks and save state')
