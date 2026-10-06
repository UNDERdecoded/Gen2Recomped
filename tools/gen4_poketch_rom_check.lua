-- Decode the project's Platinum ROM and check the graphics recipes against
-- actual tilemaps/palettes. This writes no cartridge assets into the checkout.
package.path = './?.lua;' .. package.path
local G = require('src.import.Gen4Graphics')
local S = require('src.import.Gen4Screens')
local A = require('src.import.Gen4Archives')
local N = require('src.import.NarcArchive')
local rom = assert(require('src.import.NdsRom').open(arg[1] or 'Pokemon - Platinum Version (USA) (Rev 1).nds'))
local arc = assert(N.parse(rom:read('/graphic/poketch.narc')))
local specialties = assert(require('src.import.Gen4Mart').specialties(rom:arm9()))
local BerryData = require('src.import.Gen4BerryData')
local berryGrowth = assert(BerryData.growth(N.parse(rom:read(BerryData.PATH))))
local berryPositions = assert(BerryData.positions(rom))
local berryInitial = assert(BerryData.initial(rom))
local checks = 0
local function check(v, why) checks = checks + 1; assert(v, why) end
local orders=assert(require('src.import.Gen4Dex').orders(rom),'ROM dex sort archive')
check(#orders.sinnoh==210 and orders.sinnoh[1]==387,'Sinnoh dex has 210 species starting with Turtwig')
check(#orders.national==493 and orders.national[1]==1,'National dex retains all 493 species')
local coin=assert(require('src.import.Gen4PoketchSprites').coin(arc))
check(coin.heads~=coin.tails and #coin.spin>1,'ROM coin has distinct faces and spinning frames')
local hidden=assert(require('src.import.Gen4Pickups').hiddenItems(rom:arm9()))
local rangeCounts={[0]=0,[1]=0,[2]=0}
for _,item in pairs(hidden) do
 assert(rangeCounts[item.range]~=nil,'hidden ROM item uses unsupported dowsing range')
 rangeCounts[item.range]=rangeCounts[item.range]+1
end
check(rangeCounts[0]>0 and rangeCounts[1]>0 and rangeCounts[2]>0,'ROM hidden items use all three scan ranges')
local watchRoutes=assert(require('src.import.Gen4PoketchMap').routes(rom))
check(watchRoutes[342].x==47 and watchRoutes[342].y==150,'Route 201 ROM watch position')
check(watchRoutes[204].x==56 and watchRoutes[204].y==102,'Ironworks ROM watch position')
local routeCount=0; for _ in pairs(watchRoutes) do routeCount=routeCount+1 end
check(routeCount==29,'all roaming route watch positions extracted')
local mapCells=assert(BerryData.mapCells(arc))
check(type(mapCells.berry)=='number' and type(mapCells.cursor)=='number','map animation cells decoded')
check(type(mapCells.roamer)=='number' and #mapCells.markers==6 and #mapCells.markerBig==6,
 'roamer and six small/large marker cells decoded from ROM sequences')
check(specialties[0][1] == 146 and specialties[0][2] == 14, 'Jubilife specialty stock')
check(specialties[12][1] == 410 and specialties[13][1] == 365, 'department store TM stocks')
check(#specialties[18] == 8 and #specialties[19] == 5, 'League and basement stocks')
check(berryGrowth[149].stageHours==3 and berryGrowth[149].baseYield>=1,
 'Cheri ROM growth parameters: hours='..berryGrowth[149].stageHours..', yield='..berryGrowth[149].baseYield)
check(berryPositions[0].x==5 and berryPositions[117].x>0,'all berry watch-map positions decoded')
check(berryInitial[0].item==155 and berryInitial[117].yield==1,'initial ripe berries decoded')
local function member(i)
 local b = assert(arc:get(i)); return G.isCompressed(b) and assert(G.decompress(b)) or b
end
local recipe; for _, r in ipairs(S.ARCHIVES) do if r.out == 'poketch' then recipe = r end end
local jobs, named = S.plan(recipe.path, recipe), {}
for _, j in ipairs(jobs) do named[j.name] = j end
check(named.map and named.map.cell,'map icons extracted as ROM cell sprites')
for name, job in pairs(named) do
 if job.tilemap and name ~= 'unavailable' and name ~= 'poketch_border' then
  check(job.palette == 0, name .. ' must use the generic app palette')
 end
end
check(named.marking_map.tiles == A.find(recipe.path, 'map_bg_tiles.NCGR.lz'), 'Marking Map uses map sheet')
check(named.berry_searcher.tiles == named.marking_map.tiles, 'Berry Searcher shares map sheet')
check(named.coin_toss_sprite and named.coin_toss_sprite.cell, 'coin sprites retained alongside BG')
check(named.counter_sprite and named.counter_sprite.cell, 'counter sprites retained alongside BG')
local border = named.poketch_border
local image = assert(require('src.import.RomExtractorGen4').composeJob({}, arc, border))
check(border.paletteSlot == nil, 'full border palette is not relocated')
local function alpha(x,y) return image.rgba:byte((y*image.width+x)*4+4) end
check(alpha(240,64) == 255, 'bezel button has opaque ROM pixels')
check(alpha(100,80) == 0, 'border leaves LCD hole transparent')
check(alpha(16,100) == 0 and alpha(200,100) == 0, 'full LCD width remains visible')
local red, white = 0, 0
for at = 1, #image.rgba, 4 do
 local r,g,b,a = image.rgba:byte(at,at+3)
 if a==255 and r>200 and g<130 and b<150 then red=red+1 end
 if a==255 and r>200 and g>200 and b>200 then white=white+1 end
end
check(red>500 and white>5000, 'ROM red buttons and light device bezel retain their colours')
local Script = require('src.import.Gen4Script')
local seq = assert(N.parse(rom:read('/fielddata/script/scr_seq.narc')))
local common = seq:get(A.find('/fielddata/script/scr_seq.narc','scripts_common'))
local entry = Script.entries(common)[3]
local visited, healed = {}, false
local function walk(at)
 if visited[at] then return end; visited[at] = true
 for _, ins in ipairs(Script.decode(common,at)) do
  if ins.name == 'healparty' then healed = true end
  if ins.target then walk(ins.target) end
 end
end
walk(entry)
check(healed, 'ROM nurse acceptance reaches healparty')
rom:close()
print(checks .. ' ROM checks passed')
