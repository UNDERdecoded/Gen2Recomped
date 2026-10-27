-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local L=require('src.import.Gen2VramLayout')
local E=require('src.import.RomExtractorGen2')
local Writer=require('src.import.ImageWriter')
local Version=require('src.core.GameVersion')
local Importer=require('src.import.RomImporter')
local before=Version.get()
local bytes={};for i=1,3072 do bytes[i]=(i*17+math.floor(i/1537)*9)%256 end
local expanded,stride=L.expand(bytes)
T.eq(stride,128,'two 96-tile banks retain the $80 source address')
T.eq(#expanded,4096,'both banks and reserved slots fit one 256-tile atlas')
local bank0,bank1,gap,tail={},{},{},{}
for i=1,1536 do bank0[i]=expanded[i];bank1[i]=expanded[2048+i]end
T.same(bank0,{unpack(bytes,1,1536)},'all first-bank bytes preserved')
T.same(bank1,{unpack(bytes,1537,3072)},'all second-bank bytes preserved')
for i=1537,2048 do gap[#gap+1]=expanded[i]end
for i=3585,4096 do tail[#tail+1]=expanded[i]end
T.eq(table.concat(gap),string.rep('0',512),'reserved $60-$7f slots are blank')
T.eq(table.concat(tail),string.rep('0',512),'unused $e0-$ff slots are blank')
for _,n in ipairs({0,1536,4096,6144})do
 local raw={};for i=1,n do raw[i]=i%256 end
 local out,bank=L.expand(raw)
 T.eq(out,raw,'single-bank, placeholder and extended layouts retain identity')
 T.eq(bank,nil,'non-split payload cannot advertise bank 1')
end
local palettes={};for i=1,224 do palettes[i]=(i-1)%16 end
local mapped=L.paletteMap(palettes)
T.eq(#mapped,256,'palette addresses use the same dense atlas')
for tile=0,255 do
 local valid=tile<96 or tile>=128 and tile<224
 T.eq(L.tileIndex(tile),valid and tile or 0,'source tile address '..tile)
 T.eq(mapped[tile+1],valid and tile%8 or 0,'palette follows source tile '..tile)
end
for _,bad in ipairs({-1,256,1.5,'128',false})do T.eq(L.tileIndex(bad),0,'malformed tile cannot address the atlas')end

-- Real extraction path with synthetic ROM bytes; only image encoding is
-- captured, so there is no graphics driver or copyrighted cartridge fixture.
local decode,save=Writer.decode2bpp,Writer.save
local lastImage
Writer.decode2bpp=function(raw,w,h)return{raw=raw,width=w,height=h}end
Writer.save=function(image)lastImage=image;return true end
local function fixture(version,tiles,attributes)
 Version.set(version);lastImage=nil
 local symbols={TilesetJohtoGFX={1,0x4000},TilesetJohtoMeta={1,0x5000},
  TilesetJohtoColl={1,0x5020},TilesetJohtoPalMap={1,0x6000}}
 local e=E.new(nil,version,{symbols=symbols,tilesets={TilesetJohto={blockCount=2}}})
 local compressed={}
 local function fill(n,value)
  while n>0 do local count=math.min(n,1024);local length=count-1
   compressed[#compressed+1]=0xe4+math.floor(length/256)
   compressed[#compressed+1]=length%256;compressed[#compressed+1]=value;n=n-count
  end
 end
 fill(96*16,0x3c);if tiles>96 then fill((tiles-96)*16,0xa5)end;compressed[#compressed+1]=0xff
 local block={};for i=1,(attributes and 256 or 32)do block[i]=({0,95,128,159,191,223,224,255})[(i-1)%8+1]end
 if attributes then for i=1,#block do block[i]=(i-1)%96 end end
 local palette={};for i=1,112 do palette[i]=i<=48 and 0x10 or i<=64 and 0xff or 0xba end
 e.rom={bytes=function(_,_,address,count)
  if address==0x4000 then return compressed end
  if address==0x5000 then return block end
  if address==0x5020 then local r={};for i=1,count do r[i]=0 end;return r end
  if address==0x6000 then local r={};for i=1,count do r[i]=palette[i]end;return r end
  error('unexpected synthetic ROM read')
 end}
 e.constants=function()return{tilesetOrder={'TilesetJohto'}}end
 e.readSourceTable=function()return{TEST={tileset='TilesetJohto'}}end
 e.gen2EnvPalettes=function()return nil end;e.gen2TilesetEnvironments=function()return{}end
 e.gen2CollisionClasses=function()return{land={},water={}}end
 e.gen2TilesetAnimation=function()end
 if attributes then
  e.layout=function(_,key,default)if key=='tilesetCompressed'then return 1 end;return default end
  e.gen2Lz=function(_,name)
   if name=='TilesetJohtoMeta'then return block end
   if name=='TilesetJohtoColl'then return{0,0,0,0}end
   if name=='TilesetJohtoAttr'then local r={};for i=1,#block do r[i]=i%2==0 and 10 or 3 end;return r end
  end
 end
 local stop,result={},nil
 e.write=function(_,name,value)if name=='tilesets'then result=value;error(stop,0)end end
 local ok,why=pcall(e.extractRuntimeScaffolds,e)
 T.eq(ok,false,'fixture stops after the real tileset publication boundary')
 T.eq(why,stop,'extractor reaches native tileset publication without other errors')
 return result and result.TilesetJohto,lastImage
end
local split,img=fixture('crystal',192)
T.eq(split.gen2VramBankStride,128,'real importer publishes logical-bank descriptor')
T.eq(split.imageWidth,128,'atlas width stays stable')
T.eq(split.imageHeight,128,'real image metadata matches expanded address space')
T.eq(img.height,split.imageHeight,'saved image and definition use the same height')
T.eq(img.raw[96*16+1],0,'saved reserved slot is blank')
T.eq(img.raw[128*16+1],0xa5,'saved bank-1 pixels start at tile $80')
T.same(split.blocks[1],{0,95,128,159,191,223,0,0,0,95,128,159,191,223,0,0},'actual metatile references retain source ids')
T.eq(#split.palMap,256,'actual palette map retains dense logical addresses')
T.eq(split.palMap[129],2,'actual bank-1 palette follows $80 tile')
T.eq(split.palMap[130],3,'actual odd bank-1 tile selects its own palette')
for _,edition in ipairs({'gold','silver'})do
 local one,image=fixture(edition,96)
 T.eq(one.gen2VramBankStride,nil,edition..' single bank is unchanged')
 T.eq(one.imageHeight,48,edition..' native 96-tile dimensions retained')
 T.eq(image.height,48,edition..' saved single-bank dimensions retained')
end
for _,edition in ipairs({'prism','polishedcrystal'})do
 local attr,image=fixture(edition,256,true)
 T.eq(attr.gen2VramBankStride,nil,edition..' attribute-bank layout is not mistaken for packed Crystal')
 T.eq(attr.blocks[1][2],129,edition..' explicit attribute-bank reference retained')
 T.eq(attr.palMap[130],2,edition..' attribute palette follows its original owner')
end
Writer.decode2bpp,Writer.save=decode,save

local markerFor
for i=1,100 do local name,value=debug.getupvalue(Importer.readyReport,i)
 if name=='markerFor'then markerFor=value;break end;if not name then break end
end
assert(markerFor)
for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 local marker=markerFor(edition)
 T.check(marker:find('gen2%-vram%-layout%-v1:')~=nil,edition..' cache records tile-address contract')
 Version.set(edition);love.filesystem.write(Version.cachePrefix(edition)..'rom-cache.complete',marker:gsub('gen2%-vram%-layout%-v1:',''))
 T.eq(Importer.readyReport(edition).ok,false,edition..' compact legacy cache cannot skip reimport')
end
for _,edition in ipairs({'red','emerald','platinum'})do
 T.check(not markerFor(edition):find('gen2%-vram%-layout%-v1:'),edition..' unrelated import marker is unchanged')
end
Version.set(before)
T.finish('native Crystal VRAM tile identity, extraction, palette alignment and cache invalidation')
