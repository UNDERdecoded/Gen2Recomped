-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-landmarks.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
local Native=require('src.world.Gen2Landmarks');local E=require('src.import.RomExtractorGen2')
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local VM=require('src.script.Gen2ScriptVM');local Runner=require('src.script.ScriptRunner')
local Gear=require('src.ui.PokegearMenu');local TownMap=require('src.ui.TownMap')
local Importer=require('src.import.RomImporter')
local markerFor
for i=1,100 do local name,value=debug.getupvalue(Importer.readyReport,i)
 if name=='markerFor'then markerFor=value;break end;if not name then break end
end
assert(markerFor)
local function extractor(version,order)
 local records={}
 for i=0,95 do records[#records+1]=string.char(i%160,(i+20)%144,0,0x50)end
 local raw=string.rep('\0',0x4000)..table.concat(records)
 raw=raw..string.rep('\0',0x5000-#raw)..string.char(0x80,0x80,0x50)..string.rep('\0',0x2ffd)
 local e=E.new(raw,version,{symbols={Landmarks={1,0x4000}},landmarkOrder=order})
 function e:readSourceTable(key)assert(key=='charmap');return{['128']='A'}end -- authored source-table IO
 return e
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);local order=Native.order(version);local count=version=='crystal' and 96 or 95
 T.eq(#order,count,version..' exact native landmark count includes the final ship')
 T.eq(order[30],version=='crystal' and 'LANDMARK_BATTLE_TOWER' or 'LANDMARK_ROUTE_40',version..' Duellturm insertion is edition-specific')
 T.eq(order[#order],'LANDMARK_FAST_SHIP',version..' final identity remains the native ship')
 local e=extractor(version);local rows=e:gen2Landmarks()
 T.eq(rows[count-1].id,'LANDMARK_FAST_SHIP',version..' real ROM reader reaches final native row')
 T.eq(rows[count-1].index,count-1,version..' importer records actual map-header byte')
 T.eq(rows[count-1].name,'AA',version..' actual native text decoder supplies display name')
 T.eq(rows[count-1].x,(count-1)%160,version..' raw OAM x coordinate is not converted to a tile cell')
 T.eq(rows[count-1].y,(count+19)%144,version..' raw OAM y coordinate is unchanged')
 T.eq(rows[count],nil,version..' stock import cannot read beyond its actual landmark count')
 order[1]='LEAK';T.eq(Native.order(version)[1],'LANDMARK_SPECIAL',version..' identity views are detached')
 local town=e:gen2TownMap()
 T.eq(town.landmarks[count-1].id,'LANDMARK_FAST_SHIP',version..' missing picture does not discard valid script names')
 T.eq(town.landmarkOrder[count],'LANDMARK_FAST_SHIP',version..' actual town-map output carries identity order')
 T.eq(town.johto,nil,version..' missing picture cannot invent fallback map art')
 local marker=markerFor(version)
 T.check(marker:find('gen2%-landmark%-identities%-v1:')~=nil,version..' new native identity cache revision is present')
 love.filesystem.write(V.cachePrefix(version)..'rom-cache.complete',marker:gsub('gen2%-landmark%-identities%-v1:',''))
 T.eq(Importer.readyReport(version).ok,false,version..' old truncated identity-less cache requires reimport')
end
for _,version in ipairs({'prism','polishedcrystal','red'})do
 T.eq(#Native.order(version),0,version..' unreviewed layout cannot acquire stock landmark identities')
 T.eq(Native.order(version,{landmarkOrder={'AUTHORED_ZERO','AUTHORED_ONE'}})[2],'AUTHORED_ONE',version..' explicit manifest identities remain authoritative')
end
T.eq(extractor('crystal',{'DUPLICATE','DUPLICATE'}):gen2Landmarks(),nil,'invalid declared identities cannot silently fall back to retail count')
T.eq(extractor('crystal',{'ONLY'}):gen2Landmarks()[1],nil,'explicit custom count bounds actual ROM reads')
local function fixture(version)
 local d=T.fixtures.fresh();local pallet=version=='crystal' and 47 or 46
 d.field.townMap={johto='qa-johto-'..version,kanto='qa-kanto-'..version,playerIcon='qa-player-'..version,
  landmarkOrder=Native.order(version),landmarks={
   [0]={id='LANDMARK_SPECIAL',index=0,name='NOWHERE',x=0,y=0},
   [1]={id='LANDMARK_NEW_BARK_TOWN',index=1,name='LOCAL HOME',x=20,y=32},
   [2]={id='LANDMARK_ROUTE_29',index=2,name='LOCAL ROAD',x=40,y=48},
   [pallet]={id='LANDMARK_PALLET_TOWN',index=pallet,name='LOCAL PALLET',x=72,y=80},
   [pallet-1]={id='LANDMARK_SILVER_CAVE',index=pallet-1,name='LOCAL CAVE',x=88,y=96}}}
 d.maps.HOME={id='HOME',landmark=1};d.maps.CAVE={id='CAVE',landmark=pallet-1}
 d.maps.PALLET_TOWN={id='PALLET_TOWN',landmark=pallet};d.maps.EXTRA={id='EXTRA',landmark=200}
 d.map_scripts={scripts={HERE={{'getcurlandmarkname',0},{'end'}},THERE={{'getlandmarkname',200,0},{'end'}}}}
 return d
end
local function load(d,source,mode)
 for root in pairs(require('src.mods.Builtins').namespaceRoots())do d[root]=nil end
 local files,paths={},{}
 if source then
  files['mods/landmarks/manifest.json']=Json.encode({id='landmarks',name='Landmarks',version='1.0.0',
   api=mode and mode[1] or 2,content_format=mode and mode[2] or 'native',entry='main.lua',affects_link=false})
  files['mods/landmarks/main.lua']='local mod=...;mod.exports.api=mod;'..source;paths={'mods/landmarks'}
 end
 return T.sdk.loadMods(paths,{data=d,fs=T.sdk.memfs(files)})
end
local function finish(r)Loader.teardown();r.release()end
local function game(d,map)
 return {data=d,save={inventory={}},overworld={map={id=map,def=d.maps[map]}},
  stack={pop=function()end},input={wasPressed=function()return false end}}
end
local function run(g,label)
 local r=Runner.new(g,g.overworld);r:run(assert(VM.compile(g.data,label)));return r
end
local oldImage,oldDraw=love.graphics.newImage,love.graphics.draw
local paints={}
love.graphics.newImage=function(path)return{path=path,getDimensions=function()return 160,144 end}end
love.graphics.draw=function(image,x,y)paints[#paints+1]={path=image.path,x=x,y=y}end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 do
  local d=fixture(version);local before=d.field.townMap.landmarks;local clean=load(d)
  T.eq(#clean.errors,0,version..' no-mod native boot stays valid')
  T.eq(d.field.townMap.landmarks,before,version..' no-mod load leaves native target identity untouched')
  finish(clean)
 end
 for _,mode in ipairs({{1,'native'},{2,'native'}})do
  local d=fixture(version);local before=d.field.townMap.landmarks
  local r=load(d,[[local p=mod.content["landmarks"]
   assert(p:supports())
   assert(p:get('LANDMARK_ROUTE_29').name=='LOCAL ROAD')
   local v=p:get('LANDMARK_ROUTE_29');v.name='LEAK'
   for _,row in p:each()do row.x=999 end
   assert(p:get('LANDMARK_ROUTE_29').x==40)
   p:patch('LANDMARK_NEW_BARK_TOWN',{name='AUTHORED\nHOME',x=52,y=68})
   p:register('LANDMARK_EXTRA',{name='AUTHORED EXTRA',x=100,y=104,index=200})
   p:remove('LANDMARK_ROUTE_29')
  ]],mode)
  local label=version..'/'..mode[1]..'/'..mode[2]
  T.eq(#r.errors,0,label..' public landmark records load through real mod API')
  T.eq(d.field.townMap.landmarks[1].name,'AUTHORED\nHOME',label..' native numeric row receives authored text')
  T.eq(d.field.townMap.landmarks[2],nil,label..' removed row cannot survive by fallback')
  T.eq(d.field.townMap.landmarks[200].landmarkId,'LANDMARK_EXTRA',label..' new identity binds actual byte200')
  T.eq(before[1].name,'LOCAL HOME',label..' source native row is not mutated')
  local g=game(d,'HOME');run(g,'HERE')
  T.eq(g.stringBuffers and g.stringBuffers[3],'AUTHORED HOME',label..' actual current-landmark VM reads authored native name')
  run(g,'THERE');T.eq(g.stringBuffers and g.stringBuffers[3],'AUTHORED EXTRA',label..' actual named-landmark VM reads registered byte')
  local screen=TownMap.new(g)
  T.eq(screen.mode,'gen2',label..' real map controller consumes native table')
  T.eq(screen.byMap.HOME.px,48,label..' actual map marker applies native OAM origin once')
  T.eq(screen.byMap.HOME.py,56,label..' native marker y keeps raw coordinate units')
  T.eq(screen.byMap.PALLET_TOWN.region,'kanto',label..' first actual Kanto byte selects Kanto')
  T.eq(screen.byMap.CAVE.region,'johto',label..' preceding cave remains on Johto')
  T.eq(screen.byMap.EXTRA.name,'AUTHORED EXTRA',label..' native map controller consumes added marker')
  local text
  local gear=setmetatable({game=g,drawStrip=function()end,drawModeArrow=function()end,
   text=function(_,value)text=value end},{__index=Gear})
  paints={};gear:drawMap()
  T.eq(text,'AUTHORED HOME',label..' actual Pokegear label reads the same authored name')
  T.eq(paints[1].path,d.field.townMap.johto,label..' actual Pokegear paints the correct Johto image')
  T.eq(paints[2].x,44,label..' actual Pokegear player sprite consumes authored OAM x')
  T.eq(paints[2].y,52,label..' actual Pokegear player sprite consumes authored OAM y')
  g.overworld.map={id='PALLET_TOWN',def=d.maps.PALLET_TOWN};paints={};gear:drawMap()
  T.eq(paints[1].path,d.field.townMap.kanto,label..' Pokegear correctly paints Gold/Silver first Kanto town too')
  local api=r.loader.exports.landmarks.api.content.landmarks
  T.check(not pcall(function()api:patch('LANDMARK_EXTRA',{name='LATE'})end),label..' content freezes after load')
  finish(r);local clean=load(d)
  T.eq(d.field.townMap.landmarks,before,label..' disabling restores original numeric table identity')
  T.eq(d.field.townMap.landmarks[200],nil,label..' disabling removes the authored byte')
  finish(clean)
 end
end
V.set('crystal')
for _,source in ipairs({
 "p:register('BAD',{name='BAD',x=1,y=1,index=256})",
 "p:register('BAD',{name='BAD',x=-1,y=1,index=200})",
 "p:register('BAD',{name='BAD',x=0/0,y=1,index=200})",
 "p:register('BAD',{name='BAD',x=1,y=math.huge,index=200})",
 "p:register('BAD',{name='BAD',x=1,y=1,index=200,typo=true})",
 "p:patch('LANDMARK_NEW_BARK_TOWN',{name=mod.DELETE})",
 "local x={};x.name=x;p:register('BAD',x)",
 "error('entry failed')",
})do
 local d=fixture('crystal');local before=d.field.townMap.landmarks
 local r=load(d,"local p=mod.content.landmarks;p:patch('LANDMARK_NEW_BARK_TOWN',{name='FAIL'});"..source)
 T.check(#r.errors>0,'invalid native record is attributed: '..source)
 T.eq(d.field.townMap.landmarks,before,'failed entry rolls back prior valid landmark edits')
 finish(r)
end
do
 local d=fixture('crystal');local r=load(d,[[local p=mod.content.landmarks
  p:register('Z_NEW',{name='Z',x=10,y=20,index=200})
  p:register('A_NEW',{name='A',x=30,y=40,index=200})
  p:register('A_SHADOW',{name='SHADOW',x=99,y=99,index=1})
 ]])
 T.eq(#r.errors,0,'reference-compatible duplicate index claims are deterministic')
 T.eq(d.field.townMap.landmarks[1].name,'LOCAL HOME','native identity wins its own slot')
 T.eq(d.field.townMap.landmarks[200].name,'A','lexically earlier newcomer wins other slot')
 finish(r)
end
do
 local d=fixture('crystal');local r=load(d,[[mod.content.landmarks:patch('LANDMARK_NEW_BARK_TOWN',{index=201})]])
 T.eq(#r.errors,0,'reference record may move to an unused native index')
 T.eq(d.field.townMap.landmarks[201].landmarkId,'LANDMARK_NEW_BARK_TOWN','moved identity reaches new native index')
 T.eq(d.field.townMap.landmarks[1].name,'LOCAL HOME','reference order remains fallback for unclaimed original slot')
 finish(r)
end
do
 local d=fixture('crystal');d.field.townMap.landmarks['2']=d.field.townMap.landmarks[2]
 d.map_scripts.scripts.ZERO={{'getlandmarkname',0,0},{'end'}}
 local before=d.field.townMap.landmarks;local r=load(d,[[local p=mod.content.landmarks
  p:remove('LANDMARK_ROUTE_29');p:patch('LANDMARK_SPECIAL',{name='AUTHORED ZERO'})
 ]])
 T.eq(#r.errors,0,'numeric/string native aliases and byte zero remain supported')
 T.eq(d.field.townMap.landmarks[2],nil,'removal drops numeric native slot')
 T.eq(d.field.townMap.landmarks['2'],nil,'string fallback cannot resurrect removed landmark')
 local g=game(d,'HOME');run(g,'ZERO')
 T.eq(g.stringBuffers[3],'AUTHORED ZERO','actual native script names byte zero rather than treating it as absent')
 finish(r);local clean=load(d)
 T.eq(d.field.townMap.landmarks,before,'unload restores original numeric/string alias layout')
 T.eq(before['2'],before[2],'restored aliases retain their original shared record')
 finish(clean)
end
do
 local d=fixture('crystal');local r=load(d,[[mod.content.landmarks:patch('LANDMARK_PALLET_TOWN',{index=48})]])
 T.eq(#r.errors,0,'moving the logical first Kanto landmark is a native byte edit')
 T.eq(Native.kantoStart(d),48,'region boundary consumes authored landmark index metadata')
 local g=game(d,'PALLET_TOWN');local screen=TownMap.new(g)
 T.eq(screen.byMap.PALLET_TOWN.region,'johto','town map follows the same authored boundary')
 paints={};setmetatable({game=g,drawStrip=function()end,drawModeArrow=function()end,text=function()end},{__index=Gear}):drawMap()
 T.eq(paints[1].path,d.field.townMap.johto,'actual Pokegear background consumes authored boundary')
 finish(r)
end
do
 local d=fixture('crystal');local before=d.field.townMap.landmarks
 local r=load(d,[[mod.content.landmarks:patch('LANDMARK_NEW_BARK_TOWN',{name='OWN'})
  mod.content.landmarks:register('EXTRA',{name='EXTRA',x=100,y=100,index=200})]])
 local row=d.field.townMap.landmarks[1];row.name='EXTERNAL'
 finish(r);local clean=load(d)
 T.eq(d.field.townMap.landmarks[1],row,'reload preserves externally edited native record identity')
 T.eq(row.name,'EXTERNAL','reload preserves external text')
 T.eq(d.field.townMap.landmarks[200],nil,'external edit does not retain unchanged owned addition')
 T.eq(d.field.townMap.landmarks[2],before[2],'unrelated original record identity restores')
 finish(clean)
end
do
 local d=T.fixtures.fresh();d.field=nil
 local r=load(d,[[mod.content.landmarks:register('NEW',{name='NEW',x=20,y=30,index=200})]])
 T.eq(#r.errors,0,'indexed authored names can create a native script target without map art')
 T.eq(d.field.townMap.landmarks[200].name,'NEW','new native target is readable')
 finish(r);local clean=load(d)
 T.eq(d.field,nil,'unload retires exclusively owned rows, town and field namespaces')
 finish(clean)
end
for _,version in ipairs({'red','firered','emerald','heartgold'})do
 V.set(version);local d=fixture('crystal');local before=d.field.townMap.landmarks
 local r=load(d,[[local p=mod.content.landmarks;assert(not p:supports());assert(p:get('LANDMARK_ROUTE_29')==nil)
  p:register('NO_WRITE',{name='NO',x=20,y=30,index=200})]])
 T.eq(#r.errors,0,version..' absent native target is reported through public handle')
 T.eq(d.field.townMap.landmarks,before,version..' cannot mutate lookalike Gen2 town map')
 finish(r)
end
love.graphics.newImage=oldImage;love.graphics.draw=oldDraw;V.set(original)
T.finish('native landmark identities, real map/gear/name consumers, reload ownership and edition boundaries')
