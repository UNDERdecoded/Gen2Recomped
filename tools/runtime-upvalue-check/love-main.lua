function love.load()
  local minimum = assert(tonumber(os.getenv('UPVALUE_TEST_MINIMUM')))
  assert(love.getVersion() >= 12, 'pinned LOVE12 host required')
  assert(love.filesystem.getIdentity() == os.getenv('UPVALUE_TEST_IDENTITY'))
  local saved = arg
  arg = {tostring(minimum)}
  assert(love.filesystem.load('check.lua'))()
  arg = saved
  local ffi = require('ffi')
  local callback = ffi.cast('double(*)(double)', function(value) return value + .5 end)
  assert(callback(2.25) == 2.75, 'host FFI callback failed')
  callback:free()
  local channel = love.thread.newChannel()
  local worker = love.thread.newThread('thread.lua')
  worker:start(channel, minimum)
  local result = channel:demand(10)
  assert(result and result.ok and result.capacity == minimum,
    worker:getError() or 'thread VM did not complete')
  worker:wait()
  assert(not worker:getError(), worker:getError())
  print('LOVE_RUNTIME_ABI_PASS ' .. minimum .. ' ' .. jit.arch)
  love.event.quit(0)
end

function love.errorhandler(why)
  io.stderr:write(debug.traceback(tostring(why), 2) .. '\n')
  return function() return 1 end
end
