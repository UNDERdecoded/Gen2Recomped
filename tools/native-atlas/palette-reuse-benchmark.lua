-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional CPU comparison; accepts an exact earlier AtlasPixels.lua source.
-- No timing threshold or gameplay/frame-rate acceptance is inferred here.
io.stdout:setvbuf('no')
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local F=require('tools.native-atlas.fixture')
local current=require('src.compat.gen1.AtlasPixels')
local path=assert(arg[1],'supply the exact earlier AtlasPixels.lua path')
local prior=assert(loadfile(path))()
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local a,b=F.new(edition),F.new(edition)
 local old,new=prior.new(a.pair,a.layout),current.new(b.pair,b.layout)
 for i=1,300 do old:update(i);new:update(i)end
 local times={old={},new={}}
 local function measure(label,model)
  collectgarbage('collect');local start=os.clock()
  for tick=1,3000 do model:update(tick)end
  times[label][#times[label]+1]=(os.clock()-start)*1000
 end
 for trial=1,5 do
  if trial%2==1 then measure('old',old);measure('new',new)
  else measure('new',new);measure('old',old)end
 end
 assert(old:rgba(false)==new:rgba(false)and old:rgba(true)==new:rgba(true),'benchmark pixels differ')
 table.sort(times.old);table.sort(times.new)
 print('PALETTE_BENCHMARK',edition,times.old[3],times.new[3],times.old[3]/times.new[3])
end
