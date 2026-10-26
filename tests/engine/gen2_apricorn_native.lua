-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-apricorn-selection.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
local E=require('src.import.RomExtractorGen2');local Writer=require('src.import.LuaWriter')
local A=require('src.world.Gen2Apricorns');local VM=require('src.script.Gen2ScriptVM')
local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack')
local Commands=require('src.script.Commands');local Flags=require('src.script.Gen2Flags')
local Importer=require('src.import.RomImporter')
local markerFor
for i=1,100 do
 local name,value=debug.getupvalue(Importer.readyReport,i)
 if name=='markerFor'then markerFor=value;break end
 if not name then break end
end
assert(markerFor)
local function extractor(version,bytes,address,length)
 address=address or 0x4000
 local raw=string.rep('\0',address)..string.char(unpack(bytes))
 if length and #raw<length then raw=raw..string.rep('\0',length-#raw)end
 local e=E.new(raw,version,{symbols={ApricornBalls={1,address}}})
 function e:readSourceTable()return{}end
 return e
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 local e=extractor(version,{117,201,119,203,118,202,255},nil,0x8000)
 local rows,info=e:gen2ApricornBalls()
 T.eq(info.complete,true,version..' actual terminated native table is complete')
 T.eq(info.rowsRead,3,version..' terminator is not a fabricated recipe')
 T.eq(rows[1].apricorn,'ITEM_117',version..' importer retains actual native item ID')
 T.eq(rows[2].apricorn,'ITEM_119',version..' importer retains cartridge table order')
 T.eq(rows[2].ball,'ITEM_203',version..' importer retains actual paired ball ID')
 T.eq(rows[3].index,3,version..' native pair index is explicit')
 local encoded
 function e:write(name,value)if name=='map_scripts'then encoded=Writer.encode(value)end end
 e:extractMapScripts()
 local data={map_scripts=assert(loadstring(assert(encoded)))()}
 T.eq(data.map_scripts.apricornInfo.complete,true,version..' actual map-script output serializes completeness')
 T.eq(data.map_scripts.apricornBalls[2].ball,'ITEM_203',version..' actual output retains native recipe pairs')
 local menu=A.inBag(data,{inventory={ITEM_118=2,ITEM_119=3,ITEM_117=1,ITEM_120=9}})
 T.eq(#menu,3,version..' native selector excludes unrelated inventory items')
 T.eq(menu[1].item,117,version..' selector follows cartridge order rather than bag order')
 T.eq(menu[2].item,119,version..' selector does not sort native IDs numerically')
 T.eq(menu[2].quantity,3,version..' native inventory quantity reaches the selector')
 menu[1].apricorn='LEAK'
 T.eq(data.map_scripts.apricornBalls[1].apricorn,'ITEM_117',version..' returned menu records are detached')
 T.eq(#A.inBag(data,{inventory={ITEM_117=-1,ITEM_118=0/0,ITEM_119=math.huge}}),0,version..' invalid counts cannot populate the native menu')
 local empty,meta=extractor(version,{255}):gen2ApricornBalls()
 T.eq(meta.complete,true,version..' explicit empty table is complete')
 T.eq(#A.rows({map_scripts={apricornBalls=empty,apricornInfo=meta}}),0,version..' empty table never restores retail recipes')
 for _,bytes in ipairs({{117,201,118},{117,201,117,202,255},{117,0,255},{0,201,255}})do
  local bad,bounds=extractor(version,bytes):gen2ApricornBalls()
  T.eq(bounds.complete,false,version..' malformed/truncated table is explicit')
  T.eq(#bad,0,version..' malformed table never publishes a partial native prefix')
  T.eq(#A.rows({map_scripts={apricornBalls=bad,apricornInfo=bounds}}),0,version..' malformed table cannot silently restore retail recipes')
 end
 local bytes={};for i=1,129 do bytes[#bytes+1]=i;bytes[#bytes+1]=200 end
 local bad,bounds=extractor(version,bytes):gen2ApricornBalls()
 T.eq(bounds.complete,false,version..' unterminated table is bounded')
 T.eq(bounds.reason,'unterminated table',version..' bounded failure is explained')
 T.eq(#bad,0,version..' bounded failure publishes no partial list')
 bad,bounds=extractor(version,{117},0x7fff):gen2ApricornBalls()
 T.eq(bounds.complete,false,version..' pair cannot cross a cartridge bank boundary')
 T.eq(#bad,0,version..' bank-boundary failure has no invented pair')
 local fallback=A.rows({})
 for i,id in ipairs({85,89,92,93,97,99,101})do
  T.eq(fallback[i].apricorn,string.format('ITEM_%03d',id),version..' historical fallback retains native cartridge item order at slot'..i)
 end
 T.eq(fallback[3].ball,nil,version..' historical fallback does not invent missing ball mappings')
 local marker=markerFor(version)
 T.check(marker:find('gen2%-apricorn%-table%-v1:')~=nil,version..' stock native cache records the recipe import format')
 love.filesystem.write(V.cachePrefix(version)..'rom-cache.complete',marker:gsub('gen2%-apricorn%-table%-v1:',''))
 local report=Importer.readyReport(version)
 T.eq(report.ok,false,version..' actual readiness rejects the recipe-less cache')
 T.check(report.why:find('another version',1,true)~=nil,version..' recipe-less cache is rejected before missing-file checks')
end
for _,version in ipairs({'prism','polishedcrystal','red','emerald'})do
 T.eq(extractor(version,{117,201,255}):gen2ApricornBalls(),nil,version..' unrelated layout is not guessed')
 T.check(not markerFor(version):find('gen2%-apricorn%-table%-v1:'),version..' unrelated cache format is unchanged')
end
local oldSound=require('src.core.Sound').play
require('src.core.Sound').play=function()end
local oldText=Commands.show_text;Commands.show_text=function()end -- text/audio IO only
local serial=0
local function gameFor(version,inventory,tableRows)
 V.set(version);serial=serial+1
 local d=T.fixtures.fresh()
 d.items.ITEM_117={id='ITEM_117',name='AUTHORED APRICORN',pocket='ITEM'}
 d.items.ITEM_119={id='ITEM_119',name='OTHER APRICORN',pocket='ITEM'}
 d.items.ITEM_202={id='ITEM_202',name='NATIVE BALL',pocket='BALL',ball=true}
 local label='SELECT_'..serial
 d.map_scripts={apricornBalls=tableRows or {{index=1,apricorn='ITEM_117',ball='ITEM_202'},
  {index=2,apricorn='ITEM_119',ball='ITEM_202'}},apricornInfo={complete=true},
  scripts={[label]={{'special',85,'SelectApricornForKurt'},{'end'}},
   COLLECT={{'checkevent',604},{'iffalse','DONE'},{'verbosegiveitemvar',202,0x16},
    {'iffalse','DONE'},{'clearevent',604},{'end'}},DONE={{'end'}}}}
 local stack=setmetatable({},{__index=Stack});stack:init();stack:push({name='map'})
 local g={data=d,save={inventory=inventory or{}},stack=stack,overworld={}}
 local r=Runner.new(g,g.overworld);r:run(assert(VM.compile(d,label)))
 return g,r
end
local function press(g,key)
 g.input={wasPressed=function(_,k)return k==key end}
 g.stack:update(0)
end
for _,version in ipairs({'gold','silver','crystal'})do
 local g,r=gameFor(version,{ITEM_117=3,ITEM_119=1})
 T.eq(#g.stack:top().items,3,version..' actual native list includes an explicit CANCEL row')
 T.eq(g.stack:top().items[1].label,'AUTHORED APRICORN x3',version..' actual Menu consumes native item display text')
 press(g,'a')
 if version=='crystal'then
  T.eq(g.stack:top().items[1].label,'x1','Crystal actually opens quantity input')
  T.eq(g.save.inventory.ITEM_117,3,'opening quantity input cannot toss an item')
  press(g,'down');press(g,'down');press(g,'a')
 end
 local count=version=='crystal' and 3 or 1
 T.eq(r:isRunning(),false,version..' actual native special completes after confirmation')
 T.eq(r.ctx.g2Var,117,version..' native VM receives the selected actual item byte')
 T.eq(r.ctx.lastCheck,true,version..' confirmed selection reports native success')
 T.eq(g.save.g2KurtApricorns,count,version..' native quantity variable is correct for this cartridge')
 T.eq(g.save.inventory.ITEM_117,3-count>0 and 3-count or nil,version..' actual bag toss removes exactly the confirmed quantity')
 T.eq(g.save.inventory.ITEM_119,1,version..' selection cannot consume another apricorn')
 T.eq(g.stack:top().name,'map',version..' actual Menu/Runner returns to its native owner')
 g,r=gameFor(version,{ITEM_117=3});g.save.g2KurtApricorns=0
 press(g,'down');press(g,'a')
 T.eq(r.ctx.g2Var,0,version..' explicit CANCEL returns false')
 T.eq(g.save.inventory.ITEM_117,3,version..' CANCEL preserves all bag items')
 T.eq(g.save.g2KurtApricorns,0,version..' CANCEL cannot retain a previous quantity')
 g,r=gameFor(version,{})
 T.eq(r:isRunning(),false,version..' empty native bag does not open an empty menu')
 T.eq(r.ctx.g2Var,0,version..' empty native bag returns false')
end
do
 local g,r=gameFor('crystal',{ITEM_117=3,ITEM_119=1})
 press(g,'a');press(g,'b')
 T.eq(r:isRunning(),true,'Crystal quantity cancel returns to the actual apricorn menu')
 T.eq(g.stack:top().items[1].label,'AUTHORED APRICORN x3','quantity cancel restores native list')
 T.eq(g.save.inventory.ITEM_117,3,'quantity cancel does not silently take one apricorn')
 press(g,'down');press(g,'a')
 T.eq(#g.stack:top().items,1,'Crystal asks for quantity even when only one is held')
 press(g,'a')
 T.eq(r.ctx.g2Var,119,'selection after quantity cancel can choose a different actual item')
 T.eq(g.save.inventory.ITEM_117,3,'reselection preserves the original apricorn stack')
 T.eq(g.save.inventory.ITEM_119,nil,'reselection consumes the confirmed other apricorn')
 g,r=gameFor('crystal',{ITEM_117=2});press(g,'a');g.save.inventory.ITEM_117=nil;press(g,'a')
 T.eq(r.ctx.g2Var,0,'concurrent native bag removal cannot create a paid Kurt job')
 T.eq(g.save.g2KurtApricorns,0,'failed revalidation cannot mint a job quantity')
 g,r=gameFor('crystal',{ITEM_117=3});press(g,'a');press(g,'down');press(g,'down');press(g,'a')
 local event=Flags.eventFlag(604);g.save.flags={[event]=true};g.save.inventory.ITEM_202=97
 local function collect()
  local runner=Runner.new(g,g.overworld);runner:run(assert(VM.compile(g.data,'COLLECT')));return runner
 end
 collect()
 T.eq(g.save.inventory.ITEM_202,97,'actual verbosegiveitemvar refuses the whole overflowing ball stack')
 T.eq(g.save.flags[event],true,'failed native ball delivery preserves the recipe event')
 g.save.inventory.ITEM_202=96;collect()
 T.eq(g.save.inventory.ITEM_202,99,'actual native delivery grants the confirmed three-ball quantity')
 T.eq(g.save.flags[event],false,'successful native script clears its real event')
 collect();T.eq(g.save.inventory.ITEM_202,99,'native event guard prevents a duplicate ball collection')
 g,r=gameFor('crystal',{ITEM_117=3,ITEM_119=1})
 press(g,'down');press(g,'a');press(g,'b')
 T.eq(g.stack:top().index,2,'Crystal quantity cancel retains the selected apricorn cursor')
 press(g,'b')
 T.eq(r.ctx.g2Var,0,'cancelling the restored list cancels the native transaction')
 T.eq(g.save.inventory.ITEM_119,1,'cancelling restored list cannot remove the selected apricorn')
 g,r=gameFor('crystal',{ITEM_117=200});press(g,'a')
 T.eq(#g.stack:top().items,99,'native Crystal quantity caps at99 for an oversized historical stack')
 T.eq(g.stack:top().maxVisible,5,'quantity input uses bounded scrolling instead of extending offscreen')
 press(g,'up');press(g,'a')
 T.eq(g.save.g2KurtApricorns,99,'actual Menu wrap can confirm the native maximum quantity')
 T.eq(g.save.inventory.ITEM_117,101,'capped native handover removes no unconfirmed excess')
 local rows,inventory={},{}
 for i=1,7 do
  local key=string.format('ITEM_%03d',110+i);rows[i]={index=i,apricorn=key,ball='ITEM_202'};inventory[key]=1
 end
 g,r=gameFor('crystal',inventory,rows)
 T.eq(#g.stack:top().items,8,'full native list retains seven recipes and CANCEL')
 T.eq(g.stack:top().maxVisible,4,'Crystal recipe list uses four visible scrolling rows')
 press(g,'up')
 T.eq(g.stack:top().index,8,'actual recipe cursor wraps to CANCEL')
 T.eq(g.stack:top().scroll,4,'actual recipe scroll keeps wrapped CANCEL visible')
 press(g,'a');T.eq(r.ctx.g2Var,0,'visible wrapped CANCEL exits the native special')
end
for _,version in ipairs({'prism','polishedcrystal'})do
 local g,r=gameFor(version,{ITEM_085=2},{{index=1,apricorn='ITEM_085',ball='ITEM_202'}})
 press(g,'a');press(g,'b')
 T.eq(r.ctx.g2Var,85,version..' unreviewed hack retains its legacy quantity-cancel protocol')
 T.eq(g.save.g2KurtApricorns,1,version..' hack quantity-cancel behavior is not silently converted to Crystal')
 T.eq(g.save.inventory.ITEM_085,1,version..' hack legacy selection still consumes its original single item')
end
Commands.show_text=oldText;require('src.core.Sound').play=oldSound;V.set(original)
T.finish('native ApricornBalls importer, actual Kurt menus, cartridge quantities and native ball delivery')
