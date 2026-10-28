-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local E=require('src.import.RomExtractorGen2')
local M=require('src.import.Gen2FontExtras')
local Writer=require('src.import.ImageWriter')
local imageBefore=love.image
love.image=love.image or {}
local before=love.image.newImageData
love.image.newImageData=function(w,h)
  local rows={}
  return{getDimensions=function()return w,h end,setPixel=function(_,x,y,...)
    assert(x>=0 and x<w and y>=0 and y<h,'pixel outside sheet')
    rows[y*w+x]={...}
  end,getPixel=function(_,x,y)return unpack(rows[y*w+x]or{0,0,0,0})end,
    mapPixel=function(self,f)for y=0,h-1 do for x=0,w-1 do self:setPixel(x,y,f(x,y,self:getPixel(x,y)))end end end}
end
for _,edition in ipairs{'gold','silver','crystal'}do
  local e=E.new(nil,edition,{symbols={FontBattleExtra={2,0x4000},Frames={3,0x5000}}})
  local reads,images={},{ }
  function e:saveImage(image,path)images[path]=image end
  e.rom={bytes=function(_,bank,address,count)
    reads[#reads+1]={bank,address,count}
    local raw={};for i=1,count do raw[i]=0 end
    if bank==2 then raw[1],raw[2]=128,128 else
      for frame=0,7 do raw[frame*48+1]=2^(7-frame)end
    end
    return raw
  end}
  local d=M.extract(e)
  T.same(reads,{{2,0x4000,512},{3,0x5000,384}},edition..' actual symbols and bounded source lengths')
  T.eq(d.frameCount,8);T.eq(d.frameBase,0x79);T.eq(d.frameTiles,6)
  T.eq(d.imageFrames,'assets/generated/fonts/frames.png')
  T.eq(d.imageBattleExtra,'assets/generated/fonts/font_battle_extra.png')
  local f,b=images['fonts/frames.png'],images['fonts/font_battle_extra.png']
  T.same({f:getDimensions()},{48,64})
  T.same({b:getDimensions()},{128,16})
  for frame=0,7 do
    T.same({f:getPixel(frame,frame*8)},{0,0,0,1},'independent 1bpp row '..frame)
    T.same({f:getPixel((frame+1)%8,frame*8)},{0,0,0,0},'paper remains transparent')
  end
  T.same({b:getPixel(0,0)},{0,0,0,1})
  T.same({b:getPixel(1,0)},{0,0,0,0})
  e.manifest.fontSheets={extra={{symbol='Custom',compressed=true}}}
  T.same(M.extract(e),{},'custom compressed/strided layouts are not guessed as retail')
  e.manifest.fontSheets=nil;e.symbols.FontBattleExtra=nil
  e.rom.bytes=function()return{}end
  T.same(M.extract(e),{},'short optional input cannot emit bogus paths')
  e.rom.bytes=function()error('out of ROM')end
  T.same(M.extract(e),{},'unreadable optional input retains original font')
end
-- Drive the actual existing atlas importer, not just the extension module:
-- unused bold A/B/C must be replaced by the cartridge's black/arrow/phone.
for _,edition in ipairs{'gold','silver','crystal'}do
  local symbols={Font={1,0x4000},FontExtra={2,0x4000},Frames={3,0x4000},PokegearPhoneIconGFX={6,0x4000}}
  if edition=='crystal'then
    symbols.FontsExtra_SolidBlackGFX={4,0x4000};symbols.FontsExtra2_UpArrowGFX={5,0x4000}
  else symbols.FontsExtra_SolidBlackAndUpArrowGFX={4,0x4000}end
  local e=E.new(nil,edition,{symbols=symbols});local images={}
  e.saveImage=function(_,image,path)images[path]=image end
  e.rom={bytes=function(_,bank,at,count)
    local raw={};for i=1,count do raw[i]=bank==2 and 255 or 0 end
    if bank==4 then raw[1]=128;if count==16 then raw[9]=64 end end
    if bank==5 then raw[1],raw[2]=64,64 end
    if bank==6 then raw[1],raw[2]=32,32 end
    return raw
  end}
  T.check(e:extractFontSheets(),edition..' real ordinary font importer completes')
  local image=assert(images['fonts/font_extra.png'])
  for tile,x in ipairs{0,1,2}do
    T.same({image:getPixel((tile-1)*8+x,0)},{0,0,0,1},edition..' correct ROM source for special tile '..tile)
    T.same({image:getPixel((tile-1)*8+7,0)},{0,0,0,0},edition..' transparent paper replaces unused bold glyph')
  end
end
-- The real readiness gate must reject an old generated font record, so a
-- pre-existing private install imports the new sheets rather than hiding the
-- setting forever. No ROM or save data is bundled in the test.
local I=require('src.import.RomImporter')
local Version=require('src.core.GameVersion');local version=Version.get()
local markerFor
for i=1,100 do local n,v=debug.getupvalue(I.readyReport,i);if n=='markerFor'then markerFor=v;break end;if not n then break end end
assert(markerFor)
for _,edition in ipairs{'gold','silver','crystal'}do
  local marker=markerFor(edition)
  T.check(marker:find('gen2%-font%-extras%-v1:')~=nil)
  Version.set(edition)
  love.filesystem.write(Version.cachePrefix(edition)..'rom-cache.complete',(marker:gsub('gen2%-font%-extras%-v1:','')))
  local report=I.readyReport(edition)
  T.eq(report.ok,false);T.check(report.why:find('another version',1,true)~=nil)
end
for _,edition in ipairs{'red','emerald','platinum'}do
  T.check(not markerFor(edition):find('gen2%-font%-extras'),edition..' cache unchanged')
end
Version.set(version);love.image.newImageData=before;love.image=imageBefore
T.finish('GSC ROM battle font and all eight frame imports, pixels and cache regeneration')
