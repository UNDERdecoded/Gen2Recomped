-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
_G.love=_G.love or require('tests.love_stub')
local T=require('tests.modkit')
local Wire=require('src.mods.JobData')
local Cache=require('src.mods.JobCache')
local Store=require('src.mods.Storage')
local Writer=require('src.import.LuaWriter')
local F=require('tests.pack_sources.fixture')
for _,value in ipairs({true,false,3.141592653589793,-1.2345678901234567,1e-200,'\0\n\\"',
    {a={2,3},[1.2345678901234567]='fractional key'}}) do
  local out,why=Wire.decode(assert(Wire.encode(value)))
  T.eq(why,nil,'valid plain data decodes')
  T.same(out,value,'plain data crosses states without precision loss')
end
local bytes=assert(Wire.encode(nil));local value,err=Wire.decode(bytes)
T.eq(value,nil,'nil result is valid');T.eq(err,nil,'nil result is not a decoding error')
for _,value in ipairs({function()end,coroutine.create(function()end),0/0,math.huge,
    setmetatable({},{__index=function()error('metatable must not run')end})}) do
  T.eq(Wire.encode(value),nil,'executable or non-finite values do not cross worker states')
end
local cycle={};cycle.self=cycle;T.eq(Wire.encode(cycle),nil,'cyclic data is rejected')
T.eq(Wire.encode({[false]=1}),nil,'non-string/number keys are rejected')
local deep={};local cursor=deep;for _=1,17 do cursor.child={};cursor=cursor.child end
T.eq(Wire.encode(deep),nil,'depth ceiling is enforced')
T.eq(Wire.encode(string.rep('x',1000),128),nil,'byte budget rejects before encoding')
T.eq(Wire.decode('return {value=(function()error("executed")end)()}'),nil,'wire data is parsed without executing Lua')

local root='modstorage/jobmod'
local function memory(initial)
  local fs,files=F.memory(initial)
  function fs.getDirectoryItems(path)
    local out,seen={},{}
    for name in pairs(files) do
      if name:sub(1,#path+1)==path..'/' then
        local child=name:sub(#path+2):match('^[^/]+')
        if not seen[child] then seen[child]=true;out[#out+1]=child end
      end
    end
    return out
  end
  return fs,files
end
local function originals()
  return {[root..'/hero.bin']='old image',[root..'/done.bin']='old marker',
    [root..'/legacy.rec']='return {old=true}',['imports/source.bin']='original source',
    ['modstorage/another/hero.bin']='other mod'}
end
local function prepare(fs)
  local store=Store.new('jobmod',fs);local tx=Cache.new(store,fs,'abc123')
  assert(tx:write('hero','new image'));assert(tx:write('done','new marker'))
  assert(tx:write('legacy','new bytes'))
  return store,tx
end
do
  local fs,files=memory(originals());local store,tx=prepare(fs)
  T.eq(store:readBytes(nil,'hero'),'old image','staging never changes live cache')
  T.eq(tx:read('hero'),'new image','worker can read its staged output')
  T.eq(tx:info('hero').size,9,'worker sees staged byte size')
  T.check(tx:exists('hero'),'worker sees its own pending key')
  T.eq(tx:exists('absent'),false,'missing key is a normal lookup')
  T.check(tx:commit(),'complete output publishes')
  T.eq(store:readBytes(nil,'hero'),'new image','completed job becomes readable through native storage')
  T.eq(files[root..'/legacy.rec'],nil,'byte publication replaces an old record representation')
  T.eq(files['imports/source.bin'],'original source','source imports are preserved')
  T.eq(files['modstorage/another/hero.bin'],'other mod','other namespaces are preserved')
  for path in pairs(files) do T.check(not path:find('.job-transactions',1,true),'successful transaction leaves no staging files') end
end
for failure=1,9 do
  local initial=originals();local fs,files=memory(initial);local store,tx=prepare(fs)
  local rename=fs.rename;local calls=0
  function fs.rename(a,b)
    calls=calls+1
    if calls==failure then return nil,'injected publication failure' end
    return rename(a,b)
  end
  local ok=tx:commit()
  if not ok then
    for path,old in pairs(initial) do T.eq(files[path],old,'failure at rename '..failure..' restores prior data') end
  else T.eq(store:readBytes(nil,'hero'),'new image','successful publication keeps complete output') end
end
do
  local fs,files=memory(originals());local _,tx=prepare(fs);tx:cancel()
  T.eq(files[root..'/hero.bin'],'old image','cancel preserves prior usable cache')
  T.eq(tx:state(),'cancelled','cancel retires the transaction')
  for path in pairs(files) do T.check(not path:find('.job-transactions',1,true),'cancel removes only its own staging files') end
end
for _,key in ipairs({'../escape','/absolute','C:/drive','x\\y','.job-transactions/hijack'}) do
  local fs=memory();local tx=Cache.new(Store.new('jobmod',fs),fs,'abc')
  T.eq(pcall(tx.write,tx,key,'data'),false,'unsafe or reserved key is rejected before write')
  T.eq(fs.writes,0,'invalid key performs no filesystem writes')
end
do
  local fs,files=memory(originals());local tx=Cache.new(Store.new('jobmod',fs),fs,'abc')
  fs.shortWrite=true
  T.eq(tx:write('new','longer bytes'),false,'truncated staging write fails')
  T.eq(tx:commit(),nil,'failed staging cannot publish a completion marker')
  tx:cancel()
  T.eq(files[root..'/.job-transactions/abc/new-1.part'],nil,'failed staging data is removed')
  T.eq(files[root..'/hero.bin'],'old image','failed staging preserves previous cache')
end
do
  local fs=memory();local tx=Cache.new(Store.new('jobmod',fs),fs,'abc')
  local bytes=string.rep('staged bytes',200000)
  T.check(tx:write('large',bytes),'large staged output verifies in chunks')
  T.check(fs.maxRead<=1048576,'verification never requests an entire large output')
  T.eq(tx:read('large'),bytes,'chunked verification preserves output bytes')
  tx:cancel()
end
do
  local fs=memory();local where='first';fs.getWriteRoot=function()return where end
  local tx=Cache.new(Store.new('jobmod',fs),fs,'abc');assert(tx:write('new','data'))
  local writes=fs.writes;where='second'
  T.eq(pcall(tx.commit,tx),false,'folder switch aborts publication')
  tx:cancel();T.eq(fs.writes,writes,'folder switch never routes later writes into another root')
end
for _,state in ipairs({'publishing','committed'}) do
  local dir=root..'/.job-transactions/abc'
  local fs,files=memory({[root..'/hero.bin']='new image',[dir..'/old-bytes-1.part']='old image',
    [dir..'/journal.lua']=Writer.encode({format=1,owner='jobmod',state=state,
      rows={{key='hero',bytes=true,record=false}}})})
  T.check(Cache.recover(Store.new('jobmod',fs),fs),'restart recovery accepts engine journal')
  T.eq(files[root..'/hero.bin'],state=='publishing' and 'old image' or 'new image','restart distinguishes interrupted and committed output')
  T.eq(files[dir..'/journal.lua'],nil,'recovery cleans completed journal')
end
do
  local dir=root..'/.job-transactions/abc'
  local fs,files=memory({[dir..'/journal.lua']=Writer.encode({format=1,owner='jobmod',state='publishing',
    rows={{key='../another/hero',bytes=false,record=false}}}),['modstorage/another/hero.bin']='other mod'})
  T.eq(Cache.recover(Store.new('jobmod',fs),fs),nil,'recovery refuses forged path traversal')
  T.eq(files['modstorage/another/hero.bin'],'other mod','malformed journal cannot delete neighbouring data')
end
do
  local file=assert(io.open('main.lua','rb'));local source=file:read('*a');file:close()
  local function extract(value)return assert(value:gsub('\r\n','\n'):match('\nfunction love%.quit%(%).-\nend\n'))end
  local hook=extract(source)
  T.eq(extract(source:gsub('\r\n','\n'):gsub('\n','\r\n')),hook,'quit regression reads Windows CRLF checkouts')
  for _,veto in ipairs({true,false}) do
    local stopped,closed=0,0
    local env={love={},editorMode=true,EditorApp={quit=function()return veto end},
      WindowFrame={shutdown=function()closed=closed+1 end},
      package={loaded={['src.mods.Job']={unloadAll=function()stopped=stopped+1 end}}}}
    local chunk=assert(loadstring(hook,'@main.lua:love.quit'));setfenv(chunk,env);chunk()
    T.eq(env.love.quit(),veto,'editor quit preserves veto result')
    T.eq(stopped,veto and 0 or 1,'only accepted editor quit stops mod jobs')
    -- This upstream host has no separate window-frame owner.
  end
end
T.finish('Native job data and cache transactions')
