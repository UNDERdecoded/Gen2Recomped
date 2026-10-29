-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Actual participant/spectator queues must share GSC order and RNG ownership.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Copy=require('src.mods.Merge').deepCopy
local H=require('src.link.Handshake')
local P,N,L=require('src.link.Protocol'),require('src.link.Net'),require('src.link.LinkBattle')
local old=V.get()
for _,edition in ipairs{'gold','silver','crystal'}do
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 data.moves.QA_PROTECT={id='QA_PROTECT',name='QA PROTECT',power=0,type='NORMAL',accuracy=100,pp=20,effect='PROTECT_EFFECT'}
 local run=T.sdk.loadNone({data=data});T.link.prepare(data)
 local games={}
 for i=1,3 do
  local game=T.link.fakeGame(data,'FIXMON_A',{name='ROLE'..i,level=30})
  game.save.version=edition;game.save.party[1].moves={{id='QA_PROTECT',pp=20}}
  games[i]=game
 end
 local hello=H.hello(games[1],'battle');local legacy=Copy(hello);legacy.nativeBattleRevision=nil
 T.eq(hello.nativeBattleRevision,'gsc-1','GSC advertises changed command/RNG semantics')
 T.eq(H.checkCompat(hello,legacy),'subset','legacy GSC cannot enter changed lockstep')
 T.eq(H.checkCompat(legacy,hello),'subset','GSC command mismatch is symmetric')
 for _,host in ipairs{false,true}do
  local state=setmetatable({game=games[1],myHello=hello,peerHello=legacy},{__index=require('src.link.LinkState')})
  state:decideCompat('battle',host)
  T.eq(state.stage,'notice','actual admission refuses old commands before exchange')
 end
 local na,nb=N.loopbackPair();local inbox={}
 local sn={update=function()end,poll=function()local packets=inbox;inbox={};return packets end}
 for i,net in ipairs{na,nb}do
  local send,side=net.send,i==1 and'host'or'guest'
  net.send=function(self,packet)inbox[#inbox+1]={type='spectate',side=side,msg=Copy(packet)};return send(self,packet)end
 end
 local pa,pb=P.packParty(games[1].save.party),P.packParty(games[2].save.party)
 local a=assert(L.newHost(games[1],na,{myParty=pa,theirParty=pb,theirName='GUEST',seed=327,verdict='full',strict=true}))
 local b=assert(L.newGuest(games[2],nb,{myParty=pb,theirParty=pa,theirName='HOST',seed=327,verdict='full',strict=true}))
 local s=assert(L.newSpectator(games[3],sn,{hostParty=pa,guestParty=pb,hostName='HOST',guestName='GUEST',seed=327,verdict='full',strict=true}))
 local roles={a,b,s}
 for i,battle in ipairs(roles)do games[i].stack:push(battle)end
 for _=1,20000 do
  for i,game in ipairs(games)do
   require('src.core.Input').pressed=(i==3 or not roles[i].localHashes[1])and{a=true}or{}
   game.stack:update(1/60)
  end
  if a.localHashes[1]and b.localHashes[1]and s.turnCount==1 and s.phase=='waitBoth'then break end
 end
 T.check(a.localHashes[1]~=nil and b.localHashes[1]~=nil,'both actual participant queues complete')
 T.eq(a.localHashes[1],b.localHashes[1],'GSC protection RNG and state hashes agree')
 T.same(a.localParts[1],b.localParts[1],'all completed native state components agree')
 for _,battle in ipairs(roles)do
  local x,y=battle.player.protectRun,battle.enemy.protectRun
  T.check(x==1 and y==0 or x==0 and y==1,'only actual first actor succeeds; second clears its counter')
  T.eq(battle.player.mon.moves[1].pp,19,'own first-round move spends PP exactly once')
  T.eq(battle.enemy.mon.moves[1].pp,19,'other first-round move spends PP exactly once')
  T.eq(battle.result,nil,'no hidden participant/spectator error')
 end
 T.eq(s.player.protectRun,a.player.protectRun,'spectator preserves host protection owner')
 T.eq(s.enemy.protectRun,a.enemy.protectRun,'spectator preserves guest protection owner')
 run.release()
end
V.set(old)
T.finish('native GSC protection participant, spectator and protocol admission')
