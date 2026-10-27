-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local G=require('src.core.Game3')
local Host=require('src.mods.Runtime')
local Views=require('src.compat.gen1.SessionView')
local PViews=require('src.compat.gen1.PokemonView')
local Bag=require('src.core.game3.bag')
local Field=require('src.core.game3.field')
local Source=require('src.compat.gen1.SourcePokemon')
local Scope=require('src.compat.gen1.ScriptBoundary')
local Message=require('src.ui.game3.message')
local Choice=require('src.ui.game3.choice')
local Stream=require('src.core.game3.asset_stream')
T.eq(require('src.core.game3.player').running,false,'no admitted player is not running')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Stream.shutdown();G.release()
 local bf=require('tools.battle-source-runtime.fixture').new(edition)
 local nativeMon=bf.fresh('TACKLE').battle.player.mon
 local f=require('tools.session-runtime.fixture').new(edition)
 local g,w,p=f.game,f.world,f.player
 local maps=g.data.maps;g.data=bf.data;g.data.maps=maps
 g.data.constants.types={NORMAL={index=0}};g.data.constants.typeOrder={'NORMAL'}
 local pair=require('src.compat.gen1.PairNames')[edition][1]
 g.data.tilesets={PAIR={id='PAIR',primaryKey='P',secondaryKey='S',blockCells=1,blockTiles=2}}
 g.data.map_tilesets={P={address=pair[1],secondary=false},S={address=pair[2],secondary=true}}
 w.map.def.tileset='PAIR'
 g.data.constants.gen3Layout={};g.data.constants.itemOrder={[7]='PROBE_ITEM'}
 local evolved=require('src.mods.Merge').deepCopy(g.data.pokemon.CHARMANDER)
 evolved.id,evolved.name,evolved.index,evolved.dex='CHARMELEON','CHARMELEON',5,5
 g.data.pokemon.CHARMELEON=evolved;g.data.constants.speciesOrder[5]='CHARMELEON'
 for number,name in pairs{[34]='GROWL',[35]='TAIL_WHIP',[36]='SPLASH',[37]='LEER'}do
  g.data.constants.moveOrder[number]=name
  g.data.moves[name]={id=name,index=number,name=name,pp=40,power=0,type='NORMAL',category='status',accuracy=100}
 end
 g.data.items.PROBE_ITEM={id='PROBE_ITEM',name='PROBE',index=7,pocket='ITEM',price=1}
 g.save.party={nativeMon};g.save.inventory={PROBE_ITEM=2};g.save.bagOrder={'PROBE_ITEM'}
 g.save.pokedex={seen={},owned={},caught={}}
 g.mods={mods={runtime_probe={enabled=true},other={enabled=true}},exports={},hooks={wrap=function()end}}
 Host.currentMod='runtime_probe'
 local view=assert(G.forNative(g));local session=view.session;local mon=session.party[1]
 T.check(mon~=nativeMon);T.eq(mon.species,4);T.eq(mon.moves[1],33);T.eq(mon.pp[1],10)
 local snapshot={};for k,v in pairs(mon)do snapshot[k]=v end
 T.eq(snapshot.species,4);T.neq(snapshot.moves,mon.moves)
 local pp=mon.pp;pp[1]=7;G._withCallbackOwner('runtime_probe',function()end);T.eq(nativeMon.moves[1].pp,7)
 local invalid=mon.pp;invalid[1]=-1;T.raises(function()PViews.flush()end,'invalid native PP')
 T.eq(nativeMon.moves[1].pp,7);invalid[1]=7;PViews.flush()
 local numericMoves=mon.moves;numericMoves[1]=34;T.raises(function()PViews.flush()end,'native moves changed')
 numericMoves[1]=33;PViews.flush()
 require('src.core.game3.pokemon').setFriendship(mon,200);T.eq(nativeMon.happiness,200)
 mon.hp=12;T.eq(nativeMon.hp,12);mon.status=128;T.eq(nativeMon.status,'PSN');T.eq(nativeMon.toxic,true)
 mon.status=0;T.eq(nativeMon.status,nil)
 T.eq(Bag.count(session.bag,7),2)
 local inventory,order=g.save.inventory,g.save.bagOrder
 T.eq(Bag.canAdd(session.bag,7,2),true);T.eq(g.save.inventory,inventory);T.eq(g.save.bagOrder,order);T.eq(inventory.PROBE_ITEM,2)
 T.eq(Bag.add(session.bag,7,2),true);T.eq(inventory.PROBE_ITEM,4)
 T.eq(Bag.remove(session.bag,7,-2),false);T.eq(inventory.PROBE_ITEM,4)
 T.eq(Bag.add(session.bag,7,0/0),false);T.eq(Bag.add(session.bag,9999,1),false)
 T.eq(Bag.remove(session.bag,7,2),true);T.eq(inventory.PROBE_ITEM,2)
 local Dex=require('src.core.game3.dex');T.eq(Dex.isCaught(session.dex,4),false)
 g.save.pokedex.owned.CHARMANDER=true;T.eq(Dex.isCaught(session.dex,4),true)
 local Safari=require('src.core.game3.safari');T.eq(Safari.isActive(session),false)
 g.save.safari={balls=30};T.eq(Safari.isActive(session),true);g.save.safari=nil
 T.eq(Field.lock('same'),true);T.eq(Field.locked,true);T.eq(w:busy(),true)
 Host.currentMod='other';Field.lock('same');Field.unlock('same');T.eq(Field.locked,true,'one mod cannot release another lock')
 Stream.cancelOwner('other');T.eq(Field.locked,true)
 Host.currentMod='runtime_probe';Field.unlock('same');T.eq(Field.locked,false)
 local interactions=0;local base=Field.interact
 Field.interact=function()base();return base()end
 Field._dispatch(g,w,function()interactions=interactions+1;return'handled'end)
 T.eq(interactions,1);T.eq(base(),nil,'no manufactured interaction between native phases');Field.interact=base
 local Player=require('src.core.game3.player');T.eq(Player.startFieldMove(3,'test'),true)
 T.eq(p.fieldMove,true);T.eq(w:busy(),true);T.eq(Player.startFieldMove(2),false)
 p:update();p:update();T.eq(Player.fieldMoveAnim,1);p:update();T.eq(Player.fieldMoveAnim,0);T.eq(p._gen3FieldMovePoseOwner,nil)
 Player.startFieldMove(3);Stream.cancelOwner('runtime_probe');T.eq(p.fieldMove,nil)
 local moves=require('src.core.game3.field_moves')
 g.data.constants.gen3FieldMoves={SURF={badgeFlag=0x820}}
 T.eq(moves.hasBadge(session,'SURF'),false);g.save.flags.FLAG_G3_0820=true;T.eq(moves.hasBadge(session,'SURF'),true)
 w.partyKnows=function(_,key)return key=='SURF'and nativeMon end
 local user,slot=moves.partyMoveUser(session.party,'SURF');T.eq(user,mon);T.eq(slot,0)
 local none,missing=moves.partyMoveUser(session.party,'CUT');T.eq(none,nil);T.eq(missing,6)
 local fighter={species=4,level=30,personality=9,ivs={hp=31,atk=20,def=10,spe=8,spa=7,spd=6},moves={33},pp={10}}
 require('src.core.game3.battle.damage').ensureStats(fighter)
 T.check(fighter.maxHp>1);T.eq(fighter.hp,fighter.maxHp)
 local raw,owner=Source.resolve(fighter);T.eq(owner,g);T.eq(raw.species,'CHARMANDER');T.eq(raw.ivs.attack,20)
 local def=g.data.moves.MOVE_033;local row=require('src.core.game3.battle.moves').get(33)
 T.eq(row.power,def.power);T.eq(row.type,0);row.power=900;T.eq(def.power,35)
 local damage,info=require('src.core.game3.battle.damage').calc({mon=fighter},{mon=fighter},33,{noCrit=true,rng=function(lo,hi)return hi or lo end})
 T.check(damage>0);T.eq(info.critical,false);T.eq(info.effectiveness,1)
 local NativeDamage=require('src.battle.Damage');local rules=require('src.battle.Rulesets').gen3_emerald
 local b={mon=raw,def=g.data.pokemon.CHARMANDER,curStats=raw.stats,curTypes={'NORMAL'},stages={},items=g.data.items,statuses=g.data.statuses}
 local expected=NativeDamage.compute(rules,b,b,def,{forceCrit=false,rng=function(lo,hi)return hi or lo end,data=g.data})
 T.eq(damage,expected,'field damage shares the native formula')
 nativeMon.stats=require('src.pokemon.Stats').calcGen3(g.data.pokemon.CHARMANDER,30,nativeMon.ivs,nativeMon.evs,nativeMon.nature);nativeMon.hp=nativeMon.stats.hp
 nativeMon.level=30;nativeMon.exp=require('src.pokemon.Growth').expForLevel(g.data.pokemon.CHARMANDER.growthRate,30,g.data.growth_rates)
 local exp=require('src.core.game3.battle.experience');local before=nativeMon.exp
 local threshold=require('src.pokemon.Growth').expForLevel(g.data.pokemon.CHARMANDER.growthRate,31,g.data.growth_rates)
 local award=exp.apply(mon,threshold-before+1)
 T.eq(nativeMon.level,31);T.eq(award.fromLevel,30);T.eq(award.toLevel,31);T.eq(award.gained,threshold-before+1);T.eq(award.levels[1],31)
 T.check(#award.steps>=1)
 local sfx=require('src.core.game3.se_ids');T.eq(sfx.SE_SUCCESS,(edition=='firered'or edition=='leafgreen')and 25 or 31)
 local catalogue=require('src.core.game3.items_data');T.eq(catalogue.info(7).pocket,'ITEMS');T.eq(catalogue.isTm(7),false)
 local r=require('src.core.game3.rng');local random=r.Random32();T.check(random>=0 and random<4294967296 and random%1==0)
 T.eq(r.mulU32(0xffffffff,0xffffffff),1)
 T.eq(Message.show('Hello',{speed=0}),true);T.eq(Message.isOpen(),true);T.eq(Message.isWaiting(),true)
 local box=g.stack:top();T.eq(box.done,true);T.eq(Message.currentPage(),'Hello')
 local count,update=0,Message.tick
 Message.tick=function()count=count+1;update();return update()end
 box:update(1/60);T.eq(count,1);T.eq(g.stack:top(),box);Message.tick=update
 T.eq(Message.close(),true);T.eq(g.stack:top(),w);T.eq(Message.isOpen(),false)
 local chosen,calls=nil,0
 T.eq(Choice.multi({'A','B','C'},1,function(index)chosen=index;calls=calls+1 end),true)
 local choice=g.stack:top();f.input.edges.a=true;choice:update();f.input.edges.a=nil
 T.eq(chosen,1);T.eq(calls,1);choice.onChoose(0);T.eq(calls,1,'one continuation per choice')
 T.eq(g.stack:top(),w)
 Message.showStay('Held',{speed=0});local held=g.stack:top()
 local foreign={modOwnedScreen=true};g.stack:push(foreign)
 Stream.cancelOwner('runtime_probe');T.eq(g.stack:top(),foreign,'teardown leaves foreign overlays intact')
 for _,s in ipairs(g.stack.states)do T.neq(s,held)end
 g.stack:pop()
 -- Admission carries the visible individual into the actual native constructor.
 local battle,cleanup,done=nil,0,0
 function w:pushBattle(value)battle=value;g.stack:push(value);return true end
 function w:afterBattle()cleanup=cleanup+1 end
 Host.currentMod='runtime_probe'
 local ok,why=require('src.core.game3.battle_bridge').startWild(nil,view,
  {species=4,level=17,personality=0x12345678,ivs={hp=31,atk=30,def=29,spe=28,spa=27,spd=26},moves={33},pp={4},hp=12,status=64,item=7},
  {done=function()done=done+1 end})
 T.eq(ok,true,tostring(why));T.check(battle~=nil)
 if battle then
  T.eq(battle.enemy.mon.personality,0x12345678);T.eq(battle.enemy.mon.ivs.spdef,26)
  T.eq(battle.enemy.mon.moves[1].pp,4);T.eq(battle.enemy.mon.hp,12);T.eq(battle.enemy.mon.status,'PAR');T.eq(battle.enemy.mon.item,'PROBE_ITEM')
  battle.onFinish('run');battle.onFinish('run');T.eq(cleanup,1);T.eq(done,1)
  g.stack:removeAll({battle})
 end
 -- Source collectors and follower renderers are presentation-only.
 local Actors=require('src.compat.gen1.SourceActors')
 local effects=require('src.core.game3.field_effects');local collect=effects.collectActors
 local rendered,collectorCalls=0,0
 local originalEntities=w.entities
 effects.collectActors=function(rows,cx,cy)
  collectorCalls=collectorCalls+1;collect(rows,cx,cy);collect(rows,cx,cy)
  rows[#rows+1]={kind='test',x=32,y=48,sortY=48,elevation=3,draw=function()rendered=rendered+1 end}
 end
 local retainedActor
 Actors.withActors(g,w,function()
  T.neq(w.entities,originalEntities);T.eq(#w.entities,#originalEntities+1)
  retainedActor=w.entities[#w.entities];retainedActor:draw(0,0)
  T.eq(require('src.world.Collision').occupied(w.entities,retainedActor.cellX,retainedActor.cellY),nil,'a draw-only actor cannot enter the collision cast')
 end)
 T.eq(w.entities,originalEntities);T.eq(collectorCalls,1);T.eq(rendered,1)
 T.eq(retainedActor:draw(0,0),false,'draw-only proxies retire after their frame')
 T.raises(function()Actors.withActors(g,w,function()error('actor failure')end)end,'actor failure')
 T.eq(w.entities,originalEntities,'failed custom rendering restores the logical actor collection')
 effects.collectActors=collect
 local Follower=require('src.compat.game3.Follower');local baseFollow=Follower.update;local updates=0
 Follower.update=function()baseFollow();return baseFollow()end
 Follower._dispatch(g,w,function()updates=updates+1 end);T.eq(updates,1);Follower.update=baseFollow
 local menuSource=require('src.ui.game3.party_menu')
 local menu=require('src.ui.Gen3PartyMenu').new(g)
 g.stack:push(menu)
 menu.submenu={{label='SUMMARY',action='summary'},{label='ITEM',action='item'},{label='CANCEL',action='cancel'}};menu.subIndex=1
 local mu,mi=menuSource.update,menuSource.handleInput
 menuSource.update=function(dt)
  mu(dt);local a=menuSource.ACTIONS;if a and a[1]=='SUMMARY'and a[2]~='ROLE'then table.insert(a,2,'ROLE')end
 end
 menuSource.handleInput=function(input)
  if input:wasPressed('a')and menuSource.ACTIONS[menuSource.actionCursor]=='ROLE'then
   menuSource.ACTIONS={'FOLLOW','BACK'};menuSource.actionCursor=1;return true
  end
  return mi(input)
 end
 menu:update(1/60);T.eq(menu.submenu[2].sourceLabel,'ROLE');T.eq(menuSource._party[1].species,4)
 menu.subIndex=2;f.input.edges.a=true;menu:update(1/60);f.input.edges.a=nil
 T.eq(menu.submenu[1].sourceLabel,'FOLLOW','source submenu edits reach native navigation')
 T.eq(menu.submenu[2].sourceLabel,'BACK');T.eq(menuSource.actionCursor,1)
 menuSource.update,menuSource.handleInput=mu,mi
 local peerSelected=0
 menu.submenu={{label='PEER',onSelect=function()peerSelected=peerSelected+1 end},{label='CANCEL',action='cancel'}};menu.subIndex=1
 menu:update(1/60)
 local peerKey=menuSource.ACTIONS[1]
 menuSource.ACTIONS={'ROLE',peerKey,'CANCEL'};menu:update(1/60)
 Stream.cancelOwner('runtime_probe')
 T.eq(#menu.submenu,2,'unloading removes only owned source action rows')
 T.eq(menu.submenu[1].label,'PEER','native peer actions survive source teardown')
 f.input.edges.a=true;menu:update(1/60);f.input.edges.a=nil
 T.eq(peerSelected,1,'native callback-only submenu actions keep functioning')
 g.stack:removeAll({menu})
 -- Native evolution cancellation/completion and reminder windows remain owned.
 local Evo=require('src.ui.game3.evolution_scene');local Relearn=require('src.ui.game3.move_relearner')
 local row=g.data.pokemon.CHARMANDER
 row.evolutions={{method='LEVEL',level=31,species='CHARMELEON'}}
 T.eq(require('src.core.game3.evolution').levelTarget(mon,session),5)
 local evoDone=0
 local function closeText()
  local class=require('src.render.TextBox')
  for _=1,40 do
   local top=g.stack:top();if getmetatable(top)~=class then return end
   top:revealPage();top.holdFrames=0;top.preWait=0;top:advance()
  end
  error('native dialogue did not finish')
 end
 T.eq(Evo.start(mon,5,{onDone=function()evoDone=evoDone+1 end}),true)
 local scene=g.stack.states[#g.stack.states-1];closeText();scene:stop();closeText()
 T.eq(nativeMon.species,'CHARMANDER');T.eq(evoDone,1);T.eq(Evo.isOpen(),false);T.eq(g.stack:top(),w)
 T.eq(Evo.start(mon,5,{onDone=function()evoDone=evoDone+1 end}),true)
 scene=g.stack.states[#g.stack.states-1];closeText();scene:finish();closeText()
 T.eq(nativeMon.species,'CHARMELEON');T.eq(mon.species,5);T.eq(evoDone,2);T.eq(g.stack:top(),w)
 local movesRow=g.data.pokemon.CHARMELEON;movesRow.learnset={{level=1,move='GROWL'}}
 T.eq(require('src.core.game3.move_learn').relearnableMoves(mon)[1],34)
 local learned,learnDone=nil,0
 local function chooseTop()
  local input=g.input;local pressed=input.wasPressed
  input.wasPressed=function(_,key)return key=='a'end
  g.stack:update(1/60);input.wasPressed=pressed
 end
 T.eq(Relearn.show(mon,{onDone=function(ok)learned=ok;learnDone=learnDone+1 end}),true)
 chooseTop();closeText()
 T.eq(nativeMon.moves[2].id,'GROWL');T.eq(nativeMon.moves[2].pp,40)
 T.eq(learned,true);T.eq(learnDone,1);T.eq(Relearn.isOpen(),false);T.eq(g.stack:top(),w)
 nativeMon.moves[3]={id='TAIL_WHIP',pp=40};nativeMon.moves[4]={id='SPLASH',pp=40}
 movesRow.learnset={{level=1,move='LEER'}}
 T.eq(Relearn.show(mon,{onDone=function()learnDone=learnDone+1 end}),true)
 chooseTop();T.eq(getmetatable(g.stack:top()),require('src.render.TextBox'))
 Stream.cancelOwner('runtime_probe');T.eq(g.stack:top(),w);T.eq(learnDone,1)
 T.eq(nativeMon.moves[4].id,'SPLASH','unloading a reminder cannot replace a native move')
 -- Optional features retain native pools, input guards and consumption.
 local Features=require('src.core.game3.enhancements')
 local flags={timedEncounters=true,trainingDetails=true,repelPrompt=true,quickBall=true}
 local release=Features.attach{active=function()return true end,option=function(key)return flags[key]end,
  time=function()return 100 end,outdoors=function()return true end,language=function()return'en'end}
 T.eq(Features.enabled('quickBall'),true)
 g.mods.mods.runtime_probe.enabled=false;T.eq(Features.enabled('quickBall'),false,'disabled owner cannot enable native conveniences')
 g.mods.mods.runtime_probe.enabled=true;T.eq(Features.enabled('quickBall'),true)
 local sourcePool={grass={rate=100,buckets={60,100},bucketSpan=100,slots={{species='LARV',level=3,chance=60},{species='SEED',level=5,chance=40}}}}
 g.data.pokemon.LARV={dex=19};g.data.pokemon.SEED={dex=10}
 g.data.constants.speciesOrder[19]='LARV';g.data.constants.speciesOrder[10]='SEED'
 g.data.encounters={TEST=sourcePool}
 local nativePool=require('src.world.Encounter').forMap(g.data,w.map.def,'TEST',nil,g.save)
 T.neq(nativePool,sourcePool);T.eq(nativePool.grass.slots[1].species,'SEED')
 T.eq(nativePool.grass.slots[1].chance,60);T.eq(nativePool.grass.slots[2].chance,40)
 T.eq(sourcePool.grass.slots[1].species,'LARV','timed frequencies do not rewrite imported pools')
 local encounters=require('src.core.game3.encounters')
 T.eq(encounters.tableFor(f.canonical).land.slots[1].species,10)
 T.check(encounters.rollSweetScent(f.canonical,'land')~=nil,'guaranteed selection uses a native weighted pool')
 T.eq(encounters.rollSweetScent(f.canonical,'water'),nil,'missing water never falls back to land')
 local details=require('src.ui.TrainingDetails');local summary={game=g,page=2,mon=nativeMon,pages={'Info','Skills','Moves'}}
 f.input.edges.select=true;require('src.ui.Gen3SummaryMenu').update(summary,1/60);f.input.edges.select=nil
 T.eq(details.mode(summary),1);T.eq(details.stats(summary),nativeMon.ivs);T.eq(details.title(summary,'Skills'),'IV')
 f.input.edges.select=true;require('src.ui.Gen3SummaryMenu').update(summary,1/60);f.input.edges.select=nil
 T.eq(details.mode(summary),2);T.eq(details.stats(summary),nativeMon.evs)
 flags.trainingDetails=false;T.eq(details.mode(summary),0);T.eq(details.stats(summary),nil)
 g.data.items.MAX_REPEL={id='MAX_REPEL',name='MAX REPEL',index=88,pocket='ITEM'};g.save.inventory.MAX_REPEL=1
 local prompt=require('src.ui.RepelPrompt');T.eq(prompt.show(g),true)
 g.stack:top().choice(false);T.eq(g.save.inventory.MAX_REPEL,1);T.eq(g.save.repelSteps,nil)
 T.eq(prompt.show(g),true);g.stack:top().choice(true)
 T.eq(g.save.inventory.MAX_REPEL,nil);T.eq(g.save.repelSteps,250)
 local nativeText=g.stack:top();nativeText:revealPage();nativeText:advance();T.eq(g.stack:top(),w)
 g.data.items.POKE_BALL={id='POKE_BALL',name='POKE BALL',index=4,pocket='BALL'};g.save.inventory.POKE_BALL=2
 local qb=require('src.battle.BattleState').newWild(g,'CHARMANDER',17);g.stack:push(qb)
 qb.phase='menu';qb.queue={};qb.current=nil;qb.introSlide=0;qb.showEnemyTrainer=nil;qb.showPlayerBack=nil;qb.enemySendingOut=nil
 local Q=require('src.battle.QuickItem');local thrown=0
 qb.throwBall=function()thrown=thrown+1 end
 f.input.edges.r=true;local request=Q.request(qb);f.input.edges.r=nil
 T.check(request~=nil,'quick item uses the native idle-menu admission')
 if request then T.eq(Q.dispatch(qb,request),true);T.eq(thrown,1);T.eq(g.save.inventory.POKE_BALL,1)end
 qb.queue={{wait=1}};f.input.edges.r=true;T.eq(Q.request(qb),nil);f.input.edges.r=nil
 T.eq(g.save.inventory.POKE_BALL,1,'busy combat cannot spend another ball')
 g.stack:removeAll({qb});release();T.eq(Features.enabled('quickBall'),false)
 T.eq(require('src.world.Encounter').forMap(g.data,w.map.def,'TEST',nil,g.save),sourcePool)
 local prior=g.save;g.save={player=prior.player,options={}}
 T.eq(session.party,nil);T.raises(function()mon.hp=1 end,'retired')
 T.eq(Bag.add(session.bag or{},7,1),false)
 Host.currentMod=nil;Stream.shutdown();G.release();bf.close()
end
T.finish('native companion commands, typed residents, UI and encounter lifecycle')
