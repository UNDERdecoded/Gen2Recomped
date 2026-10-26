-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root=assert(os.getenv('JOB_ENGINE_ROOT'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local J,fs,co
local count=0
io.stdout:setvbuf('no');io.stderr:setvbuf('no')
function love.errorhandler(message)
  print('Native job probe failed: '..tostring(message))
  if J then J.unloadAll() end
  return function()return 1 end
end
local function check(value,why)count=count+1;assert(value,why)end
local function eq(a,b,why)check(a==b,(why or 'equality')..': '..tostring(a)..' != '..tostring(b))end
local function yield()coroutine.yield()end
local function runTests()
  local Manifest=require('src.mods.Manifest')
  local Access=require('src.mods.ImportAccess')
  local function mod(id,permissions)
    local m=Manifest.validate({id=id,name=id,version='1.0.0',entry='main.lua',api=2,
      affects_link=false,permissions=permissions or {'background'},
      required_imports={{id='base',file='baseroms/base.bin',size=4}}})
    m.path='mods/'..id
    assert(fs.createDirectory(m.path..'/baseroms'))
    assert(fs.write(m.path..'/baseroms/base.bin','ABCD'))
    local cache=select(2,Access.new(m,fs))
    return J.forMod({}, {manifest=m,path=m.path},cache),m.path,cache
  end
  local api,path,cache=mod('jobqa')
  local function script(name,text)
    assert(fs.write(path..'/'..name..'.lua',text));return name..'.lua'
  end
  local function wait(api,handle)
    local deadline=love.timer.getTime()+5
    while true do
      local state=api:poll(handle)
      if state.status~='pending' then return state end
      assert(love.timer.getTime()<deadline,'job did not settle');yield()
    end
  end
  local function retired()
    local deadline=love.timer.getTime()+3
    while J.diagnostics().retained>0 do
      assert(love.timer.getTime()<deadline,'physical workers were not retired');yield()
    end
    eq(J.diagnostics().running,0,'no physical worker left running')
  end
  check(J.available(),'real LOVE threads available')
  local denied=mod('denied',{})
  eq(denied:available(),false,'permissionless probe is safe')
  eq(pcall(denied.run,denied,'anything.lua',{}),false,'permission enforced before run')
  local argument={n=10000,nested={value=1.2345678901234567}}
  local h=assert(api:run(script('sum','local a=...;local n=0;for i=1,a.n do n=n+i end;return {sum=n,nested=a.nested}'),argument))
  argument.n=0;argument.nested.value=0
  local result=wait(api,h)
  eq(result.status,'ok','real job completes');eq(result.result.sum,50005000,'argument snapshotted')
  eq(result.result.nested.value,1.2345678901234567,'numeric precision retained')
  result.result.nested.value=999
  eq(api:poll(h).result.nested.value,1.2345678901234567,'poll returns detached result')
  check(api:release(h),'release known handle');eq(api:release(h),false,'double release is harmless')
  for _,body in ipairs({'return false','return nil'}) do
    h=assert(api:run(script('scalar',body),{}));result=wait(api,h)
    eq(result.status,'ok','false/nil results are successful')
    local expected;if body=='return false' then expected=false end
    eq(result.result,expected,'scalar result retained')
    api:release(h)
  end
  h=assert(api:run(script('sandbox',[[
    assert(io==nil and os==nil and ffi==nil and package==nil and debug==nil)
    assert(love==nil and mod==nil and loadstring==nil and getfenv==nil)
    assert(getmetatable('text')==nil)
    assert(not pcall(require,'src.core.Game'))
    assert(job.cache==nil and job.imports==nil)
    return true
  ]]),{}))
  result=wait(api,h);eq(result.status,'ok',result.err);eq(result.result,true,'sandbox is active');api:release(h)
  h=assert(api:run(script('errorobject',[[
    error(setmetatable({}, {__tostring=function()while true do end end}))
  ]]),{}, {maxSeconds=1}))
  result=wait(api,h);eq(result.status,'error','error object cannot execute after removing hooks')
  check(result.err:find('table',1,true),'error object produces a plain diagnostic')
  api:release(h)
  for _,bad in ipairs({'../other.lua','/absolute.lua','x\\y.lua','C:/x.lua'})do eq(api:run(bad,{}),nil,'unsafe script refused')end
  eq(api:run('sum.lua',{fn=function()end}),nil,'functions cannot cross states')
  assert(cache:write('hero','old image'));assert(cache:write('done','old marker'))
  h=assert(api:run(script('assets',[[
    assert(job.imports:info('base').size==4)
    assert(job.imports:read('base',1,2)=='BC')
    assert(not job.imports:read('other',0,1))
    assert(not job.imports:read('base',0,999999999))
    assert(job.cache:write('hero','new image'))
    assert(job.cache:read('hero')=='new image')
    assert(job.cache:info('hero').size==9 and job.cache:exists('hero'))
    assert(job.cache:write('done','new marker'))
    job.progress({phase='staged'})
    return {finished=true}
  ]]),{}, {assetIO=true,maxSeconds=2}))
  result=wait(api,h);eq(result.status,'ok',result.err)
  eq(cache:read('hero'),'new image','committed worker output visible through native cache')
  eq(cache:read('done'),'new marker','completion marker published with successful output')
  eq(fs.read(path..'/baseroms/base.bin'),'ABCD','source preserved')
  api:release(h)
  for _,tail in ipairs({"error('after write')",'while true do end'})do
    h=assert(api:run(script('failed',"assert(job.cache:write('hero','broken'));assert(job.cache:write('done','broken marker'));"..tail),{},
      {assetIO=true,maxSeconds=.15}))
    result=wait(api,h);eq(result.status,'error','failed or timed-out job reports error')
    eq(cache:read('hero'),'new image','failed job preserves old complete image')
    eq(cache:read('done'),'new marker','failed job cannot publish a completion marker')
    api:release(h);retired()
  end
  for _,body in ipairs({
    'while true do end',
    'while true do pcall(function()while true do end end)end',
    "xpcall(function()error('x')end,function()while true do end end)",
    'local c=coroutine.create(function()while true do end end);coroutine.resume(c)',
  })do
    h=assert(api:run(script('cancel','job.progress(true);'..body),{}, {maxSeconds=1}))
    local deadline=love.timer.getTime()+2
    while api:poll(h).progress~=true do assert(love.timer.getTime()<deadline,'worker did not start');yield()end
    check(api:cancel(h),'cancel running worker');eq(api:poll(h).status,'cancelled','cancel status')
    check(api:release(h),'release cancelled handle');retired()
  end
  local second,p2=mod('jobqa2');local third=mod('jobqa3')
  local handles={}
  for _,which in ipairs({{api,path},{api,path},{second,p2},{second,p2}})do
    assert(fs.write(which[2]..'/busy.lua','job.progress(true);while true do end'))
    handles[#handles+1]={which[1],assert(which[1]:run('busy.lua',{}, {maxSeconds=2}))}
  end
  eq(api:run('busy.lua',{}),nil,'per-mod limit enforced')
  eq(third:run('missing.lua',{}),nil,'global limit enforced before another worker starts')
  eq(second:release(handles[1][2]),false,'another mod cannot release a handle')
  eq(second:poll(handles[1][2]).status,'error','another mod cannot poll a handle')
  for _,item in ipairs(handles)do item[1]:release(item[2])end
  retired()
  h=assert(api:run('busy.lua',{}, {maxSeconds=2}));J.unloadAll();retired()
  eq(api:poll(h).status,'error','unload retires handles')
  do
    local orphan,orphanPath=mod('jobqaorphan')
    assert(fs.write(orphanPath..'/busy.lua','while true do end'))
    assert(orphan:run('busy.lua',{}, {maxSeconds=2}))
  end
  collectgarbage('collect');collectgarbage('collect')
  eq(J.diagnostics().retained,1,'live job retains its teardown owner after API collection')
  J.unloadAll();retired()
  print('Native mod workers: '..count..' checks PASS; real CPU jobs, plain data, sandbox, scoped I/O, transactional cache, timeout/cancel, protected calls/coroutines, limits and physical retirement.')
end
function love.load()
  print('Native job probe: preparing engine source')
  if love.filesystem.getInfo('src/mods/job_worker.lua','file') then
    -- The portable probe includes only the worker bootstrap and its three
    -- pure dependencies. Never mount a player's complete data directory.
  elseif love.filesystem.mountFullPath then
    assert(love.filesystem.mountFullPath(root..'/src','src','read',true))
  else assert(love.filesystem.mount(root..'/src','src',true),'probe needs a source mount or a fused engine payload') end
  J=require('src.mods.Job');fs=require('src.import.CacheFs').dataFs()
  assert(fs.getWriteRoot()==love.filesystem.getSaveDirectory(),'QA writes must remain in their owned identity')
  co=coroutine.create(runTests)
  print('Native job probe: source mounted, data scope verified')
end
function love.update()
  local ok,why=pcall(J.update)
  if not ok then print(why);J.unloadAll();love.event.quit(1);return end
  local resumed,err=coroutine.resume(co)
  if not resumed then print(debug.traceback(co,tostring(err)));J.unloadAll();love.event.quit(1)
  elseif coroutine.status(co)=='dead' then love.event.quit(0) end
  love.timer.sleep(.001)
end
