function love.errorhandler(err)
 io.stderr:write(debug.traceback(tostring(err)).."\n");io.stderr:flush()
 return function()return 1 end
end
local Fetch, Net, base
local checks, pulses = 0, 0
local function check(ok, message)
  checks = checks + 1
  assert(ok, message)
end
local function await(api, handle)
  local at = love.timer.getTime()
  while true do
    local before = love.timer.getTime()
    local state = api:poll(handle)
    check(love.timer.getTime() - before < .1, 'poll must not perform transport IO')
    if state.status ~= 'pending' then return state end
    check(love.timer.getTime() - at < 10, 'request completes within test deadline')
    pulses = pulses + 1; love.timer.sleep(.005)
  end
end
function love.load()
  Fetch = require('src.net.Fetch'); Net = require('src.mods.Net')
  base = assert(os.getenv('GET_TEST_URL'))
  local newThread = love.thread.newThread
  love.thread.newThread = function(source, ...)
    if source == 'src/net/download_worker.lua' then source = 'download_test_worker.lua' end
    return newThread(source, ...)
  end
end
function love.run()
  local ok, err = xpcall(function()
    love.load()
    local loader = {}
    local function mod(id, network) return Net.forMod(loader, {manifest={id=id, permissionSet={network=network}}}) end
    local a, b, denied = mod('a', true), mod('b', true), mod('denied', false)
    check(not denied:available(), 'network permission required')
    check(not pcall(denied.get, denied, base), 'ungranted GET refuses')
    check(a:available(), 'real thread workers available')
    check(a:capabilities().maxResponseBytes >= 4194304, 'bounded receive ceiling advertised to package consumers')
    check(a:get('file:///etc/hosts') == nil, 'non HTTP URL denied')
    check(a:get(base..'/binary', {boundedHttpsGet=1}) == nil, 'bounded HTTPS rejects HTTP')
    local started = love.timer.getTime()
    local slow = assert(a:get(base..'/slow', {maxSeconds=3}))
    check(love.timer.getTime()-started < .1, 'GET starts without waiting for server')
    check(b:poll(slow).status == 'error', 'handles isolated between mods')
    check(not b:cancel(slow) and not b:release(slow), 'foreign cancellation denied')
    local binary = assert(a:get(base..'/binary?encoded=%22%26%25', {maxBytes=256}))
    local result = await(a, binary)
    check(result.status=='ok' and result.body==string.char(0,255,13,10)..'GET binary', 'binary bytes and encoded URL preserved: '..tostring(result.status)..' '..tostring(result.err)..' bytes='..tostring(result.body and #result.body))
    check(result.receivedBytes==14, 'received byte count exact')
    a:release(binary)
    local state = await(a, slow)
    check(state.status=='ok' and state.body=='slow', 'delayed request completes: '..tostring(state.status)..' '..tostring(state.err)..' bytes='..tostring(state.body and #state.body))
    a:release(slow)
    check(pulses>20, 'caller keeps pumping during slow response')
    local missing=assert(a:get(base..'/missing'));state=await(a, missing)
    check(state.status=='error' and state.httpStatus==404, 'HTTP errors retained');a:release(missing)
    local big=assert(a:get(base..'/big', {maxBytes=64}));state=await(a,big)
    check(state.status=='error' and state.body==nil, 'oversize body refused');a:release(big)
    local chunk=assert(a:get(base..'/chunk', {maxBytes=64}));state=await(a,chunk)
    check(state.status=='error' and state.body==nil, 'body without content length bounded');a:release(chunk)
    local cancelled=assert(a:get(base..'/slow'));a:cancel(cancelled)
    check(a:poll(cancelled).status=='cancelled','cancel terminal');a:release(cancelled)
    local timeout=assert(a:get(base..'/slow', {maxSeconds=1}));state=await(a,timeout)
    check(state.status=='error','deadline enforced');a:release(timeout)
    local held={}
    for i=1,4 do held[i]=assert(a:get(base..'/slow')) end
    check(a:get(base..'/slow')==nil,'per-mod pending ceiling')
    Net.releaseAll(loader,'a')
    check(a:poll(held[1]).status=='error','unload invalidates handles')
    Net.unloadAll();Fetch.shutdown()
    check(Fetch.available(),'worker service can restart')
    local restart=assert(b:get(base..'/binary'));state=await(b,restart)
    check(state.status=='ok','GET after shutdown works');b:release(restart)
    local inFilePoll = false
    local getInfo = love.filesystem.getInfo
    love.filesystem.getInfo = function(...)
      assert(not inFilePoll, 'file poll must not perform filesystem IO')
      return getInfo(...)
    end
    local fileApi = {poll = function(_, id)
      inFilePoll = true
      local ok, result = pcall(Fetch.poll, id)
      inFilePoll = false
      assert(ok, result)
      return result
    end}
    local expected = string.char(0,255,13,10)..'GET binary'
    love.filesystem.createDirectory('downloads')
    local target = 'downloads/target.bin'
    local function oldFile()
      assert(love.filesystem.write(target, 'previous complete file'))
    end
    local function preserved(label)
      check(love.filesystem.read(target) == 'previous complete file', label)
    end
    oldFile()
    started = love.timer.getTime()
    local fileJob = assert(Fetch.download(base..'/stream', target, {size=262144}))
    check(love.timer.getTime()-started < .1, 'file transfer starts without waiting for server')
    local observedProgress = false
    local pattern = {}; for i=0,255 do pattern[#pattern+1] = string.char(i) end
    pattern = table.concat(pattern)
    local completeFile = pattern:rep(1024)
    while true do
      local before = love.timer.getTime()
      state = fileApi:poll(fileJob)
      check(love.timer.getTime()-before < .1, 'file poll never waits on HTTP')
      if state.status ~= 'pending' then break end
      -- Publication can finish after poll returns pending. Bracket the read
      -- with a fresh control snapshot: only an unclaimed transfer still
      -- promises the old file. At every phase the bytes must be one complete
      -- version, never an in-place/partial overwrite.
      local contents = love.filesystem.read(target)
      local boundary = fileApi:poll(fileJob)
      check(contents == 'previous complete file' or contents == completeFile,
        'concurrent publication exposes only a complete old or new file')
      if boundary.status == 'pending' and boundary.cancellable then
        check(contents == 'previous complete file',
          'unclaimed transfer preserves previous complete file')
      end
      if state.receivedBytes > 0 and state.receivedBytes < 262144 then observedProgress = true end
      pulses = pulses + 1; love.timer.sleep(.005)
    end
    check(state.status == 'ok' and state.receivedBytes == 262144, 'streamed file completes: '..tostring(state.err))
    check(observedProgress, 'progress available before transfer finishes')
    check(love.filesystem.read(target) == pattern:rep(1024), 'streaming preserves all binary bytes')
    Fetch.release(fileJob)
    for _, case in ipairs({
      {'/missing', {size=14}, 'HTTP failure'},
      {'/partial', {}, 'truncated response'},
      {'/binary', {size=13}, 'expected-size mismatch'},
      {'/binary', {maxBytes=3}, 'known-length bound'},
      {'/chunk', {maxBytes=64}, 'unknown-length bound'},
      {'/slow', {maxSeconds=.1}, 'deadline'},
    }) do
      oldFile();fileJob=assert(Fetch.download(base..case[1], target, case[2]))
      state=await(fileApi,fileJob)
      check(state.status=='error',case[3]..' reported: '..tostring(state.err))
      if case[1]=='/missing' then check(state.httpStatus==404,'file HTTP status retained') end
      preserved(case[3]..' preserves previous file');Fetch.release(fileJob)
    end
    oldFile();fileJob=assert(Fetch.download(base..'/slow',target))
    Fetch.cancel(fileJob);state=Fetch.poll(fileJob)
    check(state.status=='error' and state.err=='cancelled','legacy file cancellation remains terminal')
    preserved('cancel preserves previous file');Fetch.release(fileJob)
    local binaryFile=assert(Fetch.download(base..'/redirect','downloads/redirect.bin',{size=14}))
    state=await(fileApi,binaryFile)
    check(state.status=='ok' and love.filesystem.read('downloads/redirect.bin')==expected,'redirect and encoded binary output')
    Fetch.release(binaryFile)
    local empty=assert(Fetch.download(base..'/empty','downloads/empty.bin',{size=0}))
    state=await(fileApi,empty)
    check(state.status=='ok' and love.filesystem.getInfo('downloads/empty.bin').size==0,'zero-byte HTTP success')
    Fetch.release(empty)
    local large=assert(Fetch.download(base..'/large','downloads/large.bin',{size=17*1024*1024,maxBytes=20*1024*1024}))
    state=await(fileApi,large)
    check(state.status=='ok' and state.receivedBytes==17*1024*1024,'file can exceed in-memory GET ceiling')
    check(love.filesystem.read('downloads/large.bin')==pattern:rep(69632),'large file bytes exact')
    Fetch.release(large)
    local delayedPath='downloads/delay-publish.bin'
    assert(love.filesystem.write(delayedPath,'previous complete file'))
    local finishing=assert(Fetch.download(base..'/binary',delayedPath,{size=14}))
    local observedPublication=false
    local finishingAt=love.timer.getTime()
    while true do
      state=fileApi:poll(finishing)
      if state.status~='pending' then break end
      if state.phase=='publishing' then
        observedPublication=true
        check(not Fetch.cancel(finishing),'cancellation after publication claim is refused without waiting')
        check(state.cancellable==false,'committing request reports cancellation boundary')
      end
      check(love.timer.getTime()-finishingAt<5,'delayed publication completes')
      love.timer.sleep(.005)
    end
    check(observedPublication and state.status=='ok','main thread pumps during slow filesystem publication')
    check(love.filesystem.read(delayedPath)==expected,'claimed publication completes with exact bytes')
    Fetch.release(finishing)
    local invalidTarget=assert(Fetch.download(base..'/binary','downloads',{size=14}))
    state=await(fileApi,invalidTarget)
    check(state.status=='error' and love.filesystem.getInfo('downloads').type=='directory','publish error preserves existing directory')
    Fetch.release(invalidTarget)
    local heldFiles={}
    for i=1,8 do heldFiles[i]=assert(Fetch.download(base..'/slow','downloads/held'..i)) end
    check(Fetch.download(base..'/slow','downloads/overflow')==nil,'file queue bounded')
    for _, handle in ipairs(heldFiles) do Fetch.cancel(handle);Fetch.release(handle) end
    check(Fetch.download(base..'/slow','downloads/overflow')==nil,'release cannot bypass occupied file workers')
    Fetch.shutdown()
    for _, child in ipairs(love.filesystem.getDirectoryItems('net-download')) do
      check(#love.filesystem.getDirectoryItems('net-download/'..child)==0,'shutdown cleans file worker staging data')
    end
    preserved('late cancellation cannot publish after shutdown')
    print(('async GET and file downloads: %d checks, %d pump ticks PASS'):format(checks,pulses))
  end, debug.traceback)
  if not ok then io.stderr:write(tostring(err).."\n");io.stderr:flush(); if Fetch then Fetch.shutdown() end end
  return function() return ok and 0 or 1 end
end
