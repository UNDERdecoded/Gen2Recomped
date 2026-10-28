-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Intro=require('src.core.game3.battle.intro_seq')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local base=Intro.update;local original=package.loaded['src.core.Game']
local function pack(...)return{n=select('#',...),...}end
local function fresh(edition,kind)
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 package.loaded['src.core.Game']=f.game
 local b=f.fresh('TACKLE').battle
 if kind then b.kind=kind end
 f.game.stack:push(b)
 return f,b
end
local function close(f)
 f.game.stack:pop();Intro._service.release();Battle._service.release();f.close();G.release()
end
local function proposal(steps)
 local out={}
 for i,step in ipairs(steps)do out[i]={kind=step.kind,data={}}
  for key,value in pairs(step.data)do
   if type(value)=='table'then local values={};for n,item in ipairs(value)do values[n]=item end;value=values end
   out[i].data[key]=value
  end
 end
 return out
end
T.eq(base(),nil);T.eq(Intro.busy(),false);T.eq(Intro.introText({}),nil);T.eq(Intro.sendOutText({},'player'),nil)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 -- Real native enter builds every message, action, sound, shiny and throw
 -- row. The source step list must not retain a row, function or battler.
 local f,b=fresh(edition)
 local game=f.game;local view=Battle.getState();local steps=Intro._steps
 T.eq(Intro._st,view);T.eq(Intro.busy(),true);T.eq(Intro._i,1);T.eq(Intro._waiting,false)
 T.eq(steps,Intro._steps);T.eq(steps[1].kind,'bgslide')
 T.eq(steps[1].data.slideFrames,b.introSlide)
 T.eq(steps[1].data.unlockAt,b.frlgIntro and b.frlgIntro.hold or 0)
 T.eq(Intro.introText(view),b.introText);T.eq(Intro.sendOutText(view,'player'),b:sendOutText(b.player.name))
 local throw,go
 for _,step in ipairs(steps)do
  T.eq(step.fn,nil);T.eq(step.data.mon,nil)
  if step.kind=='player_throw'then throw=step end
  if step.kind=='msg'and step.data.text==Intro.sendOutText(view,'player')then go=step end
 end
 T.neq(throw,nil);T.eq(throw.data.ids[1],0);T.neq(go,nil)
 T.eq(#steps,#b.queue+1,'only actual native entry rows are described')
 local queued={};for i,row in ipairs(b.queue)do queued[i]=row end
 local tooLong=proposal(steps);tooLong[1].data.slideFrames=100000
 T.raises(function()Intro._steps=tooLong end,'shorten')
 local changed=proposal(steps);changed[2].kind='player_throw'
 T.raises(function()Intro._steps=changed end,'identity')
 local unread=proposal(steps);unread[#unread].data.injected=true
 T.raises(function()Intro._steps=unread end,'read-only')
 local oldFrames,oldSlide=steps[1].data.frames,steps[1].data.slideFrames
 steps[1].data.frames,steps[1].data.slideFrames=100000,100000
 T.raises(function()Intro._steps=proposal(steps)end,'shorten')
 steps[1].data.frames,steps[1].data.slideFrames=oldFrames,oldSlide
 local fast=proposal(steps);fast[1].data={frames=1,slideFrames=1,unlockAt=0,
  playerFrom=0,enemyFrom=0,enemyMonFrom=0}
 Intro._steps=fast;T.eq(b.introSlide,1);T.eq(b.frlgIntro and b.frlgIntro.hold or 0,0)
 for i,row in ipairs(b.queue)do T.eq(row,queued[i],'shortening never rebuilds the native queue')end
 local frame=b.frame;local hp,pp=b.player.mon.hp,b.player.mon.moves[1].pp
 Intro.update=function()return false end
 b:update(1/60);T.eq(b.frame,frame);T.eq(b.introSlide,1);T.eq(Intro._i,1)
 Intro.update=function()base();return base()end
 b:update(1/60);T.eq(b.frame,frame+1,'multiple base calls borrow one native frame')
 T.eq(b.introSlide,0);T.eq(b.player.mon.hp,hp);T.eq(b.player.mon.moves[1].pp,pp)
 T.raises(function()Intro._steps=fast end,'already started')
 T.eq(base(),nil,'source cannot advance native time outside its callback')
 Intro.update=function()error('intro source before native')end
 frame=b.frame;T.raises(function()b:update(1/60)end,'intro source before native');T.eq(b.frame,frame)
 Intro.update=function()base();error('intro source after native')end
 T.raises(function()b:update(1/60)end,'intro source after native');T.eq(b.frame,frame+1)
 local tick=b.tickFx;b.tickFx=function()error('native intro failed')end
 Intro.update=function()pcall(base);return true end
 T.raises(function()b:update(1/60)end,'native intro failed');b.tickFx=tick
 local rejected
 Intro.update=function()game.stack:push({});local a,why=base();rejected=why;game.stack:pop();return a,why end
 frame=b.frame;local a=b:update(1/60);T.eq(a,false);T.eq(rejected,'native intro admission changed');T.eq(b.frame,frame)
 Intro.update=function()error('covered battle must not call intro wrapper')end
 game.stack:push({});b:update(1/60);game.stack:pop();T.eq(b.frame,frame)
 local seams=require('src.mods.ModSeams');local owner=G._callbackOwner()
 Intro.update=function()T.eq(G._callbackOwner(),'intro_owner');return base()end
 seams._journal[#seams._journal+1]={tbl=Intro,key='update',after=Intro.update,owner='intro_owner'}
 b:update(1/60);table.remove(seams._journal);T.eq(G._callbackOwner(),owner)
 Intro._service.releaseOwner(nil,'unrelated');T.eq(Intro.busy(),true)
 Intro._service.releaseOwner(nil,'intro_owner');T.eq(Intro.busy(),false)
 Intro.update=function()error('retired observers cannot hold the native entry')end
 frame=b.frame;b:update(1/60);T.eq(b.frame,frame+1)
 Intro.update=base;close(f);T.eq(Intro._steps,nil);T.eq(Intro._st,nil)
 -- Native module-absent/default/wrapped entry traces have the same clock,
 -- slide, queue and text typing state through the initial FRLG hold.
 local traces={}
 for _,mode in ipairs{'absent','default','wrapped'}do
  if mode=='absent'then package.loaded['src.core.game3.battle.intro_seq']=nil
  else package.loaded['src.core.game3.battle.intro_seq']=Intro end
  Intro.update=mode=='wrapped'and function()base();return base()end or base
  local current,screen=fresh(edition);local rows={}
  for _=1,45 do screen:update(1/60);rows[#rows+1]=table.concat({screen.frame,screen.introSlide,
   screen.frlgIntro and screen.frlgIntro.hold or 0,#screen.queue,screen.charIndex or -1},':')end
  traces[mode]=table.concat(rows,'|');close(current)
 end
 T.eq(traces.default,traces.absent,edition..' default entry trace')
 T.eq(traces.wrapped,traces.absent,edition..' wrapped entry trace')
 package.loaded['src.core.game3.battle.intro_seq']=Intro;Intro.update=base
 local entry,screen=fresh(edition,'trainer')
 local enemyMessage=Intro.sendOutText(Battle.getState(),'enemy');local enemyStep
 for _,step in ipairs(Intro._steps)do if step.kind=='opponent_sendout'then enemyStep=step end end
 T.neq(enemyMessage,nil);T.neq(enemyStep,nil);T.eq(enemyStep.data.ids[1],1)
 local values=pack(Intro._nativeUpdate(screen,1/60,function()return nil,7,nil end))
 T.eq(values.n,3);T.eq(values[1],nil);T.eq(values[2],7);T.eq(values[3],nil)
 -- Public metadata is detached: mutating it cannot widen the real native
 -- slide budget or turn a message into an executable action.
 local live=Intro._steps;live[1].data.frames=100000;live[1].data.slideFrames=100000
 T.raises(function()Intro._steps=proposal(live)end,'already started')
 local goRow,throwRow
 for _,row in ipairs(screen.queue)do
  if row.text==Intro.sendOutText(Battle.getState(),'player')then goRow=row end
  if row._sourceIntroKind=='player_throw'then throwRow=row end
 end
 T.neq(goRow,nil);T.neq(throwRow,nil)
 screen.introSlide=0;if screen.frlgIntro then screen.frlgIntro.hold=0 end
 screen.queue={throwRow};screen:startMessage(goRow)
 local cursor=Intro._i
 T.raises(function()Intro._waitingMsg=false end,'not complete')
 screen.charIndex=screen.total;screen.scrollPx=nil
 T.raises(function()Intro._i=cursor+2 end,'cannot skip')
 Intro._waitingMsg=false;Intro._waiting=false;Intro._i=cursor+1
 T.eq(screen.current,nil);T.eq(screen.queue[1],throwRow);T.eq(#screen.queue,1)
 T.eq(Intro._steps[Intro._i].kind,'player_throw','acknowledgment does not consume the native throw')
 local admission
 Intro.update=function()
  local saved=entry.game.save;entry.game.save={}
  local ok,why=base();admission=why;entry.game.save=saved;return ok,why
 end
 local frame=screen.frame;screen:update(1/60)
 T.eq(admission,'native intro admission changed');T.eq(screen.frame,frame)
 T.eq(Intro._steps,nil,'a replaced cohort retires native intro observations')
 Intro.update=base
 close(entry)
end
-- Exercise the real clock/UI composition too. Intro holds must leave the
-- already-owned presentation task alive, and repeated pump/base calls must
-- not tick either native owner twice.
local Anim=require('src.core.game3.battle.anim')
local Ui=require('src.core.game3.battle.ui');local pump=Ui.pump
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f,b=fresh(edition);local samples=0
 Anim.tweenStage(3,function()samples=samples+1 end)
 Ui.pump=function(...)pump(...);return pump(...)end
 Intro.update=function()base();return base()end
 local frame=b.frame;b:update(1/60);T.eq(b.frame,frame+1);T.eq(samples,1)
 Intro.update=function()return false end
 b:update(1/60);T.eq(b.frame,frame+1);T.eq(samples,2)
 Intro.update=base;b:update(1/60);T.eq(b.frame,frame+2);T.eq(samples,3)
 Ui.pump=pump;Intro.update=base;close(f);Anim._service.release()
end
-- Retained public steps cannot keep a completed native entry/session alive.
local function retired()
 local f,b=fresh('firered');local steps=Intro._steps;local game=f.game
 local weak=setmetatable({game,game.save,game.data,b,b._sourceIntroSequence},{__mode='v'})
 close(f);package.loaded['src.core.Game']=original
 return steps,weak
end
local retained,weak=retired();require('src.render.Font').load(T.fixtures.fresh())
for _=1,4 do collectgarbage('collect')end
for i=1,5 do T.eq(weak[i],nil,'retained entry steps release owner '..i)end
T.eq(retained[1].kind,'bgslide');Intro.update=base;package.loaded['src.core.Game']=original
T.finish('actual native intro rows, presentation shortening, shared update and observer retirement')
