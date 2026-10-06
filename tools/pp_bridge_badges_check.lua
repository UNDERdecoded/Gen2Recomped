package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('PP, bridge, doubles and badges')
local V=require('src.core.GameVersion');local P=require('src.pokemon.Pokemon');local Effects=require('src.inventory.ItemEffects')
local F=require('src.render.Font');local printed={};F.draw=function(s) printed[#printed+1]=tostring(s) end;F.drawBox=function() end;F.width=function(s) return #tostring(s)*6 end;F.fit=function(s) return s end
local Summary=require('src.ui.Gen3SummaryMenu')
local data={moves={TACKLE={name='Tackle',pp=15,type='NORMAL'}},items={PP_UP={},PP_MAX={}},constants={gen3ItemEffects={PP_UP={ppUp=true},PP_MAX={ppMax=true}}}}
V.set('emerald')
local mon={moves={{id='TACKLE',pp=15}},friendship=70,hp=50,stats={hp=50}}
local save={inventory={PP_UP=3,PP_MAX=1}}
for ups=1,3 do
 T.eq(Effects.use(data,save,'PP_UP',mon,nil,1),'consumed','PP Up consumes')
 T.eq(mon.moves[1].ppUps,ups,'PP Up stage');T.eq(mon.moves[1].pp,P.maxPP(data.moves.TACKLE,mon.moves[1]),'new current PP equals new max')
 local s=setmetatable({mon=mon,game={data=data},rows=function() return {0,16,32,48} end,cols=function() return 0,100 end,windows=function() end},{__index=Summary})
 printed={};s:drawMoves(false)
 local wanted=tostring(mon.moves[1].pp)..'/'..tostring(P.maxPP(data.moves.TACKLE,mon.moves[1]));local found=false
 for _,text in ipairs(printed) do if text:find(wanted,1,true) then found=true end end
 T.check(found,'summary prints boosted denominator '..wanted)
end
T.eq(Effects.use(data,save,'PP_UP',mon,nil,1),'failed','fourth PP Up refused')
mon.moves[1]={id='TACKLE',pp=5};T.eq(Effects.use(data,save,'PP_MAX',mon,nil,1),'consumed','PP Max consumes')
T.eq(mon.moves[1].ppUps,3,'PP Max reaches three stages');T.eq(mon.moves[1].pp,14,'PP Max preserves PP deficit')
P.restorePP(mon,data.moves);T.eq(mon.moves[1].pp,24,'healing uses boosted cap')
local Badges=require('src.inventory.Badges');local SD=require('src.core.SaveData');local Serializer=require('src.core.SaveSerializer')
require('src.script.Gen4Commands');local C=require('src.script.Commands')
V.set('platinum')
local badgeData={isGen4Cache=true,constants={badges=Badges.list(nil,'platinum')},items={},pokemon={},moves={},maps={ROOM={}},field={boot={startMap='ROOM'}}}
for _,entry in ipairs(badgeData.constants.badges) do
 local sv={inventory={[entry.id]=1},flags={},party={},boxes={},player={map='ROOM'},badges={[entry.id]=true}}
 local report=SD.validate(sv,badgeData);T.eq(#report.lostItems,0,'legacy badge is migrated, not removed')
 T.check(sv.flags[entry.id] and not sv.inventory[entry.id],'badge lives outside bag')
 local restored=assert(Serializer.decode(Serializer.encode(sv)));SD.validate(restored,badgeData)
 T.check(Badges.has(restored,entry),'badge survives serialized save validation')
 T.eq(Badges.count(nil,restored,'platinum'),1,'launcher counts native badge without Data')
end
local sv={inventory={},flags={},player={map='ROOM'}};local ctx={save=sv,game={data=badgeData}}
C.g4_give_badge(ctx,0);SD.validate(sv,badgeData);C.g4_check_badge(ctx,0,0x4000);T.eq(sv.gen4Vars[0x4000],1,'story reads Coal Badge after validation')
Badges.set(sv,badgeData.constants.badges[1],false,'platinum');T.check(not Badges.has(sv,badgeData.constants.badges[1]),'badge editor removes all canonical stores')
local Collision=require('src.world.Collision')
for _,z in ipairs({3,4,5,6}) do T.check(not Collision.sameElevation({elevation=z},{elevation=1}),'bridge trainer cannot spot surfer') end
T.check(Collision.sameElevation({elevation=3},{elevation=3}),'same deck trainer sees player');T.check(Collision.sameElevation({elevation=0},{elevation=1}),'ROM wildcard elevation')
V.set('emerald');local Game=require('src.core.Game');Game.data={constants={}};Game.save={flags={}}
local OW=require('src.world.OverworldController')
for i=1,30 do
 local name=debug.getupvalue(OW.useSurfFieldMove,i)
 if name=='Game' then debug.setupvalue(OW.useSurfFieldMove,i,Game);break end
end
for _,z in ipairs({1,4,5,15}) do
 local ow=setmetatable({player={elevation=z},partyKnows=function() return {} end},{__index=OW})
 T.eq(ow:useSurfFieldMove(),'no_water','Surf from elevated deck refused');T.eq(ow:trySurf(1,1),false,'direct Surf route also guarded')
end
local ow=setmetatable({player={elevation=3,facingCell=function() return 1,1 end},partyKnows=function() return {} end,frlgFastWaterAt=function() return false end,facingIsShoreOrWater=function() return true end},{__index=OW})
T.eq(ow:useSurfFieldMove(),'ok','shoreline Surf still works')
local B=require('src.battle.Gen3Battle')
local battle={game={data={}},phase='menu',menuIndex=1,player={name='FIRST'},menuBattler=function() return {name='SECOND'} end}
printed={};B.drawTextArea(battle)
local seen=false;for _,s in ipairs(printed) do if s:find('SECOND',1,true) then seen=true end end
T.check(seen,'double command prompt names the choosing Pokemon')
V.set('emerald');battle.data=data;battle.game.data=data;battle.phase='moveSelect';battle.moveIndex=1
battle.menuBattler=function() return {curMoves=mon.moves} end
printed={};B.drawTextArea(battle)
local ppShown=false;for _,s in ipairs(printed) do if s:find('24/24',1,true) then ppShown=true end end
T.check(ppShown,'battle move details show the boosted PP denominator')
T.finish()
