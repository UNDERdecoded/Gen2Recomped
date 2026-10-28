package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local F=require('tools.native-atlas.fixture')
local Golden=require('tools.native-atlas.golden')
local Pixels=require('src.compat.gen1.AtlasPixels')
local Tiles=require('src.render.Gen3Tiles')
local digest=require('src.link.Fingerprint').digest
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  local f=F.new(edition);local p=Pixels.new(f.pair,f.layout)
  T.eq(#p.mids,31);T.eq(p.width,256);T.eq(p.height,32)
  T.eq(p.midToSlot[0],0);T.eq(p.midToSlot[f.layout.metatilesInPrimary],19)
  T.eq(p.midToSlot[19],nil,'unowned source bank gaps are not invented metatiles')
  for _,over in ipairs({false,true})do
    local key=edition..(over and'-over'or'-under')
    T.eq(digest(p:blob(over)),Golden[key..'.idx'],'indexed pixels equal the independent reference')
    T.eq(digest(p:rgba(over)),Golden[key..'.rgba'],'RGBA equals the independent reference, including flips, priority and rounding')
  end
  local revision=p.revision;local under,over=p:update(0)
  T.eq(next(under),nil);T.eq(next(over),nil);T.eq(p.revision,revision,'observing the same native time does no upload work')
  local bottom,top=p:rgba(false),p:rgba(true)
  T.eq(bottom:byte(#bottom),255,'unused under-atlas slots retain an opaque backdrop')
  T.eq(top:byte(#top),0,'unused overhead slots remain transparent')
  local native=f.pair.primary.palettes[1][1]
  local previous={native[1],native[2],native[3]}
  local words={};for i=1,16 do words[i]=31 end
  p:setPalette(0,words)
  T.eq(p.paletteOverrides[0][1][1],255);T.eq(p.paletteOverrides[0][1][2],0)
  T.same(native,previous,'palette overrides do not write into native bank colours')
  T.eq(p:rgba(false):sub(-4),'\0\0\0\255','palette zero patches do not repaint unused atlas padding')
  T.eq(digest(p:rgba(false)),Golden[edition..'-palette0-under.rgba'])
  T.eq(digest(p:rgba(true)),Golden[edition..'-palette0-over.rgba'])
  p:setPalette(0,nil);T.eq(p:rgba(false),bottom);T.eq(p:rgba(true),top)
  local indexRevision=p.indexRevision
  p:setPalette(1,words)
  T.eq(digest(p:rgba(false)),Golden[edition..'-palette1-under.rgba'])
  T.eq(digest(p:rgba(true)),Golden[edition..'-palette1-over.rgba'])
  T.eq(p.indexRevision,indexRevision,'palette changes retain the indexed geometry and reverse lookups')
  p:setPalette(1,nil)
  -- A custom RGB channel that coincides with a cartridge-floor value must
  -- not be rounded when it no longer matches the imported word's colour.
  local base=p.decoder:palette(0)[2]
  base[1],base[2],base[3]=24,24,24;p:update(1)
  T.eq(p.paletteKey:sub(5,8),string.char(24,24,24,255),'modified RGB is preserved byte-exactly')
  f.pair.primary.sourcePaletteBytes=nil;f.pair.secondary.sourcePaletteBytes=nil
  p:update(2);T.eq(p.paletteKey:sub(5,8),string.char(24,24,24,255),'legacy RGB has no invented raw-colour provenance')
end
do
  local f=F.new('emerald')
  local frames={};for i=1,34 do frames[i]=string.rep(string.char(i%256),32)end
  f.pair.primary.animations={{tile=0,count=1,step=3,frames={string.rep('\17',32),string.rep('\34',32),string.rep('\51',32)}},
    {tile=2,count=1,step=5,frames=frames}}
  local tiles=Tiles.new(f.pair,f.layout)
  local held=tiles:tilePixels(31)
  for tick=0,400 do
    tiles:setAnimationTicks(tick)
    T.eq(tiles.tileOverride[0],f.pair.primary.animations[1].frames[math.floor(tick/3)%3+1],'each animation retains its own cadence')
    T.eq(tiles.tileOverride[2],frames[math.floor(tick/5)%34+1],'long source cycles are not truncated by atlas pre-bake limits')
    T.eq(tiles:tilePixels(31),held,'unaffected native tile decodes are retained')
    T.eq(next(tiles:setAnimationTicks(tick)),nil,'repeat observations are stable')
  end
  T.raises(function()tiles:setAnimationTicks(-1)end,'invalid terrain animation ticks','negative animation time is rejected')
  local p=Pixels.new(f.pair,f.layout);local revision=p.revision
  local before=p:rgba(false);p:update(15)
  T.check(p:rgba(false)~=before);T.check(p.revision>revision)
  local repeatRevision=p.revision;p:update(15);T.eq(p.revision,repeatRevision)
end
T.finish('native atlas pixel projection')
