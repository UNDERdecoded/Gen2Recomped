package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local F=require("tools.native-palettes.fixture")
local Tiles=require("src.render.Gen3Tiles")
local Cycles=require("src.render.Gen3PaletteCycles")
local Copy=require("src.mods.Merge").deepCopy
local raw=Cycles.sample
local samples=0
Cycles.sample=function(...) samples=samples+1;return raw(...) end
for _,version in ipairs({"emerald","firered"})do
 local f=F.new(version,2,true);local layout=f.state.game.data.constants.gen3Layout
 local pair={primary=f.records.P,secondary=f.records.S}
 pair.primary.paletteCycles={}
 local first=layout.palettesInPrimary*16
 local frames={string.char(1,2,3,4,5,6),string.char(6,7,8,9,10,11),string.char(21,22,23,24,25,26),string.char(31,32,33,34,35,36)}
 pair.secondary.paletteCycles={{kind="frames",first=first,count=2,step=4,phase=1,frames=frames}}
 local original=Copy(pair);local d=Tiles.new(pair,layout)
 for tick=0,31 do
  d:setPaletteTicks(tick)
  T.same(d.paletteState,assert(raw(pair,layout,tick)),"native sample equals independent pure sampler")
 end
 local count=samples;local cache=d.paletteSampler;local before=cache:stats()
 for tick=32,255 do
  d:setPaletteTicks(tick)
  T.same(d.paletteState,assert(raw(pair,layout,tick)),"warmed sample preserves all RGB bytes and phase indices")
 end
 T.eq(samples,count,"four repeating states cause zero full samples after warmup")
 T.eq(cache:stats().entries,4,"native sample pictures bounded to four")
 T.check(cache:stats().hits>before.hits,"warmed states reused")
 T.same(pair,original,"shared source tables remain unchanged")
 local held=d.paletteState
 pair.primary.palettes[16][16][1]=(pair.primary.palettes[16][16][1]+1)%256
 d:setPaletteTicks(256)
 T.check(d.paletteState~=held,"same-table RGB edit invalidates retained states")
 T.same(d.paletteState,assert(raw(pair,layout,256)),"source edit outside active program also observed")
 pair.secondary.paletteCycles[1].frames[2]=string.char(101,102,103,104,105,106)
 for tick=257,272 do d:setPaletteTicks(tick);T.same(d.paletteState,assert(raw(pair,layout,tick)),"same-table frame edit invalidates even before frame selected") end
 pair.secondary.paletteCycles[1].step=3;pair.secondary.paletteCycles[1].phase=2
 d:setPaletteTicks(273);T.same(d.paletteState,assert(raw(pair,layout,273)),"cadence and phase edits invalidate state selection")
 -- Multiple independent programs produce more than four combinations.
 pair.primary.paletteCycles={{kind="rotate",first=17,count=4,step=3,direction=-1}}
 for tick=0,95 do
  d:setPaletteTicks(tick);T.same(d.paletteState,assert(raw(pair,layout,tick)),"bounded eviction preserves independent program phases")
  T.check(cache:stats().entries<=4,"phase combinations cannot grow retained picture count")
 end
 pair.primary.paletteCycles[1].direction=1
 d:setPaletteTicks(96);T.same(d.paletteState,assert(raw(pair,layout,96)),"rotate direction edit observed")
 local function reject(edit)
  d.primary,d.secondary=Copy(original.primary),Copy(original.secondary)
  d:setPaletteTicks(0);edit(d)
  local _,reason=d:setPaletteTicks(1)
  T.eq(d.paletteState,nil,"invalid source cannot reuse previous colours")
  T.eq(reason,"palette animation data unavailable","malformed metadata still declines")
  T.eq(cache:stats().entries,0,"invalid source drops retained samples")
 end
 reject(function(t)t.primary.paletteCycles=nil end)
 reject(function(t)t.secondary.paletteCycles.extra=true end)
 reject(function(t)t.secondary.paletteCycles[1].frames[3]="short" end)
 reject(function(t)t.secondary.paletteCycles[1].frames=setmetatable(Copy(frames),{}) end)
 reject(function(t)t.primary.palettes[1][1][2]=256 end)
 reject(function(t)t.primary.palettes[1].extra=true end)
 reject(function(t)t.secondary=setmetatable(t.secondary,{}) end)
 d.primary,d.secondary=Copy(original.primary),Copy(original.secondary);d:setPaletteTicks(0)
 for _,tick in ipairs({-1,0/0,math.huge,9007199254740992})do
  local _,reason=d:setPaletteTicks(tick)
  T.eq(d.paletteState,nil,"invalid clock clears cached output")
  T.eq(reason,"terrain clock unavailable","clock rejection preserved")
  T.eq(cache:stats().entries,0,"invalid clock drops native pictures")
  d:setPaletteTicks(0)
 end
 d.primary.paletteCycles={};d.secondary.paletteCycles={};d:setPaletteTicks(0)
 local still=d.paletteState;d:setPaletteTicks(1)
 T.eq(d.paletteState,still,"animated-to-static transition keeps static reuse")
 local static=Tiles.new({primary=d.primary,secondary=d.secondary},layout);static:setPaletteTicks(0)
 T.eq(static.paletteSampler,nil,"initially static FireRed/legacy terrain gets no sample cache")
 d.primary,d.secondary=Copy(original.primary),Copy(original.secondary);d:setPaletteTicks(9007199254740991)
 T.same(d.paletteState,assert(raw(d,layout,9007199254740991)),"maximum exact tick phase precision preserved")
 local detached=assert(raw(d,layout,9007199254740991));detached.primary[1][1][1]=-1
 T.check(d.paletteState.primary[1][1][1]>=0,"public samples remain detached from native retained state")
 f.run.release()
end
Cycles.sample=raw
T.finish("Native animated palette sample reuse, eviction and source invalidation")
