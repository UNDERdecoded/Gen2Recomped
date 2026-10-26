package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Manifest=require('src.mods.Manifest')
local Imports=require('src.mods.ModImports')
local Access=require('src.mods.ImportAccess')
local Files=require('src.mods.ImportFiles')
local MD5=require('src.mods.StreamMD5')
local CacheFs=require('src.import.CacheFs')
local Versions=require('src.core.GameVersion')
local Json=require('src.link.Json')
local Launcher=require('src.mods.LauncherMods')
local Manager=require('src.mods.ManagerState')
local savedVersion=Versions.get()
Versions.set('red')

local function memory(initial)
  local data,times={},{}
  for path,body in pairs(initial or {}) do data[path]=body;times[path]=1 end
  local clock=1
  local f={reads={},maxRead=0,openHandles=0}
  local function store(path,body) clock=clock+1;data[path]=body;times[path]=clock end
  function f.getInfo(path,kind)
    if data[path] then return {type='file',size=#data[path],modtime=times[path]} end
    if kind=='file' then return nil end
    local prefix=path=='' and '' or path..'/'
    for key in pairs(data) do if key:sub(1,#prefix)==prefix then return {type='directory'} end end
  end
  function f.read(path)
    f.reads[path]=(f.reads[path] or 0)+1
    assert(not f.strictWholeRead or not data[path] or #data[path]<=1024,'whole-file import allocation forbidden')
    return data[path]
  end
  function f.write(path,body) store(path,body);return true end
  function f.remove(path) data[path]=nil;times[path]=nil;return true end
  function f.createDirectory() return true end
  function f.rename(from,to)
    if f.failRename then return false,'simulated publish failure' end
    if not data[from] then return nil,'missing staged file' end
    store(to,data[from]);f.remove(from);return true
  end
  function f.load(path) return (loadstring or load)(data[path] or 'error("missing source")',path) end
  function f.getDirectoryItems(path)
    local out,seen={},{}
    local prefix=path=='' and '' or path..'/'
    for key in pairs(data) do
      if key:sub(1,#prefix)==prefix then
        local name=key:sub(#prefix+1):match('^[^/]+')
        if name and not seen[name] then seen[name]=true;out[#out+1]=name end
      end
    end
    table.sort(out);return out
  end
  function f.newFile(path,mode)
    local at,opened,writing=0,false,false
    local file={}
    function file:open(m)
      if m=='r' and not data[path] then return false,'missing file' end
      opened,writing=true,m=='w';f.openHandles=f.openHandles+1
      if writing then store(path,'') end
      return true
    end
    function file:seek(offset) at=offset;return at end
    function file:read(n)
      T.check(n<=Files.MAX_READ_BYTES,'physical import reads stay bounded')
      f.maxRead=math.max(f.maxRead,n)
      local chunk=data[path]:sub(at+1,at+n);at=at+#chunk
      return #chunk>0 and chunk or nil
    end
    function file:write(chunk)
      if f.failWrite and path:find('imports/staging/',1,true) then return false,'simulated disk failure' end
      if f.shortWrite and path:find('imports/staging/',1,true) then chunk=chunk:sub(1,1) end
      store(path,(data[path] or '')..chunk);return true
    end
    function file:close()
      if opened then f.openHandles=f.openHandles-1;opened=false end
      return true
    end
    if mode then local ok=file:open(mode);if not ok then return nil end end
    return file
  end
  return f,data
end

local function raw(extra,id)
  local out={id=id or 'native',name=id or 'Native',version='1.0.0',api=2,entry='main.lua',games={'all'}}
  for key,value in pairs(extra or {}) do out[key]=value end
  return out
end
local function manifest(extra)
  local m=Manifest.validate(raw(extra));m.path='mods/native';return m
end

for _,vector in ipairs({{'','d41d8cd98f00b204e9800998ecf8427e'},
  {'a','0cc175b9c0f1b6a831c399e269772661'}, {'abc','900150983cd24fb0d6963f7d28e17f72'},
  {'message digest','f96b697d7cb7938d525a2f31aaf161d0'},
  {string.rep('a',1000000),'7707d6ae4e027c70eea2a935c2296f21'}}) do
  for _,step in ipairs({1,63,64,65,65537}) do
    local hash=MD5.new()
    for at=1,#vector[1],step do hash:update(vector[1]:sub(at,at+step-1)) end
    T.eq(hash:final(),vector[2],'incremental digest matches standard vector across chunk boundaries')
  end
end

local m=manifest({required_imports={{id='base',file='base.bin',md5='900150983cd24fb0d6963f7d28e17f72',size=3}},
  optional_imports={{id='extra',file='extra.pack',verify='mod',max_size=10,extensions={'.PACK'}}}})
T.eq(m.requiredImports[1].relativeFile,'baseroms/base.bin','bare filename gets canonical import folder')
T.eq(m.optionalImports[1].required,false,'optional requirement retained')
T.same(Imports.extensions(m.optionalImports[1]),{'pack'},'picker sees declared extensions')
T.eq(#Imports.of(m),2,'legacy declaration listing grows to include optional files')
T.same(m.required_imports[1].md5,{'900150983cd24fb0d6963f7d28e17f72'},'portable manifest digest array matches declaration contract')
T.eq(m.required_imports[1].format,'raw','portable manifest has an explicit raw format')
local descriptor={required_imports=m.required_imports,optional_imports=m.optional_imports}
T.eq(Imports.required(descriptor)[1].relativeFile,'baseroms/base.bin','serialized import declarations preserve canonical path')
T.eq(Imports.optional(descriptor)[1].verify,'mod','delegated optional import survives descriptor round trip')
T.eq(Access.MAX_READ_BYTES,Files.MAX_READ_BYTES,'public range-read ceiling is available')
for _,bad in ipairs({{file='../escape'},{file='C:escape'},{file='bad\\escape'},{file='bad\0file'},
  {file='ok',size=-1},{file='ok',max_size=1,size=2},{file='ok',md5='bad'},
  {file='ok',verify='anything'},{file='ok',magic='x1'},{file='ok',magic='00',magic_offset=Files.MAX_READ_BYTES}}) do
  T.raises(function()manifest({required_imports={bad}})end,nil,'malformed import rejected')
end
T.raises(function()manifest({required_imports={[2]={file='late'}}})end,nil,'sparse import array rejected')
T.raises(function()manifest({required_imports={{id='same',file='a'}},optional_imports={{id='same',file='b'}}})end,nil,'cross-list duplicate IDs rejected')
T.raises(function()manifest({required_imports={{id='one',file='a'}},optional_imports={{id='two',file='baseroms/a'}}})end,nil,'canonical path aliases cannot declare two owners')

local fs,body=memory({['mods/native/baseroms/base.bin']='abc'})
local api=Access.new(m,fs,function(path)return fs.read('mods/native/'..path)end)
T.eq(api:info('extra'),nil,'missing optional portable import answers unavailable')
local list=api:list();list[2].extensions[1]='.bad'
T.eq(api:list()[2].extensions[1],'.pack','declaration views cannot mutate picker policy')
T.eq(api:info('base').verified,'md5','info reports actual verification')
T.eq(api:info('base').size,3,'info exposes file size')
T.eq(api:read('base',1,2),'bc','range addresses only declared file')
T.eq(api:read('base',0,0),'','zero-length validated read works')
for _,range in ipairs({{-1,1},{0,-1},{0.5,1},{0,0.5},{2,2},{0,Files.MAX_READ_BYTES+1}}) do
  T.eq(api:read('base',range[1],range[2]),nil,'invalid or oversized range rejected')
end
T.eq(api:read('base'),nil,'portable reads require explicit bounded range')
T.eq(api:read('undeclared',0,1),nil,'undeclared path unavailable')
T.eq(fs.reads['mods/native/baseroms/base.bin'],nil,'digest and range access do not materialize file with read()')
local before=fs.maxRead
for _=1,5 do T.check(api:info('base')~=nil,'verified metadata remains available') end
T.eq(fs.maxRead,before,'repeated metadata inspection reuses validation')
fs.write('mods/native/baseroms/base.bin','xyz')
T.eq(api:info('base'),nil,'same-length changed source invalidates verification')
T.eq(api:read('base',0,1),nil,'corrupt source cannot be read through import facade')

local legacy=manifest({required_imports={{id='old',file='baseroms/old.bin',size=3}}})
fs.write('mods/native/baseroms/old.bin','old')
local old=Access.new(legacy,fs,function(path)return fs.read('mods/native/'..path)end)
T.eq(old:read('old'),'old','existing whole-file legacy accessor retained')
local portable=manifest({required_imports={{id='base',file='base.bin',verify='mod',size=3}}})
local legacyFs=memory({['mods/native/base.bin']='old'})
T.eq(Imports.pathFor(portable,portable.requiredImports[1],legacyFs),'mods/native/base.bin','legacy bare-file location remains usable')
T.eq(Imports.resolveRead(portable,'baseroms/base.bin',legacyFs),'mods/native/base.bin','canonical spelling resolves existing legacy file')

local canonical='\128\55\18\64'..string.rep('abcd',16)
local n64=manifest({required_imports={{id='cart',file='cart.z64',format='n64',size=#canonical,
  md5=MD5.new():update(canonical):final()}}})
local entry=n64.requiredImports[1]
local savedFs=CacheFs.dataFs
CacheFs.dataFs=function()return fs end
for _,width in ipairs({1,2,4}) do
  local source=Files.swap(canonical,width)
  if width~=1 then source=string.rep('\0',512)..source end
  local ok,why=Imports.install(n64,entry,source)
  T.check(ok,'N64 source is installed: '..tostring(why))
  T.eq(body['mods/native/baseroms/cart.z64'],canonical,'installed portable cartridge is canonical')
  local cart=Access.new(n64,fs)
  T.eq(cart:read('cart',3,9),canonical:sub(4,12),'unaligned logical slice is canonical')
end
local previous=body['mods/native/baseroms/cart.z64']
local ok=Imports.install(n64,entry,canonical:sub(1,-2)..'x')
T.eq(ok,false,'wrong digest cannot replace a valid import')
T.eq(body['mods/native/baseroms/cart.z64'],previous,'failed verification preserves previous bytes')
fs.failWrite=true
T.eq(Imports.install(n64,entry,canonical),false,'failed write is rejected')
fs.failWrite=false;fs.failRename=true
T.eq(Imports.install(n64,entry,canonical),false,'failed publication is rejected')
fs.failRename=false
T.eq(body['mods/native/baseroms/cart.z64'],previous,'failed publication preserves previous bytes')
local flexible=manifest({optional_imports={{id='flexible',file='flexible.bin',format='raw',verify='mod',max_size=1024}}})
fs.write('mods/native/baseroms/flexible.bin','KEEP')
fs.shortWrite=true
T.eq(Imports.install(flexible,flexible.optionalImports[1],canonical),false,'short write cannot pass without an exact declared size')
fs.shortWrite=false
T.eq(body['mods/native/baseroms/flexible.bin'],'KEEP','short write preserves previous valid import')
local shared={id='another',path='mods/another',requiredImports={entry}}
T.eq(Imports.adoptShared(shared),1,'another mod can adopt the verified shared file')
T.eq(body['mods/another/baseroms/cart.z64'],canonical,'shared import retains canonical bytes')
local large=manifest({required_imports={{id='large',file='large.bin',format='raw',size=2097152,
  md5='3d1fac9a0e90cdd71f19e717128c8bc6'}}})
local source=string.rep('0123456789abcdef',131072)
fs.write('inbox/source.bin',source)
fs.strictWholeRead=true
local installed,why=Imports.installFrom(large,large.requiredImports[1],{savePath='inbox/source.bin'})
T.check(installed,'multi-chunk source is validated and installed: '..tostring(why))
T.check(body['mods/native/baseroms/large.bin']==source,'multi-chunk publication preserves every byte')
T.check(body['inbox/source.bin']==source,'original source remains intact')
T.eq(fs.reads['inbox/source.bin'],nil,'source import never calls whole-file read')
T.eq(fs.reads['mods/native/baseroms/large.bin'],nil,'published import never calls whole-file read')
fs.strictWholeRead=false
local virtual=manifest({optional_imports={{id='huge',file='huge.bin',verify='mod'}}})
local hugeSize=3*1024*1024*1024
local requested
local vfs={getInfo=function()return {type='file',size=hugeSize,modtime=1}end,
  readRange=function(_,offset,length)requested=offset;return string.rep('z',length)end}
local huge=Access.new(virtual,vfs)
T.eq(huge:info('huge').size,hugeSize,'multi-GiB source metadata does not allocate its contents')
T.eq(huge:read('huge',hugeSize-2,2),'zz','range offsets remain valid above 32-bit signed size')
T.eq(requested,hugeSize-2,'large offset is not truncated')
local wholeRead=false
local noRanges={getInfo=vfs.getInfo,read=function()wholeRead=true;error('must stay bounded')end}
T.eq(Access.new(virtual,noRanges):read('huge',0,1),nil,'host without bounded I/O refuses the operation')
T.check(not wholeRead,'unavailable random access never falls back to whole multi-GiB read')
T.eq(fs.openHandles,0,'every opened import handle closes on success and failure')
for path in pairs(body) do T.check(not path:find('imports/staging/',1,true),'no failed import staging is exposed') end

local rows=Launcher.deriveList({m},{mods={}},'red')
T.eq(rows[1].status,'warn','launcher flags invalid required file')
fs.write('mods/native/baseroms/base.bin','abc')
rows=Launcher.deriveList({m},{mods={}},'red')
T.eq(rows[1].status,'ok','optional missing file does not block launcher readiness')
T.eq(rows[1].missingImports[1].entry.id,'extra','optional import is available in existing picker flow')
T.check(rows[1].missingImports[1].reason:find('Optional',1,true),'optional picker is clearly labeled')
CacheFs.dataFs=savedFs
local savedRoot=CacheFs.root
local savedPublisher=package.loaded['src.net.DownloadPublish']
local paths
CacheFs.root=function()return '/virtual data' end
package.loaded['src.net.DownloadPublish']=function(from,to)paths={from,to};return true end
T.check(CacheFs.rawRename('imports/staging/test.part','mods/native/baseroms/base.bin'),'custom-root publisher forwards an atomic operation')
for i,path in ipairs(paths) do paths[i]=path:gsub('\\','/') end
T.same(paths,{'/virtual data/imports/staging/test.part','/virtual data/mods/native/baseroms/base.bin'},'publication stays within the chosen data root')
CacheFs.root=savedRoot;package.loaded['src.net.DownloadPublish']=savedPublisher

local function boot(file)
  local definitions={
    importer={required_imports={{id='base',file='base.bin',verify='mod',size=3}}},
    dependent={dependencies={'importer'}},
    optional={optional_imports={{id='extra',file='extra.pack',verify='mod'}}},
    independent={},
  }
  local files,paths={},{}
  for id,extra in pairs(definitions) do
    local path='mods/'..id;paths[#paths+1]=path
    files[path..'/manifest.json']=Json.encode(raw(extra,id))
    files[path..'/main.lua']='local mod=...;mod.exports.executed=true'
  end
  if file then files['mods/importer/baseroms/base.bin']=file end
  local f=memory(files)
  return T.sdk.loadMods(paths,{fs=f,dev=false}),f
end
local run,waitingFs=boot()
T.eq(run.loader.exports.importer,nil,'required file is gated before entry')
T.eq((run.loader.apis or {}).importer,nil,'blocked mod acquires no API or subscriptions')
T.eq(run.loader.exports.dependent,nil,'required import gate propagates to hard dependents')
T.check(run.loader.exports.optional.executed,'missing optional file allows original entry')
T.check(run.loader.exports.independent.executed,'unrelated mod still executes')
T.eq(run.mods.importer.state,'missing_imports','required-file state is actionable')
local status=run.loader:status()
local waiting
for _,row in ipairs(status.available) do if row.id=='importer' then waiting=row end end
T.check(waiting.waitingImports,'manager status retains import wait')
local manager=Manager.new({mods=run.loader,save={options={}}})
manager:_importLanded(waiting,{required=true})
T.check(not manager.restartPending,'still-missing source does not stage a pointless restart')
waitingFs.write('mods/importer/baseroms/base.bin','abc')
manager:_importLanded(waiting,{required=true})
T.check(manager.restartPending,'importing a blocked requirement stages restart')
manager:refresh()
T.check(manager.restartPending,'refresh retains restart for a newly satisfied blocked import')
run.release()
run=boot('abc')
T.check(run.loader.exports.importer.executed,'required file permits original entry after import')
T.check(run.loader.exports.dependent.executed,'dependent recovers on fresh boot')
run.release()
local optionalManager=Manager.new({})
optionalManager:_importLanded(waiting,{required=false})
T.check(not optionalManager.restartPending,'optional imports do not force restart')
Versions.set(savedVersion)
T.finish('Native import contracts')
