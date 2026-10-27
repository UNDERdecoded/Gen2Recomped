-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Objects=require('src.core.game3.objects')
local Actors=require('src.compat.gen1.SourceActors')
local Optional=require('src.world.OptionalFollower')
local Host=require('src.mods.Runtime')
local Stream=require('src.core.game3.asset_stream')
local G=require('src.core.Game3')
local previousHooks=Host.hooks
local function gc()collectgarbage('collect');collectgarbage('collect')end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Objects.release();G.release();Actors.release()
 local f=require('tools.session-runtime.fixture').new(edition);local g,w,p=f.game,f.world,f.player
 w.npcs={};w.entities={p};g.mods.mods={gc_owner={enabled=true},peer={enabled=true}}
 Host.hooks=require('src.mods.Hooks').new()
 Host.hooks:wrap('world.follower.spawn',function()return true end,0,'gc_owner')
 Optional.onMapEntered(g,w,nil,true)
 local npc=assert(Optional.current(w),'native follower admission failed');local nativeDraws,customDraws=0,0
 npc.sprite={draw=function()nativeDraws=nativeDraws+1 end}
 Host.currentMod='gc_owner'
 do local view=Objects.find(250);view.sprite=nil end
 Host.currentMod=nil;gc()
 local sprite,overridden=Actors.renderer(npc)
 T.eq(sprite,nil);T.eq(overridden,true,'an owned absent renderer survives view collection')
 npc:draw(0,0);T.eq(nativeDraws,0,'native fallback artwork cannot reappear after GC')
 local watched=setmetatable({},{__mode='v'})
 Host.currentMod='gc_owner'
 do
  local view=Objects.find(250);local renderer={draw=function()customDraws=customDraws+1 end}
  watched[1]=renderer;view.sprite=renderer
 end
 Host.currentMod=nil;gc()
 T.check(watched[1]~=nil,'an installed renderer remains owned without a retained view')
 npc:draw(0,0);T.eq(customDraws,1)
 Stream.cancelOwner('peer');gc();npc:draw(0,0);T.eq(customDraws,2,'foreign teardown cannot retire the renderer')
 Stream.cancelOwner('gc_owner');gc()
 T.eq(watched[1],nil,'owner teardown releases installed artwork')
 npc:draw(0,0);T.eq(nativeDraws,1,'owner teardown restores native artwork')
 -- Removing a native actor or retiring its dataset releases its lease too.
 Host.currentMod='gc_owner'
 local retainedView=Objects.find(250)
 do local r={draw=function()end};watched[1]=r;retainedView.sprite=r end
 Host.currentMod=nil;gc()
 w.npcs={};w.entities={p}
 T.eq(type(Actors.poll),'function')
 if Actors.poll then Actors.poll()end
 gc();T.eq(watched[1],nil,'removed native actors release presentation without a draw')
 T.eq(retainedView.localId,nil,'retained caller view observes native removal')
 local _,active=Actors.renderer(npc);T.eq(active,false)
 w.npcs={npc};w.entities={p,npc};Host.currentMod='gc_owner'
 local cohortView=Objects.find(250)
 do local r={draw=function()end};watched[1]=r;cohortView.sprite=r end
 Host.currentMod=nil;gc();g.save={player={}}
 if Actors.poll then Actors.poll()end
 gc();T.eq(watched[1],nil,'a replaced save retires the previous presentation cohort')
 T.eq(cohortView.localId,nil,'retained caller view observes cohort retirement')
 -- The draw-time lookup must release the same ownership even when poll has
 -- not run between native removal and the last caller asking for artwork.
 g.save={player={}};Host.currentMod='gc_owner'
 local drawView=Objects.find(250)
 do local r={draw=function()end};watched[1]=r;drawView.sprite=r end
 Host.currentMod=nil;w.npcs={};w.entities={p}
 local removed,owned=Actors.renderer(npc)
 T.eq(removed,nil);T.eq(owned,false,'renderer lookup retires a removed native actor')
 gc();T.eq(watched[1],nil,'renderer lookup releases artwork while its view is retained')
 T.eq(drawView.localId,nil,'draw-time retirement keeps the native view invalid')
 Objects.release();Actors.release();G.release()
end
Host.hooks=previousHooks
T.finish('owned native actor presentation survives GC and retires with its cohort')
