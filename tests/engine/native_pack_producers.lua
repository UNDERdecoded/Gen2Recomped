-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local F=require('tests.pack_sources.fixture')
local Lz=require('src.import.snes.Lz2')
local G=require('src.import.snes.Graphics')
local Producer=require('src.import.PackProducer')
local I=require('src.import.Importers')
local Packs=require('src.mods.AssetPacks')
local MD5=require('src.mods.StreamMD5')
local LT=require('src.import.lttp.LttpImport')
local b=string.char

for _,v in ipairs({{b(2)..'abc'..b(255),'abc'}, {b(0x22,7,255),b(7,7,7)},
  {b(0x44,1,2,255),b(1,2,1,2,1)},{b(0x63,254,255),b(254,255,0,1)},
  {b(1)..'ab'..b(0x83,0,0,255),'ababab'},
  {b(0xe1,0)..string.rep('A',256)..'B'..b(0x80,0,1,255),string.rep('A',256)..'BB'}}) do
  local out,consumed=Lz.decompress(v[1],0)
  T.eq(out,v[2],'command stream matches explicit byte vector')
  T.eq(consumed,#v[1],'decoder reports exact consumed source length')
end
for _,head in ipairs({0x80,0xa0,0xc0}) do
  T.eq(Lz.decompress(b(0)..'Z'..b(head,0,0,255),0),'ZZ','copy opcode aliases preserve output addressing')
end
T.eq(Lz.decompress(b(0)..'Z'..b(0xfc,0,0,0,255),0),'ZZ','extended copy opcode is decoded')
for _,bad in ipairs({b(0xe0),b(4)..'x',b(0x40,1),b(0x80,0),b(0x80,0,0,255),b(0x20,1)}) do
  T.eq(Lz.decompress(bad,0),nil,'truncated or invalid stream is rejected')
end
T.eq(Lz.decompress(b(0xe7,255,1,255),0,10),nil,'expansion budget is checked before output growth')
T.eq(Lz.decompress(b(255),0,math.huge),nil,'caller cannot remove expansion ceiling')
T.eq(Lz.decompress(b(255),-1),nil,'negative source offset is rejected')
T.eq(#assert(Lz.decompress(string.rep(b(0xe7,255,42),64)..b(255),0)),65536,'maximum allowed expansion succeeds')
T.eq(Lz.decompress(string.rep(b(0xe7,255,42),65)..b(255),0),nil,'expansion beyond maximum is rejected')
T.eq(G.loRomOffset(0x92,0xa0,0),0x92000,'LoROM mirrors high banks')
T.eq(G.loRomOffset(0x12,0x20,0),nil,'LoROM lower bank addresses are not cartridge data')
for _,bits in ipairs({2,3,4}) do
  local bytes={};for i=1,bits*8 do bytes[i]=0 end
  for plane=0,bits-1 do
    local at=bits==3 and plane==2 and 17 or math.floor(plane/2)*16+plane%2+1
    bytes[at]=128
  end
  local unpack=table.unpack or unpack
  local tiles=assert(G.decodeTiles(b(unpack(bytes)),bits))
  T.eq(tiles[1][1],2^bits-1,'all bit planes contribute to the top-left pixel')
  T.eq(tiles[1][2],0,'adjacent clear pixel stays transparent')
  T.eq(tiles[1][9],0,'row stride remains independent of bit depth')
end
T.eq(G.decodeTiles('x',3),nil,'incomplete tile cannot be decoded')
T.eq(G.decodeTiles(string.rep('\0',32),8),nil,'unsupported bit depth cannot be guessed')
T.same(G.readPalette(b(31,0,0,124),0,2),{{255,0,0},{0,0,255}},'SNES palette primaries are correctly expanded')
T.eq(G.readPalette('x',0,1),nil,'truncated palette is rejected')
local synthetic=F.cartridge()
local digest=MD5.new():update(synthetic):final()
T.eq(LT.identify(synthetic),nil,'generated format bytes are not accepted as an original cartridge')
LT.SOURCES[digest]={name='Generated format fixture, not a cartridge',size=#synthetic}
local source,normalized=LT.identify(string.rep('H',512)..synthetic)
T.eq(normalized,synthetic,'copier header is removed without changing normalized bytes')
T.eq(source.md5,digest,'source hash identifies normalized bytes')
T.eq(LT.sheetOffset(synthetic,0),0x92000,'compressed sheet uses native source pointer')
T.eq(LT.sheetOffset(synthetic,115),0x93000,'raw sprite sheet uses its own source pointer')
T.eq(LT.sheetOffset(synthetic,223),nil,'out-of-table sheet is rejected')
local sheet,bits=LT.readSheet(synthetic,0)
T.eq(bits,3,'compressed graphics retain their three bit planes')
T.eq(#sheet,64,'sheet geometry derives from decoded data length')
T.eq(sheet[1][1],1,'compressed sheet decoded pixel matches format vector')
T.eq(assert(LT.readSheet(synthetic,115))[1][1],1,'raw sprite sheet bypasses decompression')
local player=assert(LT.readPlayer(synthetic))
T.eq(#player,896,'player has its separate native tile count')
T.eq(player[1][1],8,'player uses its fourth bit plane')
local palettes=assert(LT.readPalettes(synthetic))
T.same(palettes.armor[1][8],{0,0,255},'player selects the armor palette row')
local raster=G.sheet(player,palettes.armor[1])
T.same({raster.width,raster.height},{128,448},'player sheet size is computed from native tile units')
T.eq(raster.rgba:sub(1,4),b(0,0,255,255),'player raster preserves the fourth-plane color')
T.eq(raster.rgba:sub(5,8),b(0,0,0,0),'palette index zero remains transparent')
local world=require('src.import.lttp.Overworld').raster(synthetic,LT.readSheet)
local function pixel(x,y)return world.rgba:sub((y*world.width+x)*4+1,(y*world.width+x+1)*4)end
T.same({world.width,world.height},{1024,1024},'overworld atlas contains 4096 sixteen-pixel metatiles')
for _,xy in ipairs({{0,0},{15,0},{0,15},{15,15}}) do
  T.eq(pixel(xy[1],xy[2]),b(255,0,0,255),'metatile quadrant flip preserves the correct palette pixel')
end
T.eq(pixel(1,0),b(74,156,74,255),'transparent metatile pixels reveal the native background color')
LT.SOURCES[digest]=nil

local fs,files=F.memory()
local provenance={name='Generated test source',md5=string.rep('0',32)}
local producer=assert(Producer.new('lttp','sprites','1.0.0',provenance,fs))
local entry=assert(producer:put('hero','PNG!',{width=16,height=24,sprite={anchorY=24}},{frames={1,2}}))
T.eq(I.readPack('lttp','sprites',fs),nil,'native extraction stays unpublished until complete')
T.check(producer:alias('hero_female','hero')~=nil,'native provider can reuse identical gender artwork')
entry.sprite.anchorY=1
T.eq(assert(producer:finish()).entries,2,'finished native extraction publishes its full entry set')
local api=Packs.new({required_assets={{importer='lttp',pack='sprites'}}},fs)
T.eq(api:read('lttp','sprites','hero'),'PNG!','native provider output feeds the real pack consumer')
T.eq(api:entry('lttp','sprites','hero').sprite.anchorY,24,'producer views do not mutate committed anchors')
T.same(api:metadata('lttp','sprites','hero').frames,{1,2},'provider animation metadata is literal data')
local path=I.manifestPath('lttp','sprites');local prior=files[path]
for _,fault in ipairs({'failWrite','shortWrite','failRename','throwRename','failDirectory'}) do
  producer=assert(Producer.new('lttp','sprites','2.0.0',provenance,fs));fs[fault]=true
  T.eq(producer:put('hero','NEW!',{}),nil,'native provider propagates '..fault)
  fs[fault]=false
  T.eq(producer:finish(),nil,'failed native provider cannot publish a partial pack')
  T.eq(files[path],prior,'native publication failure preserves the previous descriptor')
  T.eq(api:read('lttp','sprites','hero'),'PNG!','native publication failure preserves previous assets')
end
producer=assert(Producer.new('lttp','sprites','2.0.0',provenance,fs))
assert(producer:put('hero','OTHER',{}));producer:cancel()
T.eq(producer:finish(),nil,'cancelled extraction cannot publish')
T.eq(files[path],prior,'cancelled extraction leaves prior descriptor untouched')
producer=assert(Producer.new('lttp','sprites','2.0.0',provenance,fs))
entry=assert(producer:put('hero','OTHER',{}));fs.remove(I.assetPath('lttp','sprites',entry.file))
T.eq(producer:finish(),nil,'missing object prevents native publication')
T.eq(files[path],prior,'missing-object failure preserves prior descriptor')
producer=assert(Producer.new('lttp','sprites','2.0.0',provenance,fs))
T.eq(producer:put(nil,'X',{}),nil,'invalid entry identity cannot reach storage')
T.eq(producer:finish(),nil,'invalid native entry does not publish')
T.eq(Producer.new('unknown','sprites','1.0.0',provenance,fs),nil,'unknown provider identity is rejected')
producer=assert(Producer.new('lttp','sprites','2.0.0',provenance,fs))
T.eq(producer:put('hero',string.rep('x',8*1024*1024+1),{}),nil,'native extraction cannot exceed consumer read limit')
T.check(fs.maxRead<=8*1024*1024,'all physical native-provider reads stay bounded')
local pending=0;for name in pairs(files) do if name:find('.pending-',1,true) then pending=pending+1 end end
T.eq(pending,0,'native failures leave no staging files')
local publishName='src.import.PackPublish'
local originalPublisher=package.loaded[publishName]
math.randomseed(12345);local expectedRandom=math.random();math.randomseed(12345)
package.loaded[publishName]=nil;local firstPublisher=require(publishName)
T.eq(math.random(),expectedRandom,'publisher initialization does not consume the gameplay random stream')
package.loaded[publishName]=nil;local secondPublisher=require(publishName)
package.loaded[publishName]=originalPublisher
local names={};local concurrentFs=F.memory();local write=concurrentFs.write
concurrentFs.write=function(p,bytes)names[#names+1]=p;return write(p,bytes)end
T.check(firstPublisher(concurrentFs,'packs/pack.lua','FIRST'),'first independent publisher works')
T.check(secondPublisher(concurrentFs,'packs/pack.lua','SECOND'),'second independent publisher works')
T.neq(names[1],names[2],'independent Lua states do not share a numbered staging filename')
local scope='first-folder';fs.getWriteRoot=function()return scope end
producer=assert(Producer.new('lttp','sprites','2.0.0',provenance,fs))
assert(producer:put('hero','ROOT!',{}));scope='second-folder'
T.eq(producer:finish(),nil,'folder change prevents a native descriptor spanning two roots')
T.eq(files[path],prior,'folder change leaves previous native pack descriptor intact')
scope='first-folder'
local inboxRoot='imports/test';local W=require('src.import.LuaWriter')
fs.write(inboxRoot..'/pack.lua',W.encode({format=1,importer='lttp',pack='sprites',kind='sprite',version='2.0.0',
  source=provenance,entries={hero={file='a.png',size=1},other={file='b.png',size=1}}}))
fs.write(inboxRoot..'/a.png','A');fs.write(inboxRoot..'/b.png','B')
local importing=I.install('lttp','sprites',fs,inboxRoot,fs)
T.check(coroutine.resume(importing),'portable inbox can yield after an entry')
scope='second-folder'
T.check(not coroutine.resume(importing),'folder change stops a portable inbox operation too')
T.eq(files[path],prior,'portable folder change preserves previous descriptor')
T.finish('Native pack producers and SNES graphics')
