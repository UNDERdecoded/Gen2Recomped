-- Generated native data only; no ROM, mod render DTO, player or file cache.
local F={}
local function le(n,size)
  local s={};for i=1,size do s[i]=string.char(n%256);n=math.floor(n/256)end
  return table.concat(s)
end
function F.bytes(seed,count)
  local out={}
  for i=0,count*32-1 do
    local value=seed+math.floor(i/32)*7
    out[#out+1]=string.char((value+i*3)%16+((value+i*5+1)%16)*16)
  end
  return table.concat(out)
end
function F.new(version)
  local T=require('tests.modkit')
  require('src.core.GameVersion').set(version)
  local fr=version=='firered'
  local split,palSplit=fr and 640 or 512,fr and 7 or 6
  local data={maps={},map_tilesets={},constants={gen3Layout={tilesInPrimary=split,
    metatilesInPrimary=split,palettesInPrimary=palSplit,metatileLayers=2}}}
  for index,name in ipairs({'P','S','T'})do
    local palettes,entries,attrs={},{},{}
    for p=0,15 do
      palettes[p+1]={}
      for c=0,15 do
        local word=(c+p)%32+(p*2%32)*32+c*1024
        local r,g,b=require('src.import.RomGba').bgr555(word)
        palettes[p+1][c+1]={(r+index*11)%256,(g+index*23)%256,(b+index*37)%256}
      end
    end
    for mid=0,2 do
      for k=0,7 do
        entries[#entries+1]=le((k%2==0 and 0 or split)+k%2+(k%4)*1024
          +(k%2==0 and 1 or palSplit)*4096,2)
      end
      attrs[#attrs+1]=le(mid*4096+0x42,2)
    end
    data.map_tilesets[name]={address=index*0x1000,metatileCount=3,
      tiles=string.rep(string.char(0x21),32)..string.rep(string.char(0x43),32),
      palettes=palettes,metatiles=table.concat(entries),attributes=table.concat(attrs)}
  end
  local records=data.map_tilesets
  records.P.animations={{tile=0,count=1,step=8,
    frames={F.bytes(1,1),F.bytes(3,1),F.bytes(5,1),F.bytes(7,1)}}}
  records.S.animations={{tile=0,count=2,step=12,
    frames={F.bytes(2,2),F.bytes(4,2),F.bytes(6,2)}}}
  records.T.animations={{tile=1,count=1,step=4,frames={F.bytes(9,1),F.bytes(11,1)}}}
  local def={id='PALETTE_TEST',width=3,height=2,blocks=''}
  for i,mid in ipairs({0,split,1,2,split+1,split+2})do
    def.blocks=def.blocks..le(mid+(i%4)*1024+0x6000,2)
  end
  data.maps[def.id]=def
  local map=require('src.world.Map').new(def,{id='palette-test',blockTiles=2,
    blockCells=1,primaryKey='P',secondaryKey='S'})
  local game={data=data}
  local run=T.sdk.loadNone({data=T.fixtures.fresh()})
  return {state={map=map,game=game},records=records,run=run}
end
return F
