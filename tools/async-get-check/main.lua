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
    Fetch.shutdown()
    print(('async GET: %d checks, %d pump ticks PASS'):format(checks,pulses))
  end, debug.traceback)
  if not ok then io.stderr:write(tostring(err).."\n");io.stderr:flush(); if Fetch then Fetch.shutdown() end end
  return function() return ok and 0 or 1 end
end
