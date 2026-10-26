-- Run locally with a legally supplied cartridge and its native manifest.
-- No ROM data, extracted text, cache or graphics are written by this test.
local romPath,manifestPath=assert(arg[1]),assert(arg[2])
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local bytes=read(romPath)
local J=require('src.link.Json');local manifest=J.decode(read(manifestPath))
local X=require('src.import.RomExtractorGen3')
local stride=manifest.pokedexEntrySize or(manifest.frlgItemMenu and 36 or 32)
local poseAt=stride==36 and 26 or 22
local base=assert(manifest.symbols.gPokedexEntries)
local function word(at)local a,b=bytes:byte(at+1,at+2);return a+b*256 end
local function signed(at)local w=word(at);return w>=32768 and w-65536 or w end
local function extract(m)
 local x=X.new(bytes,'dex-layout-regression',m)
 x._pokemon={};for dex=1,386 do x._pokemon[dex]={id='DEX_'..dex,dex=dex}end
 x.write=function(self,name,value)assert(name=='pokemon'and value==self._pokemon)end
 x:extractDexEntries();return x._pokemon
end
local actual=extract(manifest);local fields=0
for dex=1,386 do
 local row=actual[dex];local at=base+dex*stride
 assert(type(row.category)=='string'and #row.category>0,'Missing category at '..dex)
 assert(row.height==word(at+12)/10 and row.weight==word(at+14)/10,'Wrong size at '..dex)
 local pose=assert(row.dexPose,'Missing dex pose at '..dex)
 assert(pose.monScale==word(at+poseAt)and pose.monOffset==signed(at+poseAt+2)
  and pose.trainerScale==word(at+poseAt+4)and pose.trainerOffset==signed(at+poseAt+6),'Wrong affine pose at '..dex)
 fields=fields+6
end
local negative=0
if manifest.pokedexEntrySize==36 and not manifest.frlgItemMenu then
 local legacy={};for k,v in pairs(manifest)do legacy[k]=v end;legacy.pokedexEntrySize=nil
 local wrong=extract(legacy)
 for dex=1,386 do if wrong[dex].height~=actual[dex].height or wrong[dex].weight~=actual[dex].weight then negative=negative+1 end end
 assert(negative>300,'Legacy 32-byte negative control did not reproduce corruption')
 assert(actual[129].height==.9 and actual[321].height==14.5,'Measured cartridge sentinel sizes changed')
end
print('PASS_GEN3_DEX_LAYOUT',stride,386,fields,'raw size/pose fields; legacy corrupt species',negative)
