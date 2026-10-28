package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Effects=require('src.battle.MoveEffects').primary
local Pictures=require('src.battle.Gen2PicturePresentation')
local before=Version.get()
local function make(edition,side,op)
  Version.set(edition)
  local data=T.fixtures.fresh();data.constants.gen=2
  data.moves.PIC_TEST={id='PIC_TEST',name='PICTURE TEST',type='NORMAL',pp=10,power=0}
  data.battle_anims={gen2=true,moveAnims={PIC_TEST=1},scripts={
    [1]={entry=1,code={{op='delay',frames=3},{op=op},{op='delay',frames=3},{op='ret'}}},
  }}
  require('src.render.Font').load(data)
  local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
  local s=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
  s.queue,s.current,s.waitFrames={},nil,nil
  s.introSlide,s.sendingOut,s.enemySendingOut=0,false,false
  s.showPlayerBack,s.showEnemyTrainer=false,false
  local row={anim='PIC_TEST',attackerIsPlayer=side=='player',animDelayed=true}
  s.queue[1],s.moveAnimRow=row,row
  return s,s[side],s[side=='player'and'enemy'or'player'],row
end
local function endAnim(s)
  local count=0
  while s.animPlaying and count<120 do s:updateQueue();count=count+1 end
  T.check(count<120,'picture program releases its native queue')
end
for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 for _,side in ipairs({'player','enemy'})do
  local s,b,target,row=make(edition,side,'transform')
  local sprite,species,hp,pp=b.sprite,b.mon.species,b.mon.hp,b.curMoves[1].pp
  local savedStats=b.mon.stats
  Effects.TRANSFORM_EFFECT(s,b,target)
  local copied=b.sprite
  T.neq(copied,sprite,'native effect resolves its replacement immediately')
  T.eq(b.curStats.attack,target.curStats.attack,'native copied combat stats are not delayed')
  T.eq(b.mon.stats,savedStats,'saved stats retain their owner')
  T.eq(s:pictureStill(b),s:picImage(sprite),'queued view retains the actual preceding image')
  T.eq(s:battlerPic(b),s:picImage(sprite),'native drawer retains preceding image')
  if s.pic then
    T.eq(s:pic(b.mon,b.isPlayer),s:picImage(sprite),'same-side public capture retains preceding image')
    local front,_,path=s:pic(b.mon,false)
    T.check(path:find('fixmon_a',1,true)or path:find('fixmon_c',1,true),
      'opposite capture resolves an existing species path')
  end
  T.eq(Pictures.species(s,b),species,'queued front identity precedes actual transform command')
  s:updateQueue()
  T.eq(s.animPlaying,true,'actual native queue starts picture program')
  local r=s.anim
  T.eq(s._gen2PictureChanges[1].runner,r,'pin is bound to actual command interpreter')
  local ticks=0
  while r.picOverride[side]~='transform'and ticks<120 do
    T.eq(s:battlerPic(b),s:picImage(sprite),'all pre-command frames show preceding species')
    local frames=r.frames
    for _=1,3 do
      if s.pic then s:pic(b.mon,false)end
      s:animPicState(side);s:battlerPic(b)
    end
    T.eq(r.frames,frames,'drawing never advances the VM')
    s:updateQueue();ticks=ticks+1
  end
  T.check(ticks>0 and ticks<120,'actual transform opcode is reached')
  T.eq(s:battlerPic(b),s:picImage(copied),'the opcode reveals the actual replacement')
  T.eq(b.species,target.mon.species,'public species identity commits at that same command')
  T.eq(Pictures.species(s,b),target.mon.species,'opposite capture follows transformed identity')
  T.eq(#s._gen2PictureChanges,0,'revealed picture releases its transient pin')
  endAnim(s)
  T.eq(b.mon.species,species,'saved species is never transformed')
  T.eq(b.mon.hp,hp,'picture commands do not change HP')
  T.eq(b.curMoves[1].pp,5,'native Transform still supplies copied moves at five PP')
  T.eq(b.mon.moves[1].pp,pp,'saved PP is not consumed by picture reads')

  s,b,target,row=make(edition,side,'raisesub')
  local oldHP=b.mon.hp
  Effects.SUBSTITUTE_EFFECT(s,b)
  T.check(b.mon.hp<oldHP and b.substituteHP>0,'native substitute cost resolves before animation')
  T.eq(s:substituteVisible(b),false,'new doll is held until real raisesub command')
  T.eq(s:animPicState(side).pic,false,'explicit preceding normal picture is observable')
  s:updateQueue();r=s.anim;ticks=0
  while r.picOverride[side]~='substitute'and ticks<120 do
    T.eq(s:substituteVisible(b),false,'pre-command frames retain normal picture')
    s:updateQueue();ticks=ticks+1
  end
  T.check(ticks<120,'real raisesub command executes')
  T.eq(s:substituteVisible(b),true,'actual raisesub reveals doll')
  T.eq(#s._gen2PictureChanges,0,'doll reveal retires transient creation pin')
  endAnim(s)
  T.eq(s:substituteVisible(b),true,'native substitute survives animation cleanup')

  s,b=make(edition,side,'dropsub');b.substituteHP=17
  s:updateQueue();r=s.anim;ticks=0
  while r.picOverride[side]~=false and ticks<120 do s:updateQueue();ticks=ticks+1 end
  T.check(ticks<120,'actual dropsub command executes')
  T.eq(s:animPicState(side).pic,false,'false override survives public observation')
  T.eq(s:substituteVisible(b),false,'dropsub paints Pokemon despite positive combat substitute HP')
  local dolls,draw=0,s.drawSubstituteDoll
  s.drawSubstituteDoll=function()dolls=dolls+1 end
  if s.drawPic then s:drawPic(b.mon,false)
  else s:drawPicsLayer(0,0,0,side,true)end
  T.eq(dolls,0,'actual public capture no longer paints hidden doll')
  s.drawSubstituteDoll=draw
  T.eq(b.substituteHP,17,'temporary drawing never destroys combat substitute')
  endAnim(s)
  T.eq(s:substituteVisible(b),true,'finishing move restores native retained substitute')

  s,b=make(edition,side,'beatup')
  local species=b.mon.species
  local chosen=side=='player'and'FIXMON_C'or'FIXMON_A'
  s.data.pokemon[chosen].index=207 -- deliberately outside a six-member party
  row=s.queue[1];row.animParam=207
  s:updateQueue();r=s.anim;ticks=0
  while not r.picOverride[side]and ticks<120 do s:updateQueue();ticks=ticks+1 end
  T.check(ticks<120,'actual Beat Up command executes')
  T.eq(Pictures.species(s,b),chosen,'Beat Up wire byte resolves species, not party slot')
  T.eq(s:pictureStill(b),s:picImage(s:speciesSprite(chosen,b.isPlayer)),
    'native placement measures actual Beat Up image')
  T.eq(s:battlerPic(b),s:pictureStill(b),'native drawer uses actual Beat Up image')
  if s.pic then T.eq(s:pic(b.mon,b.isPlayer),s:pictureStill(b),'public same-side capture uses same image')end
  T.eq(b.mon.species,species,'Beat Up never replaces the active saved Pokemon')
  endAnim(s)
  T.eq(Pictures.species(s,b),species,'Beat Up temporary picture is released with native VM')
 end
end

-- Missing/disabled/cancelled programs and a real slot replacement cannot
-- leave a pinned picture hanging or repaint the incoming saved Pokemon.
for _,mode in ipairs({'disabled','missing','cancelled','stopped','new-program','replacement'})do
 local s,b,target,row=make('crystal','player','transform')
 local species=b.mon.species
 if mode=='disabled'then s.game.save.options.animations=false end
 if mode=='missing'then s.animPlayer.anims.scripts[1]=nil end
 Effects.TRANSFORM_EFFECT(s,b,target)
 if mode=='cancelled'then s:cancelMoveAnim();Pictures.sync(s)
 elseif mode=='replacement'then
   local incoming=Pokemon.new(s.data,'FIXMON_B',18)
   if s.switchPlayerInto then s:switchPlayerInto(Battle.POS.PLAYER_LEFT,incoming)
   else s.player={mon=incoming,isPlayer=true,sprite={}}end
   Pictures.sync(s)
   T.eq(s.player.mon,incoming,'native switch retains actual incoming mon')
   T.eq(Pictures.species(s,s.player),'FIXMON_B','old transform cannot repaint replacement slot')
 elseif mode=='stopped'then
   s:updateQueue();s.anim.stop=true;s:updateQueue()
 elseif mode=='new-program'then
   s:updateQueue()
   local retired=s.anim
   s:animForMove('PIC_TEST','enemy')
   T.neq(s.anim,retired,'public start creates a distinct real native runner')
   s:updateQueue()
   T.eq(retired.picOverride.player,nil,'replacing runner does not invent a retired transform opcode')
 else s:updateQueue()end
 T.eq(#(s._gen2PictureChanges or {}),0,mode..' releases native picture pin')
 if mode~='replacement'then T.eq(b.species,target.mon.species,mode..' commits resolved native visual identity')end
 T.eq(b.mon.species,species,mode..' retains saved species')
end
for _,disabled in ipairs({false,true})do
 local s,b,target,row=make('crystal','player','transform')
 local initial=s:picImage(b.sprite)
 Effects.TRANSFORM_EFFECT(s,b,target)
 local middle=b.sprite
 local second={anim='PIC_TEST',attackerIsPlayer=true,animDelayed=true}
 if not disabled then s.queue[2]=second;s.moveAnimRow=second end
 target.species='FIXMON_B'
 Effects.TRANSFORM_EFFECT(s,b,target)
 local final=b.sprite
 T.eq(s:battlerPic(b),initial,'two resolved transforms still show the original queued picture')
 if disabled then
  s.game.save.options.animations=false
  s:updateQueue()
 else
  s:updateQueue();local r=s.anim;local n=0
  while r.picOverride.player~='transform'and n<120 do s:updateQueue();n=n+1 end
  T.check(n<120,'first native transform opcode completes')
  T.eq(s:battlerPic(b),s:picImage(middle),'first command reveals only its own queued identity')
  endAnim(s)
  s:updateQueue();r=s.anim;n=0
  while r.picOverride.player~='transform'and n<120 do s:updateQueue();n=n+1 end
  T.check(n<120,'second native transform opcode completes')
 end
 T.eq(b.species,'FIXMON_B','native admission commits transforms in original queue order')
 T.eq(s:battlerPic(b),s:picImage(final),'last resolved visual remains after repeated transforms')
 T.eq(#s._gen2PictureChanges,0,'repeated transform pins retire completely')
 T.eq(b.mon.species,'FIXMON_A','repeated transforms cannot change the saved species')
end
for _,edition in ipairs({'red','emerald','firered'})do
 Version.set(edition)
 local s,b=make('crystal','player','dropsub');Version.set(edition)
 b.substituteHP=17;s.anim={picOverride={player=false}}
 T.check(s:substituteVisible(b),edition..' keeps its original substitute owner')
 T.eq(s:pictureSprite(b),b.sprite,edition..' keeps native image owner')
end
Version.set(before)
T.finish('native GSC command-time picture identity and substitute visibility')
