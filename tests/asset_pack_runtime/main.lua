local root=assert(os.getenv('PACK_ENGINE_ROOT'),'PACK_ENGINE_ROOT is required')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.load()
  local ok,err=pcall(function()
    local I=require('src.import.Importers')
    local P=require('src.mods.AssetPacks')
    local W=require('src.import.LuaWriter')
    local fs=I.fs()
    local source='imports/asset_packs/lttp/sprites'
    assert(fs.createDirectory(source))
    local image=love.image.newImageData(1,1)
    image:setPixel(0,0,0.25,0.5,0.75,1)
    local encoded=image:encode('png'); local bytes=encoded:getString()
    image:release(); encoded:release()
    assert(fs.write(source..'/pixel.png',bytes))
    local metadata=W.encode({directions={'south','north'},durations={2,3}})
    assert(fs.write(source..'/pixel.lua',metadata))
    assert(fs.write(source..'/pack.lua',W.encode({format=1,importer='lttp',pack='sprites',kind='sprite',
      version='1.0.0',source={name='Generated QA pixel; no cartridge content',md5=string.rep('0',32)},
      entries={pixel={file='pixel.png',size=#bytes,width=1,height=1,
        metadata={file='pixel.lua',size=#metadata}}}})))
    local co=I.install('lttp','sprites',fs,source,fs)
    repeat local resumed,why=coroutine.resume(co); assert(resumed,why) until coroutine.status(co)=='dead'
    local manifest={required_assets={{importer='lttp',pack='sprites'}}}
    assert(not P.missing(manifest,fs))
    local api=P.new(manifest,fs)
    local installed=assert(api:read('lttp','sprites','pixel'))
    assert(installed==bytes)
    local fileData=love.filesystem.newFileData(installed,'pixel.png')
    local decoded=love.image.newImageData(fileData)
    assert(decoded:getWidth()==1 and decoded:getHeight()==1)
    decoded:release(); fileData:release()
    assert(api:metadata('lttp','sprites','pixel').directions[2]=='north')
    assert(fs.read(source..'/pixel.png')==bytes)
    local path=I.manifestPath('lttp','sprites'); local previous=fs.read(path)
    local failing=setmetatable({rename=function()return nil,'injected native publication failure' end},{__index=fs})
    local replacement=I.install('lttp','sprites',fs,source,failing)
    local failed=false
    repeat local resumed=coroutine.resume(replacement);if not resumed then failed=true;break end
    until coroutine.status(replacement)=='dead'
    assert(failed and fs.read(path)==previous)
    assert(api:read('lttp','sprites','pixel')==bytes)
    print('Native pack filesystem, PNG decode, metadata and failed replacement: PASS')
  end)
  if not ok then io.stderr:write(tostring(err)..'\n'); love.event.quit(1)
  else love.event.quit(0) end
end
