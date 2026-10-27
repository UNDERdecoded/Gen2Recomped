package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Objects=require('src.core.game3.objects')
local Ghosts=require('src.core.game3.ghosts')
local R=require('src.compat.gen1.ObjectRuntime')
T.eq(package.loaded['src.core.Game'],nil,'queries do not bootstrap Game')
T.eq(Objects.find(1),nil); T.eq(#Objects.forDraw(),0); T.eq(Objects.blocks(1,1),false)
T.eq(Objects.playerBlocks(1,1),false); T.eq(#Ghosts.forDraw('missing'),0)
local Native=require('src.world.NPC')
local Identity=require('src.compat.gen1.MapIdentity')
local Version=require('src.core.GameVersion')
local F=require('tools.session-runtime.fixture')
local function npc(id,x,y)
  return setmetatable({id='native_obj_'..id,def={index=id,localId=id,graphicsId=42,
    elevation=3,x=x,y=y,passable=false,script={'native'}},
    sprite={def={id='SPRITE_G3_042',frames=9}},cellX=x,cellY=y,px=x*16,py=y*16,
    facing='down',moving=false,progress=0,animClock=0,stepFlip=false},Native)
end
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'}) do
  Objects.release()
  local f=F.new(edition); local g,w=f.game,f.world
  local a,b=npc(1,5,5),npc(2,6,6)
  w.npcs={a,b}; w.entities={f.player,a,b}
  g.data.constants.gen3MovementTypes={[1]={facing='left',wanders=false}}
  local v=assert(Objects.find(1)); T.check(v~=a,'never lend the native actor')
  T.eq(Objects.find(1),v,'stable live object view'); T.eq(v.localId,1); T.eq(v.id,a.id)
  T.eq(v.originMapId,f.canonical); T.eq(Objects._mapId,f.canonical)
  T.eq(v.graphicsId,42); T.eq(v.currentElevation,3); T.eq(v.visible,true)
  T.eq(select(2,Objects.loadMap(g,f.canonical)),nil,'adopting a pool never lends its private native context')
  T.eq(select(2,Objects._pool(f.canonical)),nil,'shared neighbour entry returns only owned views')
  T.eq(v.def.passable,false,'definition copy retains false values')
  v.def.script[1]='detached'; T.eq(a.def.script[1],'native','nested definitions are owned')
  v.customExtension={probe=true}; T.eq(a.customExtension,nil)
  T.eq(Objects._byId[1],v); T.same(Objects._order,{1,2})
  local ids=Objects._order; ids[1]=99; T.same(Objects._order,{1,2},'external lists cannot replace native actors')
  T.same(Objects.listActive(),{1,2}); T.eq(#Objects.forDraw(),2)
  T.eq(Objects.at(5,5),v); T.eq(Objects.at(0/0,5),nil)
  T.eq(Objects.blocks(5,5),true); T.eq(Objects.blocks(5,5,1),false)
  T.eq(Objects.blocks(5,5,nil,4),false); T.eq(Objects.blocks(5,5,nil,0),true)
  T.eq(Objects.playerBlocks(4,4,3),true); T.eq(Objects.playerBlocks(4,4,4),false)
  T.eq(Objects.find(0xFF),require('src.core.game3.player')); T.eq(Objects.find(0x800F),Objects.find(0xFF))
  T.eq(Objects.findObjectByLocalIdAndMap(1,f.map.def.group,f.map.def.number),v)
  T.eq(Objects.findObjectByLocalIdAndMap(1,255,255),nil,'unknown map cannot fall through to current pool')
  T.eq(Objects.hideObject(1),true); T.eq(a.hidden,true); T.eq(#Objects.forDraw(),1)
  T.eq(Objects.blocks(5,5),false); T.eq(Objects.showObject(1),true)
  v.invisible=true; T.eq(#Objects.forDraw(),1); T.eq(Objects.blocks(5,5),true,'invisible objects remain solid')
  v.invisible=false; v.passable=true; T.eq(Objects.blocks(5,5),false); v.passable=false
  v.facing='right'; T.eq(a.facing,'right'); T.eq(Objects.turnObject(1,2),true); T.eq(a.facing,'up')
  T.eq(Objects.turnObject(1,'bad'),false); T.eq(a.facing,'up')
  T.raises(function() v.cellX=9 end,'native command owner','unpaired teleport is refused')
  T.raises(function() v.graphicsId=99 end,'native command owner','raw sprite identity writes are refused')
  T.raises(function() v.hidden=1 end,'invalid object boolean','typed visibility')
  T.raises(function() v.raiseX=0/0 end,'invalid object offset','finite offsets')
  v.raiseX=7; T.eq(a.shiftPx,7); T.eq(v.raiseX,7)
  v.customFrame=8; T.eq(a.fixedFrame,8)
  T.raises(function() v.customFrame=9 end,'invalid object frame','frame is in actual sheet')
  v.customFrame=nil; T.eq(a.fixedFrame,nil)
  T.eq(Objects.freeze(1),true); T.eq(a.gen3ScriptFrozen,true); T.eq(v.frozen,true)
  T.eq(Objects.unfreeze(1),true); T.eq(a.gen3ScriptFrozen,nil)
  T.eq(Objects.setMovementType(1,1),true); T.eq(a.facing,'left'); T.eq(v.movementType,1)
  T.eq(Objects.setMovementType(1,250),false); T.eq(a.gen3MovementType,1)
  T.eq(Objects.facePlayer(1),true); T.eq(a.facing,'up')
  a.sprite={def={id='SPRITE_G3_077',frames=9}}; T.eq(v.graphicsId,77,'live variable-sheet identity')
  a.moving=true; a.targetX=6; a.targetY=5; a.progress=4
  T.eq(Objects.at(5,5),nil); T.eq(Objects.at(6,5),v)
  T.eq(Objects.blocks(5,5),true); T.eq(Objects.blocks(6,5),true)
  T.eq(Objects.walkPhase(v),a:walkPhase())
  a.sliding=true; T.eq(Objects.walkPhase(v),0,'native sliding pose holds standing frame'); a.sliding=nil
  a.sprite.def.holdStep=true; T.eq(Objects.walkPhase(v),1,'native held walk animation'); a.sprite.def.holdStep=nil
  b.def.passable=true; T.eq(Objects.blocks(6,6),false,'authored passable bodies stay passable'); b.def.passable=false
  b.berryVisualEmpty=true; T.eq(#Objects.forDraw(),1,'empty berry stage is not rendered'); b.berryVisualEmpty=nil
  local before=R.copy(a); local clock=g.save.playTime
  for _=1,12 do Objects.forDraw(); local observed=Objects._byId end
  T.eq(a.progress,before.progress); T.eq(a.animClock,before.animClock); T.eq(g.save.playTime,clock)
  -- The native walker alone moves the actor. Observations see each pixel.
  a.frozen=true
  for _=1,12 do
    a:update(f.map,w.entities)
    T.eq(v.px,a.px); T.eq(v.cellX,a.cellX); T.eq(Objects.walkPhase(v),a:walkPhase())
  end
  T.eq(a.cellX,6); T.eq(a.moving,false); T.eq(v.stepFlip,true)
  a.hopFrames=16; a.hopTotal=32
  local _,_,poseY=a:pose(); T.eq(v.raiseY,a.py-poseY)
  for _=1,5 do T.eq(v.raiseY,a.py-poseY) end
  T.eq(a.hopFrames,16,'render observations never advance jump timers')
  local others=require('src.compat.gen1.MapNames')[edition]
  local row
  for _,candidate in ipairs(others) do if candidate[3]~=f.canonical then row=candidate; break end end
  local def={id='AWAY',group=row[1],number=row[2]}; g.data.maps.AWAY=def
  local awayMap={id='AWAY',def=def}; local other=npc(1,2,3)
  local nb={map=awayMap,peers={other},cx=20,cy=-10}
  w.neighbors={nb}; w.ghosts={{npc=other,nb=nb,ox=320,oy=-160}}
  local ghosts=Ghosts.forDraw(row[3]); T.eq(#ghosts,1,'peer/ghost duplicate has one live view')
  local gv=ghosts[1]; T.check(gv~=v); T.eq(gv.px,32); T.eq(gv.py,48,'offsets are applied by renderer once')
  T.eq(gv.originMapId,row[3]); T.eq(Objects.findObjectByLocalIdAndMap(1,row[1],row[2]),gv)
  T.eq(Objects.find(1),v,'same local id on another map does not alias')
  collectgarbage('collect'); T.eq(Objects.find(1),v,'held views retain their identity across collection')
  T.eq(Ghosts.visibleIds(row[3])[1],true); T.eq(#Ghosts.forDraw(f.canonical),0)
  T.eq(#Ghosts.forDraw('DOES_NOT_EXIST'),0,'unknown map never borrows the home pool')
  -- Native removal irrevocably retires observed handles.
  w.npcs={b}; w.entities={f.player,b}; T.eq(v.px,nil)
  w.npcs={a,b}; w.entities={f.player,a,b}; T.eq(v.px,nil)
  local replacement=Objects.find(1); T.check(replacement~=v,'reinserted actor gets fresh handle')
  T.raises(function() v.hidden=true end,'retired','retired handle cannot affect reinserted actor')
  w.neighbors={}; w.ghosts={}; T.eq(gv.px,nil)
  w.neighbors={nb}; w.ghosts={{npc=other,nb=nb,ox=320,oy=-160}}; T.eq(gv.px,nil)
  -- Save, loader, dataset, player, map and generation swaps all retire views.
  for _,replace in ipairs({
    function() g.save={player={}} end,
    function() g.mods={} end,
    function() local maps={}; for k,value in pairs(g.data.maps) do maps[k]=value end; g.data.maps=maps end,
    function() local data={}; for k,value in pairs(g.data) do data[k]=value end; g.data=data end,
    function() w.player=R.copy(f.player) end,
    function() w.map={id=f.map.id,def=f.map.def,inBounds=f.map.inBounds} end,
  }) do
    local old=assert(Objects.find(1)); replace(); T.eq(old.px,nil)
    T.raises(function() old.facing='left' end,'retired','cohort switch rejects stale writes')
    T.check(Objects.find(1)~=old)
  end
  local old=Objects.find(1); Objects.clear(); T.eq(old.px,nil); T.eq(#w.npcs,2,'clear does not clear native NPCs')
  T.check(Objects.find(1)~=old)
  local live=Objects.find(1); Version.set('crystal'); T.eq(live.px,nil); Version.set(edition)
  T.check(Objects.find(1)~=live,'a retired cohort cannot revive after edition restoration')
  Version.set('crystal'); T.eq(Objects.find(1),nil)
end
T.finish('native object views')
