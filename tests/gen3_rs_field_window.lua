-- Actual cartridge extractor metadata; no generated cache or artwork written.
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local bytes=read(assert(arg[1]));local manifest=require('src.link.Json').decode(read(assert(arg[2])))
require('src.core.GameVersion').set(manifest.version)
local X=require('src.import.RomExtractorGen3');local native=assert(manifest.rsFieldMessageWindow)
assert(native.kind=='rs-field-code'and native.evidence.printerCallCount==2)
local function extract(m)
 local x=X.new(bytes,'rs-field-window-regression',m)
 x.write=function(self,name,value)assert(name=='constants');self.captured=value end
 x.saveImage=function()error('Data-only field-window regression does not write artwork')end
 x:extractConstants();return assert(x.captured)
end
local actual=extract(manifest);local w=assert(actual.gen3FieldMessageWindow)
assert(w.left==2 and w.top==15 and w.width==26 and w.height==4)
assert(w.source==native.source and w.source:find('PrintFieldMessage',1,true))
assert(not actual.gen3MessageWindow,'Field coordinates became a battle-window scan anchor')
local legacy={};for k,v in pairs(manifest)do legacy[k]=v end;legacy.rsFieldMessageWindow=nil
local old=extract(legacy);assert(not old.gen3FieldMessageWindow and not old.gen3MessageWindow,'Old missing-field metadata negative did not reproduce')
local B=require('src.battle.Gen3Battle')
local before,after=B.strip({data={constants=old}}),B.strip({data={constants=actual}})
for k,v in pairs(before)do assert(after[k]==v,'Field metadata altered native battle strip '..k)end
for k,v in pairs(after)do assert(before[k]==v,'Field metadata added native battle strip field '..k)end
print('PASS_RS_FIELD_WINDOW actual extractor 26x4 at 2,15; legacy missing negative; native battle strip unchanged')
