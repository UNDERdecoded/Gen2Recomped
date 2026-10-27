package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local World=require('src.world.OverworldController')
local Fishing=require('src.world.Gen2Fishing')
local Pokemon=require('src.pokemon.Pokemon')
local Battle=require('src.battle.BattleState')
local Stack=require('src.core.StateStack')
local Map=require('src.world.Map')
local Player=require('src.world.Player')
local StartMenu=require('src.ui.StartMenu')
local BagMenu=require('src.ui.BagMenu')
local Input=require('src.core.Input')
local before=Version.get();local random=love.math.random
local slot,previousGame
for i=1,100 do local name,value=debug.getupvalue(World.useRod,i)
 if not name then break end;if name=='Game'then slot,previousGame=i,value;break end
end
assert(slot)
local draws,creations=0,0
local new=Pokemon.new
Pokemon.new=function(...)creations=creations+1;return new(...)end
local function fixture(edition)
 Fishing.release();Version.set(edition or 'crystal')
 love.math.random=random
 local data=T.fixtures.fresh();data.constants.gen=2
 data.field.fishGroups={POND={chance=128,rods={
  old={{chance=255,species='FIXMON_B',level=7}},
  good={{chance=255,species='FIXMON_B',level=17}},
  super={{chance=255,species='FIXMON_B',level=27}},
 }}}
 data.items.ITEM_058={index=58,key='OLD_ROD',name='OLD ROD',keyItem=true,pocket='KEY_ITEM',registerable=true}
 local game=T.link.fakeGame(data,'FIXMON_A',{level=30})
 T.link.prepare(data)
 local stack=setmetatable({}, {__index=Stack});stack:init();game.stack=stack
 local ts={id='FISH',collision={},walkable={0},waterTiles={0x29},blocks={}}
 for i=1,40 do ts.collision[i]=0x29 end
 local def={id='NATIVE_FISH',tileset='FISH',width=3,height=3,blocks={1,2,3,4,5,6,7,8,9},generation=2,fishGroup='POND',connections={}}
 data.maps[def.id]=def;data.tilesets.FISH=ts
 local p=setmetatable({cellX=2,cellY=2,px=32,py=32,facing='right'},{__index=Player})
 local w=setmetatable({isOverworld=true,map=Map.new(def,ts),player=p,scriptMoves={},pendingScripts={},runner={isRunning=function()return false end}},{__index=World})
 game.overworld=w;game.world=w;game.phase='play';stack.states={w}
 function w:pushBattle(battle)game.lastBattle=battle end -- device transition only
 debug.setupvalue(World.useRod,slot,game)
 draws,creations=0,0
 love.math.random=function(a,b)
  draws=draws+1
  if b==nil then return a and 1 or .1 end
  return a
 end
 return w,game,data,def,ts
end
local function closeText(game)
 local box=game.stack:top();T.check(box~=nil,'native verdict textbox exists')
 for _=1,600 do
  if game.stack:top()~=box then break end
  Input.pressed={a=true};game.stack:update(1/60)
 end
 Input.pressed={}
 T.neq(game.stack:top(),box,'ordinary native textbox input completes the verdict')
end
local function verdict(w)
 for _=1,83 do w:updateFishing()end
end
for _,edition in ipairs({'gold','silver','crystal','prism'})do
 for _,rod in ipairs({'OLD_ROD','GOOD_ROD','SUPER_ROD','ITEM_058','ITEM_059','ITEM_061'})do
  local w,g=fixture(edition)
  local begin=w.beginFishing;local calls,observed=0
  w.beginFishing=function(self,outcome,wild)
   calls=calls+1;observed=wild;return begin(self,outcome,wild)
  end
  T.eq(w:goFishing(rod),'battle','ordinary native rod path enters the public lifecycle')
  local st=w.fishing;T.eq(calls,1,'one synchronous public cast admission')
  T.eq(st.wild,observed,'presentation sees the actual rolled individual')
  T.eq(st.wild.species,'FIXMON_B','ROM group chooses the encounter')
  T.eq(creations,1,'one native Pokemon created for the cast')
  T.eq(pcall(Battle.newWild,g,'FIXMON_B',st.wild.level,{nativeFishingMon={species='FIXMON_B',level=st.wild.level}}),false,'fabricated no-reroll admission is refused')
  T.eq(w.player.fishingState,st,'player and world share the same native state')
  T.eq(st.bobber.cellX,3);T.eq(st.bobber.cellY,2);T.eq(st.bobber.px,48)
  T.eq(w:useRod(rod),'nowhere','active cast refuses reentry without another roll')
  T.eq(creations,1)
  for _=1,40 do w:updateFishing()end
  T.eq(st.phase,'cast');T.eq(st.timer,0,'cast uses native frame ticks')
  w:updateFishing();T.eq(st.phase,'bite');T.eq(st.timer,40)
  w:updateFishing()
  local _,_,biteY=w.player:pose()
  T.eq(biteY,w.player.py-1,'native player pose applies the bite jerk')
  local bubble=w.emote;T.eq(bubble.npc,w.player,'native bite emote belongs to the player')
  for _=1,39 do w:updateFishing()end
  T.eq(st.timer,0);T.eq(st.phase,'bite')
  w:updateFishing();T.eq(st.phase,'done');T.eq(g.lastBattle,nil,'verdict owns the field before battle')
  closeText(g)
  T.eq(w.fishing,nil);T.eq(w.player.fishingState,nil);T.eq(w.player.fishing,nil)
  T.eq(w.emote,nil,'only the cast-owned bite emote is released')
  T.eq(g.lastBattle.enemy.mon,observed,'battle receives the identical individual, DVs, moves and stats')
  T.eq(creations,1,'battle constructor does not generate a second Pokemon')
  T.eq(pcall(Fishing.takePrepared,g,observed,observed.species,observed.level),false,'prepared handoff is single use')
 end
end
-- Distinct cart outcomes: no target, no fish group, genuine no bite.
for _,kind in ipairs({'dry','surf','nofish','nibble'})do
 local w,g,data,def,ts=fixture()
 if kind=='dry'then for i in pairs(ts.collision)do ts.collision[i]=0 end end
 if kind=='surf'then w.player.surfing=true end
 if kind=='nofish'then def.fishGroup=0 end
 if kind=='nibble'then data.field.fishGroups.POND.chance=0 end
 local outcome=w:useRod('ITEM_058')
 T.eq(outcome,(kind=='dry'or kind=='surf')and'nowhere'or kind)
 T.eq(creations,0,'empty/refused casts never generate a Pokemon')
 if outcome=='nowhere'then T.eq(w.fishing,nil);T.eq(draws,0)
 else verdict(w);closeText(g);T.eq(w.fishing,nil);T.eq(g.lastBattle,nil)end
end
-- Drive the actual upstream START -> bag -> USE sequence. Its Menu exits
-- START before opening the bag, unlike the fork's native Gen2 PACK widget.
for _,wet in ipairs({false,true})do
 local w,g,data,def,ts=fixture()
 if not wet then for i in pairs(ts.collision)do ts.collision[i]=0 end end
 g.save.inventory.ITEM_058=1
 local start=StartMenu.new(g);g.stack:push(start)
 local at;for i,row in ipairs(start.items)do if row.label=='ITEM'then at=i end end
 T.check(at~=nil,'actual upstream START offers its native bag')
 start.index=at;start:choose()
 local pack=g.stack:top();T.neq(pack,start,'native START hands input to its bag')
 -- Move to KEY ITEMS through the bag's real pocket input.
 for _=1,2 do Input.pressed={right=true};g.stack:update(1/60)end
 Input.pressed={}
 local row;for i,item in ipairs(pack.items)do if item.value=='ITEM_058'then pack.index=i;row=item end end
 T.check(row~=nil,'native pocket contains the held rod')
 pack:choose();local submenu=g.stack:top()
 T.neq(submenu,pack,'actual bag opens the USE submenu')
 local use=w.useRod;local calls=0;w.useRod=function(self,rod)calls=calls+1;return use(self,rod)end
 submenu:choose()
 T.eq(calls,wet and 1 or 0,'bag uses the public rod only after native admission')
 if wet then
  T.eq(g.stack:top(),w,'successful rod returns to the actual native field');T.check(w.fishing~=nil)
 else
  local retained=false;for _,state in ipairs(g.stack.states)do if state==pack then retained=true end end
  T.eq(retained,true,'refused rod preserves its native bag');T.eq(draws,0)
 end
 T.eq(g.save.inventory.ITEM_058,1,'rods are never consumed')
end

do
 local w,g=fixture();g.save.inventory.ITEM_058=1;g.save.registeredItem='ITEM_058'
 local use=w.useRod;local calls=0;w.useRod=function(self,rod)calls=calls+1;return use(self,rod)end
 T.eq(BagMenu.useRegistered(g),true);T.eq(calls,1,'SELECT enters the same public lifecycle')
 T.check(w.fishing~=nil);T.eq(g.save.inventory.ITEM_058,1)
end
for _,key in ipairs({'battleActive','transitioning','emote','mapSetup','headbutt','moveState','iceSlide','_modScriptLock'})do
 local w=fixture();w[key]=true
 T.eq(w:useRod('OLD_ROD'),'nowhere',key..' retains native input ownership');T.eq(draws,0)
end
for _,key in ipairs({'moving','surfing','inputLocked','fieldMove','stairExit','spinning'})do
 local w=fixture();w.player[key]=true
 T.eq(w:useRod('OLD_ROD'),'nowhere',key..' retains actor ownership');T.eq(draws,0)
end
for _,change in ipairs({'save','data','map','player','position','edition','removedText','worldRetired'})do
 local w,g=fixture();T.eq(w:useRod('OLD_ROD'),'battle');local st=w.fishing;local old=w.player
 if change=='removedText'then verdict(w);g.stack:pop()
 elseif change=='worldRetired'then g.stack:pop()
 elseif change=='save'then g.save={}
 elseif change=='data'then g.data={}
 elseif change=='map'then w.map={}
 elseif change=='player'then w.player={cellX=2,cellY=2,facing='right'}
 elseif change=='position'then old.cellX=3
 else Version.set('gold')end
 require('src.core.game3.asset_stream').poll();T.eq(w.fishing,nil,change..' retires the cast through native services');T.eq(old.fishingState,nil)
 T.eq(pcall(Fishing.takePrepared,g,st.wild,st.wild.species,st.wild.level),false,'retired individual cannot enter battle')
end
do
 local w,g=fixture();w:useRod('OLD_ROD');verdict(w);local box=g.stack:top();local replacement={name='new owner'}
 w.emote=replacement;Fishing.cancel(w);closeText(g)
 T.eq(g.lastBattle,nil,'cancelled verdict cannot start a stale battle');T.eq(w.emote,replacement,'cleanup preserves another emote owner')
end
do
 local w,g,data=fixture();data.items.ITEM_058.index=1
 T.eq(World.isRod('ITEM_058',data.items),false,'conflicting ROM item metadata is not treated as a rod')
 T.eq(w:useRod('ITEM_058'),'nowhere');T.eq(draws,0)
 T.eq(w:useRod('BICYCLE'),'nowhere');T.eq(draws,0)
end
for _,night in ipairs({false,true})do
 local w,g,data=fixture();w.clockTimeOfDay=function()return night and'NITE'or'DAY'end
 data.field.fishGroups.POND.rods.old={{chance=255,timeGroup=1}}
 data.field.timeFishGroups={[1]={day={species='FIXMON_A',level=8},nite={species='FIXMON_B',level=9}}}
 local outcome,wild=w:rollFishing('OLD_ROD')
 T.eq(outcome,'battle');T.eq(wild.species,night and'FIXMON_B'or'FIXMON_A');T.eq(wild.level,night and 9 or 8)
 T.eq(w.fishing,nil,'pure native roll does not start animation or battle')
 local st=w:beginFishing(outcome,wild);T.eq(st.wild,wild,'public cast accepts its exact native roll')
end
for _,offset in ipairs({1,2})do
 local w,g,data,def,ts=fixture();w.player.cellX=5
 local dest={id='FISH_DEST',tileset='FISH',width=3,height=3,blocks={10,11,12,13,14,15,16,17,18},fishGroup='OTHER'}
 data.maps[dest.id]=dest;def.connections.east={map=dest.id,offset=offset}
 for i=41,80 do ts.collision[i]=0x29 end
 local outcome=w:useRod('OLD_ROD')
 T.eq(outcome,offset==1 and'battle'or'nowhere','native un-clamped seam selects the actual facing-water tile')
 if offset==1 then
  T.eq(w.fishing.bobber.cellX,6,'bobber stays in current-map coordinates at a seam')
  T.eq(w.fishing.wild.level,7,'fishing keeps the current map fish group')
 else T.eq(draws,0,'non-overlapping native connection strip never rolls')end
 T.eq(w.map.id,def.id,'fishing query cannot load or switch the current map')
end
for _,covered in ipairs({false,true})do
 local w,g,data,def,ts=fixture();w.player.cellX=5
 local dest={id='FISH_DEST',tileset='FISH',width=3,height=3,blocks={10,11,12,13,14,15,16,17,18}}
 data.maps[dest.id]=dest;def.connections.east={map=dest.id,offset=1}
 for i=41,80 do ts.collision[i]=0x29 end
 g.save.inventory.ITEM_058=1;g.save.registeredItem='ITEM_058'
 local foreign={name='unrelated screen'};local foreignSlot=#g.stack.states+1;if covered then g.stack:push(foreign)end
 local use=w.useRod;local calls=0;w.useRod=function(self,rod)calls=calls+1;return use(self,rod)end
 BagMenu.useRegistered(g)
 T.eq(calls,covered and 0 or 1,'registered rod uses native boundary water and respects overlays')
 if covered then
  T.eq(g.stack.states[foreignSlot],foreign,'registered item cannot close another screen');T.eq(w.fishing,nil);T.eq(draws,0)
 else T.eq(w.fishing.bobber.cellX,6);T.eq(w.fishing.wild.level,7)end
 T.eq(g.save.inventory.ITEM_058,1)
end
do
 local w=fixture();local roll=w.rollFishing;local calls=0
 w.rollFishing=function(self,rod)
  calls=calls+1;T.eq(self:useRod(rod),'nowhere','public roll wrapper cannot reenter rod admission')
  return roll(self,rod)
 end
 T.eq(w:useRod('OLD_ROD'),'battle');T.eq(calls,1,'actual rod uses the public roll exactly once')
end
do
 local w=fixture();local begin=w.beginFishing
 w.beginFishing=function(self,...)begin(self,...)end
 T.eq(w:useRod('OLD_ROD'),'battle','an observing wrapper may preserve the original void-return convention')
 T.check(w.fishing~=nil)
end
do
 local w,g=fixture()
 T.eq(w:tryFishing('OLD_ROD'),'battle','legacy immediate encounter uses the same native roll')
 T.eq(w.fishing,nil,'immediate legacy path does not create a competing cast')
 T.eq(g.lastBattle.enemy.mon.species,'FIXMON_B');T.eq(creations,1)
end
do
 local w,g=fixture();local native=Battle.newWild(g,'FIXMON_B',7)
 T.eq(native.enemy.mon.species,'FIXMON_B');T.eq(creations,1,'ordinary native battles still construct their own Pokemon')
 local outcome,wild=w:rollFishing('OLD_ROD');local count=creations
 g.save={}
 T.eq(pcall(Battle.newWild,g,wild.species,wild.level,{nativeFishingMon=wild}),false,'expired pure roll cannot bypass cohort admission')
 T.eq(creations,count,'invalid handoff fails before Pokemon/RNG construction')
end
for _,where in ipairs({'roll','begin','text'})do
 local w,g=fixture();local original
 if where=='roll'then
  original=w.rollFishing;w.rollFishing=function()error('intentional fishing roll failure')end
 elseif where=='begin'then
  original=w.beginFishing;w.beginFishing=function(self,...)original(self,...);error('intentional fishing cast failure')end
 else
  w:useRod('OLD_ROD');local TextBox=require('src.render.TextBox');original=TextBox.new
  TextBox.new=function()error('intentional fishing textbox failure')end
 end
 local ok
 if where=='text'then ok=pcall(verdict,w);require('src.render.TextBox').new=original
 else ok=pcall(w.useRod,w,'OLD_ROD');w[where=='roll'and'rollFishing'or'beginFishing']=original end
 T.eq(ok,false,'native '..where..' errors remain visible')
 T.eq(w.fishing,nil);T.eq(w.player.fishingState,nil);T.eq(w.player.fishing,nil)
 T.eq(w:useRod('OLD_ROD'),'battle','failed admission releases its lease for the next real action')
end
do
 local w,g=fixture()
 g.stack.worldOwner=nil;g.stack.worldState=nil;g.stack.states={w}
 T.eq(w:useRod('OLD_ROD'),'battle','native lifecycle also follows the screen-owned field contract')
 local player=w.player;g.stack.states={}
 Fishing.poll();T.eq(w.fishing,nil,'screen-owned field retirement releases the cast')
 T.eq(player.fishingState,nil)
end
do
 local w,g=fixture();w:useRod('OLD_ROD');w._beginFishingBattle=function()return {enemy={mon={}}}end
 verdict(w)
 local box=g.stack:top();box.done=true;box.waiting=false;Input.pressed={a=true}
 T.eq(pcall(g.stack.update,g.stack,1/60),false,'a fake battle callback cannot report a native handoff')
 T.eq(w.fishing,nil);T.eq(w.player.fishingState,nil)
 Input.pressed={}
end
for _,edition in ipairs({'red','emerald','firered','platinum','black'})do
 local w=fixture(edition);T.eq(w:useRod('OLD_ROD'),'nowhere','Gen2 public path cannot alter other generations');T.eq(draws,0)
end
do
 local w,g,data=fixture()
 data.field.fishSwarms={routes={POND={kind='native_swarm',group='SWARM'}}}
 data.field.fishGroups.SWARM={chance=128,rods={old={{chance=255,species='FIXMON_A',level=12}}}}
 g.save.g2FishSwarm='native_swarm'
 local loaded=T.sdk.loadMods({'mods/fishing_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/fishing_probe/manifest.json']='{"id":"fishing_probe","name":"Fishing probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/fishing_probe/main.lua']=[[
   local mod=...;mod.exports.calls=0;mod.exports.reply={species='FIXMON_B',level=19}
   mod.hooks:wrap('encounter.fishing',function(nextFn,rod,map,candidates,ctx)
    mod.exports.calls=mod.exports.calls+1;mod.exports.group=ctx.fishGroup
    mod.exports.candidates=candidates;mod.exports.rod=rod;mod.exports.map=map
    local rolled=nextFn(rod,map,candidates,ctx);mod.exports.native=rolled
    return mod.exports.reply
   end)
  ]],
 })})
 T.eq(#loaded.errors,0,'actual public fishing hook provider installs')
 local outcome,wild=w:rollFishing('OLD_ROD');local observed=loaded.loader.exports.fishing_probe
 T.eq(outcome,'battle');T.eq(observed.calls,1);T.eq(observed.group,'SWARM')
 T.eq(observed.candidates,data.field.fishGroups.SWARM,'hook observes the actual native swarm group')
 T.eq(observed.native.species,'FIXMON_A');T.eq(observed.native.level,12)
 T.eq(wild.species,'FIXMON_B');T.eq(wild.level,19,'hook replacement becomes the actual native individual')
 T.eq(creations,1,'hook never creates a second display Pokemon')
 for _,reply in ipairs({{species='UNKNOWN_NATIVE_FISH',level=7},{species='FIXMON_B',level=0},
  {species='FIXMON_B',level=101},{species='FIXMON_B',level=1.5},{level=7}})do
  observed.reply=reply;draws=0
  T.eq(pcall(w.useRod,w,'OLD_ROD'),false,'invalid hook encounter cannot acquire a cast')
  T.eq(draws,2,'invalid encounter fails before drawing native Pokemon DVs')
  T.eq(w.fishing,nil);T.eq(w.player.fishingState,nil)
 end
 loaded.release()
end
Fishing.release();Pokemon.new=new;love.math.random=random;debug.setupvalue(World.useRod,slot,previousGame);Version.set(before)
T.finish('native Gen2 fishing lifecycle and exact battle individual')
