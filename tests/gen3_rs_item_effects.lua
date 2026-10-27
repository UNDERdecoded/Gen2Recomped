-- Actual extractor against a user's local cartridge; writes no cache/assets.
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local bytes=read(assert(arg[1]));local manifest=require('src.link.Json').decode(read(assert(arg[2])))
local X=require('src.import.RomExtractorGen3')
local config=assert(manifest.stageOverrides and manifest.stageOverrides.ITEM_EFFECTS)
assert(config.FIRST==13 and config.COUNT==163)
local function word(at)local a,b,c,d=bytes:byte(at+1,at+4);return a+b*256+c*65536+d*16777216 end
local function extract(m)
 local x=X.new(bytes,'item-effect-layout-regression',m)
 local order={};for i=0,348 do order[i]='ITEM_'..i end
 x._constants={itemOrder=order};x.write=function(self,name,value)assert(name=='constants'and value==self._constants)end
 x:extractItemEffects();return x._constants.gen3ItemEffects or{}
end
local actual=extract(manifest);local nonnull,fields=0,0
local function flag(value,mask)return math.floor(value/mask)%2==1 end
for i=0,config.COUNT-1 do
 local pointer=word(config.TABLE+i*4);local row=actual['ITEM_'..(13+i)]
 if pointer==0 then assert(not row,'Null ROM entry acquired an effect')
 else
  assert(pointer>=0x08000000 and pointer<0x08000000+#bytes)
  local at=pointer-0x08000000;nonnull=nonnull+1;assert(row,'Real ROM item effect omitted')
  local _,_,_,cure,amount,extra=bytes:byte(at+1,at+6)
  assert((row.levelUp==true)==flag(cure,64))
  assert((row.heal==true)==flag(amount,4))
  assert((row.revive==true)==flag(amount,64))
  assert((row.ppUp==true)==flag(amount,32))
  assert((row.stone==true)==flag(amount,128))
  assert((row.ppMax==true)==flag(extra,16))
  assert(row.source:find(string.format('%08X',pointer),1,true));fields=fields+7
 end
end
assert(actual.ITEM_13.heal and actual.ITEM_13.amount==20,'Potion is not the cartridge 20 HP')
assert(actual.ITEM_64.ev=='attack'and actual.ITEM_64.amount==10,'Protein lost the actual attack EV effect')
assert(actual.ITEM_68.levelUp,'Rare Candy lost its native level-up bit')
local legacy={};for k,v in pairs(manifest)do legacy[k]=v end;legacy.stageOverrides=nil
local wrong=extract(legacy)
assert(not wrong.ITEM_13 or not wrong.ITEM_13.heal or wrong.ITEM_13.amount~=20,'Emerald-address negative control did not reproduce')
assert(X.ITEM_EFFECTS.TABLE~=config.TABLE,'Extractor did not restore stage constants for another edition')
print('PASS_RS_ITEM_EFFECTS',config.COUNT,nonnull,fields,'raw ROM fields; potion/protein/candy and legacy-address negative control')
