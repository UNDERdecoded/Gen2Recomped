-- Real native move resolution -> queue -> VM -> picture/BG observations.
-- Programs are generated fixtures, not cartridge data or modified mods.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Catalog=require('src.battle.Gen2AnimCatalog')
local previous=Version.get()
local function make(edition,format)
  Version.set(edition)
  local data=T.fixtures.fresh();data.constants.gen=Version.generation()
  for _,id in ipairs{'FLY','DIG','SOLARBEAM','PROBE'}do
    data.moves[id]={id=id,name=id,type='NORMAL',power=1,accuracy=100,accuracyRaw=255,pp=10,
      effect=id=='PROBE'and 'NO_ADDITIONAL_EFFECT' or id=='SOLARBEAM'and 'CHARGE_EFFECT' or 'FLY_EFFECT'}
  end
  local main={entry=1,code={
    {op='ifparamequal',args={1},to=7},
    {op='delay',frames=3},
    {op='bgeffect',args={'BATTLE_BG_EFFECT_SHOW_MON',0,1,0}},
    {op='delay',frames=8},{op='ret'},{op='ret'},
    {op='delay',frames=3},
    {op='bgeffect',args={'BATTLE_BG_EFFECT_REMOVE_MON',0,1,0}},
    {op='delay',frames=45},{op='ret'},
  }}
  local probe={entry=1,code={
    {op='bgeffect',args={'BATTLE_BG_EFFECT_SHOW_MON',0,0,0}},
    {op='bgeffect',args={'BATTLE_BG_EFFECT_BATTLEROBJ_1ROW',0,0,0}},
    {op='delay',frames=8},{op='ret'},
  }}
  local anims={gen2=true,moveAnims={FLY=1,DIG=1,SOLARBEAM=1,PROBE=2},scripts={[1]=main,[2]=probe},
    objects={},framesets={},oam={},gfx={}}
  anims.functions={[0]='Null'}
  anims.framesets[0]={frames={{oam=0,duration=1}},loop='restart'}
  anims.oam[0]={tile=0,sprites={{x=0,y=0,tile=0,attr=0}}}
  for index,name in ipairs(require('src.battle.Gen2AnimObjectIds').battleAnimObjectOrder)do
    if name=='BATTLE_ANIM_OBJ_PLAYERHEAD_1ROW' or name=='BATTLE_ANIM_OBJ_ENEMYFEET_1ROW'then
      anims.objects[index-1]={oamFlags=0,fixY=255,fn=0,frameset=0,palette=0,gfx=0}
    end
  end
  if format=='native'then
    anims=Catalog.compile(anims,nil,edition)
    anims.gen2,anims.format,anims.moveAnims,anims.indices,anims.misc=nil,nil,nil,nil,nil
  end
  data.battle_anims=anims
  require('src.render.Font').load(data)
  local save=Save.newGame();save.options.textSpeed=1
  save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',18)}
  local s=Battle.newWild({data=data,save=save,stack={top=function()end},
    input={wasPressed=function()return true end,isDown=function()return true end}},'FIXMON_C',23)
  s.queue,s.current,s.waitFrames={},nil,nil
  s.introSlide,s.sendingOut,s.enemySendingOut=0,false,false
  s.showPlayerBack,s.showEnemyTrainer=false,false
  s.rngCalls=0;s.rng=function()s.rngCalls=s.rngCalls+1;return 0 end
  return s
end
local function untilState(s,predicate,label)
  local frames=0
  while not predicate() and frames<1500 do s:updateQueue();frames=frames+1 end
  T.check(frames<1500,label)
  return frames
end
local function drained(s)
  return #s.queue==0 and not s.current and not s.animPlaying and (s.waitFrames or 0)<=0
    and not s.draining
end
local function finish(s)untilState(s,function()return drained(s)end,'native queue and VM release')end
local function pictureHidden(s,side)
  local state=s:animPicState(side);return state and state.hidden or false
end
local function underground(s,side,mon)
  return s.isUnderground and s:isUnderground(side,mon) or false
end
local function release(s,id,side,move)
  local p=s._gen2VanishPictures and s._gen2VanishPictures[side]
  s:act(function()
  s:performMove(s[side],s[side=='player'and'enemy'or'player'],move)
  if id~='SOLARBEAM'then
    T.eq(p and p.phase,'release','actual release retains the preceding cleared box')
    T.eq(p and p.row,s.moveAnimRow,'release latch binds the real native row')
  end
  end)
  untilState(s,function()return s.animPlaying end,'actual release program starts')
  if id~='SOLARBEAM'then
    T.eq(s._gen2VanishPictures[side],p,'release admission retains its original picture latch')
    T.eq(p and p.runner,s.animPlayer.runtime,'release admission binds its actual VM')
  end
  T.eq(s.animPlayer.moveId,id,'release uses the actual move')
  T.eq(s.animPlayer.vars.param,0,'release uses cartridge param zero')
end
for _,edition in ipairs{'gold','silver','crystal'}do
 for _,format in ipairs{'flat','native'}do for _,side in ipairs{'player','enemy'}do
  for _,id in ipairs{'FLY','DIG','SOLARBEAM'}do
    local s=make(edition,format)
    local b,target=s[side],s[side=='player'and'enemy'or'player']
    local move={id=id,pp=10};b.curMoves={move}
    local expectedPP=not b.isPlayer and s.kind~='link' and s.ruleset
      and s.ruleset.enemyUnlimitedPP and 10 or 9
    local hp=b.mon.hp
    s:performMove(b,target,move)
    T.eq(b.charging,move,'native first charge retains the original instance')
    T.eq(move.pp,expectedPP,'first charge keeps the native side PP policy')
    T.eq(b.invulnerable==true,id~='SOLARBEAM','only real Fly/Dig charge hides the battler')
    local rows={};for _,row in ipairs(s.queue)do if row.anim then rows[#rows+1]=row end end
    T.eq(#rows,1,'charge has one animation, no legacy extra clock')
    T.eq(rows[1].anim,id,'charge uses its own ROM program, never a Gen1 substitute')
    T.eq(rows[1].animParam,1,'first charge selects the real param-1 arm')
    untilState(s,function()return s.animPlaying end,'actual queued charge program starts')
    T.eq(s.animPlayer.moveId,id,'native queue starts the move itself')
    T.eq(s.animPlayer.vars.param,1,'actual interpreter sees charge parameter')
    T.eq(underground(s,side),false,'takeoff/burrow still starts with a visible battler')
    T.eq(s.animPlayer.runtime.env.flying[side],false,'first charge SHOW_MON can still use the battler')
    local r=s.anim
    finish(s)
    local vanished=id~='SOLARBEAM'
    T.eq(underground(s,side),vanished,'picture disappears only after native charge animation')
    T.eq(pictureHidden(s,side),vanished,'actual public picture state follows the native latch')
    local calls=s.rngCalls
    for _=1,3 do underground(s,side);s:animPicState(side);if s.pic then s:pic(b.mon,false)end end
    T.eq(s.rngCalls,calls,'picture reads never consume battle RNG')
    T.eq(b.mon.hp,hp,'charge/picture reads retain native HP')
    T.eq(move.pp,expectedPP,'picture reads never spend additional PP')
    T.eq(r.env.flying[side],false,'retained first runner keeps its admission snapshot')
    release(s,id,side,move)
    T.eq(b.charging,nil,'native release clears its original charge instance')
    T.eq(b.invulnerable,nil,'native release clears invulnerability before animation')
    T.eq(move.pp,expectedPP,'native second turn spends no extra PP')
    T.eq(pictureHidden(s,side),vanished,'release stays absent during pre-SHOW_MON wait')
    T.eq(s.animPlayer.runtime.env.flying[side],false,'release SHOW_MON is admitted after real flag clears')
    local current=s.anim
    untilState(s,function()return current.bg.picSize[side]~=nil end,'real native SHOW_MON executes')
    T.eq(pictureHidden(s,side),false,'SHOW_MON reveals the same native battler')
    T.eq(current.frames,5,'reveal uses the VM wait, no invented presentation clock')
    finish(s)
    T.eq(underground(s,side),false,'release retires cleared picture latch')
    T.eq(next(s._gen2VanishPictures or {}),nil,'completed native release retains no stale battler owner')
    s.animPlayer:release()
  end
  -- A move aimed at a genuinely vanished target must not copy its battler
  -- rows into OBJ or reveal the target's BG box (both read the same flags).
  local s=make(edition,format)
  local b=s[side];local other=side=='player'and'enemy'or'player'
  local move={id='DIG',pp=10};b.curMoves={move}
  s:performMove(b,s[other],move);finish(s)
  T.check(underground(s,side,b.mon),'optional source mon resolves actual active slot')
  T.eq(underground(s,side,{}),false,'an unrelated mon cannot borrow active volatile state')
  T.check(s:animForMove('PROBE',other),'actual opposing native move starts')
  local r=s.anim
  T.eq(r.env.flying[side],true,'the real opposing VM sees the hidden target')
  s:updateQueue();s:updateQueue();s:updateQueue()
  T.eq(r.bg.picSize[side],nil,'CheckFlyDigStatus suppresses actual SHOW_MON')
  T.eq(r.bg.liftedRows[side],nil,'hidden target contributes no lifted BG rows')
  T.eq(r.objects:activeCount(),0,'hidden target contributes no battler-row OBJ')
  finish(s)
  b.invulnerable=nil;b.hiddenAs=nil;s:updateQueue()
  T.eq(underground(s,side),false,'native cancellation removes visibility flag')
  T.eq(r.env.flying[side],true,'retained VM snapshot never follows future combat flags')
  T.check(s:animForMove('PROBE',other),'next opposing program has a fresh native runner')
  T.eq(s.anim.env.flying[side],false,'fresh runner reads the cleared actual flag')
  s:updateQueue();s:updateQueue()
  T.check(s.anim.bg.picSize[side]~=nil,'on-field target admits actual SHOW_MON')
  T.check(s.anim.objects:activeCount()>0,'on-field target admits real battler OBJ')
  T.eq(r.env.flying[side],true,'starting next runner cannot rebind retained runner')
  s.animPlayer:release()
 end end
end
-- Disabled/missing programs, skipped/cancelled rows and replacement/faint
-- release only their own picture state; the move's combat result is native.
for _,mode in ipairs{'disabled','missing','suppressed','cancelled','switch','faint','replaced','missed-release'}do
 local s=make('crystal','native');local b=s.player;local move={id='DIG',pp=10};b.curMoves={move}
 if mode=='disabled'then s.game.save.options.animations=false end
 if mode=='missing'then s.data.battle_anims.scripts={}end
 s:performMove(b,s.enemy,move,false,mode=='suppressed')
 if mode=='cancelled'then s:cancelMoveAnim()end
 if mode=='replaced'then
   untilState(s,function()return s.animPlaying end,'charge to replace starts')
   s:animForMove('PROBE','enemy')
 end
 finish(s)
 T.eq(underground(s,'player'),mode~='cancelled',mode..' follows its actual charge admission')
 if mode=='switch'then
   s:switchPlayerInto(Battle.POS.PLAYER_LEFT,s.game.save.party[2]);s:updateQueue()
   T.eq(underground(s,'player'),false,'incoming battler never inherits old cleared box')
   T.eq(next(s._gen2VanishPictures or {}),nil,'actual switch releases old native picture owner')
 elseif mode=='faint'then
   b.mon.hp=0;b.fainted=true;s:updateQueue()
   T.eq(next(s._gen2VanishPictures or {}),nil,'actual faint releases its cleared picture owner')
 else
   if mode=='disabled'then s.game.save.options.animations=true end
   if mode=='missed-release'then s.data.moves.DIG.accuracyRaw=0 end
   s:act(function()s:performMove(b,s.enemy,move)end);finish(s)
   T.eq(underground(s,'player'),false,mode..' releases the hidden box after the actual second turn')
   T.eq(next(s._gen2VanishPictures or {}),nil,mode..' retains no stale presentation owner')
 end
 T.eq(move.pp,9,mode..' presentation preserves native PP continuation')
 s.animPlayer:release()
end
-- Existing non-GSC charge animation selection is unchanged.
for _,edition in ipairs{'red','firered','emerald'}do
 local s=make(edition,'flat');local move={id='DIG',pp=10}
 s:performMove(s.player,s.enemy,move)
 local animation;for _,row in ipairs(s.queue)do if row.anim then animation=row.anim end end
 if edition=='red'then T.eq(animation,'SLIDE_DOWN_ANIM','Gen1 keeps original charge animation')end
 T.eq(s._gen2VanishPictures,nil,edition..' never creates GSC presentation state')
end
Version.set(previous)
T.finish('native GSC Fly/Dig charge, release, VM status snapshots and picture ownership')
