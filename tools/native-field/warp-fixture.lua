-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Real API-2 loader and native world; only map materialization is synthetic.
local M={}
function M.new(edition)
 local T=require('tests.modkit')
 local source=require('tools.session-runtime.fixture').new(edition)
 local game,ow=source.game,source.world
 local data=T.fixtures.fresh();data.maps=game.data.maps
 local home,dest='TEST','SOURCE_WARP_DEST'
 data.maps[home].width,data.maps[home].height=3,3
 data.maps[dest]={id=dest,width=2,height=3,tileset='FIX',blocks={1}}
 local run=T.sdk.loadMods({'mods/warp'},{data=data,fs=T.sdk.memfs({
  ['mods/warp/manifest.json']=[[{"id":"warp","name":"Warp probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
  ['mods/warp/main.lua']=[[local mod=...;mod.exports.nativeOwner=true]],
 })})
 assert(#run.errors==0,table.concat(run.errors,'\n'))
 game.data,game.mods=run.data,run.loader
 local f={game=game,ow=ow,player=ow.player,loader=run.loader,home=home,dest=dest,trace={}}
 function f:arrive()
  local destination=assert(self.destination)
  ow.map={id=destination[1],def=game.data.maps[destination[1]],isDoorTileCell=function()return false end}
  ow.player.cellX,ow.player.cellY,ow.player.facing=destination[2],destination[3],destination[4]
 end
 function f:complete(...)if self.callback then self.callback(...)end end
 function ow:startWarpTo(id,x,y,facing,done,opts)
  f.trace[#f.trace+1]={mapId=id,x=x,y=y,facing=facing,keepMusic=opts.keepMusic,fade=opts.fade}
  f.callback=done;f.destination={id,x,y,facing};self.arriveWarp=nil;self.transitioning=true
 end
 function f:close()require('src.mods.Loader').teardown();run.release()end
 return f
end
return M
