-- ROM-free runtime probe. A higher minimum is an explicit experimental gate;
-- the stock runtime is still expected to support the default minimum of 60.
local minimum = tonumber(arg and arg[1]) or 60
assert(minimum >= 1 and minimum <= 120, 'minimum must be between 1 and 120')
local Json = require('src.link.Json')
local compile = loadstring or load
local report = {runtime = jit and jit.version or _VERSION, minimum = minimum,
  cases = {}, checks = 0}
local function check(value, reason)
  assert(value, reason); report.checks = report.checks + 1
end
local function factory(count)
  local lines, terms = {}, {}
  for i = 1, count do
    lines[#lines + 1] = ('local v%d = %d'):format(i, i)
    terms[#terms + 1] = 'v' .. i
  end
  local sum = table.concat(terms, '+')
  lines[#lines + 1] = ('return function(d) v%d=v%d+d; return %s end, '
    .. 'function(d) v1=v1+d; return %s end'):format(count, count, sum, sum)
  return compile(table.concat(lines, '\n'), '@synthetic-shared-upvalues-' .. count)
end
local wasJit = jit and jit.status()
for _, count in ipairs({1, 8, 32, 60, 61, 64, 96, 120}) do
  local chunk, why = factory(count)
  local result = {upvalues = count, compiles = chunk ~= nil}
  if not chunk then
    check(count > minimum, 'required closure rejected: ' .. tostring(why))
    check(tostring(why):find('upvalues', 1, true), 'unexpected compiler rejection')
  else
    for _, mode in ipairs({'interpreter', 'jit'}) do
      if mode == 'interpreter' then if jit then jit.off(); jit.flush() end
      elseif jit then jit.on(); jit.flush(); jit.opt.start('hotloop=1', 'hotexit=1') end
      local first, second = chunk()
      local found = 0
      while debug.getupvalue(first, found + 1) do found = found + 1 end
      check(found == count, 'closure captures the requested number of values')
      local expected = count * (count + 1) / 2
      for step = 1, 10000 do
        expected = expected + 1
        check(first(1) == expected, 'first closure retains all captured values')
        expected = expected + 1
        check(second(1) == expected, 'sibling closure shares the captured cells')
        if step % 251 == 0 then collectgarbage('collect') end
      end
      local name, value = debug.getupvalue(first, found)
      check(name ~= nil and type(value) == 'number', 'high-index debug read')
      -- Match stock LuaJIT's debug-surgery contract: a previously constant
      -- upvalue may be embedded in a trace. Flush before replacing it.
      -- https://github.com/LuaJIT/LuaJIT/issues/968
      if jit then jit.flush() end
      check(debug.setupvalue(first, found, value + 7) == name, 'high-index debug write')
      expected = expected + 7
      local observed = second(0)
      check(observed == expected, ('debug write reaches the shared sibling cell (%d, %s: %s vs %s)')
        :format(count, mode, tostring(observed), tostring(expected)))
      local dumped = string.dump(first)
      local restored = assert(compile(dumped, '@restored-shared-upvalues'))
      if jit then jit.flush() end
      for index = 1, found do
        local _, current = debug.getupvalue(first, index)
        check(debug.setupvalue(restored, index, current) ~= nil, 'restore bytecode upvalue')
      end
      check(restored(0) == expected, 'bytecode round trip retains high-index values')
      result[mode] = true
    end
  end
  report.cases[#report.cases + 1] = result
end
if jit then if wasJit then jit.on() else jit.off() end end
report.passed = true
print('RUNTIME_UPVALUES ' .. Json.encode(report))
