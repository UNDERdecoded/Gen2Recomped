package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local eq,check=T.eq,T.check
local FrameCache=require("src.render.Gen3PaletteFrameCache")
local released={}
local function value(name)
 local data={name=name}
 function data:release()released[name]=(released[name] or 0)+1 end
 return {data}
end
local cache=FrameCache.new(100,2)
local a,b={},{}
local a1,a2,a3,b1=value('a1'),value('a2'),value('a3'),value('b1')
check(cache:put(a,'one',a1,30),'first owner stores picture')
check(cache:put(a,'two',a2,30),'owner stores second picture')
eq(cache:get(a,'one'),a1,'return visits update LRU')
check(cache:put(a,'three',a3,30),'per-owner limit evicts oldest')
eq(released.a2,1,'cold owner picture released once')
eq(cache:get(a,'two'),nil,'evicted picture unavailable')
check(cache:put(b,'one',b1,50),'global byte pressure stores another owner')
eq(released.a1,1,'global eviction follows actual LRU')
eq(cache:get(b,'one'),b1,'owner namespaces separate equal keys')
eq(cache:stats().bytes,80,'total byte accounting exact')
local big=value('oversize')
check(not cache:put(a,'large',big,101),'oversize picture cannot evict everything or exceed budget')
eq(released.oversize,nil,'rejected picture remains caller-owned')
FrameCache.release(big);eq(released.oversize,1,'caller can release rejected picture')
cache:drop(a);eq(released.a3,1,'owner release frees only its own pictures')
eq(cache:get(b,'one'),b1,'other owner survives release')
cache:clear();eq(released.b1,1,'global reset frees remaining picture')
eq(cache:stats().bytes,0,'global reset removes byte accounting')
eq(cache:stats().entries,0,'global reset removes entries')
cache:clear();cache:drop(a);eq(released.b1,1,'repeated reset never double-releases')
local prior=value('prior');local replacement=value('replacement')
cache:put(a,'same',prior,25);cache:put(a,'same',replacement,40)
eq(released.prior,1,'replacing picture releases old storage')
eq(cache:stats().bytes,40,'replacement size is accounted')
cache:clear();eq(released.replacement,1,'replacement released on reset')
for i=1,200 do
 local owner=i%2==0 and a or b
 local picture=value('cycle-'..i)
 cache:put(owner,tostring(i%7),picture,25)
 check(cache:stats().bytes<=100,'many cycles remain within global budget')
 check(cache:stats().entries<=4,'many cycles remain within both owner limits')
end
cache:clear()
for i=1,200 do eq(released['cycle-'..i],1,'every retained picture released exactly once') end
T.finish()
