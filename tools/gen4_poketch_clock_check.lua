package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Platinum digital watch')
local G=require('src.import.Gen4Graphics')
local A=require('src.import.Gen4Archives')
local Art=require('src.import.Gen4PoketchArt')
local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local arc=assert(require('src.import.NarcArchive').parse(rom:read(Art.PATH)))
local function member(name)
  local b=assert(arc:get(assert(A.find(Art.PATH,name))))
  return G.isCompressed(b) and G.decompress(b) or b
end
local original=assert(G.tilemap(member('digital_watch_digits.NSCR.lz')))
T.eq(original.width,320,'native strip width')
T.eq(original.height,72,'native strip height')
local map=Art.digitalWatchMap(original)
T.eq(Art.digitalWatchMap(map),map,'normalized map is not rearranged twice')
T.check(map~=original and map.cells~=original.cells,'original ROM tilemap not mutated')
local expected={
 {'####','#..#','#..#','#..#','#..#','#..#','#..#','#..#','####'},
 {'..#.','..#.','..#.','..#.','..#.','..#.','..#.','..#.','..#.'},
 {'####','...#','...#','...#','####','#...','#...','#...','####'},
 {'####','...#','...#','...#','####','...#','...#','...#','####'},
 {'#..#','#..#','#..#','#..#','####','...#','...#','...#','...#'},
 {'####','#...','#...','#...','####','...#','...#','...#','####'},
 {'####','#...','#...','#...','####','#..#','#..#','#..#','####'},
 {'####','#..#','#..#','#..#','...#','...#','...#','...#','...#'},
 {'####','#..#','#..#','#..#','####','#..#','#..#','#..#','####'},
 {'####','#..#','#..#','#..#','####','...#','...#','...#','####'},
}
for d=0,9 do for y=0,8 do
  local row=''
  for x=0,3 do local tile=map.cells[y*40+d*4+x+1].tile;T.check(tile==1 or tile==2,'native digit uses solid generic tiles');row=row..(tile==2 and '#' or '.') end
  T.eq(row,expected[d+1][y+1],'native numeral '..d..' row '..y)
end end
T.eq(Art.COMPOSE.digital_watch_digits[2],'generic_bg_tiles.NCGR.lz','import uses generic tile bank')
local image=assert(G.compose(map,G.tiles(member(Art.COMPOSE.digital_watch_digits[2])),G.palette(member('generic_bg_tiles.NCLR'))))
T.eq(image.width,320,'fresh numeral strip width')
T.eq(image.height,72,'fresh numeral strip height')
local ink=Art.data(rom)
T.eq(ink.tilemaps.digital_watch_digits.layout,'linear_watch_digits','fresh ink identifies normalized order')
local S=require('src.import.Gen4Screens');local recipe
for _,entry in ipairs(S.ARCHIVES) do if entry.out=='poketch' then recipe=entry end end
local found
for _,job in ipairs(S.plan(Art.PATH,recipe)) do if job.name=='digital_watch_digits' then found=job end end
T.check(found.watchDigits,'general screen importer normalizes only digital watch strip')
T.eq(found.tiles,A.find(Art.PATH,'generic_bg_tiles.NCGR.lz'),'general screen importer uses generic tiles')
local P=require('src.ui.Gen4Poketch')
local oldDate=os.date;local now
os.date=function() return now end
local legacy={width=40,cells={}}
for i,c in ipairs(original.cells) do legacy.cells[i]=c.tile end
local current=ink.tilemaps.digital_watch_digits
for _,source in ipairs({legacy,current}) do
  local watch=setmetatable({cache={},game={data={gen4_poketch_ink={tilemaps={digital_watch_digits=source}}}},artImage=function(_,name) assert(name=='generic_bgtiles','wrong runtime tile bank');return {} end},{__index=P})
  local placements
  watch.drawTiles=function(_,sheet,words,w,x,y) placements[#placements+1]={sheet=sheet,words=words,w=w,x=x,y=y};return true end
  for hour=0,23 do for minute=0,59 do
    now={hour=hour,min=minute};placements={};watch:drawDigitalWatch()
    T.eq(#placements,4,'every time draws four native numerals')
    local digits={math.floor(hour/10),hour%10,math.floor(minute/10),minute%10}
    for i,p in ipairs(placements) do
      T.eq(p.x,({3,8,15,20})[i],'native digit column')
      T.eq(p.y,7,'native digit row')
      for y=0,8 do for x=0,3 do
        assert(p.words[y*4+x+1]%1024==map.cells[y*40+digits[i]*4+x+1].tile,'wrong numeral at '..hour..':'..minute)
      end end
    end
  end end
end
os.date=oldDate;T.finish()
