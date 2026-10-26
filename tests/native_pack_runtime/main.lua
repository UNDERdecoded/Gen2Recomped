-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root=assert(os.getenv('PACK_ENGINE_ROOT'),'PACK_ENGINE_ROOT is required')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.load()
  local ok,err=pcall(function()
    local F=require('tests.pack_sources.fixture')
    local LT=require('src.import.lttp.LttpImport')
    local I=require('src.import.Importers')
    local Packs=require('src.mods.AssetPacks')
    local Inbox=require('src.import.PackInbox')
    local MD5=require('src.mods.StreamMD5')
    local Data=require('src.import.PackData')
    local source=F.cartridge()
    local hash=MD5.new():update(source):final()
    assert(not LT.identify(source),'format fixture must not identify as a real cartridge')
    LT.SOURCES[hash]={name='Generated format fixture, not cartridge evidence',size=#source}
    local fs=I.fs()
    assert(fs.getWriteRoot()==love.filesystem.getSaveDirectory(),'QA data must stay in its owned identity')
    assert(not fs.getInfo(Inbox.SOURCES..'/lttp.sfc'),'use a fresh empty QA identity; never overwrite unrelated source files')
    for _,pack in ipairs({'tiles','sprites','palettes'}) do
      assert(not fs.getInfo(I.manifestPath('lttp',pack)),'use a fresh empty QA identity for full extraction evidence')
    end
    assert(fs.createDirectory(Inbox.SOURCES))
    local input=Inbox.SOURCES..'/lttp.sfc'
    assert(fs.write(input,source))
    local function drain(co)
      local yielded=0
      while true do
        local resumed,value=coroutine.resume(co);assert(resumed,value)
        if coroutine.status(co)=='dead' then return value,yielded end
        yielded=yielded+1;assert(value.total>=value.done and value.done>=0)
      end
    end
    local result,yields=drain(Inbox.start(fs))
    assert(result.found==1 and #result.installed==3 and #result.failed==0)
    assert(yields>=231,'extraction must yield progress')
    local api=Packs.new({required_assets={{importer='lttp',pack='sprites'},
      {importer='lttp',pack='tiles'},{importer='lttp',pack='palettes'}}},fs)
    assert(api:info('lttp','sprites').entries==109)
    assert(api:info('lttp','tiles').entries==116)
    assert(api:info('lttp','palettes').entries==6)
    local function image(pack,id,width,height)
      local bytes=assert(api:read('lttp',pack,id))
      local file=love.filesystem.newFileData(bytes,id..'.png')
      local decoded=love.image.newImageData(file);file:release()
      assert(decoded:getWidth()==width and decoded:getHeight()==height)
      return decoded
    end
    local sheet=image('sprites','sheet_115',128,32)
    local r,g,b,a=sheet:getPixel(0,0);assert(r==1 and g==0 and b==0 and a==1);sheet:release()
    sheet=image('tiles','sheet_000',128,32)
    r,g,b,a=sheet:getPixel(0,0);assert(r==0 and g==1 and b==0 and a==1);sheet:release()
    sheet=image('sprites','player',128,448)
    r,g,b,a=sheet:getPixel(0,0);assert(r==0 and g==0 and b==1 and a==1)
    r,g,b,a=sheet:getPixel(1,0);assert(a==0);sheet:release()
    sheet=image('tiles','kakariko',1024,1024)
    for _,xy in ipairs({{0,0},{15,0},{0,15},{15,15}}) do
      r,g,b,a=sheet:getPixel(xy[1],xy[2]);assert(r==1 and g==0 and b==0 and a==1)
    end
    sheet:release()
    local palettes=assert(Data.decode(assert(api:read('lttp','palettes','armor'))))
    assert(#palettes==5 and #palettes[1]==15 and palettes[1][8][3]==255)
    assert(fs.read(input)==source,'source file must be preserved')
    local before={}
    for _,pack in ipairs({'tiles','sprites','palettes'}) do before[pack]=fs.read(I.manifestPath('lttp',pack)) end
    local reused,count=drain(LT.job(source,fs))
    assert(reused.reused and count==0,'existing complete packs must skip extraction')
    for _,pack in ipairs({'tiles','sprites','palettes'}) do assert(fs.read(I.manifestPath('lttp',pack))==before[pack]) end
    local failing=setmetatable({rename=function(from,to)
      if to:match('/pack%.lua$') then return nil,'injected descriptor failure' end
      return fs.rename(from,to)
    end},{__index=fs})
    local failed=LT.job(source,failing,{force=true})
    local failure
    while true do
      local resumed,value=coroutine.resume(failed)
      if not resumed then failure=value;break end
      assert(coroutine.status(failed)~='dead','injected descriptor failure must propagate')
    end
    assert(tostring(failure):find('injected descriptor failure',1,true))
    for _,pack in ipairs({'tiles','sprites','palettes'}) do assert(fs.read(I.manifestPath('lttp',pack))==before[pack]) end
    assert(api:read('lttp','sprites','player'))
    local Writer=require('src.import.LuaWriter')
    local override=Inbox.ROOT..'/lttp/palettes'
    local paletteBytes=Writer.encode({{{1,2,3}}})
    assert(fs.createDirectory(override));assert(fs.write(override..'/armor.lua',paletteBytes))
    assert(fs.write(override..'/pack.lua',Writer.encode({format=1,importer='lttp',pack='palettes',kind='palette',version='9.0.0',
      source={md5=string.rep('0',32),name='Generated explicit override'},entries={armor={file='armor.lua',size=#paletteBytes}}})))
    result=drain(Inbox.start(fs))
    assert(result.found==2 and #result.installed==3 and #result.failed==0,'source plus explicit override must count distinct packs')
    assert(api:info('lttp','palettes').version=='9.0.0' and api:read('lttp','palettes','armor')==paletteBytes)
    assert(fs.write(input,'Unsupported generated source'))
    result=drain(Inbox.start(fs))
    assert(#result.failed==1 and #result.installed==1,'bad source must not prevent independent explicit pack installation')
    assert(api:read('lttp','sprites','player') and fs.read(input)=='Unsupported generated source')
    LT.SOURCES[hash]=nil
    print('Native SNES extractor: 223 sheets, player, 4096 metatiles, 6 palettes, 3 packs, native PNG round trips, reuse and atomic failure: PASS')
    print('Evidence uses generated format data. Real-cartridge pixel parity and device gameplay remain unverified.')
  end)
  if ok then love.event.quit(0) else io.stderr:write(tostring(err)..'\n');love.event.quit(1) end
end
