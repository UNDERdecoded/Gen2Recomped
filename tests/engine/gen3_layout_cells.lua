package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local Version=require('src.core.GameVersion');local prior=Version.get()
local Map=require('src.world.Map');local Copy=require('src.mods.Merge').deepCopy
local function packed(cells)
 local out={};for _,c in ipairs(cells)do local word=c[1]+c[2]*1024+c[3]*4096;out[#out+1]=string.char(word%256,math.floor(word/256))end;return table.concat(out)
end
local function fixture()
 local def={id='NATIVE_GRID',width=2,height=2,blocks=packed{{7,0,3},{8,1,4},{9,2,0},{10,3,15}},collisionCells={0,1,2,3},elevationCells={3,4,0,15},borderBlock=1}
 local ts={blockCells=1,blockTiles=2,walkable={0},collision={},behaviourBytes=true}
 for i=1,1024 do ts.collision[i]=0 end
 return Map.new(def,ts),Copy(def)
end
local function cell(m,x,y)return {m:blockAt(x,y),m:cellCollision(x,y),m:cellElevation(x,y)}end
for _,version in ipairs{'firered','emerald'}do
 Version.set(version);local m,base=fixture();local original=m.def;local baseBytes=original.blocks
 local target=Copy(base);target.collisionCells[1]=3;target.elevationCells[1]=15
 T.eq(m:applyGen3Layout(target),1,version..' identical artwork can change permissions and height')
 T.same(cell(m,0,0),{7,3,15},'all three live native components agree')
 T.eq(m:isWalkableCell(0,0),false,'actual native collision blocks same-art cell')
 T.eq(m:isUnderBridgeCell(0,0),true,'actual native bridge query reads new elevation')
 T.eq(m.blocksDirty,true,'terrain change invalidates actual native drawing')
 T.eq(m.def,original,'live map keeps original definition identity');T.eq(original.blocks,baseBytes,'shared imported artwork is unchanged')
 T.same(original.collisionCells,{0,1,2,3},'shared imported collision is unchanged');T.same(original.elevationCells,{3,4,0,15},'shared imported elevation is unchanged')
 T.eq(m:applyGen3Layout(base),1,'restoring base layout compares against live state')
 T.same(cell(m,0,0),{7,0,3},'restore changes artwork collision and height back together')
 T.eq(m:patchedImpassable(0,0),false,'restore removes prior coordinate seal')
 local rev=m.gridRevision;m.blocksDirty=nil
 T.eq(m:applyGen3Layout(base),0,'already active native layout is a no-op')
 T.eq(m.gridRevision,rev,'no-op does not advance grid revision');T.eq(m.blocksDirty,nil,'no-op does not request redraw')
 m:setBlock(0,0,17,true);T.eq(m:applyGen3Layout(base),1,'base layout retires earlier scripted artwork and seal')
 T.same(cell(m,0,0),{7,0,3},'ordinary scripted mutation and layout have one owner')
 T.eq(m:setGen3Cells{{x=0,y=0,elev=0}},1,'explicit zero elevation is a change')
 T.eq(m:cellElevation(0,0),0,'native mover sees explicit zero')
 T.eq(m:setGen3Cells{{x=0,y=0,elev=15}},1,'bridge elevation 15 is retained')
 m:clearBlock(0,0);T.same(cell(m,0,0),{7,0,3},'clearing one cell restores its native elevation too')
 m.elevationPatch[1]=12;m.blockPatch={};m.collisionPatch={};m.shutCells={}
 T.eq(m:clearBlockPatches(),true,'height-only native patches can be cleared')
 T.eq(m:cellElevation(0,0),3,'height-only clear returns to source elevation')
 T.eq(m:clearBlockPatches(),false,'second clear is empty')
 rev=m.gridRevision
 T.eq(m:setGen3Cells{{x=0,y=0,mid=20},{x=0,y=0,coll=2,elev=1}},1,'duplicate rows compose before one actual native write')
 T.same(cell(m,0,0),{20,2,1},'batch preserves each explicit component')
 T.eq(m.gridRevision,rev+1,'one changed batch has one native revision')
 local before=cell(m,0,0);rev=m.gridRevision;m.blocksDirty=nil
 local invalid={
  {{x=0,y=0,mid=2},{x=2,y=0,mid=3}},
  {{x=0,y=0,mid=1024}},{{x=0,y=0,coll=4}},{{x=0,y=0,elev=16}},
  {{x=0,y=0,mid=0/0}},{{x=0.5,y=0,mid=2}},{{x=-1,y=0,mid=2}},{{x=0,y=0}},
  {[2]={x=0,y=0,mid=2}},{wrong={x=0,y=0,mid=2}},'not an array',
 }
 for _,rows in ipairs(invalid)do
  local changed,why=m:setGen3Cells(rows);T.eq(changed,nil,'invalid batch rejected');T.eq(type(why),'string','native rejection explains cause')
  T.same(cell(m,0,0),before,'invalid batch cannot partially change native cell');T.eq(m.gridRevision,rev,'invalid batch cannot advance revision');T.eq(m.blocksDirty,nil,'invalid batch cannot request redraw')
 end
 T.eq(m:setGen3Cells{{x=0,y=0,mid=7},{x=0,y=0,mid=20}},0,'intermediate duplicate changes do not leak into native state')
 T.eq(m.gridRevision,rev,'net no-op duplicate batch has no revision')
 target={width=2,height=2,blocks=packed{{1023,3,15},{8,1,4},{9,2,0},{10,3,15}}}
 T.eq(m:applyGen3Layout(target),1,'native packed layout supplies all raw bits without side arrays')
 T.same(cell(m,0,0),{1023,3,15},'full packed halfword is decoded')
 T.eq(m:applyGen3Layout{width=2,height=2,blocks={4,8,9,10}},1,'art-only authored rows preserve unspecified native permissions')
 T.same(cell(m,0,0),{4,3,15},'art-only write cannot invent passability or elevation')
 before=cell(m,0,0);rev=m.gridRevision;m.blocksDirty=nil
 for _,bad in ipairs{
  {width=3,height=2,blocks={1,2,3,4,5,6}},
  {width=2,height=2,blocks={2,3,4}},
  {width=2,height=2,blocks=packed{{2,0,0}}},
  {width=2,height=2,blocks={1,2,3,4},collisionCells={0,0,0}},
  {width=2,height=2,blocks={1,2,3,4},elevationCells={0,0,0,16}},
 }do
  local changed,why=m:applyGen3Layout(bad);T.eq(changed,nil,'invalid full layout rejects atomically');T.eq(type(why),'string','layout rejection is explained')
  T.same(cell(m,0,0),before,'invalid layout cannot change an earlier cell');T.eq(m.gridRevision,rev,'invalid layout keeps revision');T.eq(m.blocksDirty,nil,'invalid layout keeps render state')
 end
 -- Real decoded ROM command -> Gen3 VM -> actual ScriptRunner -> native grid.
 local data=T.fixtures.fresh();data.map_layouts={[1]=base,[2]=target,[3]={width=9,height=9,blocks={}}}
 data.map_scripts={source='RomExtractorGen3',scripts={ALT={{'setmaplayoutindex',2},{'end'}},BASE={{'setmaplayoutindex',1},{'end'}},BAD={{'setmaplayoutindex',3},{'end'}},ABSENT={{'setmaplayoutindex',99},{'end'}}}}
 local world={map=m};local game={data=data,save={flags={},party={}}};local runner=require('src.script.ScriptRunner').new(game,world);local VM=require('src.script.Gen3ScriptVM')
 runner:run(VM.compile(data,'ALT'));T.eq(runner:isRunning(),false,'actual native VM completes layout command')
 T.same(cell(m,0,0),{1023,3,15},'actual native compiled command changes current grid')
 T.eq(m.gen3LayoutOverride,2,'only applied layout is advertised')
 runner:run(VM.compile(data,'BAD'));T.eq(m.gen3LayoutOverride,2,'failed dimension change does not advertise another layout')
 runner:run(VM.compile(data,'ABSENT'));T.eq(m.gen3LayoutOverride,2,'missing layout keeps actual successful identity')
 runner:run(VM.compile(data,'BASE'));T.same(cell(m,0,0),{7,0,3},'actual native VM restores original source layout')
 T.eq(m.gen3LayoutOverride,1,'successful restore reports actual selected layout');m:clearBlockPatches();T.eq(m.gen3LayoutOverride,nil,'native map reload clears prior selected layout')
 local fresh=fixture();T.eq(fresh:blockAt(0,0),7,'native source grid is decoded')
 fresh.def.blocks=packed{{11,0,3},{8,1,4},{9,2,0},{10,3,15}}
 T.eq(fresh:blockAt(0,0),11,'native source replacement cannot reuse old decoded artwork')
end
Version.set(prior)
T.finish('native Gen3 grid transactions and layout restoration')
