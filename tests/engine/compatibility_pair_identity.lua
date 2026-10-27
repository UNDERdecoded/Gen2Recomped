package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local M=require('src.compat.gen1.PairIdentity');local Names=require('src.compat.gen1.PairNames')
local count=0
for _,ed in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 local defs,banks={},{}
 for i,row in ipairs(Names[ed])do
  count=count+1
  local name,p,s,alias=M.lookup(ed,row[1],row[2]);T.eq(name,row[3]);T.eq(p,row[4]);T.eq(s,row[5]);T.eq(alias,row[6])
  T.eq(M.lookup(ed,row[1],-1),nil);T.eq(M.lookup(ed,.5,row[2]),nil)
  local pk,sk='P'..i,'S'..i
  banks[pk]={address=row[1],secondary=false};banks[sk]={address=row[2],secondary=true}
  defs['NATIVE_'..i]={id='NATIVE_'..i,primaryKey=pk,secondaryKey=sk}
 end
 local binding=M.bind(defs,banks,ed)
 for i,row in ipairs(Names[ed])do
  local key='NATIVE_'..i
  T.eq(binding:nativeId(row[3]),key);T.eq(binding:canonicalId(key),row[3])
  local a,b=binding:descriptor(key),binding:descriptor(row[3])
  T.eq(a.id,b.id);T.eq(a.primary,row[4]);T.eq(a.secondary,row[5]);T.eq(a.tileset,row[6])
  a.id='EDIT';T.eq(binding:descriptor(key).id,row[3],'descriptor edits cannot corrupt binding')
  T.eq(defs[key].primaryKey,'P'..i,'binding does not mutate native pair')
 end
 local first=Names[ed][1];local original=defs.NATIVE_1
 banks.UNKNOWN={address=1,secondary=true};defs.UNRECOGNIZED={primaryKey='P1',secondaryKey='UNKNOWN'}
 local unknown=M.bind(defs,banks,ed);T.eq(unknown:canonicalId('UNRECOGNIZED'),nil,'unknown secondary source is never guessed from its primary');unknown:release();unknown=nil
 defs.UNRECOGNIZED=nil;banks.UNKNOWN=nil
 -- An alias to the identical owner is safe; independent owners remain ambiguous.
 defs.ALIAS=original
 local alias=M.bind(defs,banks,ed);T.eq(alias:nativeId(first[3]),'NATIVE_1');T.eq(alias:canonicalId('ALIAS'),first[3]);alias:release()
 defs.ALIAS={primaryKey=original.primaryKey,secondaryKey=original.secondaryKey}
 local ambiguous=M.bind(defs,banks,ed);local key,why=ambiguous:nativeId(first[3])
 T.eq(key,nil);T.eq(why,'ambiguous native pair identity');ambiguous:release();defs.ALIAS=nil
 banks.P1.address=-1;T.eq(binding:descriptor('NATIVE_1'),nil,'source address mutation retires lookup')
 banks.P1.address=first[1];T.eq(binding:canonicalId('NATIVE_1'),first[3])
 local p=banks.P1;banks.P1={address=first[1],secondary=false}
 T.eq(binding:nativeId(first[3]),nil,'bank replacement retires lookup');banks.P1=p
 p.secondary=true;T.eq(binding:canonicalId('NATIVE_1'),nil,'wrong bank role never aliases');p.secondary=false
 local sk=original.secondaryKey;original.secondaryKey='P1';T.eq(binding:canonicalId('NATIVE_1'),nil);original.secondaryKey=sk
 defs.NATIVE_1={primaryKey='P1',secondaryKey='S1'};T.eq(binding:canonicalId('NATIVE_1'),nil,'pair owner replacement retires lookup');defs.NATIVE_1=original
 local weak=setmetatable({defs,banks,original,p},{__mode='v'})
 binding:release();T.eq(binding:canonicalId('NATIVE_1'),nil);T.eq(binding:nativeId(first[3]),nil)
 T.eq(binding:descriptor('NATIVE_1'),nil);T.eq(binding:descriptor(first[3]),nil)
 alias=nil;ambiguous=nil;defs=nil;banks=nil;original=nil;p=nil;collectgarbage('collect');collectgarbage('collect')
 T.eq(weak[1],nil,'released binding drops native pair table');T.eq(weak[2],nil,'released binding drops bank table')
 T.eq(weak[3],nil);T.eq(weak[4],nil)
end
T.eq(count,303,'all source pair identities across five editions')
T.eq(M.lookup('gold',0,0),nil,'native Gen2 has no compatibility pair identity')
T.finish('native semantic tileset pair identities')
