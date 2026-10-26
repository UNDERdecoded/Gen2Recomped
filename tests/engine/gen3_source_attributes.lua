package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local X=require('src.import.RomExtractorGen3')
local Tiles=require('src.render.Gen3Tiles')
local Rom=require('src.import.RomGba')
local function word(n, bytes)
 local out={};for _=1,bytes do out[#out+1]=string.char(n%256);n=math.floor(n/256)end
 return table.concat(out)
end
local function fixture(stride)
 local bytes={};for i=1,20000 do bytes[i]='\0'end
 local function put(at,data)for i=1,#data do bytes[at+i]=data:sub(i,i)end end
 local pointer=function(at,n)put(at,word(n+0x08000000,4))end
 local a=32
 pointer(a+4,1024);pointer(a+8,512);pointer(a+12,128)
 pointer(a+(stride==4 and 20 or 16),176)
 -- Same normalized behavior can come from distinct Kanto source bytes.
 local values=stride==4 and {0x400000d1,0x20000011,0x200001d1} or {0x3002,0x2011,0x1008}
 for i,n in ipairs(values)do put(176+(i-1)*stride,word(n,stride))end
 local captured={}
 local x=setmetatable({rom=Rom.new(table.concat(bytes)),manifest={metatileAttributes={bytes=stride}},
   layout={},_tilesetAddresses={[a]=true},_layoutRecords={}},X)
 x.beginStage=function()end;x.tick=function()end
 local stop={}
 x.write=function(_,name,value)
  captured[name]=value
  if name=='map_tilesets' then error(stop,0)end
 end
 x.tilesetSheet=function()return {}end;x.saveImage=function()end
 -- No map pairs: this fixture isolates actual attribute extraction, not
 -- unrelated furniture-script scanning against a synthetic tiny cartridge.
 x.isFireRedManifest=function()return false end
 local ok,why=pcall(x.extractTilesets,x)
 T.eq(ok,false);T.eq(why,stop,'stop only after the actual tileset write boundary')
 local r=assert(captured.map_tilesets.TILESET_0000020)
 T.eq(captured.map_tilesets._romInfo.skipped,0)
 T.eq(r.sourceAttributeBytes,stride)
 local expected={};for _,n in ipairs(values)do expected[#expected+1]=word(n,stride)end
 if stride==4 then
  T.eq(r.sourceAttributes,table.concat(expected),'original 32-bit attributes survive exactly')
  T.eq(r.sourceBehaviorMask,511,'default FRLG mask preserves the ninth behavior bit')
 else
  T.eq(r.sourceAttributes,nil,'16-bit source does not allocate a duplicate string')
  T.eq(r.attributes,table.concat(expected),'native 16-bit attributes already are source bytes')
  T.eq(r.sourceBehaviorMask,255)
 end
 local tiles=Tiles.new({primary=r},{metatilesInPrimary=3})
 local b0,l0=tiles:attributes(0);local b1,l1=tiles:attributes(1)
 T.eq(l0,stride==4 and 2 or 3,'native layer convention unchanged')
 T.eq(l1,stride==4 and 1 or 2)
 T.eq(b0,stride==4 and 0x5a or 2,'native remap unchanged')
 T.eq(b1,stride==4 and 0x5b or 17)
 T.eq(tiles:sourceBehavior(0),stride==4 and 0xd1 or 2,'source numbering is separate')
 T.eq(tiles:sourceBehavior(1),17)
 T.eq(tiles:sourceBehavior(2),stride==4 and 0x1d1 or 8,'ninth source behavior bit is retained')
 return r
end
local fr,em=fixture(4),fixture(2)
local pair=Tiles.new({primary=fr,secondary=em},{metatilesInPrimary=3})
T.eq(pair:sourceBehavior(3),2,'secondary bank uses its own attribute width')
T.eq(pair:sourceBehavior(4),17)
T.eq(pair:sourceBehavior(6),nil,'out-of-range source has no guessed behavior')
for _,id in ipairs({-1,.5,'0',false,0/0,math.huge})do T.eq(pair:sourceBehavior(id),nil)end
local stale=Tiles.new({primary={attributes=fr.attributes}},{metatilesInPrimary=2})
T.eq(stale:sourceBehavior(0),nil,'normalized-only cache cannot reconstruct source')
T.eq(stale:attributes(0),0x5a,'stale cache native convention still reads normally')
T.eq(Tiles.new({primary=fr},{metatilesInPrimary=3}):sourceBehavior(3),nil,'missing secondary cannot borrow primary source')
fr.sourceAttributes=fr.sourceAttributes:sub(1,3)
T.eq(pair:sourceBehavior(0),nil,'truncated source fails explicitly')
fr.sourceBehaviorMask=254
T.eq(pair:sourceBehavior(0),nil,'malformed mask rejected')
local Importer=require('src.import.RomImporter')
local V=require('src.core.GameVersion')
local markerFor
for i=1,100 do
 local name,value=debug.getupvalue(Importer.readyReport,i)
 if not name then break end
 if name=='markerFor' then markerFor=value;break end
end
T.eq(type(markerFor),'function','inspect actual format gate without reading or mounting a cache')
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 local info=V.info(edition)
 if info then
  local marker=markerFor(edition)
  T.check(marker:find('source-metatile-attrs-v1:',1,true)~=nil,edition..' cache needs source provenance')
  T.eq(marker:sub(-40),info.sha1,edition..' marker retains exact cartridge identity')
  if edition=='ruby' or edition=='sapphire' then
   T.check(marker:find('rs-item-menu-v4:',1,true)~=nil,edition..' previous import fixes retained')
  end
 end
end
for _,edition in ipairs({'red','gold','crystal'})do
 T.eq(markerFor(edition):find('source-metatile-attrs-v1:',1,true),nil,edition..' cache unchanged')
end
T.finish('original GBA metatile attributes and native normalization')
