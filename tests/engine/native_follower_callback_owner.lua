-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
Version.set('firered')
local Native=require('src.core.Game')
local Facade=require('src.core.Game3')
local Source=require('src.compat.gen1.SourceActors')
Facade.release()
local run=T.sdk.loadMods({'mods/follower_owner'},{fs=T.sdk.memfs({
 ['mods/follower_owner/manifest.json']=[[{"id":"follower_owner","name":"Follower owner","version":"1.0.0","api":2,"entry":"main.lua"}]],
 ['mods/follower_owner/main.lua']=[[
 local mod=...
 local F=require('src.world.game3.Follower')
 local renderer={draw=function()end}
 mod.exports.renderer=renderer
 mod.hooks:wrap("world.follower.spawn",function(_,game,world)
  mod.exports.seenGame,mod.exports.seenWorld=game,world
  F.current(world).sprite=renderer
  return true
 end)
 mod.hooks:wrap('input.step',function(nextFn,game,dt)
  if mod.exports.fail then error('owned follower callback failure')end
  return nextFn(game,dt)
 end)
 ]],
})})
T.eq(#run.errors,0,'native follower consumer loads')
local data=run.data
local def={};for k,v in pairs(data.maps.FIX_TOWN)do def[k]=v end
local object={index=1,sprite='SPRITE_FIX_PLAYER',x=0,y=0,movement='STILL'}
def.id,def.group,def.number,def.objects='MAP_G04_N03',4,3,{object};data.maps[def.id]=def
local npc=require('src.world.NPC').new(data,def.id,object)
npc.optionalFollower=true
local original=npc.sprite
local world={isOverworld=true,map=require('src.world.Map').new(def,data.tilesets[def.tileset]),
 player=require('src.world.Player').new(data,1,0,'down'),npcs={npc},entities={npc}}
Native.data,Native.save,Native.overworld,Native.mods,Native.stack=data,{party={}},world,run.loader,{states={world}}
local api=run.loader.exports.follower_owner
T.check(Facade._usesCallbacks('follower_owner'),'follower-only namespace establishes ownership')
T.eq(run.loader.hooks:call("world.follower.spawn",function()return false end,Native,world),true)
T.eq(api.seenGame,Native,'native callback game is not converted')
T.eq(api.seenWorld,world,'native callback world identity is retained')
local renderer,owned=Source.renderer(npc)
T.check(owned and renderer==api.renderer,'actual native actor receives the mod-owned presentation')
T.eq(npc.sprite,original,'native sprite resources retain their original owner')
T.eq(Facade._callbackOwner(),nil,'successful callback restores its owner context')
api.fail=true
T.eq(run.loader.hooks:call('input.step',function(_,dt)return dt end,Native,0.25),0.25,'failed callback retains the native fallback')
T.eq(Facade._callbackOwner(),nil,'failed callback restores its owner context')
run.loader:_rollback('follower_owner')
T.check(not Facade._usesCallbacks('follower_owner'),'rollback removes follower callback ownership')
local _,stillOwned=Source.renderer(npc)
T.check(not stillOwned,'rollback retires the follower presentation')
T.finish('native follower callback ownership')
