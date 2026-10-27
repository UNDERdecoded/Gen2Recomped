-- CPU classification microbenchmark; not a frame-rate or gameplay test.
package.path='./?.lua;./?/init.lua;'..package.path
local native = arg[1] == 'native'
local MB = require(native and 'src.compat.gen1.MetatileBehavior' or 'src.core.game3.mb')
local factory = native and require('src.compat.gen1.CollisionClass')
local families = arg[2] and {arg[2]} or {'frlg','rse'}
for _,family in ipairs(families)do
 assert(family == 'frlg' or family == 'rse')
 local C=native and factory.impl(family) or require('src.core.game3.scripting.collision_'..family)
 local input,bits={},{}
 for i=1,4096 do
  local raw=(i*29)%256
  local behavior=MB.fromRaw(family=='frlg' and 'firered' or 'emerald',raw)
  bits[behavior]=raw%8
  input[i]={(i*37)%1024,i%4,behavior,({'route','town','indoor'})[i%3+1]}
 end
 if C.setTileBits then C.setTileBits(bits)end
 local function batch(n)
  local sum=0
  for _=1,n do for _,row in ipairs(input)do sum=sum+C.fromCell(row[1],row[2],row[3],row[4])end end
  return sum
 end
 batch(16)
 local at=os.clock();local sum=batch(256);local elapsed=os.clock()-at
 print(family,elapsed,sum,4096*256)
end
