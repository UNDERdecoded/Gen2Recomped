io.stdout:setvbuf('no')
local root=assert(os.getenv('FIELD_VIEW_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
 local g=love.graphics
 local T=require('tests.harness').suite('native field presentation GPU')
 local Field=require('src.core.game3.field_view');local base=Field.draw
 local Native=require('src.core.game3.tileset_native')
 local Flash=require('src.world.Gen3Flash')
 local Game3=require('src.core.Game3')
 local readbacks,comparisons=0,0
 local renderer,version,vendor,device=g.getRendererInfo()
 local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
 T.check(renderer:lower():find(backend,1,true)~=nil,'requested actual graphics backend')
 T.eq(love.filesystem.getIdentity(),os.getenv('POKEPORT_IDENTITY'),'owned QA profile')
 local function canvas(w,h)return g.newCanvas(w,h,{format='rgba8',dpiscale=1,msaa=0})end
 local function read(texture)
  local w,h=texture:getDimensions();local copy=canvas(w,h)
  g.push('all');g.origin();g.setCanvas(copy);g.setShader();g.setScissor();g.clear(0,0,0,0)
  g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1);g.draw(texture,0,0);g.pop()
  local pixels=g.readbackTexture and g.readbackTexture(copy)or copy:newImageData()
  local bytes=pixels:getString();pixels:release();copy:release();readbacks=readbacks+1;return bytes
 end
 local function draw(target,fn)
  g.push('all');g.origin();g.setCanvas(target);g.setShader();g.setScissor();g.clear(0,0,0,0)
  g.setBlendMode('alpha');g.setColor(1,1,1,1);fn();g.pop();return read(target)
 end
 local function samePixels(actual,expected,label)
  T.check(actual==expected,label);comparisons=comparisons+1
  if actual~=expected then
   for i=1,math.min(#actual,#expected)do if actual:byte(i)~=expected:byte(i)then print('FIRST_PIXEL_BYTE_DIFFERENCE',i,actual:byte(i),expected:byte(i));break end end
  end
 end
 local function expectedTerrain(f,w,h,panX,panY)
  -- Independent room/connection geometry: three true cells, not the padded
  -- four-cell storage stride, plus the two authored eastern strips.
  local a=assert(Native.get(f.native.pair));local b=assert(Native.get(f.native.neighborPair))
  local split=f.native.split;local mids={0,split,1,2,split+1,split+2}
  local camX=math.floor(f.world.player.px+8-w/2)+panX
  local camY=math.floor(f.world.player.py+8-h/2)+panY
  local atlas={}
  for _,ts in ipairs{a,b}do atlas[ts]={ts.imageData:getString(),ts.overImageData:getString()}end
  local rows={}
  for y=0,h-1 do local row={}
   for x=0,w-1 do
    local wx,wy=x+camX,y+camY;local cx,cy=math.floor(wx/16),math.floor(wy/16)
    local ts,mid=a,nil
    if cx>=0 and cx<3 and cy>=0 and cy<2 then mid=mids[cy*3+cx+1]
    elseif cx>=3 and cx<6 then
     for _,offset in ipairs{3,-1}do
      local ny=cy-offset
      if ny>=0 and ny<2 then ts,mid=b,mids[ny*3+cx-3+1];break end
     end
    end
    mid=mid or(cy%2==0 and 1 or 2)
    local slot=assert(ts.midToSlot[mid]);local px,py=wx%16,wy%16
    local at=(((math.floor(slot/ts.cols)*16+py)*(ts.cols*16))+(slot%ts.cols)*16+px)*4+1
    local u,o=atlas[ts][1]:sub(at,at+3),atlas[ts][2]:sub(at,at+3)
    row[x+1]=o:byte(4)>0 and o or u
   end
   rows[y+1]=table.concat(row)
  end
  return table.concat(rows)
 end
 for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  local f=require('tools.field-view-runtime.fixture').new(edition)
  local world,game=f.world,f.game
  world.waterAnim,world.ripples=nil,{}
  local facade=assert(Game3.forNative(game))
  local borrowed=world.map.renderer.gen3.bottom;local borrowedBytes=read(borrowed)
  for _,size in ipairs{{240,160},{320,200},{480,320}}do
   local w,h=size[1],size[2];local target=canvas(w,h)
   for _,pan in ipairs{{0,0},{7,-9},{-37,23}}do
    Field.setCameraPanning(pan[1],pan[2])
    local bytes=draw(target,function()assert(base(facade,w,h,{skipActors=true}))end)
    samePixels(bytes,expectedTerrain(f,w,h,pan[1],pan[2]),'native cells, borders, connected pairs and upper layer match CPU texels')
   end
   Field.setCameraPanning(0,0)
   local prior
   local bytes=draw(target,function()assert(base(facade,w,h,{skipActors=true,endUnderActors=function(fn)prior=fn end}))end)
   T.eq(prior,nil,'skipActors also excludes the actor-layer callback')
   local again=draw(target,function()assert(base(facade,w,h,{skipActors=true}))end)
   samePixels(bytes,again,'repeated field capture is stable')
   target:release()
  end
  local target=canvas(240,160)
  for _,e in ipairs(world.entities)do e.hidden=true end
  world.player.hidden=false
  world.player.draw=function(_,cx,cy)
   g.setColor(1,0,0,1);g.rectangle('fill',world.player.px-cx+4,world.player.py-cy+2,8,12)
   g.setColor(0,1,0,1);g.rectangle('fill',world.player.px-cx+4,world.player.py-cy+2,2,2)
  end
  local bytes=draw(target,function()assert(base(facade,240,160,{actorsOnly=true}))end)
  local function pixel(x,y)return bytes:sub((y*240+x)*4+1,(y*240+x)*4+4)end
  T.eq(pixel(116,74),string.char(0,255,0,255),'native actor keeps its asymmetric top-left marker')
  T.eq(pixel(119,80),string.char(255,0,0,255),'native actor body keeps its source anchor')
  T.eq(pixel(0,0),string.rep('\0',4),'actor-only capture excludes terrain and native FX')
  local words={};for i=1,16 do words[i]=31 end
  local patched=draw(target,function()assert(Field.setBgPaletteOverride(0,words));assert(base(facade,240,160,{skipActors=true}))end)
  samePixels(patched,expectedTerrain(f,240,160,0,0),'palette upload reaches the actual field batches')
  local old=Field._nativeBatch
  require('src.render.Assets').invalidate()
  local reloaded=draw(target,function()assert(base(facade,240,160,{skipActors=true}))end)
  samePixels(reloaded,patched,'asset reload preserves the active palette presentation')
  T.check(not pcall(old.getCount,old),'asset reload retires the old GPU batches')
  Field.setBgPaletteOverride(0,nil)
  local ts=assert(Native.get(f.native.pair));local batch=Field._nativeBatch
  local bytes=string.rep(string.char(255,0,255,255),256)
  local Upload=require('src.compat.gen1.AtlasUpload')
  Upload.patch(ts.imageData,ts.cols,ts.midToSlot[1],bytes,true)
  Native.markDirty(ts,false,ts.midToSlot[1]);Native.flush(ts,true,false,3,true)
  local uploaded=draw(target,function()assert(base(facade,240,160,{skipActors=true}))end)
  samePixels(uploaded,expectedTerrain(f,240,160,0,0),'rotated animation upload is sampled by queued batches')
  T.eq(Field._nativeBatch,batch,'texture rotation retains stationary cell geometry')
  T.eq(batch:getTexture(),ts.image,'stationary batch is bound to the current upload buffer')
  Field.invalidate()
  local frame=0
  game.renderer={worldViewSize=function()return 240,160 end}
  Field.draw=function(view,w,h)frame=frame+1;T.eq(view,facade);return base(view,w,h,{skipActors=true})end
  local replaced=draw(target,function()world:drawWorld()end)
  T.eq(frame,1,'actual native world phase invokes the source wrapper')
  samePixels(replaced,expectedTerrain(f,240,160,0,0),'native fallback is the same source atlas presentation')
  local failedTarget=canvas(16,16)
  Field.draw=function()g.push();g.setCanvas(failedTarget);g.setColor(.2,.3,.4,.5);error('GPU field failure')end
  g.push('all');g.setCanvas(target);local depth=g.getStackDepth();local current=g.getCanvas()
  T.raises(function()world:drawWorld()end,'GPU field failure')
  T.eq(g.getStackDepth(),depth,'native callback failure restores graphics stack depth')
  T.eq(g.getCanvas(),current,'native callback failure restores actual GPU target');g.pop()
  Field.draw=base;failedTarget:release()
  -- Integer masks are qualified separately against pinned source scanlines.
  -- These GPU checks prove that every black/transparent pixel follows them.
  for _,case in ipairs{{0,120,80},{24,120,80},{37,-9,17},{72,137,61},{200,300,-20}}do
   local radius,cx,cy=unpack(case)
   local actual=draw(target,function()Flash.drawMask(radius,240,160,cx,cy)end)
   local expected={};local spans=Flash.spans(radius,240,160,cx,cy)
   for _,s in ipairs(spans)do for y=s.y,s.y+s.height-1 do
    local row={};for x=0,239 do row[#row+1]=(x<s.left or x>=s.right)and'\0\0\0\255'or'\0\0\0\0'end
    expected[y+1]=table.concat(row)
   end end
   samePixels(actual,table.concat(expected),'GPU black window follows integer scanlines under pan')
  end
  local batch=Field._nativeBatch;Field.release()
  T.check(not pcall(batch.getCount,batch),'field retirement releases its owned GPU batch')
  samePixels(read(borrowed),borrowedBytes,'borrowed native atlas survives source rendering and teardown')
  target:release();f:release();Game3.release()
 end
 T.finish()
 local report={passed=true,checks=T.checks,readbacks=readbacks,comparisons=comparisons,
  backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,
  playerProfilesUsed=false,gameplayProven=false,
  scope='Actual native world draw boundary and source atlas composition over synthetic native maps/actors; all five GBA editions, three view sizes, camera pan, integer masks and GPU ownership.'}
 local file=assert(io.open(assert(os.getenv('FIELD_VIEW_REPORT')),'w'));file:write(require('src.link.Json').encode(report));file:close()
 print('NATIVE_FIELD_VIEW_GPU_PASS',readbacks,comparisons);love.event.quit(0)
end
