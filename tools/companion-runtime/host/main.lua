-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
io.stdout:setvbuf('no')
local root=assert(os.getenv('BATTLE_SOURCE_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;./?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
  local T=require('tests.harness').suite('native companion rendering GPU')
  local A=require('src.core.game3.battle.anim')
  local Battle=require('src.core.game3.battle')
  local Scope=require('src.render.GraphicsScope')
  local g=love.graphics
  local nativeSource=debug.getinfo(require('src.battle.BattleState').update,'S').source
  T.eq(nativeSource,'@'..root..'/src/battle/BattleState.lua')
  local renderer,version,vendor,device=g.getRendererInfo()
  local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
  T.check(renderer:lower():find(backend,1,true)~=nil,'actual requested GPU backend')
  T.eq(love.filesystem.getIdentity(),os.getenv('POKEPORT_IDENTITY'))
  local Palette=require('src.core.game3.battle.anim_pal')
  local pixel=love.image.newImageData(1,1);pixel:setPixel(0,0,1,0,0,1)
  local encoded=pixel:encode('png');local png=encoded:getString();encoded:release()
  local decoded=assert(Palette.loadImageData(png,'independent.png'))
  T.eq(decoded:getString(),pixel:getString(),'animation PNG preserves actual pixels')
  T.eq(Palette.loadImageData('invalid image','invalid.png'),nil)
  local texture=g.newImage(pixel);local canvas=g.newCanvas(1,1)
  local shader=Palette.shader();shader:send('blendColor',{0,0,1});shader:send('blendCoeff',.5)
  local ok,why=Scope.call(function()
    g.setCanvas(canvas);g.origin();g.clear();g.setColor(1,1,1,1);g.setShader(shader);g.draw(texture)
  end);assert(ok,why)
  local result=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
  local r,green,b,a=result:getPixel(0,0)
  T.check(math.abs(r-.5)<.01 and green==0 and math.abs(b-.5)<.01 and a==1,'real blend shader output')
  T.eq(Palette.hydrateIndex({},'absent',texture,function()error('no index file requested')end),false)
  local info={indexFile='explicit.png'}
  T.eq(Palette.hydrateIndex(info,'explicit',texture,function()return png end),true)
  T.eq(info.idxData:getString(),pixel:getString(),'explicit indices survive decoding')
  info.idxImage:release();info.idxData:release()
  local large=love.image.newImageData(2,1);local file=large:encode('png');local wrong=file:getString();file:release();large:release()
  T.eq(Palette.hydrateIndex({idxFile='wrong.png'},'wrong',texture,function()return wrong end),false)
  result:release();canvas:release();texture:release();decoded:release();pixel:release();Palette._service:release()
  love.filesystem.createDirectory('tests/fixture_data/assets')
  local pixels=love.image.newImageData(64,64)
  pixels:mapPixel(function(x,y)
    if x<7 or y<5 or x>56 or y>57 then return 0,0,0,0 end
    if y<20 and x<37 then return 1,0,91/255,1 end
    if x>40 and y>35 then return 0,1,125/255,1 end
    return .2,.3,.9,1
  end)
  for _,side in ipairs{'back','front'}do pixels:encode('png','tests/fixture_data/assets/fixmon_a_'..side..'.png')end
  pixels:release()
  local fontPixels=love.image.newImageData(128,64)
  fontPixels:mapPixel(function(x,y)
    local xx,yy=x%8,y%8
    if xx==1 or yy==2 and xx<6 then return 0,0,0,1 end
    if xx==2 or yy==3 and xx>1 and xx<7 then return 1,1,1,1 end
    return 0,0,0,0
  end)
  fontPixels:encode('png','tests/fixture_data/assets/fix_font.png');fontPixels:release()
  local comparisons,readbacks=0,0
  local function read(canvas)
    local data=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
    local bytes=data:getString();data:release();readbacks=readbacks+1;return bytes
  end
  local function frame(canvas,draw)
    local ok,why=Scope.call(function()
      g.setCanvas(canvas);g.origin();g.setShader();g.setScissor();g.clear(0,0,0,0);g.setColor(1,1,1,1);draw()
    end)
    assert(ok,why);return read(canvas)
  end
  local function same(a,b,label,tolerance)
    comparisons=comparisons+1
    if not tolerance then return T.eq(a,b,label)end
    local error=0
    for i=1,#a do error=math.max(error,math.abs(a:byte(i)-b:byte(i)))end
    if error>tolerance then
      local count=0
      for i=1,#a,4 do
        local bad=false;for c=0,3 do if math.abs(a:byte(i+c)-b:byte(i+c))>tolerance then bad=true end end
        if bad then
          print('PIXEL_ORACLE_DIFFERENCE',label,((i-1)/4)%160,math.floor((i-1)/4/160),
            string.format('%d,%d,%d,%d',a:byte(i,i+3)),string.format('%d,%d,%d,%d',b:byte(i,i+3)));count=count+1;if count==4 then break end
        end
      end
      print('MAX_PIXEL_ERROR',error)
    end
    T.check(#a==#b and error<=tolerance,label)
  end
  -- Independent pixel oracle: inverse-map output pixel centres into the
  -- already rendered native image, without using graphics transforms.
  local function remap(bytes,width,height,map,alpha)
    local rows={}
    for y=0,height-1 do
      local row={}
      for x=0,width-1 do
        local sx,sy=map(x+.5,y+.5);sx,sy=math.floor(sx),math.floor(sy)
        local value='\0\0\0\0'
        if sx>=0 and sx<width and sy>=0 and sy<height then
          local at=(sy*width+sx)*4+1
          if alpha then
            local values={};for c=0,3 do values[c+1]=math.floor(bytes:byte(at+c)*alpha+.5)end
            value=string.char(unpack(values))
          else value=bytes:sub(at,at+3)end
        end
        row[#row+1]=value
      end
      rows[#rows+1]=table.concat(row)
    end
    return table.concat(rows)
  end
  local outerShader=g.newShader('vec4 effect(vec4 c, Image t, vec2 uv, vec2 p) { return Texel(t,uv)*c; }')
  for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
    A.reset();Battle._service.release()
    local f=require('tools.battle-source-runtime.fixture').new(edition)
    local game=f.game;package.loaded['src.core.Game']=game
    local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b);b.phase='QA_IDLE'
    b.introSlide=0;b.frlgIntro=nil
    local canvas=g.newCanvas(160,144,{format='rgba8',dpiscale=1,msaa=0})
    local preview=g.newCanvas(160,144,{format='rgba8',dpiscale=1,msaa=0})
    -- This host bypasses the application's pixel-art graphics setup. Set
    -- the owned fixture texture explicitly so the independent nearest-pixel
    -- oracle does not compare against LOVE's default linear interpolation.
    b:battlerPic(b.player):setFilter('nearest','nearest')
    local function draw()return b:drawBattlerPic(b.player,20,20,1)end
    local baseline=frame(canvas,draw)
    T.check(baseline:find(string.char(255,0,91,255),1,true)~=nil,'real asymmetric art reaches the native draw')
    local p=A.present(0)
    same(frame(canvas,draw),baseline,'observing a pose preserves native pixels '..edition)
    local expected=remap(baseline,160,144,function(x,y)return x-13,y-5 end)
    p.ox,p.oy=13,5
    same(frame(canvas,draw),expected,'source offsets compose with native sprite draw '..edition)
    T.check(expected~=baseline);p.ox,p.oy=nil,nil
    local img=b:battlerPic(b.player);local w,h=img:getDimensions();local cx,cy=20+w/2,20+h/2
    expected=remap(baseline,160,144,function(x,y)
      -- A clockwise quarter turn exchanges axes; the horizontal reflection
      -- then reverses the vertical axis in output space.
      return cx-(y-cy),cy-(x-cx)/2
    end,.5)
    p.hFlip,p.rotation,p.scale,p.sx,p.sy,p.alpha=true,math.pi/2,.5,2,4,.5
    same(frame(canvas,draw),expected,'flip, rotation, scale and alpha preserve authored orientation '..edition,1)
    p.hFlip,p.rotation,p.scale,p.sx,p.sy,p.alpha=nil,nil,nil,nil,nil,nil
    same(frame(canvas,draw),baseline,'clearing source overrides restores native pixels '..edition)
    p.visible=false;local hidden=frame(canvas,draw);T.check(hidden~=baseline);T.eq(hidden,string.rep('\0',160*144*4))
    p.visible=nil
    local old=b.drawBattlerPicAt;p.ox=1
    local ok,why=Scope.call(function()
      g.setCanvas(canvas);g.setShader(outerShader)
      local depth=g.getStackDepth()
      b.drawBattlerPicAt=function()g.push();g.setCanvas(preview);error('native sprite draw failure')end
      local success,err=pcall(draw);T.eq(success,false);T.check(tostring(err):find('native sprite draw failure',1,true)~=nil)
      T.eq(g.getCanvas(),canvas);T.eq(g.getShader(),outerShader);T.eq(g.getStackDepth(),depth)
    end)
    assert(ok,why);b.drawBattlerPicAt=old;p.ox=nil
    local base={.8,.2,.35}
    for _,effect in ipairs{'invert','fade_white','fade_black','darken','grayscale','custom_blend'}do
      A.setScreenEffect({type=effect,coeff=.5,targetColor={.2,.4,.6}})
      frame(canvas,function()
        g.setShader(outerShader);T.eq(A.beginScreenEffect(),true)
        local active=g.getShader();T.neq(active,outerShader)
        T.eq(A.beginScreenEffect(),true);T.eq(g.getShader(),active,'repeated begin does not nest')
        local nested=Scope.call(function()
          T.eq(A.beginScreenEffect(),true);T.eq(A.endScreenEffect(),true);T.eq(g.getShader(),active)
        end);T.eq(nested,true)
        g.setColor(base[1],base[2],base[3],1);g.rectangle('fill',0,0,160,144)
        T.eq(A.endScreenEffect(),true);T.eq(g.getShader(),outerShader)
      end)
      local data=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData();readbacks=readbacks+1
      local actual={data:getPixel(10,10)};data:release()
      local luma=base[1]*.299+base[2]*.587+base[3]*.114
      for channel=1,3 do
        local target=effect=='fade_white'and 1 or(effect=='grayscale'and luma or(effect=='custom_blend'and({.2,.4,.6})[channel]or 0))
        local value=effect=='invert'and 1-base[channel]or(base[channel]+target)/2
        T.check(math.abs(actual[channel]-value)<2/255,'screen effect GPU colour '..effect..' '..edition)
      end
      T.eq(actual[4],1)
    end
    local priorShader=g.getShader();local depth=g.getStackDepth();local priorCanvas=g.getCanvas()
    ok,why=Scope.call(function()A.beginScreenEffect();g.push();g.setCanvas(preview);error('effect failure')end)
    T.eq(ok,false);T.check(tostring(why):find('effect failure',1,true)~=nil)
    T.eq(g.getShader(),priorShader);T.eq(g.getStackDepth(),depth);T.eq(g.getCanvas(),priorCanvas)
    A.setScreenEffect(nil);T.eq(A.beginScreenEffect(),false)
    -- Nested source text must restore the outer native two-tone uniforms.
    local Font=require('src.render.Font');local SourceFont=require('src.ui.game3.frlg_font')
    game.data.font.pages={main={image='tests/fixture_data/assets/fix_font.png',base=0x80,
      glyphWidth=8,glyphHeight=8,glyphsPerRow=16,preTinted=true}}
    Font.load(game.data)
    local sample=love.image.newImageData(1,1);sample:setPixel(0,0,0,0,0,1)
    local texture=g.newImage(sample);sample:release();texture:setFilter('nearest','nearest')
    local function pixelAt(x)return function()g.draw(texture,x,100)end end
    local expectedText=frame(canvas,function()
      Font.beginTwoTone({1,0,0,1},{0,1,0,1});pixelAt(5)();pixelAt(10)();Font.endTwoTone()
    end)
    T.eq(expectedText:sub((100*160+5)*4+1,(100*160+5)*4+4),string.char(255,0,0,255),'native outer shader produces red ink')
    local actualText=frame(canvas,function()
      Font.beginTwoTone({1,0,0,1},{0,1,0,1});pixelAt(5)()
      T.eq(SourceFont.measure('AB',{letterSpacing=2}),Font.width('AB')+2)
      local oldCanvas,oldShader,depth=g.getCanvas(),g.getShader(),g.getStackDepth()
      SourceFont.draw('AB',5,5,{colors={fg={0,0,1,1},shadow={1,1,0,1}},letterSpacing=2})
      T.eq(g.getCanvas(),oldCanvas);T.eq(g.getShader(),oldShader);T.eq(g.getStackDepth(),depth)
      pixelAt(10)();Font.endTwoTone()
    end)
    -- Compare only the two independent sample pixels; text occupies other rows.
    local function pixel(bytes,x,y)local at=(y*160+x)*4+1;return bytes:sub(at,at+3)end
    same(pixel(actualText,5,100),pixel(expectedText,5,100),'outer ink before nested text '..edition)
    same(pixel(actualText,10,100),pixel(expectedText,10,100),'outer ink after nested text '..edition)
    T.eq(pixel(actualText,6,5),string.char(0,0,255,255),'real source text paints native ink '..edition)
    T.eq(pixel(actualText,7,5),string.char(255,255,0,255),'real source text retains native shadow '..edition)
    T.eq(SourceFont._spec.nativeLayout,(edition=='firered'or edition=='leafgreen')and'frlg'or'rs')
    texture:release()
    canvas:release();preview:release();game.stack.states={};f.close();A.reset();Battle._service.release()
  end
  outerShader:release();T.finish()
  local report={passed=true,checks=T.checks,comparisons=comparisons,readbacks=readbacks,
    backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,
    nativeBattleSource=nativeSource,engineRoot=root,syntheticBattlerArt=true,nestedNativeText=true,
    playerProfilesUsed=false,originalModLoaded=false,gameplayProven=false}
  local file=assert(io.open(assert(os.getenv('BATTLE_SOURCE_REPORT')),'w'))
  file:write(require('src.link.Json').encode(report));file:close();love.event.quit(0)
end
