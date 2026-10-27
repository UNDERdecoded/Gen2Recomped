-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
io.stdout:setvbuf('no')
local root=assert(os.getenv('NATIVE_TEXT_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)print(debug.traceback(tostring(err),2));return function()return 1 end end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
function love.load()
 assert(love.graphics==nil,'native art decoding must not initialize graphics')
 local J=require('src.link.Json');local V=require('src.core.GameVersion')
 local X=require('src.import.RomExtractorGen3');local Art=require('src.import.Gen3LevelUpArt')
 local inputs=J.decode(read(assert(os.getenv('NATIVE_TEXT_INPUTS'))))
 local results={editions={},pass=true,playerProfilesUsed=false,gpu=false}
 for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  V.set(edition);local raw=read(inputs[edition])
  local manifest=J.decode(read(root..'/'..V.info().manifest))
  local x=X.new(raw,V.info(),manifest)
  local record,why=Art.read(x)
  if Art.supports(edition)then
   assert(record,why);local image=Art.image(record)
   assert(image:getWidth()==8 and image:getHeight()==16)
   local bytes=image:getString()
   results.editions[edition]={gfx=record.gfxOffset,palette=record.paletteOffset,
    romSha1=record.romSha1,rgbaSha256=love.data.encode('string','hex',love.data.hash('sha256',bytes))}
   -- Fingerprint gate precedes every palette/tile read, not just profile selection.
   x.rom.data=string.char((raw:byte(1)+1)%256)..raw:sub(2)
   assert(Art.read(x)==nil,'changed cartridge was accepted')
   image:release()
  else
   assert(record==nil and why,'unsupported edition acquired FRLG artwork')
   results.editions[edition]={supported=false}
  end
 end
 local f=assert(io.open(assert(os.getenv('NATIVE_TEXT_RESULT')),'w'));f:write(J.encode(results));f:close()
 print('NATIVE_LEVEL_ART_OK');love.event.quit(0)
end
