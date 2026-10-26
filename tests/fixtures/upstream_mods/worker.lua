-- Read-only external packages; production Loader, manifests, registries and buses.
package.path='./?.lua;./?/init.lua;'..package.path
local reference,fixture,version=assert(arg[1]),assert(arg[2]),arg[3] or 'red'
love=require('tests.love_stub')
local Json=require('src.link.Json')
local Files=require('tests.fs_io').new(reference)
local Writer=require('src.import.LuaWriter')
local I={
 manifestPath=function(importer,pack)return 'asset_packs/'..importer..'/'..pack..'/pack.lua' end,
 assetPath=function(importer,pack,file)return 'asset_packs/'..importer..'/'..pack..'/'..file end,
}
local raw=assert(Files.read('mods/'..fixture..'/manifest.json'))
local manifest=assert(Json.decode(raw));local id=manifest.id
local mount='mods/'..id
local overlay={['options.lua']=Writer.encode({mods={[id]=true},modCallbackProfiles={[id]=id=='example_mew_starter' and 'decoded' or nil}})}
local function pack(importer,kind,name,entry)
 local p={format=1,importer=importer,pack=kind,kind=kind=='tiles' and 'tileset' or 'sprite',version='1.1.0',source={name='Synthetic fixture',md5=string.rep('0',32)},entries={[name]=entry}}
 overlay[I.manifestPath(importer,kind)]=Writer.encode(p)
 overlay[I.assetPath(importer,kind,entry.file)]='PNG!'
end
pack('lttp','sprites','player',{file='synthetic.png',size=4,width=16,height=24})
pack('lttp','tiles','kakariko',{file='synthetic.png',size=4,width=1024,height=1024})
local pmdMeta={dexNumber=25,monsterId=25,frameWidth=16,frameHeight=24,frameColumns=1,
 anchorX=8,anchorY=24,animations={{1,1,1,1,1,1,1,1}},sequences={{{1,2,0,0,0,0,0}}}}
local pmdBytes=Writer.encode(pmdMeta)
pack('pmd_red','sprites','pikachu',{file='synthetic.png',size=4,width=16,height=24,frames=1,
 sprite=pmdMeta,metadata={file='synthetic-meta.lua',size=#pmdBytes}})
overlay[I.assetPath('pmd_red','sprites','synthetic-meta.lua')]=pmdBytes
local function remap(path)
 if path==mount then return 'mods/'..fixture end
 if path:sub(1,#mount+1)==mount..'/' then return 'mods/'..fixture..path:sub(#mount+1) end
 return path
end
local fs={root=reference}
function fs.read(path)if path:match('^assets/generated/')then return nil end;return overlay[path] or Files.read(remap(path))end
function fs.write(path,bytes)overlay[path]=bytes;return true end
function fs.remove(path)overlay[path]=nil;return true end
function fs.rename(a,b)if not overlay[a]then return false end;overlay[b]=overlay[a];overlay[a]=nil;return true end
function fs.createDirectory()return true end
function fs.load(path)local bytes=fs.read(path);if not bytes then return nil,'missing '..path end;return loadstring(bytes,'@'..path)end
function fs.getInfo(path)
 if overlay[path]then return {type='file',size=#overlay[path]}end
 if path=='mods'then return {type='directory'}end
 if path:match('^assets/generated/')then return nil end
 return Files.getInfo(remap(path))
end
function fs.getDirectoryItems(path)if path=='mods'then return {id}end;return Files.getDirectoryItems(remap(path))end
-- CPU image objects exercise the real assembling consumer, without claiming pixels.
love.image={newImageData=function(w,h)
 if type(w)=='string'then w,h=1024,1024 end
 return {getWidth=function()return w end,getHeight=function()return h end,
  getDimensions=function()return w,h end,paste=function()end,setPixel=function()end,
  getPixel=function()return 0.5,0.5,0.5,1 end,getString=function()return 'synthetic' end,
  release=function()end,encode=function()return {getString=function()return 'PNG!' end}end}
end}
require('src.core.GameVersion').set(version)
local data=require('tests.fixtures.upstream_mods.data').fresh()
local Loader=require('src.mods.Loader')
local loader=Loader.new({fs=fs,dev=false})
local ok,result=pcall(loader.load,loader,data)
local names,known={},{}
local handle=assert(io.open('tests/fixtures/upstream_mods/index.json','rb'))
local index=assert(Json.decode(handle:read('*a')));handle:close()
for _,name in ipairs(index.hooks)do known[name]=true end
for _,bus in ipairs({loader.hooks,loader._decodedHooks})do
 for name in pairs(bus.chains)do assert(known[name],'unknown hook '..name);names[#names+1]=name end
end
table.sort(names)
local loaded=ok and result==true and loader.mods[id] and loader.mods[id].state=='loaded'
local errorText=ok and table.concat(loader.errors,'; ') or tostring(result)
-- Execute a registered gift handler, without substituting any loader/API method.
if loaded and id=='example_mew_starter' and version=='red' then
 local gift={species='CHARMANDER',level=5,ctx={overworld={map={id='OAKS_LAB'}},save={flags={},party={}}}}
 loader.events:emit('pokemon.before_give',gift)
 assert(gift.species=='MEW' and gift.level==20,'legacy starter event did not run')
end
-- Authentic unchanged starter code now runs through the actual Gen-3 compiler,
-- runner, existing gift event and Pokémon constructor on test-owned data.
local functional
if loaded and id=='example_mew_starter' and version=='firered' then
 data.maps.MAP_G04_N03={id='MAP_G04_N03',group=4,number=3}
 data.constants.speciesOrder={[4]='CHARMANDER',[151]='MEW'}
 data.map_scripts={source='RomExtractorGen3',scripts={ENTRY={
  {'setvar',0x4002,4},{'givemon',0x4002,5,0},{'end'},
 }},maps={}}
 local save={flags={},party={},gen3Vars={},player={name='TEST',id=12345},
  pokedex={seen={},owned={}}}
 local game={data=data,save=save,mods=loader}
 local world={map={id='MAP_G04_N03',def=data.maps.MAP_G04_N03}}
 local runner=require('src.script.ScriptRunner').new(game,world)
 runner:exec(require('src.script.Gen3ScriptVM').compile(data,'ENTRY'),runner:makeContext())
 assert(save.gen3Vars[0x4002]==151,'unchanged starter hook did not rewrite the native variable')
 local mon=assert(save.party[1],'native gift did not create a Pokémon')
 assert(#save.party==1 and mon.species=='MEW' and mon.level==20 and mon.nickname=='HOGHEAD',
  'unchanged starter event did not produce the requested native gift')
 assert(world.map.id=='MAP_G04_N03','profile renamed the native map')
 functional={species=mon.species,level=mon.level,nickname=mon.nickname,variable=save.gen3Vars[0x4002]}
end
if loaded and id=='mystery_dungeon_follower' then
 local Native=require('src.core.Game')
 local previous={Native.data,Native.save,Native.overworld}
 local image=love.graphics.newImage
 love.graphics.newImage=function(path)
  if path=='asset_packs/pmd_red/sprites/synthetic.png'then
   return {getDimensions=function()return 16,24 end,getWidth=function()return 16 end,getHeight=function()return 24 end}
  end
  return image(path)
 end
 local npc={optionalFollower=true,pikachuFollower=true,px=0,py=0,moving=true}
 local world={player={px=16,py=0,visible=true},npcs={npc}}
 local save={party={{species='PIKACHU',hp=10,dvs={attack=0,defense=0,speed=0,special=0}}}}
 Native.data,Native.save,Native.overworld=data,save,world
 local count=#loader.errors
 local spawn=loader.hooks:call('world.follower.spawn',function()return false end,Native,world)
 assert(spawn and npc.sprite,'unchanged follower did not install its published pack renderer')
 local stepped=loader.hooks:call('input.step',function(_,dt)return dt end,Native,0.25)
 assert(stepped==0.25 and npc.sprite.pmdTicks==1,'unchanged follower did not advance its sprite')
 assert(#loader.errors==count,table.concat(loader.errors,'; '))
 functional={spawned=true,stepped=true,anchorX=npc.sprite.anchorX,anchorY=npc.sprite.anchorY}
 love.graphics.newImage=image
 Native.data,Native.save,Native.overworld=unpack(previous)
end
print('FIXTURE_RESULT '..Json.encode({fixture=fixture,version=version,loaded=loaded and true or false,hooks=names,error=errorText,functional=functional}))
if not loaded then os.exit(1)end
