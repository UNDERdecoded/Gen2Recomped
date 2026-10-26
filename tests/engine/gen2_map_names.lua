package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Identity=require('src.core.MapIdentity')
local Names=require('src.core.Gen2MapNames')
local Registry=require('src.mods.Registry')
local Schemas=require('src.mods.Schemas')
local Merge=require('src.mods.Merge')
local original=Version.get()
local native,canonical='PLAYERS_HOUSE1_F','PLAYERS_HOUSE_1F'
local function fixture()
 local raw={id=native,tileset='FIX_OUT',width=5,height=4,blocks={1,2},warps={{destMap='NEW_BARK_TOWN'}},objects={{x=1,y=2}}}
 local alias=Merge.deepCopy(raw);alias.id=canonical;alias.sourceId=native
 return {maps={[native]=raw,[canonical]=alias}},raw,alias
end
local function registry(data)
 local r=Registry.new('maps',Schemas.REGISTRIES.maps);r.base=function()return data.maps end;return r
end
for _,version in ipairs(Version.ORDER)do
 Version.set(version)
 local data,raw,alias=fixture()
 T.eq(Identity.same(data,native,canonical),false,'copied records are not one live map')
 T.eq(Names.publish(data),Version.isGen2(),version..' Gen2-only publication')
 if Version.isGen2()then
  T.eq(data.maps[native],raw,'native geometry remains authoritative')
  T.eq(data.maps[canonical],raw,'public/native names share the actual record')
  T.eq(raw.id,canonical,'public runtime Map identity')
  T.eq(raw.sourceId,native,'native provenance retained')
  T.eq(Identity.runtimeId(data,native),canonical,'raw request resolves public runtime identity')
  T.eq(Identity.runtimeId(data,canonical),canonical,'public request stays stable')
  T.eq(Identity.sourceId(data,canonical),native,'native source lookup remains stable')
  T.eq(Identity.same(data,native,canonical),true,'verified shared live identity')
  T.eq(raw.warps[1].destMap,'NEW_BARK_TOWN','warp data is not rewritten')
  local objects=raw.objects
  data.maps[canonical].objects[1].x=7
  T.eq(raw.objects,objects,'no copied object array')
  T.eq(raw.objects[1].x,7,'public map edit reaches native map')
  local r=registry(data)
  r:patch(native,{width=7},'native_pack')
  r:patch(canonical,{height=6},'public_pack')
  T.eq(r:get(native),r:get(canonical),'actual Registry shares one folded record')
  T.eq(r:get(native).width,7,'native patch retained')
  T.eq(r:get(canonical).height,6,'canonical patch composes instead of replacing native patch')
  T.eq(#r:claimants(native),2,'native conflict attribution includes both packs')
  T.eq(#r:claimants(canonical),2,'public conflict attribution includes both packs')
  r:preferOwner(native,'native_pack')
  T.eq(r:preferredOwner(canonical),'native_pack','conflict preference shares physical identity')
  T.eq(r:get(canonical).height,4,'set-aside owner does not affect the other name')
  r:preferOwner(canonical,nil)
  r:rollback('native_pack')
  T.eq(r:get(native).width,5,'rollback removes only its owner')
  T.eq(r:get(native).height,6,'other name keeps its own contribution')
  Names.write(data.maps,r)
  T.eq(data.maps[native],data.maps[canonical],'native loader merge preserves shared record')
  T.eq(data.maps[native],r:get(native),'registry and live dataset see one result')
  T.eq(Names.publish(data),true,'republication after actual registry merge')
  T.eq(data.maps[native].height,6,'post-merge publication retains authored content')
  local current=data.maps[native]
  local editor=Merge.deepCopy(current);editor.width=9
  data.maps[native]=editor
  Names.publish(data)
  T.eq(data.maps[canonical],editor,'one editor replacement updates the existing physical family')
  T.eq(editor.id,canonical,'editor copy retains public identity')
  local a,b=Merge.deepCopy(editor),Merge.deepCopy(editor);a.width=10;b.width=11
  data.maps[native],data.maps[canonical]=a,b
  Names.publish(data)
  T.eq(data.maps[native],a,'conflicting explicit replacements are not guessed')
  T.eq(data.maps[canonical],b,'neither authored replacement is overwritten')
  local deleted=fixture();Names.publish(deleted);local dr=registry(deleted)
  dr:remove(native,'remove_pack');Names.write(deleted.maps,dr);Names.publish(deleted)
  T.eq(deleted.maps[native],nil,'removal deletes native record')
  T.eq(deleted.maps[canonical],nil,'removal cannot leave a stale public copy')
  local replaced=fixture();Names.publish(replaced);local rr=registry(replaced)
  rr:override(native,{id=native,width=12,height=4},'replacement');Names.write(replaced.maps,rr);Names.publish(replaced)
  T.eq(replaced.maps[native],replaced.maps[canonical],'full replacement preserves alias family')
  T.eq(replaced.maps[native].id,canonical,'native-addressed full replacement still publishes runtime name')
  T.eq(rr:get(native),rr:get(canonical),'native alias lookup remains stable after replacement')
  T.eq(#rr:claimants(native),1,'replacement retains native owner attribution')
 else
  T.eq(data.maps[native],raw,'other-generation native record retained')
  T.eq(data.maps[canonical],alias,'other-generation copied alias retained')
  T.eq(raw.id,native,'other-generation IDs unchanged')
  local r=registry(data);r:patch(native,{width=7},'native_pack')
  T.eq(r:get(canonical).width,5,'other-generation registry address space unchanged')
 end
end
Version.set('crystal')
local conflicting,raw,alias=fixture();alias.width=99;Names.publish(conflicting)
T.eq(conflicting.maps[native],raw,'authored different canonical map does not replace native')
T.eq(conflicting.maps[canonical],alias,'authored geometry is not overwritten')
T.eq(raw.id,native,'conflict keeps native runtime identity')
T.eq(Identity.runtimeId(conflicting,native),native,'conflict does not route to an authored variant')
local unrelated=fixture();unrelated.maps[canonical].sourceId='OTHER';unrelated.maps.OTHER={id='OTHER'};Names.publish(unrelated)
T.eq(unrelated.maps[native].id,native,'unrelated declared source is never guessed')
local reload=fixture();Names.publish(reload);local fresh=fixture();reload.maps=fresh.maps;Names.publish(reload)
T.eq(reload.maps[native],reload.maps[canonical],'replacement dataset gets its own families')
T.eq(Names.publish({}),false,'missing registry safe')
T.eq(Identity.same({},nil,'X'),false,'missing map cannot match another map')
-- Use the actual engine declaration adapter for old group/number caches.
local Data=require('src.core.Data')
local seed
for n=1,100 do local name,value=debug.getupvalue(Data.seedDefaults,n);if not name then break end;if name=='seedMapAliases'then seed=value;break end end
T.check(type(seed)=='function','actual engine scaffold alias adapter')
local scaffold='MAP_G18_N06';local declared={[scaffold]=native}
local oldCache={maps={[scaffold]={id=scaffold,width=5,height=4,blocks={1}}}}
seed(oldCache.maps,declared);Names.publish(oldCache,declared)
T.eq(oldCache.maps[scaffold],oldCache.maps[native],'native scaffold spelling shares actual map')
T.eq(oldCache.maps[canonical],oldCache.maps[scaffold],'old scaffold cache receives public floor spelling')
T.eq(Identity.sourceId(oldCache,canonical),scaffold,'old cache keeps real native source key')
local noDigits={maps={ELMS_LAB={id='ELMS_LAB',blocks={1}}}}
seed(noDigits.maps,{MAP_G24_N05='ELMS_LAB'});Names.publish(noDigits,{MAP_G24_N05='ELMS_LAB'})
T.eq(noDigits.maps.MAP_G24_N05,noDigits.maps.ELMS_LAB,'unchanged public name still shares declared scaffold alias')
T.eq(Identity.runtimeId(noDigits,'MAP_G24_N05'),'ELMS_LAB','scaffold request reaches existing unchanged native name')
-- Exercise the real mod loader merge and its failed-entry rollback, not
-- merely the map write helper or a made-up registry fixture.
-- Replace the native dataset as a ROM import does; adding mod maps after
-- startup intentionally does not enroll them in the engine alias families.
local data=T.fixtures.fresh();data.maps=Merge.deepCopy(data.maps)
local homes=fixture();data.maps[native],data.maps[canonical]=homes.maps[native],homes.maps[canonical]
Names.publish(data)
local files={}
for _,id in ipairs({'native_patch','public_patch','failed_patch'})do
 files['mods/'..id..'/manifest.json']='{"id":"'..id..'","name":"'..id..'","version":"1.0.0","api":2,"entry":"main.lua","affects_link":true}'
end
files['mods/native_patch/main.lua']=[[local mod=...;mod.content.maps:patch('PLAYERS_HOUSE1_F',{width=7})]]
files['mods/public_patch/main.lua']=[[local mod=...;mod.content.maps:patch('PLAYERS_HOUSE_1F',{height=6})]]
files['mods/failed_patch/main.lua']=[[local mod=...;mod.content.maps:patch('PLAYERS_HOUSE1_F',{width=99});error('intentional alias rollback')]]
local run=T.sdk.loadMods({'mods/native_patch','mods/public_patch','mods/failed_patch'},{data=data,fs=T.sdk.memfs(files)})
T.eq(#run.errors,1,'only deliberate failing entry is rejected')
T.eq(data.maps[native],data.maps[canonical],'actual loader retains one physical map')
T.eq(data.maps[native].width,7,'real native mod patch remains after rollback')
T.eq(data.maps[canonical].height,6,'real canonical mod patch composes')
T.eq(run.loader.content.maps:get(native),run.loader.content.maps:get(canonical),'real mod reads share merged record')
T.eq(#run.loader.content.maps:claimants(native),2,'failed owner removed from shared attribution')
Version.set(original)
T.finish('Gen2 physical map names and native content transactions')
