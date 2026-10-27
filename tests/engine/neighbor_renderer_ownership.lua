-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local T=require('tests.harness')
love=require('tests.love_stub')
local Version=require('src.core.GameVersion')
local Loader=require('src.world.MapLoader')
local Pipelines=require('src.render.Pipelines')
local Fixture=require('tests.world_draw.fixture')
local old=Version.get()
local cacheSlot,originalCache
for i=1,100 do
 local name,value=debug.getupvalue(Loader.cached,i)
 if name=='cache'then cacheSlot,originalCache=i,value;break end
 if not name then break end
end
assert(cacheSlot)
local pipeline,draw,load=Pipelines.worldPipeline,Pipelines.drawWorld,Loader.load
for _,edition in ipairs({'red','gold','crystal','emerald','firered','platinum'})do
 Version.set(edition)
 for _,declines in ipairs({false,true})do
  local f=Fixture.new(2);local draws,above=0,0
  local native={id='OWNED_NEIGHBOR',renderer={
   drawMapOnly=function(_,x,y,w,h)
    T.eq(x,f.world.camera.x-32,'native strip keeps neighbor X origin')
    T.eq(y,f.world.camera.y+16,'native strip keeps neighbor Y origin')
    T.eq(w,160);T.eq(h,144);draws=draws+1
   end,
   drawAbove=function()above=above+1 end,
  }}
  local view={id=native.id,renderer={image='source-owned-presentation'}}
  local neighbor={id=native.id,map=view,ox=32,oy=-16}
  f.world.neighbors={neighbor}
  debug.setupvalue(Loader.cached,cacheSlot,{[native.id]=native})
  Pipelines.worldPipeline=function()if declines then return 'source_draw',{ }end end
  Pipelines.drawWorld=function()return nil end
  T.eq(Loader.forNeighbor(neighbor,f.game.data),native,'loader retains native renderer ownership')
  local ok,why=pcall(f.world.drawWorld,f.world)
  T.check(ok,edition..' native draw survives '..(declines and'pipeline decline'or'flat draw')..': '..tostring(why))
  T.eq(draws,1,'actual native ground pass draws the resident neighbor once')
  T.eq(above,1,'actual upper layer uses the same native renderer')
  T.eq(neighbor.map,view,'source presentation view is not overwritten')
  T.eq(view.renderer.drawMapOnly,nil,'native draw does not inject methods into a borrowed view')
  debug.setupvalue(Loader.cached,cacheSlot,{})
  f.game.data.maps={[native.id]={id=native.id}}
  local reloads=0
  Loader.load=function(data,id)T.eq(data,f.game.data);T.eq(id,native.id);reloads=reloads+1;return native end
  T.eq(Loader.forNeighbor(neighbor,f.game.data),native,'invalidated native renderer is resolved through its actual loader')
  T.eq(reloads,1,'missing native resource is rebuilt once through loader authority')
  T.eq(Loader.forNeighbor({id='CUSTOM',map=view},f.game.data),view,'custom non-native neighbor keeps its own renderer')
  Loader.load=load
 end
end
debug.setupvalue(Loader.cached,cacheSlot,originalCache)
Pipelines.worldPipeline,Pipelines.drawWorld,Loader.load=pipeline,draw,load
Version.set(old)
T.finish('native neighbor renderers survive borrowed source views and pipeline decline')
