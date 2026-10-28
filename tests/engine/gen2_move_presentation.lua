package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Sound=require('src.core.Sound')
local previous=Version.get()
local function make()
  local data=T.fixtures.fresh()
  data.moves.FIX_MOVE={id='FIX_MOVE',name='MOVE',power=20,type='NORMAL',pp=20}
  data.battle_anims={gen2=true,moveAnims={FIX_MOVE=1},scripts={
    [1]={entry=1,code={{op='delay',frames=2},{op='ret'}}},
    [0x10f]={entry=1,code={{op='delay',frames=3},{op='ret'}}},
    [0x110]={entry=1,code={{op='delay',frames=4},{op='ret'}}},
    [0x112]={entry=1,code={{op='delay',frames=5},{op='ret'}}},
    [0x113]={entry=1,code={{op='delay',frames=6},{op='ret'}}},
  }}
  require('src.render.Font').load(data)
  local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
  local game={data=data,save=save,stack={top=function()end}}
  local s=Battle.newWild(game,'FIXMON_C',23)
  s.queue,s.current,s.waitFrames={},nil,nil
  return s,game
end
for _,edition in ipairs({'gold','silver','crystal'})do
 Version.set(edition)
 for _,side in ipairs({'player','enemy'})do
  local s=make();local starts,ticks,entryCalls,tail,hits=0,0,0,0,0
  local start,update,entry=s.animPlayer.start,s.animPlayer.update,s.animForMove
  s.animPlayer.start=function(self,...)starts=starts+1;return start(self,...)end
  s.animPlayer.update=function(self,...)ticks=ticks+1;return update(self,...)end
  s.animForMove=function(self,id,who,param,...)
    entryCalls=entryCalls+1;T.eq(id,'FIX_MOVE','actual queued move reaches public owner')
    T.eq(who,side,'queued side remains native');T.eq(param,19,'queued param reaches real VM')
    return entry(self,id,who,param,...)
  end
  s.applyHitFx=function()hits=hits+1 end
  s.queue={{anim='FIX_MOVE',attackerIsPlayer=side=='player',animParam=19,animDelayed=true,hit={sfx='Damage'}},
    {fn=function()tail=tail+1 end}}
  local hp,pp=s.player.mon.hp,s.player.curMoves[1].pp
  s:updateQueue()
  T.eq(starts,1,'one native start per queue row');T.eq(entryCalls,1,'real queue calls source owner exactly once')
  T.eq(ticks,0,'starting does not invent a native logic frame')
  T.eq(s.animPlayer.vars.param,19,'actual native script parameter')
  T.eq(s.animId,nil,'presentation observation does not replace screen state')
  T.eq(s.anim.animId,'FIX_MOVE','screen observes actual running animation')
  T.eq(s.anims,s.data.battle_anims,'screen exposes actual native animation dataset')
  T.eq(s.animPlayer.enemySide,side=='enemy','native VM still owns mirroring')
  local frames=0
  while s.animPlaying and frames<200 do
    local before=ticks;s:updateQueue();frames=frames+1
    T.eq(ticks,before+1,'one native VM tick per held queue update')
    T.eq(tail,0,'pending command remains behind actual animation')
  end
  T.check(frames<200,'native move terminates')
  T.eq(hits,1,'native hit applies once after animation completes')
  T.eq(s.anim,nil,'finished animation releases live observation')
  s:updateQueue();T.eq(tail,1,'queue releases next command after animation')
  T.eq(s.player.mon.hp,hp,'presentation cannot change party HP')
  T.eq(s.player.curMoves[1].pp,pp,'presentation cannot spend PP')
  T.eq(starts,1,'draw/read completion never restarts VM')
 end
 for _,side in ipairs({'player','enemy'})do for _,kind in ipairs({'damage','statdown'})do
  local s=make();local sounds={};local play=Sound.play
  Sound.play=function(_,name)sounds[#sounds+1]=name end
  T.eq(s:animForMove('FIX_MOVE',side,7,20,kind),true,'native move with after-program starts')
  local name=s:afterAnimFor(side,kind)
  local observed=s.anim;local hops=0
  while s.animPlayer.moveId=='FIX_MOVE'and hops<200 do s:updateQueue();hops=hops+1 end
  T.check(hops<200,'after program starts when native first program ends')
  T.eq(s.animPlayer.moveId,name,'actual named ROM after-program runs')
  T.eq(s.animPlayer.enemySide,side=='enemy','after-program keeps native attacker side')
  T.eq(observed.animId,'FIX_MOVE','old observation retains original program identity')
  T.eq(s.anim.animId,name,'current observation follows actual new program')
  T.eq(s.pendingAfterAnim,nil,'after-program is consumed once')
  T.eq(#sounds,kind=='damage'and 1 or 0,'only damaging after-program plays hit sound')
  if kind=='damage'then T.eq(sounds[1],'Super_Effective','native sound spelling matches effectiveness')end
  while s.animPlaying and hops<400 do s:updateQueue();hops=hops+1 end
  T.check(hops<400,'after program terminates on native VM clock')
  T.eq(s.animPlaying,false,'after-chain releases native hold')
  Sound.play=play
 end end
 do
  local s,game=make();game.save.options.animations=false
  T.eq(s:animForMove('FIX_MOVE','player'),false,'native option skips real move scripts')
  T.eq(s:animForId('ANIM_ENEMY_DAMAGE','player'),true,'non-move animation keeps its native option exemption')
  local running=s.anim
  T.eq(s:animForId('ANIM_MISSING','player'),false,'unavailable ROM programs remain unavailable')
  T.eq(s.anim,running,'failed lookup cannot retire a real running observation')
  T.eq(s.anims.ids.ANIM_THROW_POKE_BALL,nil,'name metadata does not fabricate absent programs')
  T.eq(s.anims.ids.ANIM_ENEMY_DAMAGE,0x10f,'old native caches expose existing named ROM row')
 end
end
Version.set(previous)
T.finish('native Gen2 queued move owner and actual after-animation programs')
