-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Objects=require('src.core.game3.objects')
local Actors=require('src.compat.gen1.SourceActors')
local Follower=require('src.compat.game3.Follower')
local Optional=require('src.world.OptionalFollower')
local Host=require('src.mods.Runtime')
local Stream=require('src.core.game3.asset_stream')
local G=require('src.core.Game3')
local base,previousHooks=Follower.update,Host.hooks
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Objects.release();G.release();Actors.release()
 local f=require('tools.session-runtime.fixture').new(edition);local g,w,p=f.game,f.world,f.player
 w.npcs={};w.entities={p};g.mods.mods={source_owner={enabled=true},peer={enabled=true}}
 Host.hooks=require('src.mods.Hooks').new();Host.hooks:wrap('world.follower.spawn',function()return true end)
 Optional.onMapEntered(g,w,nil,true);local npc=assert(Optional.current(w))
 local nativeDraws,customDraws,calls=0,0,0
 npc.sprite={draw=function()nativeDraws=nativeDraws+1 end}
 Follower.current();local _,assigned=Actors.renderer(npc)
 T.eq(assigned,false,'mere source observation preserves native follower art')
 npc:draw(0,0);T.eq(nativeDraws,1)
 Host.currentMod='source_owner'
 local expectedRenderer
 Follower.update=function(game)
  local a,b,c=base(game);base(game) -- native phase remains single-use
  -- Consumers compare against a cached nil renderer and may make no write.
  T.eq(Follower.current().sprite,expectedRenderer)
  return a,b,c
 end
 local a,b,c=Follower._dispatch(g,w,function()calls=calls+1;return 'native',nil,37 end)
 T.eq(a,'native');T.eq(b,nil);T.eq(c,37);T.eq(calls,1)
 local sprite,overridden=Actors.renderer(npc)
 T.eq(sprite,nil);T.eq(overridden,true,'wrapped source follower starts without fallback artwork')
 collectgarbage('collect');collectgarbage('collect');npc:draw(0,0);T.eq(nativeDraws,1)
 T.eq(w.follower,npc);T.eq(w.entities[2],npc,'native simulation membership is preserved')
 Host.currentMod='peer';local view=Objects.find(250)
 local custom={draw=function()customDraws=customDraws+1 end};expectedRenderer=custom;view.sprite=custom
 Host.currentMod='source_owner';Follower._dispatch(g,w,function()calls=calls+1 end)
 T.eq(select(1,Actors.renderer(npc)),custom,'default admission preserves an existing owned renderer')
 Stream.cancelOwner('source_owner');npc:draw(0,0);T.eq(customDraws,1)
 Stream.cancelOwner('peer');T.eq(select(2,Actors.renderer(npc)),false)
 Follower.update=base
 Follower._dispatch(g,w,function()calls=calls+1 end)
 T.eq(select(2,Actors.renderer(npc)),false,'ordinary native update retains native artwork')
 Host.currentMod=nil;Objects.release();Actors.release();G.release()
end
Follower.update=base;Host.hooks=previousHooks
T.finish('source follower default artwork admission preserves native actors and owners')
