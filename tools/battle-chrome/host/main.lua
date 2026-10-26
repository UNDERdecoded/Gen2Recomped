-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
io.stdout:setvbuf('no')
local root=assert(os.getenv('BATTLE_SOURCE_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;./?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
  local T=require('tests.harness').suite('native battle chrome rendering GPU')
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
    local Chrome=require('src.ui.game3.battle_chrome');local Native=require('src.battle.Gen3Battle')
    local Health=require('src.core.game3.battle.healthbox')
    local panel=love.image.newImageData(240,48)
    panel:mapPixel(function(x,y)
      if x<4 then return 1,0,0,.5 end
      if y<3 then return 0,1,0,1 end
      if x>235 then return 0,0,1,1 end
      return .2,.3,.4,.5
    end)
    panel:encode('png','tests/fixture_data/assets/native_panel.png');panel:release()
    game.data.constants.gen3BattleTextbox={images={action='tests/fixture_data/assets/native_panel.png'},y=112}
    require('src.render.Assets').image('tests/fixture_data/assets/native_panel.png'):setFilter('nearest','nearest')
    for _,width in ipairs{240,320,480}do
      b.gen3SurfaceWidth=function()return width end
      local wide=g.newCanvas(width,160,{format='rgba8',dpiscale=1,msaa=0})
      local expectedPanel=frame(wide,function()Native.drawPanel(b,'action')end)
      same(frame(wide,function()Chrome.drawPanel('menu')end),expectedPanel,'source panel retains native pixels at width '..width..' '..edition)
      local base=Chrome.drawPanel;local wrappers,paints=0,0
      Chrome.drawPanel=function(mode)wrappers=wrappers+1;base(mode);return base(mode)end
      local actual=frame(wide,function()
        Chrome._panel(b,'action',function()paints=paints+1;return Native.drawPanel(b,'action')end)
      end)
      same(actual,expectedPanel,'native panel scope paints alpha pixels once at width '..width..' '..edition)
      T.eq(wrappers,1);T.eq(paints,1);Chrome.drawPanel=base
      -- A pixel oracle independent of either painter proves the asymmetric top.
      local at=(113*width+10)*4+1;T.eq(actual:sub(at,at+3),string.char(0,255,0,255))
      local st=Battle.getState();local x,y=Native.healthboxGeometry(b,0);local center=Health.center(st,0)
      T.eq(center.x,x+32);T.eq(center.y,y+16)
      wide:release()
    end
    b.gen3SurfaceWidth=nil
    local old=Health.draw;local wrappers,paints=0,0
    Health.draw=function(side,mon,opts)wrappers=wrappers+1;opts.ox,opts.oy=7,3;old(side,mon,opts);return old(side,mon,opts)end
    local moved=frame(canvas,function()
      Health._nativeDraw(b,b.player,0,0,true,function()paints=paints+1;g.setColor(1,0,0,1);g.rectangle('fill',20,20,4,4)end)
    end)
    local expectedMoved=frame(preview,function()g.setColor(1,0,0,1);g.rectangle('fill',27,23,4,4)end)
    same(moved,expectedMoved,'native healthbox wrapper applies owned offsets once '..edition)
    T.eq(wrappers,1);T.eq(paints,1);Health.draw=old
    -- Actual native particle draw, with a separate inverse-pixel oracle.
    local Sprites=require('src.core.game3.battle.anim_sprites')
    game.data.constants.gen3BattleAnimGfx={PROBE={image='tests/fixture_data/assets/fixmon_a_front.png',frameWidth=64,frameHeight=64,frames=1}}
    game.data.moves.MOVE_033.anim={duration=8,events={{at=0,sheet='PROBE',x=-30,y=20,target=true,subpriority=40,priority=2}}}
    b.gen3Anim=require('src.battle.Gen3MoveAnim').new(game.data)
    T.eq(A.launchMove(33),true)
    local particles=g.newCanvas(240,160,{format='rgba8',dpiscale=1,msaa=0})
    local nativePool=Sprites._pool;T.eq(#nativePool,1)
    local particle=nativePool[1];local event=b.gen3Anim.events[1]
    require('src.render.Assets').image(game.data.constants.gen3BattleAnimGfx.PROBE.image):setFilter('nearest','nearest')
    local function drawParticle()return b.gen3Anim:drawEvent(event,b,Native,require('src.render.Assets'))end
    local nativeParticle=frame(particles,drawParticle)
    T.check(nativeParticle:find(string.char(255,0,91,255),1,true)~=nil,'actual native particle uses the asymmetric imported sheet')
    particle.x,particle.y=particle.x+13,particle.y+5
    local translated=remap(nativeParticle,240,160,function(x,y)return x-13,y-5 end)
    same(frame(particles,drawParticle),translated,'particle projection retains native pixels '..edition)
    particle.x,particle.y=particle.x-13,particle.y-5
    local cx=particle.x;particle.scaleX=-1
    local flipped=remap(nativeParticle,240,160,function(x,y)return 2*cx-x,y end)
    same(frame(particles,drawParticle),flipped,'particle reflection preserves authored orientation '..edition)
    particle.scaleX=1;same(frame(particles,drawParticle),nativeParticle,'clearing particle projection restores native pixels '..edition)
    b.gen3AnimPlaying=false;T.eq(#Sprites._pool,0);T.eq(particle.active,false,'retired native events leave no visible source rows')
    particles:release()
    local Trainer=require('src.core.game3.trainer_pic');local Host=require('src.mods.Runtime')
    game.data.constants.gen3TrainerFront={[135]='tests/fixture_data/assets/fixmon_a_front.png'}
    game.data.constants.gen3TrainerBack={player={boy=2},images={[2]='tests/fixture_data/assets/fixmon_a_front.png'},anims={[2]={throw={{1,2}}}}}
    Host.currentMod='portrait_owner';local portrait=assert(Trainer.front(135));Host.currentMod=nil
    T.eq(portrait.w,64);T.eq(portrait.h,64);T.eq(Trainer.front(135),portrait);T.eq(Trainer.front(136),nil)
    local portraitPixels=frame(canvas,function()g.draw(portrait.image,20,20)end)
    same(portraitPixels,baseline,'owned trainer artwork retains native source pixels '..edition)
    local back=assert(Trainer.back(0));T.eq(back.frames,1)
    local program=Trainer.backAnims(0);program.throw[1][2]=9
    T.eq(game.data.constants.gen3TrainerBack.anims[2].throw[1][2],2,'trainer animation queries detach native records')
    require('src.core.game3.asset_stream').cancelOwner('unrelated_portrait_owner')
    T.eq(pcall(portrait.image.getDimensions,portrait.image),true,'foreign owner cleanup retains the live trainer texture')
    collectgarbage('collect')
    require('src.core.game3.asset_stream').cancelOwner('portrait_owner')
    T.eq(pcall(portrait.image.getDimensions,portrait.image),false,'unloading releases only the owned trainer image')
    same(frame(canvas,draw),baseline,'retiring trainer artwork preserves the native battler texture '..edition)
    texture:release()
    canvas:release();preview:release();game.stack.states={};f.close();A.reset();Battle._service.release()
  end
  outerShader:release();T.finish()
  local report={passed=true,checks=T.checks,comparisons=comparisons,readbacks=readbacks,
    backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,
    nativeBattleSource=nativeSource,engineRoot=root,syntheticBattlerArt=true,nestedNativeText=true,nativePanels=true,nativeParticleProjection=true,nativeTrainerOwnership=true,nativeHealthboxOffsets=true,
    playerProfilesUsed=false,originalModLoaded=false,gameplayProven=false}
  local file=assert(io.open(assert(os.getenv('BATTLE_SOURCE_REPORT')),'w'))
  file:write(require('src.link.Json').encode(report));file:close();love.event.quit(0)
end
