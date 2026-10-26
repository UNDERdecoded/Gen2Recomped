local engine,consumer,version=assert(arg[1]),assert(arg[2]),assert(arg[3])
package.path=engine..'/?.lua;'..engine..'/?/init.lua;'..package.path
local T=require('tests.modkit')
require('src.core.GameVersion').set(version)
local out=assert(loadfile(consumer))()(T,require('src.core.game3.layout_native'))
-- The Gen1 process additionally decodes the shared fixture through its real
-- native importer. Neither engine is replaced with a test layout module.
if arg[4]=='gen1'then
 local decoded=assert(require('src.import.gba.native_pack').decodeMidLayout(out.packed.blob))
 T.eq(decoded.width,out.packed.stride,'actual native decoder agrees on worker source stride')
 T.same(decoded.cells[1],{mid=1,coll=0,elev=3},'actual decoder sees base rather than already-patched source')
 T.same(decoded.borderMids,{11,12,13,14},'actual decoder sees authored border')
end
print('GBA_LAYOUT_CONTRACT '..require('src.link.Json').encode(out))
T.finish('shared native GBA layout contract')
