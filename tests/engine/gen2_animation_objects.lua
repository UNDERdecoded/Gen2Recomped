package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Player=require('src.battle.Gen2AnimPlayer')
local View=require('src.battle.Gen2AnimView')
local Battle=require('src.battle.BattleState')
local Wide=require('src.battle.WideBattle')
local oldVersion=Version.get()
local function fixture()
  return {battle_anims={gen2=true,moveAnims={FIX_MOVE=1},misc={throwPokeBall=1},
    scripts={[1]={entry=1,code={{op='obj',args={0,40,40,0}},{op='delay',frames=5},{op='ret'}}}},
    objects={[0]={oamFlags=0,fixY=255,frameset=0,fn=0,palette=4,gfx=2}},functions={[0]='Null'},
    framesets={[0]={frames={{oam=0,duration=20}},loop='hold'}},
    oam={[0]={tile=0,sprites={{x=0,y=0,tile=0,attr=0},{x=8,y=0,tile=1,attr=32}}}},
    gfx={[2]={tiles=2,cols=2,image='fixture.png'}},palettes={[2]={{255,255,255},{200,100,50},{100,30,10},{0,0,0}}}}}
end
for _,edition in ipairs({'gold','silver','crystal'})do
  Version.set(edition)
  local data=fixture();local p=Player.new(data)
  T.eq(p:isDone(),true,'new native player has a terminal idle state')
  T.eq(getmetatable(p.view),View,'VM owns the actual public drawing class')
  T.eq(p:start('FIX_MOVE',true,{param=17}),true,'native bytecode starts normally')
  T.eq(p.vars.param,17,'native script receives its caller parameter')
  p:update()
  local native=p.objects[1]
  local rows=p:oam()
  T.eq(#rows,2,'actual frame OAM contains both object tiles')
  T.same(rows[1],{x=40,y=40,tile=0,attr=0,palette=4,gfx=2},'first native sprite projection')
  T.same(rows[2],{x=48,y=40,tile=1,attr=32,palette=4,gfx=2},'second native sprite retains tile and flip')
  local runner=View.runner(p)
  T.eq(runner.frames,1,'runner observes actual update clock')
  T.eq(runner.objects.structs[1].index,native.index,'runner observes actual native object identity')
  T.eq(runner.objects.structs[1].jt,native.state,'runner observes actual object state machine')
  local age,frame=native.age,p.frames
  runner:oam();runner:oam()
  T.eq(native.age,age,'OAM reads cannot tick object motion')
  T.eq(p.frames,frame,'OAM reads cannot tick script time')
  p:update();T.eq(runner.frames,2,'delay frames count on actual native timeline')
  data.battle_anims.framesets[0].frames[1].xflip=true
  rows=p:oam()
  T.eq(rows[1].x,32,'object X flip negates offset and eight-pixel cell width')
  T.eq(rows[1].attr,32,'object X flip reaches sprite attributes')
  T.eq(rows[2].attr,0,'object flip XORs a sprite already flipped')
  data.battle_anims.framesets[0].frames[1].yflip=true
  T.eq(p:oam()[1].y,32,'object Y flip negates native row offset')
  native.fn,native.state='PokeBall',5
  p.opts.ballPalette='TEST_BALL'
  T.eq(runner.objects.structs[1].func,'BATTLE_ANIM_FUNC_POKEBALL','source reads the actual native ball function')
  T.eq(runner.objects.structs[1].jt,5,'source reads real landed ball state')
  T.eq(p:oam()[1].palette,'TEST_BALL','typed native ball palette follows actual object')
  p.vars.var,p.keepSprites=1,true
  T.eq(runner.var,1,'capture result observation uses VM variable')
  T.eq(runner.keepSprites,true,'capture retention observation uses VM flag')
  p.presentation=runner
  local ticks=runner.frames
  p:start('FIX_MOVE',false)
  T.eq(runner.frames,ticks,'restarting VM cannot rebind previous animation observation')
  T.eq(runner:oam()[1].palette,'TEST_BALL','retired OAM retains its own throw')
  T.eq(p.frames,0,'new animation starts with its own actual clock')
  p:update()
  local g=love.graphics;local draw=g.draw;local calls={}
  g.draw=function(...)calls[#calls+1]={...}end
  local shader={};g.setShader(shader);g.setColor(.2,.3,.4,.5)
  p:draw()
  T.eq(#calls,2,'native VM draws through the actual object-view owner')
  T.eq(g.getShader(),shader,'object pass restores caller shader')
  T.same({g.getColor()},{.2,.3,.4,.5},'object pass restores caller tint')
  g.draw=function()error('actual object draw failure')end
  T.raises(function()p:draw()end,'actual object draw failure','render error remains observable')
  T.eq(g.getShader(),shader,'failed object pass restores caller state')
  g.draw=draw;g.setShader();g.setColor(1,1,1,1)
  p:release()
end
require('src.core.ModCompat').install()
T.eq(require('src.ui.gen2.BattleAnimView'),View,'compat spelling resolves actual native renderer class')
do
  Version.set('crystal')
  local data=T.fixtures.fresh();data.constants.gen=2
  data.battle_anims=fixture().battle_anims
  data.items.ITEM_FIX_BALL={id='ITEM_FIX_BALL',key='POKE_BALL',index=5}
  require('src.render.Font').load(data)
  local save=require('src.core.SaveData').newGame()
  save.party={require('src.pokemon.Pokemon').new(data,'FIXMON_A',30)}
  local s=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
  T.eq(s.animView,s.animPlayer.view,'screen exposes the same actual drawing owner')
  local item
  s.ballPalette=function(self,id) item=id;return 'TEST_QUEUED_BALL'end
  s.queue={{anim='TOSS_ANIM',attackerIsPlayer=true,ball='ITEM_FIX_BALL',caught=true,shakes=3,animDelayed=true}}
  s.current,s.waitFrames=nil,nil
  s:updateQueue()
  T.eq(item,'POKE_BALL','actual queued throw calls public palette seam with source item spelling')
  T.eq(s.animPlayer.opts.ballPalette,'TEST_QUEUED_BALL','native bytecode owns the selected thrown palette')
  T.eq(s.animPlayer.opts.ball,'ITEM_FIX_BALL','native inventory item remains unchanged')
  T.eq(s.animPlayer.battle,s.battle,'renderer sees live native battle model')
  local PaletteFX=require('src.render.PaletteFX')
  local nativePal=PaletteFX.monPal
  local observed
  PaletteFX.monPal=function(_,species)observed=species;return PaletteFX.GRAYS end
  s.animView:objPalette('PAL_BATTLE_OB_ENEMY',s)
  T.eq(observed,s.enemy.mon.species,'native battler record resolves its actual Pokemon palette')
  s.animView:objPalette('PAL_BATTLE_OB_PLAYER',{player=s.player.mon})
  T.eq(observed,s.player.mon.species,'direct native Pokemon model resolves the same palette owner')
  PaletteFX.monPal=nativePal
  s.animPlayer:update()
  local layer=s.drawAnimLayer;local layers=0
  s.drawAnimLayer=function(self,...)layers=layers+1;return layer(self,...)end
  Wide.draw(s)
  T.eq(layers,1,'wide native composition draws actual Gen2 OAM without Gen1 frame blocks')
end
Version.set(oldVersion)
T.finish('native Gen2 animation object owner, observation and queued ball palette')
