io.stdout:setvbuf('no')
local root=assert(os.getenv('FIELD_SHEETS_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
 local g=love.graphics;local T=require('tests.harness').suite('owned field-effect sheet GPU resources')
 local renderer,version,vendor,device=g.getRendererInfo()
 local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'));assert(renderer:lower():find(backend,1,true))
 local identity=assert(os.getenv('POKEPORT_IDENTITY'));assert(love.filesystem.getIdentity()==identity)
 local F=require('src.core.game3.field_effects');local V=require('src.core.GameVersion')
 local Assets=require('src.render.Assets');local Host=require('src.mods.Runtime')
 local readbacks,comparisons=0,0
 local function read(canvas)
  local copy
  if not canvas:typeOf('Canvas')then
   copy=g.newCanvas(canvas:getWidth(),canvas:getHeight(),{format='rgba8',dpiscale=1,msaa=0})
   g.push('all');g.origin();g.setCanvas(copy);g.setShader();g.setScissor();g.setColor(1,1,1,1)
   g.clear(0,0,0,0);g.setBlendMode('replace','premultiplied');g.draw(canvas,0,0);g.pop()
   canvas=copy
  end
  local data=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
  local bytes=data:getString();data:release();if copy then copy:release()end
  readbacks=readbacks+1;return bytes
 end
 local function pixels(w,h,seed)
  local rows={}
  for y=0,h-1 do for x=0,w-1 do
   if(x+y)%7==0 then rows[#rows+1]=string.char(0,0,0,0)
   else rows[#rows+1]=string.char((x*7+seed)%256,(y*13+seed)%256,(x+y*3+seed)%256,255)end
  end end
  return table.concat(rows)
 end
 local function crop(bytes,w,y,h)return bytes:sub(y*w*4+1,(y+h)*w*4)end
 love.filesystem.createDirectory('assets/generated/qa-field')
 local sizes={tall_grass={16,16,5},surf_blob={32,32,6},fly_bird={64,64,5},ripple={16,16,5},sparkle={16,16,5},emote_heart={16,16,3}}
 for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  F.release();V.set(edition);local data={constants={},sprites={}}
  local game={data=data,save={},mods={}};package.loaded['src.core.Game']=game
  local source={}
  for name,size in pairs(sizes)do
   local w,h,n=size[1],size[2],size[3];local bytes=pixels(w,h*n,n)
   local path='assets/generated/qa-field/'..name..'.png'
   local image=love.image.newImageData(w,h*n,'rgba8',bytes);image:encode('png',path);image:release()
   source[name]={path=path,bytes=bytes,w=w,h=h,n=n}
   local row={image=path,frameWidth=w,frameHeight=h,frames=n,trueColor=true}
   if name=='tall_grass'then data.constants.gen3TallGrass=row
   elseif name=='surf_blob'then data.constants.gen3SurfBlob=row
   elseif name=='fly_bird'then data.constants.gen3FRLGFlyBird={path=path,frameWidth=w,frameHeight=h,frames=n}
   elseif name=='emote_heart'then data.constants.gen3Emotes={heart={image=path,width=w,height=h,frames=n}}
   else data.constants[name=='ripple'and'gen3Ripple'or'gen3Sparkle']={key=name};data.sprites[name]=row end
  end
  for name,s in pairs(source)do
   local borrowed=Assets.image(s.path);local nativeBefore=read(borrowed)
   Host.currentMod='gpu-a';local sheet=assert(F.loadSheet(name));Host.currentMod=nil
   T.eq(read(sheet.image),s.bytes,edition..' '..name..' complete image matches its actual PNG')
   T.check(sheet.image~=borrowed,'native asset-cache images are never lent')
   for frame=0,s.n-1 do
    for _,front in ipairs({false,true})do
     local h=front and 8 or s.h;local target=g.newCanvas(s.w,h,{format='rgba8',dpiscale=1,msaa=0})
     g.push('all');g.origin();g.setCanvas(target);g.setShader();g.setScissor();g.setColor(1,1,1,1)
     g.clear(0,0,0,0);g.setBlendMode('replace','premultiplied')
     g.draw(sheet.image,(front and sheet.quadsFront or sheet.quads)[frame],0,0);g.pop()
     T.eq(read(target),crop(s.bytes,s.w,frame*s.h+(front and s.h-8 or 0),h),'original frame/crop pixels')
     comparisons=comparisons+1;target:release()
    end
   end
   Host.currentMod='gpu-b';T.eq(F.loadSheet(name),sheet);Host.currentMod=nil
   F.cancelOwner('gpu-a');T.eq(sheet._retired,nil)
   sheet.image=borrowed
   F.cancelOwner('gpu-b');T.eq(sheet._retired,true)
   T.eq(read(borrowed),nativeBefore,'native cached images survive peer retirement')
  end
  -- Native generated-asset overrides remain authoritative, with exact geometry.
  local base=source.tall_grass;local path='assets/generated/qa-field/override.png'
  local changed=pixels(base.w,base.h*base.n,193)
  local image=love.image.newImageData(base.w,base.h*base.n,'rgba8',changed);image:encode('png',path);image:release()
  local old=Assets.resolve
  Assets.resolve=function(p)return p==base.path and path or old(p)end
  local override=assert(F.loadSheet('tall_grass'));T.eq(read(override.image),changed)
  Assets.resolve=old
  local restored=assert(F.loadSheet('tall_grass'));T.eq(read(restored.image),base.bytes);T.eq(override._retired,true)
  local raw=pixels(8,32,73);local manifest="return {family='"..(V.isFRLG(edition)and'frlg'or'rse').."',objects={{name='custom',fw=8,fh=8,frames=4,rgba='custom.rgba'}}}"
  local provider={read=function(_,p)if p:sub(-11)=='objects.lua'then return manifest end;if p:sub(-11)=='custom.rgba'then return raw end end}
  Host.currentMod='gpu-cache';assert(F.install(provider));local custom=assert(F.loadSheet('custom'));Host.currentMod=nil
  T.eq(read(custom.image),raw,'explicit source RGBA requires no conversion file')
  Assets.invalidate();T.eq(custom._retired,true)
  local again=assert(F.loadSheet('custom'));T.eq(read(again.image),raw)
  F.release();T.eq(again._retired,true);T.eq(F._cache,nil)
 end
 T.finish()
 local result={status='pass',checks=T.checks,frameComparisons=comparisons,readbacks=readbacks,backend=backend,renderer=renderer,
  version=version,vendor=vendor,device=device,identity=identity,playerProfilesUsed=false,fullFieldEffectApi=false,fullRendererAcceptance=false}
 local f=assert(io.open(assert(os.getenv('FIELD_SHEETS_OUT'))..'/result.json','w'));f:write(require('src.link.Json').encode(result));f:close()
 print('Field sheet GPU pass',comparisons,readbacks);love.event.quit(0)
end
