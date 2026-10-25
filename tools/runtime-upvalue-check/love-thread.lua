require('love.thread')
local channel, capacity = ...
local declarations, terms = {}, {}
for index = 1, capacity do
  declarations[#declarations + 1] = ('local v%d=%d'):format(index, index)
  terms[#terms + 1] = 'v' .. index
end
declarations[#declarations + 1] = 'return function() return ' .. table.concat(terms, '+') .. ' end'
local factory = assert(loadstring(table.concat(declarations, '\n')))
local fn = factory()
assert(fn() == capacity * (capacity + 1) / 2)
collectgarbage('collect')
assert(fn() == capacity * (capacity + 1) / 2)
channel:push({ok = true, capacity = capacity})
