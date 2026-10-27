-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
io.stdout:setvbuf('no')
local root=assert(os.getenv('NATIVE_TEXT_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)print(debug.traceback(tostring(err),2));return function()return 1 end end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local function cacheMarker(edition)
 local importer=require('src.import.RomImporter')
 if importer.cacheContract then return importer.cacheContract(edition).marker end
 -- Older public launchers keep this exact format gate private. Inspect the
 -- actual readiness closure in QA; do not substitute a guessed marker.
 for index=1,100 do
  local name,value=debug.getupvalue(importer.readyReport,index)
  if not name then break end
  if name=='markerFor'then return value(edition)end
 end
 error('native importer format gate was not found')
end
function love.load()
 assert(love.graphics==nil,'actual task import must remain windowless')
 local J=require('src.link.Json');local V=require('src.core.GameVersion')
 local X=require('src.import.RomExtractorGen3');local Facts=require('src.import.Gen3VisualTaskFacts')
 local inputs=J.decode(read(assert(os.getenv('NATIVE_TEXT_INPUTS'))))
 local result={editions={},playerProfilesUsed=false,gpu=false,fullGameplay=false}
 for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  V.set(edition);require('src.import.CacheFs').prefix=edition..'/'
  local raw=read(assert(inputs[edition]));local info=V.info()
  assert(require('src.import.RomVerification').sha1(raw)==info.sha1,'exact native cartridge required')
  local manifest=J.decode(read(root..'/'..info.manifest));local x=X.new(raw,info,manifest)
  local worker=coroutine.create(function()x:extractConstants();x:extractMoves();x:extractMoveAnimations()end)
  repeat local ok,why=coroutine.resume(worker);assert(ok,why)until coroutine.status(worker)=='dead'
  local counts={dig_down=0,dig_up=0,surf=0};local seen={};local descriptors={}
  local function visit(value)
   if type(value)~='table'or seen[value]then return end;seen[value]=true
   if value.visualTask then
    local d=value.visualTask;assert(d.schema==Facts.SCHEMA and counts[d.kind]~=nil)
    local p=assert(d.scriptOffset,'task has no original bytecode site')
    assert(x.rom:u8(p)==3,'task metadata was attached to a different opcode')
    local fn=x.rom:u32(p+1)-0x08000000
    assert(d.nativeFunction==fn-fn%2,'native task function mismatch')
    assert(d.priority==x.rom:u8(p+5),'native task priority mismatch')
    assert(#d.args==x.rom:u8(p+6),'native task operand count mismatch')
    for i,arg in ipairs(d.args)do
     local native=x.rom:u16(p+7+(i-1)*2);if native>=32768 then native=native-65536 end
     assert(arg==native,'native signed task operand mismatch')
    end
    counts[d.kind]=counts[d.kind]+1;descriptors[#descriptors+1]=d
   end
   for _,child in pairs(value)do visit(child)end
  end
  visit(assert(x._moves));assert(counts.dig_down>0 and counts.dig_up>0 and counts.surf>=2,'required native task family missing')
  local marker=cacheMarker(edition)
  assert(marker:find('gba%-visual%-task%-v1:'),'native task cache profile was not advanced')
  result.editions[edition]={sha1=info.sha1,counts=counts,descriptors=descriptors,marker=marker}
  print('NATIVE_VISUAL_TASKS_EDITION',edition,counts.dig_down,counts.dig_up,counts.surf)
 end
 result.pass=true
 local f=assert(io.open(assert(os.getenv('NATIVE_TEXT_RESULT')),'wb'));f:write(J.encode(result));f:close()
 print('NATIVE_VISUAL_TASKS_OK');love.event.quit(0)
end
