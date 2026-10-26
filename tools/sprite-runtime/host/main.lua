io.stdout:setvbuf('no')
local root=assert(os.getenv('SPRITE_RUNTIME_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local function hash(bytes)return love.data.hash('sha256',bytes):gsub('.',function(c)return('%02x'):format(c:byte())end)end
function love.load()
  local identity=assert(os.getenv('POKEPORT_IDENTITY'));assert(love.filesystem.getIdentity()==identity)
  local g=love.graphics;local renderer,version,vendor,device=g.getRendererInfo()
  local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'));assert(renderer:lower():find(backend,1,true))
  local T=require('tests.harness').suite('owned sprite GPU resources ('..backend..')')
  local readbacks=0
  local function readImage(image)
    local w,h=image:getDimensions();local canvas=g.newCanvas(w,h,{format='rgba8',dpiscale=1,msaa=0})
    g.push('all');g.setCanvas(canvas);g.origin();g.setShader();g.setColor(1,1,1,1)
    g.setBlendMode('replace','premultiplied');g.clear(0,0,0,0);g.draw(image,0,0);g.pop()
    local data=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
    local bytes=data:getString();data:release();canvas:release();readbacks=readbacks+1;return bytes
  end
  local function asset(path,w,h,bytes)
    assert(path:match('^sprite%-tests/'),'only own QA image fixtures may be written')
    love.filesystem.createDirectory('sprite-tests')
    local data=love.image.newImageData(w,h,'rgba8',bytes);data:encode('png',path);data:release()
  end
  require('tools.sprite-runtime.resources').run(T,readImage,asset)
  local J=require('src.link.Json');local V=require('src.core.GameVersion');local S=require('src.core.game3.ow_sprites')
  local inputs=J.decode(read(assert(os.getenv('SPRITE_RUNTIME_INPUTS'))))
  local expected=J.decode(read(assert(os.getenv('SPRITE_RUNTIME_EXPECTED'))))
  local report={backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,
    identity=identity,editions={},playerProfilesUsed=false,fullOriginalModAccepted=false}
  for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
    V.set(edition);S.release()
    local manifest=J.decode(read(root..'/tools/rom_manifest_'..edition..'.json'))
    local raw=read(inputs[edition]);local sha=love.data.hash('sha1',raw):gsub('.',function(c)return('%02x'):format(c:byte())end)
    assert(sha==manifest.romSha1,'cartridge identity differs')
    local imported={};local x=require('src.import.RomExtractorGen3').new(raw,V.info(edition),manifest)
    x.write=function(_,name,value)imported[name]=value end;x.objectGfxSheet=function()return nil end
    x:extractOverworldSprites()
    local game={data={gen3_object_sheets=assert(imported.gen3_object_sheets),sprites=imported.sprites},save={player={gender=0}}}
    package.loaded['src.core.Game']=game
    local result={sheets=0,frames=0,pixels=0,different={}}
    for key,prior in pairs(expected.editions[edition].objects)do
      local id=assert(tonumber(key));local sprite,why=S.get(id);assert(sprite,why)
      local pixels=readImage(sprite.image)
      if hash(pixels)~=prior.rgba then result.different[#result.different+1]={id=id,field='gpu pixels'}end
      T.eq(sprite.width,prior.width);T.eq(sprite.height,prior.height);T.eq(sprite.frameCount,prior.frames)
      T.eq(sprite.drawOffX,prior.drawOffX);T.eq(sprite.drawOffY,prior.drawOffY)
      T.eq(pixels,sprite.imageData:getString(),'GPU and owned CPU bytes agree')
      for frame=0,sprite.frameCount-1 do
        local qx,qy,qw,qh=sprite.quads[frame]:getViewport()
        T.eq(qx,0);T.eq(qy,frame*sprite.height);T.eq(qw,sprite.width);T.eq(qh,sprite.height)
      end
      result.sheets=result.sheets+1;result.frames=result.frames+sprite.frameCount;result.pixels=result.pixels+#pixels/4
      if result.sheets%32==0 then print('SPRITE_GPU_PROGRESS',backend,edition,result.sheets,#result.different)end
    end
    report.editions[edition]=result;assert(#result.different==0,'original sprite texture pixels differ')
    S.release();collectgarbage('collect')
  end
  T.finish();report.checks=T.checks;report.readbacks=readbacks;report.status='pass'
  local f=assert(io.open(assert(os.getenv('SPRITE_RUNTIME_OUT'))..'/result.json','w'));f:write(J.encode(report));f:close()
  love.event.quit(0)
end
