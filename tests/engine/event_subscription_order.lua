-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Equal-priority UI decorators must not change order when peers subscribe.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Events=require('src.mods.Events')
for count=2,40 do
 local bus=Events.new();local seen={}
 for n=1,count do
  local id=n
  bus:on('screen',function()seen[#seen+1]=id end,0,'owner'..n)
 end
 bus:on('screen',function()seen[#seen+1]='high'end,10,'high')
 bus:on('screen',function()seen[#seen+1]='low'end,-10,'low')
 bus:emit('screen',{})
 T.eq(seen[1],'high','explicit higher priority remains first')
 for n=1,count do T.eq(seen[n+1],n,'same-priority callbacks retain subscription order with '..count..' peers') end
 T.eq(seen[#seen],'low','explicit lower priority remains last')
end
local bus=Events.new();local state={};local seen={};local retire
bus:on('screen',function(s)s.panel='generic';seen[#seen+1]='first'end)
retire=bus:on('screen',function(s)s.panel='specific';seen[#seen+1]='second'end)
bus:once('screen',function()
 seen[#seen+1]='once';retire()
 bus:on('screen',function()seen[#seen+1]='late'end)
end)
bus:emit('screen',state)
T.eq(state.panel,'specific','the later specific decorator settles after the earlier generic decorator')
T.eq(table.concat(seen,','),'first,second,once','dispatch retains its snapshot during retirement and subscription')
seen={};bus:emit('screen',state)
T.eq(table.concat(seen,','),'first,late','new callbacks participate in the following emission only')
bus:removeOwner('missing');seen={};bus:emit('screen',state)
T.eq(table.concat(seen,','),'first,late','owner removal does not reorder retained callbacks')
T.finish('stable event subscription order')
