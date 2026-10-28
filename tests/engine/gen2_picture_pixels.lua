-- Actual existing engine entry points and emitted image calls. The old
-- engine can run this fixture without adding any new helper module.
-- This is a CPU draw-stream counterexample, not GPU pixel qualification.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Effects=require('src.battle.MoveEffects').primary
local before=Version.get()
local function make(edition,side,op)
 Version.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 data.moves.PROBE={id='PROBE',power=0,type='NORMAL',pp=10,name='PROBE'}
 data.battle_anims={gen2=true,moveAnims={PROBE=1},scripts={
  [1]={entry=1,code={{op='delay',frames=3},{op=op},{op='delay',frames=4},{op='ret'}}},
 }}
 require('src.render.Font').load(data)
 local save=require('src.core.SaveData').newGame()
 save.party={require('src.pokemon.Pokemon').new(data,'FIXMON_A',30)}
 local s=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
 s.queue,s.current,s.waitFrames={},nil,nil
 s.introSlide,s.sendingOut,s.enemySendingOut=0,false,false
 s.showPlayerBack,s.showEnemyTrainer=false,false
 local row={anim='PROBE',attackerIsPlayer=side=='player',animDelayed=true}
 s.queue[1],s.moveAnimRow=row,row
 return s,s[side],s[side=='player'and'enemy'or'player'],row
end
local calls,draw={},love.graphics.draw
love.graphics.draw=function(image,...)calls[#calls+1]=image;return draw(image,...)end
local function capture(s,b,expected,label)
 calls={};s:drawPicsLayer(0,0,0,b.isPlayer and 'player'or'enemy',true)
 T.eq(#calls,1,label..' emits exactly one image')
 T.eq(calls[1],expected,label..' emits correct picture, not metadata alone')
 if s.drawPic then
  calls={};s:drawPic(b.mon,b.isPlayer)
  T.eq(#calls,1,label..' public capture emits exactly one image')
  T.eq(calls[1],expected,label..' public capture shares actual image owner')
 end
end
local function command(s,side,expected)
 local n=0
 while s.anim.picOverride[side]~=expected and n<100 do s:updateQueue();n=n+1 end
 T.check(n>0 and n<100,'native queue reaches actual image opcode')
end
for _,edition in ipairs({'gold','silver','crystal'})do for _,side in ipairs({'player','enemy'})do
 local s,b,target=make(edition,side,'transform')
 local old=s:picImage(b.sprite)
 Effects.TRANSFORM_EFFECT(s,b,target)
 local replacement=s:picImage(b.sprite)
 T.neq(old,replacement,'fixture uses distinct real image owners')
 capture(s,b,old,'queued Transform')
 s:updateQueue();capture(s,b,old,'pre-command Transform')
 command(s,side,'transform')
 capture(s,b,replacement,'post-command Transform')
 T.eq(b.mon.species,side=='player'and'FIXMON_A'or'FIXMON_C','actual saved identity is retained')

 s,b=make(edition,side,'raisesub');old=s:picImage(b.sprite)
 Effects.SUBSTITUTE_EFFECT(s,b)
 capture(s,b,old,'queued Substitute')
 s:updateQueue();capture(s,b,old,'pre-command Substitute')
 command(s,side,'substitute')
 calls={};s:drawPicsLayer(0,0,0,side,true)
 T.eq(#calls,1,'post-command Substitute emits actual doll')
 T.neq(calls[1],old,'doll image is distinct from normal Pokemon')

 s,b=make(edition,side,'dropsub');b.substituteHP=17;old=s:picImage(b.sprite)
 s:updateQueue();command(s,side,false)
 capture(s,b,old,'explicit dropsub despite retained substitute HP')
 T.eq(b.substituteHP,17,'image command retains real combat substitute')

 local row
 s,b,target,row=make(edition,side,'beatup')
 row.animParam=207;s.data.pokemon[target.mon.species].index=207
 replacement=s:picImage(s:speciesSprite(target.mon.species,b.isPlayer))
 s:updateQueue()
 local n=0
 while not s.anim.picOverride[side]and n<100 do s:updateQueue();n=n+1 end
 T.check(n>0 and n<100,'native Beat Up opcode actually runs')
 capture(s,b,replacement,'Beat Up species 207 outside party slots')
end end
love.graphics.draw=draw
Version.set(before)
T.finish('actual native GSC picture draw-stream parity')
