package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Names=require('src.core.Gen2SpeciesNames')
local Merge=require('src.mods.Merge')
local Registry=require('src.mods.Registry')
local Schemas=require('src.mods.Schemas')
local old=Version.get()
local function mon(index, name)
 local d=Merge.deepCopy(require('tests.fixture_data.pokemon').FIXMON_A)
 d.id=string.format('SPECIES_%03d',index);d.index=index;d.dex=index
 d.name=name or 'Translated display name'
 d.source=string.format('ROM:BaseData[%d]',index)
 return d
end
local function fixture()
 return {pokemon={SPECIES_133=mon(133),SPECIES_152=mon(152)},
   constants={speciesOrder={[133]='SPECIES_133',[152]='SPECIES_152'}}}
end
local function registry(data)
 local r=Registry.new('pokemon',Schemas.REGISTRIES.pokemon)
 r.base=function()return data.pokemon end
 return r
end
local function size(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
for _,version in ipairs(Version.ORDER)do
 Version.set(version);local data=fixture();local p=data.pokemon
 local supported=version=='gold' or version=='silver' or version=='crystal'
 T.eq(Names.publish(data),supported,version..' exact cartridge scope')
 if supported then
  T.eq(p.EEVEE,p.SPECIES_133,'legacy name returns live native record')
  T.eq(p.CHIKORITA,p.SPECIES_152,'Gen2 species beyond Kanto resolve')
  T.eq(p.EEVEE.id,'SPECIES_133','lookup never changes native id')
  T.eq(rawget(p,'EEVEE'),nil,'no duplicate stored row')
  T.eq(size(p),2,'iteration never duplicates species')
  T.eq(p.EEVEE.spriteFront,p.SPECIES_133.spriteFront,'actual art path comes from native record')
  p.SPECIES_133.name='Another translation'
  T.eq(p.EEVEE,p.SPECIES_133,'presentation-name change cannot rename identity')
  local r=registry(data)
  r:patch('EEVEE',{baseStats={hp=71}},'legacy')
  r:patch('SPECIES_133',{baseExp=123},'native')
  T.eq(r:get('EEVEE'),r:get('SPECIES_133'),'real registry shares one folded row')
  T.eq(r:get('EEVEE').baseStats.hp,71,'legacy edit reaches native definition')
  T.eq(r:get('EEVEE').baseExp,123,'native and legacy edits compose')
  T.eq(#r:claimants('EEVEE'),2,'conflicts attributed under same identity')
  r:preferOwner('EEVEE','legacy')
  T.eq(r:preferredOwner('SPECIES_133'),'legacy','conflict selection uses native address')
  r:preferOwner('EEVEE',nil);r:rollback('legacy')
  T.eq(r:get('EEVEE').baseStats.hp,p.SPECIES_133.baseStats.hp,'rollback restores native base')
  T.eq(r:get('EEVEE').baseExp,123,'rollback retains other contributor')
  Names.write(p,r)
  T.eq(p.EEVEE,p.SPECIES_133,'merged dataset remains a live view')
  T.eq(p.EEVEE.baseExp,123,'native merge is visible immediately')
  T.eq(size(p),2,'merge stores no alias rows')
  r=registry(data)
  local replacement=mon(133);replacement.id='EEVEE';replacement.spriteFront='replacement.png'
  r:override('EEVEE',replacement,'replace');Names.write(p,r)
  T.eq(p.EEVEE.id,'SPECIES_133','full legacy replacement retains native id')
  T.eq(p.EEVEE.spriteFront,'replacement.png','view follows full replacement')
  r=registry(data);r:remove('EEVEE','delete');Names.write(p,r)
  T.eq(p.SPECIES_133,nil,'legacy deletion removes native row')
  T.eq(p.EEVEE,nil,'deletion cannot resurrect cached art/record')
  T.eq(Names.registryId(p,'EEVEE'),'SPECIES_133','deleted identity keeps its registry address')
  T.eq(Names.publish(data),true,'idempotent publication cannot revive deletion')
  T.eq(p.EEVEE,nil,'idempotent publish retains tombstone')
 else
  T.eq(data.pokemon.EEVEE,nil,'no inferred alias on another generation/hack')
  T.eq(Names.registryId(data.pokemon,'EEVEE'),'EEVEE','other registry address spaces retained')
 end
end
Version.set('crystal')
local authored=fixture();authored.pokemon.EEVEE={id='EEVEE',spriteFront='authored.png'}
local named=authored.pokemon.EEVEE;Names.publish(authored)
T.eq(authored.pokemon.EEVEE,named,'explicit authored name wins over native alias')
T.eq(Names.registryId(authored.pokemon,'EEVEE'),'EEVEE','authored named registry remains independent')
local malformed=fixture();malformed.pokemon.SPECIES_133.dex=1
malformed.constants.speciesOrder[152]='AUTHOR_SPECIES'
T.eq(Names.publish(malformed),false,'dex or declared native-order mismatch cannot infer identity')
T.eq(malformed.pokemon.EEVEE,nil,'malformed slot is not guessed')
local custom=fixture();local mt={__index=function()return 'custom' end};setmetatable(custom.pokemon,mt)
T.eq(Names.publish(custom),false,'authored lookup behavior is not overwritten')
T.eq(getmetatable(custom.pokemon),mt,'authored metatable retained')
for _,row in ipairs({{29,'NIDORAN_F'},{32,'NIDORAN_M'},{83,'FARFETCH_D'},{122,'MR__MIME'},{250,'HO_OH'}})do
 local record=mon(row[1]);local d={pokemon={[record.id]=record},constants={speciesOrder={[row[1]]=record.id}}};Names.publish(d)
 T.eq(d.pokemon[row[2]],record,'reference punctuation/gender constant '..row[2])
end
-- Real Pokemon creation stores the native species id even when a legacy
-- script asks by name. Existing saves are only read, never migrated here.
local data=T.fixtures.fresh();data.pokemon.SPECIES_133=mon(133)
data.constants.speciesOrder={[133]='SPECIES_133'};Names.publish(data)
local made=require('src.pokemon.Pokemon').new(data,'EEVEE',5,function(lo)return lo end)
T.eq(made.species,'SPECIES_133','new Pokemon uses canonical native save identity')
local previous={species='EEVEE',level=5};T.eq(data.pokemon[previous.species],data.pokemon.SPECIES_133,'older named save remains readable')
T.eq(previous.species,'EEVEE','reading older save does not rewrite it')
-- Real loader entry, native merge and failed-entry rollback, not a fake
-- registry facade. The species count and ids stay native throughout.
data=T.fixtures.fresh();data.pokemon.SPECIES_133=mon(133);data.pokemon.SPECIES_152=mon(152)
data.constants.speciesOrder={[133]='SPECIES_133',[152]='SPECIES_152'}
local result=T.sdk.loadMods({'mods/named','mods/broken'},{data=data,fs=T.sdk.memfs({
 ['mods/named/manifest.json']=[[{"id":"named","name":"Named species contract","version":"1.0.0","api":2,"entry":"main.lua","affects_link":false}]],
 ['mods/named/main.lua']=[[
  local mod=...
  local d=assert(mod.content.pokemon:get('EEVEE'))
  assert(d.id=='SPECIES_133')
  mod.exports.front=d.spriteFront
  mod.content.pokemon:patch('EEVEE',{baseStats={hp=72}})
 ]],
 ['mods/broken/manifest.json']=[[{"id":"broken","name":"Rollback species contract","version":"1.0.0","api":2,"entry":"main.lua","priority":200,"affects_link":false}]],
 ['mods/broken/main.lua']=[[
  local mod=...
  mod.content.pokemon:patch('CHIKORITA',{baseStats={hp=99}})
  error('deliberate species rollback')
 ]],
})})
T.eq(#result.errors,1,'only deliberately broken mod fails')
T.eq(result.loader.exports.named.front,data.pokemon.SPECIES_133.spriteFront,'actual API2 named query sees native art')
T.eq(data.pokemon.EEVEE.baseStats.hp,72,'actual loader writes legacy patch to native row')
T.eq(data.pokemon.CHIKORITA.baseStats.hp,mon(152).baseStats.hp,'failed entry rolls back native-addressed edit')
T.eq(size(data.pokemon),5,'actual loader does not duplicate native/fixture species')
require('src.mods.Loader').teardown();result.release()
Version.set(old)
T.finish('native GSC species-name identity and sprite sources')
