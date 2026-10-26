-- ROM-free acceptance inside the actual vendored Android LÖVE/JNI host.
local config = require('config')
local Json = require('src.link.Json')
local function publish(value)
  value.schema = 1
  value.capacity = config.capacity
  value.identity = config.identity
  value.releaseSelectable = false
  local file = assert(io.open(config.report, 'wb'))
  assert(file:write(Json.encode(value)))
  assert(file:close())
end
function love.load()
  local major, minor, revision = love.getVersion()
  assert(major == 11 and minor == 5, 'vendored Android LÖVE 11.5 required')
  assert(love.filesystem.getIdentity() == config.identity)
  assert(jit.arch == 'x64' and jit.status(), 'owned x86-64 Android JIT host required')
  local closureReport
  local previousPrint, previousArg = print, arg
  print = function(line, ...)
    if type(line) == 'string' and line:sub(1,17) == 'RUNTIME_UPVALUES ' then
      closureReport = Json.decode(line:sub(18))
    end
    return previousPrint(line, ...)
  end
  arg = {tostring(config.capacity)}
  local ok, why = pcall(assert(love.filesystem.load('check.lua')))
  print, arg = previousPrint, previousArg
  assert(ok, why)
  assert(closureReport and closureReport.passed and closureReport.minimum == config.capacity)
  local ffi = require('ffi')
  local callback = ffi.cast('double(*)(double)', function(value) return value + .5 end)
  assert(callback(2.25) == 2.75, 'actual host FFI callback failed')
  callback:free()
  local channel = love.thread.newChannel()
  local worker = love.thread.newThread('thread.lua')
  worker:start(channel, config.capacity)
  local result = channel:demand(30)
  assert(result and result.ok and result.capacity == config.capacity,
    worker:getError() or 'actual host thread VM did not complete')
  worker:wait()
  assert(not worker:getError(), worker:getError())
  assert(love.filesystem.write('filesystem-probe.txt', config.identity))
  assert(love.filesystem.read('filesystem-probe.txt') == config.identity)
  publish({passed=true, loveVersion={major,minor,revision}, arch=jit.arch,
    jitActive=true, ffiCallbackPassed=true, threadVmPassed=true,
    filesystemPassed=true, closureReport=closureReport})
  print('ANDROID_LOVE_RUNTIME_ABI_PASS', config.capacity, jit.arch)
  love.event.quit(0)
end
function love.errorhandler(why)
  local message = debug.traceback(tostring(why), 2)
  pcall(publish, {passed=false,error=message})
  io.stderr:write(message .. '\n')
  return function() return 1 end
end
