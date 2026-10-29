-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Source callbacks draw from the actual seeded link stream in every role.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Copy=require('src.mods.Merge').deepCopy
local P,N,L=require('src.link.Protocol'),require('src.link.Net'),require('src.link.LinkBattle')
local old=V.get()
for _,edition in ipairs{'gold','silver','crystal'}do
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 data.moves.QA_ENDURE={id='QA_ENDURE',name='QA ENDURE',power=0,type='NORMAL',accuracy=100,pp=20,effect='ENDURE_EFFECT'}
 local run=T.sdk.loadMods({'mods/source_rng'},{data=data,fs=T.sdk.memfs({
  ['mods/source_rng/manifest.json']='{"id":"source_rng","name":"Source RNG","version":"1.0.0","api":2,"entry":"main.lua","affects_link":true}',
  ['mods/source_rng/main.lua']=[[
   local mod=...
   local Model=require('src.battle.gen2.Battle')
   mod.exports.rows={}
   mod.events:on('battle.move_used',function(c)
    local model=c.battle.battle
    local rows=mod.exports.rows[c.battle]
    if not rows then rows={};mod.exports.rows[c.battle]=rows end
    rows[#rows+1]={name=c.user.mon.nickname,turn=model.turn,love=model.rng(16),
     cart=model.random(256),roller=Model.roller(model)(255)}
   end)
  ]],
 })})
 T.eq(#run.errors,0,'actual source callback consumer loads');T.link.prepare(data)
 local games={}
 for i=1,3 do
  local game=T.link.fakeGame(data,'FIXMON_A',{name='ROLE'..i,level=30})
  game.save.version=edition;game.save.party[1].nickname=i==1 and'HOST'or'GUEST'
  game.save.party[1].moves={{id='QA_ENDURE',pp=20}};games[i]=game
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
 for _=1,30000 do
  for i,game in ipairs(games)do
   require('src.core.Input').pressed=(i==3 or not roles[i].localHashes[2])and{a=true}or{}
   game.stack:update(1/60)
  end
  if a.localHashes[2]and b.localHashes[2]and s.turnCount==2 and s.phase=='waitBoth'then break end
 end
 for turn=1,2 do
  T.check(a.localHashes[turn]~=nil and b.localHashes[turn]~=nil,'actual source-consumer link turn completes')
  T.eq(a.localHashes[turn],b.localHashes[turn],'source RNG calls preserve native lockstep')
  T.same(a.localParts[turn],b.localParts[turn],'every completed native state component agrees')
 end
 local rows=run.loader.exports.source_rng.rows
 T.same(rows[a],rows[b],'both participants observe the same source RNG results')
 T.same(rows[a],rows[s],'spectator observes the same source RNG results')
 for _,battle in ipairs(roles)do
  T.eq(#(rows[battle]or{}),4,'every actual move callback reads all three source RNG domains')
  for index,row in ipairs(rows[battle]or{})do
   T.eq(row.turn,math.floor((index-1)/2)+1,'actual participant/spectator moves observe the same native round')
   T.check(row.love>=1 and row.love<=16,'source LOVE call retains its positive range')
   T.check(row.cart>=0 and row.cart<256,'source random retains its byte range')
   T.check(row.roller>=0 and row.roller<255,'source roller retains its nonzero-byte-index range')
  end
  T.eq(battle.player.mon.moves[1].pp,18,'own native moves spend PP once despite source random calls')
  T.eq(battle.enemy.mon.moves[1].pp,18,'other native moves spend PP once despite source random calls')
  T.eq(battle.result,nil,'no hidden link simulation error')
 end
 T.eq(#run.errors,0,'no source callback failure is swallowed')
 run.release()
end
V.set(old)
T.finish('actual source RNG callbacks in native GSC link participant and spectator roles')
