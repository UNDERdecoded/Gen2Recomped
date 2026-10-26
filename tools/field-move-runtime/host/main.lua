io.stdout:setvbuf('no')
local root=assert(os.getenv('FIELD_MOVE_ENGINE'));package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
local function file(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
function love.load()
 local g=love.graphics;local T=require('tests.harness').suite('native field-move GPU rendering')
 local J=require('src.link.Json');local Art=require('src.import.Gen3FieldMoveArt')
 local Source=require('src.core.game3.field_move_show_mon');local Native=require('src.world.Gen3FieldMove')
 local inputs=J.decode(file(assert(os.getenv('FIELD_MOVE_INPUTS'))));local original=assert(os.getenv('FIELD_MOVE_ORIGINAL'))
 local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'));local renderer,version,vendor,device=g.getRendererInfo()
 assert(renderer:lower():find(backend,1,true));assert(love.filesystem.getIdentity()==os.getenv('POKEPORT_IDENTITY'))
 local pixels={};for y=0,63 do for x=0,63 do pixels[#pixels+1]=string.char(x*4,y*4,(x+y)*2,(x+y)%7==0 and 0 or 255)end end
 local d=love.image.newImageData(64,64,'rgba8',table.concat(pixels));d:encode('png','field-front.png');local front=g.newImage(d);front:setFilter('nearest','nearest');d:release()
 local a=g.newCanvas(240,160,{format='rgba8',dpiscale=1,msaa=0});local b=g.newCanvas(240,160,{format='rgba8',dpiscale=1,msaa=0})
 local readbacks,comparisons=0,0
 local function render(c,fn)
  g.push('all');g.origin();g.setCanvas(c);g.setShader();g.setScissor();g.setColor(1,1,1,1);g.clear(0,0,0,0);g.setBlendMode('alpha','alphamultiply');fn();g.pop()
  local data=g.readbackTexture and g.readbackTexture(c)or c:newImageData();local bytes=data:getString();data:release();readbacks=readbacks+1;return bytes
 end
 local function base(outside,art)
  local mocks={['src.core.game3.player']={startFieldMove=function()end},['src.core.game3.audio']={playCry=function()end},
   ['src.core.game3.pokemon']={picSpecies=function(n)return n end,isShiny=function()return false end,frontPic=function()return{image=front,w=64,h=64}end},
   ['src.core.game3.field_effects']={_cache={read=function(_,p)return Art.rgba(art.strips[p:find('outdoors',1,true)and'outdoors'or'indoors'])end}},['src.import.gba.extract_island1']={CACHE_ROOT='private'}}
  local env=setmetatable({package={loaded={['src.core.game3.map']={currentDef=function()return{mapType=outside and 3 or 8}end}}},require=function(n)return assert(mocks[n],n)end},{__index=_G})
  local fn=assert(loadfile(original));setfenv(fn,env);return fn()
 end
 local oldCry=require('src.core.Sound').playCry;require('src.core.Sound').playCry=function()end
 for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  local raw=file(inputs[edition].path);local sha=love.data.encode('string','hex',love.data.hash('sha1',raw));assert(sha==inputs[edition].sha1)
  local handle=io.open(root..'/tools/rom_manifest_'..edition..'.json','rb')
  local manifest
  if handle then manifest=J.decode(handle:read('*a'));handle:close()
  else manifest={romSha1=sha}end -- exercise the authenticated legacy-metadata profile
  local art=assert(Art.extract(require('src.import.RomGba').new(raw),manifest,sha,edition));raw=nil
  for _,outside in ipairs({true,false})do for _,pose in ipairs({true,false})do for _,noDuck in ipairs({true,false})do
   Source.release();local f=require('tools.session-runtime.fixture').new(edition);local game=f.game
   game.data.pokemon={TEST={spriteFront='field-front.png'}};game.data.constants.speciesOrder={[1]='TEST'};game.data.constants.gen3FieldMovePresentation=art
   f.map.def.mapType=outside and'ROUTE'or'INDOOR'
   local ref=base(outside,art);ref.start(1,{pose=pose,noDuck=noDuck});assert(Source.start(1,{pose=pose,noDuck=noDuck}));local state=game.stack:top()
   for tick=0,220 do
    if not ref.isActive()then break end
    local expected=render(a,ref.draw);local actual=render(b,function()state:draw()end)
    T.eq(actual,expected,edition..' native/original frame '..tick);comparisons=comparisons+1
    local frame=state.frame
    T.eq(render(b,function()state:draw()end),actual,'extra render cannot advance the effect');T.eq(state.frame,frame)
    -- The source renderer already draws this admission in the world pass.
    T.eq(render(b,function()Source.draw();state:draw()end),actual,'manual source draw and native UI draw compose only once')
    ref.step();game.stack:update(1/60)
   end
   T.eq(Source.isActive(),false);T.eq(state.completed,true)
   for _,img in pairs(ref._img)do img:release()end;if ref._quad then ref._quad:release()end
  end end end
 end
 -- Compare the ordinary native presentation to its frozen pre-change class.
 Source.release()
 local baseline=assert(loadfile(assert(os.getenv('FIELD_MOVE_NATIVE_BASELINE'))))
 local loaded={};for k,v in pairs(package.loaded)do if k~='src.core.game3.field_move_show_mon'then loaded[k]=v end end
 setfenv(baseline,setmetatable({package={loaded=loaded}},{__index=_G}));local previousClass=baseline()
 local classicComparisons=0
 for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  local f=require('tools.session-runtime.fixture').new(edition);local game=f.game
  game.data.pokemon={TEST={spriteFront='field-front.png'}}
  assert(previousClass.show(game,{species='TEST'}));local old=game.stack:top();local frames={}
  repeat
   frames[#frames+1]=render(a,function()old:draw()end)
   old:update()
  until game.stack:top()==f.world
  if old.sprite then old.sprite:release()end
  assert(Native.show(game,{species='TEST'}));local state=game.stack:top()
  T.eq(state.effect,nil,'cached inactive facade preserves ordinary native style')
  for tick,expected in ipairs(frames)do
   local actual=render(b,function()state:draw()end)
   T.check(actual==expected,edition..' unchanged native frame '..tick);classicComparisons=classicComparisons+1
   T.eq(render(b,function()state:draw()end),actual,'native repeated draws keep their frame')
   state:update()
  end
  T.eq(game.stack:top(),f.world)
 end
 require('src.core.Sound').playCry=oldCry;Source.release();front:release();a:release();b:release()
 T.finish();local result={status='pass',checks=T.checks,frameComparisons=comparisons,nativeDefaultComparisons=classicComparisons,readbacks=readbacks,backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,identity=os.getenv('POKEPORT_IDENTITY'),realRomBands=true,syntheticFrontFixture=true,fullPortraitParity=false,fullFieldEffectApi=false,playerProfilesUsed=false}
 local out=assert(io.open(assert(os.getenv('FIELD_MOVE_OUT'))..'/result.json','w'));out:write(J.encode(result));out:close();love.event.quit(0)
end
