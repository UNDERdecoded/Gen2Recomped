-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Battle=require('src.core.game3.battle')
local Switch=require('src.core.game3.battle.switch_seq')
local G=require('src.core.Game3')
local base=Switch.update;local original=package.loaded['src.core.Game']
T.eq(base(),nil,'source cannot invent a native queue phase')
T.eq(Switch.busy(),false)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 local game=f.game;package.loaded['src.core.Game']=game
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b)
 -- Keep the real controller and native constructor. The incoming party
 -- member is synthetic imported data, never a player save or ROM cache.
 local mon=require('src.pokemon.Pokemon').new(f.data,'CHARMANDER',30,function(lo)return lo or 0 end)
 game.save.party[2]=mon;b.queue={};b.current=nil;b.nextInsert=nil
 local incoming=b:switchPlayerInto(0,mon)
 T.eq(incoming.mon,mon);T.eq(b.player,incoming,'native logical replacement remains synchronous')
 T.eq(Switch._st,Battle.getState());T.eq(Switch._i,1);T.eq(Switch.busy(),true)
 local steps=Switch._steps;local token=b._sourceSwitchSequence
 T.eq(steps,Switch._steps,'step identity survives observation')
 T.eq(steps[1].kind,'msg_sendout');T.eq(steps[1].data.id,0);T.eq(steps[1].data.side,'player')
 T.eq(steps[2].kind,'sendout_player');T.eq(steps[2].data.id,0)
 T.eq(steps[2].fn,nil);T.eq(steps[2].data.mon,nil,'public steps retain no native actor')
 local entry,ending
 for _,row in ipairs(b.queue)do
  if row._sourceSwitchStep then entry=row end
  if row._sourceSwitchEnd then ending=row end
 end
 T.neq(entry,nil);T.neq(ending,nil);T.eq(b.queue[1],token.message)
 b.current=token.message;T.eq(Switch._waitingMsg,true);b.current=nil
 T.eq(Switch._waitingMsg,false);b.waitFrames=1;T.eq(Switch._waiting,true);b.waitFrames=0
 T.raises(function()Switch._i=9 end,'read-only')
 local nativeGrow,cry,held=0,0,0
 local grow=b.startGrowIn;local Sound=require('src.core.Sound');local sound=Sound.playCry
 local Held=require('src.battle.HeldItems');local onEntry=Held.onEntry
 b.startGrowIn=function(self,actor)T.eq(self,b);T.eq(actor,incoming);nativeGrow=nativeGrow+1 end
 Sound.playCry=function(data,species)T.eq(data,f.data);T.eq(species,mon.species);cry=cry+1 end
 Held.onEntry=function(screen,actor)T.eq(screen,b);T.eq(actor,incoming);held=held+1 end
 entry.fn()
 b.startGrowIn=grow;Sound.playCry=sound;Held.onEntry=onEntry
 T.eq(nativeGrow,1,'tagged row is the actual native send-out action');T.eq(cry,1);T.eq(held,1)
 -- The hook belongs immediately before the existing grow-in/ball action.
 -- Retain that exact row but substitute its side effects to count dispatches.
 local calls=0;entry.fn=function()calls=calls+1 end
 b.queue={entry};b.waitFrames=0;b.animPlaying=false;b.gen3BallPlaying=false;b.gen3AnimPlaying=false
 b.waitingUI=nil;b.waitingSound=nil;b.draining=nil;b.expFilling=nil
 local frame,hp,pp=b.frame,mon.hp,mon.moves[1]and mon.moves[1].pp
 Switch.update=function()return false end
 b:updateQueue();T.eq(calls,0);T.eq(b.queue[1],entry,'hold preserves the exact native row')
 T.eq(Switch._i,2);T.eq(Switch._steps,steps);T.eq(b.frame,frame);T.eq(mon.hp,hp)
 T.eq(mon.moves[1]and mon.moves[1].pp,pp)
 Switch.update=function()base();return base()end
 b:updateQueue();T.eq(calls,1,'repeated source calls consume native action once');T.eq(#b.queue,0)
 T.eq(base(),nil);T.eq(calls,1,'source call between frames has no command clock')
 -- Errors before consumption retain the row; errors after it cannot replay.
 b.queue={entry};Switch.update=function()error('before native switch')end
 T.raises(function()b:updateQueue()end,'before native switch');T.eq(b.queue[1],entry);T.eq(calls,1)
 Switch.update=function()base();error('after native switch')end
 T.raises(function()b:updateQueue()end,'after native switch');T.eq(#b.queue,0);T.eq(calls,2)
 b.queue={entry};entry.fn=function()calls=calls+1;error('native switch failed')end
 Switch.update=function()pcall(base);return true end
 T.raises(function()b:updateQueue()end,'native switch failed');T.eq(calls,3);T.eq(#b.queue,0)
 b.nextInsert=nil;entry.fn=function()calls=calls+1 end;b.queue={entry}
 Switch.update=function()game.stack:push({});local a,why=base();game.stack:pop();return a,why end
 b:updateQueue();T.eq(calls,3);T.eq(b.queue[1],entry,'covered callback cannot consume')
 Switch.update=function()return base()end
 game.stack:push({});b:updateQueue();game.stack:pop()
 T.eq(calls,3);T.eq(b.queue[1],entry,'already covered battle cannot dispatch source action')
 local seams=require('src.mods.ModSeams');local owner=G._callbackOwner()
 Switch.update=function()T.eq(G._callbackOwner(),'switch_owner');return base()end
 seams._journal[#seams._journal+1]={tbl=Switch,key='update',after=Switch.update,owner='switch_owner'}
 b:updateQueue();T.eq(calls,4);T.eq(G._callbackOwner(),owner);table.remove(seams._journal)
 b.queue={entry}
 Switch.update=function()
  local save=game.save;game.save={};local a,why=base();game.save=save;return a,why
 end
 b:updateQueue();T.eq(calls,4);T.eq(b.queue[1],entry,'replaced native session cannot consume the prior action')
 -- Completion only clears its own admission, never a later queued switch.
 local message2,entry2,end2={},{fn=function()end},{fn=function()end}
 local nextToken=Switch._nativeBind(b,3,message2,entry2,end2)
 T.eq(Switch._steps[2].kind,'sendout_enemy');T.eq(Switch._steps[2].data.id,3)
 Switch._nativeFinish(b,ending);T.eq(b._sourceSwitchSequence,nextToken)
 b.queue={end2};Switch.update=base;b:updateQueue()
 T.eq(Switch.busy(),false);T.eq(Switch._steps,nil)
 Switch._nativeBind(b,0,message2,entry2,end2);game.stack:pop()
 T.eq(b._sourceSwitchSequence,nil,'native exit retires switch observations')
 T.eq(Switch.busy(),false);T.eq(Switch._st,nil);T.eq(steps[2].data.id,0)
 Battle._service.release();f.close();G.release()
end
-- Ordinary queue functions retain their existing insertion order and native
-- owner in the other generations, with no switch facade admission.
for _,edition in ipairs{'red','crystal','platinum','black'}do
 local f=require('tools.battle-source-runtime.fixture').new('firered')
 local b=f.fresh('TACKLE').battle
 require('src.core.GameVersion').set(edition)
 local order={};b.current=nil;b.queue={{fn=function()
  order[#order+1]='first';b:actNext(function()order[#order+1]='inserted'end)
 end},{fn=function()order[#order+1]='last'end}}
 b:updateQueue();b:updateQueue();b:updateQueue()
 T.eq(table.concat(order,','),'first,inserted,last',edition..' native queue order')
 T.eq(b.current,nil);T.eq(Switch.busy(),false)
 f.close();G.release()
end
Switch.update=base;package.loaded['src.core.Game']=original
T.finish('native switch queue admission, stable steps, holds, errors and once-only action dispatch')
