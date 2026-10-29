package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Player=require('src.battle.Gen2AnimPlayer')
local View=require('src.battle.Gen2AnimView')
local previous=Version.get()
for _,edition in ipairs({'gold','silver','crystal'})do
 Version.set(edition)
 local data={battle_anims={gen2=true,moveAnims={FIX_MOVE=1},misc={throwPokeBall=0x100,sendOutMon=0x101},
  scripts={[1]={entry=1,code={{op='delay',frames=1},{op='ret'}}},
   [0x100]={entry=1,code={{op='delay',frames=2},{op='ret'}}},
   [0x101]={entry=1,code={{op='delay',frames=3},{op='ret'}}}}}}
 for _,id in ipairs({'TOSS_ANIM','GREATTOSS_ANIM','ULTRATOSS_ANIM','BLOCKBALL_ANIM','POOF_ANIM','SHINY_ANIM','FIX_MOVE'})do
  local p=Player.new(data);p:start(id,true,{ballIndex=4})
  local projections=0;local project=p.oam
  p.oam=function(self,...)projections=projections+1;return project(self,...)end
  local r=View.runner(p);p.presentation=r
  local expected=id=='FIX_MOVE'and id or(id=='POOF_ANIM'or id=='SHINY_ANIM')and'ANIM_SEND_OUT_MON'or'ANIM_THROW_POKE_BALL'
  T.eq(r.animId,expected,'observation identifies the actual native ROM program')
  T.eq(p.moveId,id,'native queue/ball parameter identity is preserved')
  T.eq(p.enemySide,id=='POOF_ANIM'or id=='SHINY_ANIM','native send-out side correction is preserved')
  if id=='SHINY_ANIM'then T.eq(p.vars.param,1,'native shiny parameter is preserved')
  elseif id=='BLOCKBALL_ANIM'then T.eq(p.vars.param,0,'native trainer block parameter is preserved')
  elseif id~='POOF_ANIM'and id~='FIX_MOVE'then T.eq(p.vars.param,4,'native ball item parameter is preserved')end
  for _=1,100 do
   local name,frames,var,stopped,kept=r.animId,r.frames,r.var,r.stopped,r.keepSprites
  end
  T.eq(r.frames,p.frames,'repeated scalar reads observe native time')
  T.eq(projections,0,'scalar queries never project OAM')
  T.eq(#r.objects.structs,10,'real object pool retains all ten hardware slots')
  T.eq(r.objects:activeCount(),0,'idle hardware slots are empty')
  T.eq(r,p.runtime,'public runner is the actual native interpreter')
  T.eq(projections,0,'object metadata queries never project OAM')
  r:oam();T.eq(projections,0,'real OAM is already emitted by the VM, with no draw-time projection')
  local before=p.frames;p:update();T.eq(r.frames,p.frames,'live frame observation advances with VM')
  T.eq(p.frames,before+1,'observation does not advance the clock')
  p:start('FIX_MOVE',false)
  T.eq(r.animId,expected,'retired observation preserves original resolved program')
  T.eq(projections,0,'old runner keeps its own OAM without retirement projection')
  r.retire();T.eq(projections,0,'repeated retirement does not rebuild sprites')
 end
 local p=Player.new(data)
 data.battle_anims.moveAnims.TOSS_ANIM=1
 p:start('TOSS_ANIM',true)
 T.eq(View.runner(p).animId,'TOSS_ANIM','different mod script cannot acquire native ball identity')
 data.battle_anims.scripts[0x100]=nil
 p:start('FIX_MOVE',true)
 T.eq(View.runner(p).animId,'FIX_MOVE','absent special programs never acquire invented identities')
end
Version.set(previous)
T.finish('native Gen2 animation identity and lazy observation')
