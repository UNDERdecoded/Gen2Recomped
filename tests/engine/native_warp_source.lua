-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Contract=require('tools.native-field.warp-fixture')
local Warp=require('src.core.game3.warp')
local Host=require('src.mods.Runtime')
local Stream=require('src.core.game3.asset_stream')
local Game3=require('src.core.Game3')
local saved=package.loaded['src.core.Game']
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Game3.release();Stream.shutdown()
 local f=Contract.new(edition)
 package.loaded['src.core.Game']=f.game;f.game.mods=f.loader
 Host.currentMod='warp'
 T.eq(Warp.isBusy(),false)
 for _,key in ipairs{'transitioning','flyAnim','teleportOut','whirlSpin','gen4Waterfall'}do
  f.ow[key]=true;T.eq(Warp.isBusy(),true,key..' is a native warp owner');f.ow[key]=nil
 end
 f.ow.emote={};T.eq(Warp.isBusy(),false,'ordinary field activity is not an invented warp');f.ow.emote=nil
 T.eq(Warp.request(nil,f.game,f.dest,-1,0),nil);T.eq(#f.trace,0,'bad destination is side-effect free')
 local called=0;local seenOwner
 T.eq(Warp.request(nil,f.game,f.dest,1,2,'up',{onDone=function(a,b,c)
  called=called+1;seenOwner=Host.currentMod;T.eq(a,'native');T.eq(b,nil);T.eq(c,'tail')
 end}),true)
 T.eq(#f.trace,1);T.eq(f.trace[1].mapId,f.dest);T.eq(f.trace[1].x,1);T.eq(f.trace[1].y,2)
 T.eq(Warp.isBusy(),true)
 Host.currentMod='peer';T.eq(Warp.clear(),false);T.eq(called,0)
 f:arrive();f:complete('native',nil,'tail');f:complete('again')
 T.eq(called,1);T.eq(seenOwner,'warp');T.eq(Host.currentMod,'peer')
 f.busy=false;f.ow.transitioning=false
 Host.currentMod='warp'
 T.eq(Warp.request(nil,f.game,f.dest,0,0,'down',{onDone=function()called=called+1 end}),true)
 local finish=f.callback
 collectgarbage('collect');Stream.cancelOwner('peer');Stream.cancelOwner('warp')
 T.eq(f.ow.transitioning,true,'revocation leaves the admitted native transition alone')
 f:arrive();finish();T.eq(called,1,'revoked continuation never fires')
 f.busy=false;f.ow.transitioning=false
 T.eq(Warp.request(nil,f.game,f.dest,0,0,'down',{onDone=function()called=called+1 end}),true)
 finish=f.callback;f.game.save={};f:arrive();finish();T.eq(called,1,'save replacement retires callback')
 Stream.shutdown();Game3.release();Host.currentMod=nil
 f:close()
 -- Observe the actual native transition, with map materialization isolated.
 local n=Contract.new(edition)
 package.loaded['src.core.Game']=n.game;n.game.mods=n.loader;Host.currentMod='warp'
 local OW=require('src.world.OverworldController');local restore
 for i=1,100 do
  local key,previous=debug.getupvalue(OW.startWarpTo,i);if not key then break end
  if key=='Game'then debug.setupvalue(OW.startWarpTo,i,n.game);restore=function()debug.setupvalue(OW.startWarpTo,i,previous)end;break end
 end
 assert(restore,'native warp Game upvalue')
 setmetatable(n.game.stack,{__index=require('src.core.StateStack')})
 n.ow.startWarpTo=OW.startWarpTo
 function n.ow:frlgBehaviours()return false end
 function n.ow:noteGen2Spawn()end
 function n.ow:setMap(id,x,y,facing)n.destination={id,x,y,facing};n:arrive()end
 n.ow.arriveWarp='escalator'
 T.eq(Warp.request(nil,n.game,n.dest,1,1),true)
 local transition=n.game.stack:top();T.eq(getmetatable(transition),require('src.render.Transition'))
 T.eq(n.ow.arriveWarp,nil);T.eq(n.ow.warpArrivalKind,'escalator')
 T.eq(Warp.isEscalatorActive(),true,'native departure retains its admitted arrival kind')
 for _=1,transition.frames+transition.framesIn+2 do
  if n.game.stack:top()==transition then transition:update(1/60)end
 end
 T.eq(Warp.isEscalatorActive(),false);T.eq(Warp.isBusy(),false);T.eq(n.ow.warpArrivalKind,nil)
 restore();Stream.shutdown();Game3.release();Host.currentMod=nil;n:close()
end
package.loaded['src.core.Game']=saved
T.finish('source warp requests use native admission and owner callback lifetime')
