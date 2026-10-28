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
local overlay={['options.lua']=Writer.encode({mods={[id]=true}})}
local function pack(importer,kind,name,entry)
 local p={format=1,importer=importer,pack=kind,kind=kind=='tiles' and 'tileset' or 'sprite',version='1.1.0',source={name='Synthetic fixture',md5=string.rep('0',32)},entries={[name]=entry}}
 overlay[I.manifestPath(importer,kind)]=Writer.encode(p)
 overlay[I.assetPath(importer,kind,entry.file)]='PNG!'
end
pack('lttp','sprites','player',{file='synthetic.png',size=4,width=16,height=24})
pack('lttp','tiles','kakariko',{file='synthetic.png',size=4,width=1024,height=1024})
pack('pmd_red','sprites','pikachu',{file='synthetic.png',size=4,width=16,height=24,sprite={dexNumber=25,monsterId=25}})
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
for name in pairs(loader.hooks.chains)do assert(known[name],'unknown hook '..name);names[#names+1]=name end
table.sort(names)
local loaded=ok and result==true and loader.mods[id] and loader.mods[id].state=='loaded'
local errorText=ok and table.concat(loader.errors,'; ') or tostring(result)
-- Execute a registered gift handler, without substituting any loader/API method.
if loaded and id=='example_mew_starter' and version=='red' then
 local gift={species='CHARMANDER',level=5,ctx={overworld={map={id='OAKS_LAB'}},save={flags={},party={}}}}
 loader.events:emit('pokemon.before_give',gift)
 assert(gift.species=='MEW' and gift.level==20,'legacy starter event did not run')
end
print('FIXTURE_RESULT '..Json.encode({fixture=fixture,version=version,loaded=loaded and true or false,hooks=names,error=errorText}))
if not loaded then os.exit(1)end
