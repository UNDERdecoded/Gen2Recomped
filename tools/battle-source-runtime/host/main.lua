io.stdout:setvbuf('no')
local root=assert(os.getenv('BATTLE_SOURCE_ENGINE'))
-- Keep the absolute frozen engine first when the SDK checks for its Lua
-- package-path sentinel. Relative fixture IO runs from that same engine.
package.path=root..'/?.lua;'..root..'/?/init.lua;./?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
  local T=require('tests.harness').suite('native battle source GPU')
  local g=love.graphics
  local Battle=require('src.core.game3.battle')
  local Ui=require('src.core.game3.battle.ui')
  local Bg=require('src.core.game3.battle.bg')
  local baseDraw,uiDraw,bgDraw=Battle.draw,Ui.draw,Bg.draw
  local nativeBattleSource=debug.getinfo(require('src.battle.BattleState').update,'S').source
  T.eq(nativeBattleSource,'@'..root..'/src/battle/BattleState.lua','native battle code comes from the frozen engine')
  local renderer,version,vendor,device=g.getRendererInfo()
  local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
  T.check(renderer:lower():find(backend,1,true)~=nil,'requested actual GPU backend')
  T.eq(love.filesystem.getIdentity(),os.getenv('POKEPORT_IDENTITY'),'owned QA profile')
  -- Owned asymmetric art makes battler draws visible; no missing-image
  -- fallback may stand in for either Pokemon picture in this test.
  love.filesystem.createDirectory('tests/fixture_data/assets')
  for side,name in ipairs{'back','front'}do
    local pixels=love.image.newImageData(64,64)
    pixels:mapPixel(function(x,y)
      if x<7 or y<5 or x>56 or y>57 then return 0,0,0,0 end
      if y<20 and x<37 then return 1,0,91/255,1 end
      if x>40 and y>35 then return 0,1,125/255,1 end
      return side==1 and .2 or .7,.3,side==1 and .9 or .1,1
    end)
    pixels:encode('png','tests/fixture_data/assets/fixmon_a_'..name..'.png');pixels:release()
  end
  local readbacks,comparisons=0,0
  local function read(canvas)
    local data=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
    local bytes=data:getString();data:release();readbacks=readbacks+1;return bytes
  end
  local function frame(canvas,fn)
    g.push('all');g.setCanvas(canvas);g.origin();g.setShader();g.setScissor();g.clear(0,0,0,0)
    g.setColor(1,1,1,1);fn();g.pop();return read(canvas)
  end
  local function same(a,b,label)comparisons=comparisons+1;T.eq(a,b,label)end
  for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
    local f=require('tools.battle-source-runtime.fixture').new(edition)
    local game=f.game;package.loaded['src.core.Game']=game
    game.data.constants=game.data.constants or{}
    game.data.constants.speciesOrder={[4]='CHARMANDER'}
    game.data.constants.moveOrder={[33]=f.ids.TACKLE}
    local b=f.fresh('TACKLE').battle
    game.stack:push(b);b.phase='menu';b.queue={};b.current=nil
    b.showPlayerBack,b.showEnemyTrainer=false,false;b.frlgIntro=nil;b.introSlide=0
    local canvas=g.newCanvas(240,160,{format='rgba8',dpiscale=1,msaa=0})
    local baseline=frame(canvas,function()b:_drawNative()end)
    T.check(baseline:find(string.char(255,0,91,255),1,true)~=nil,'asymmetric fixture pixels reach the native GPU frame')
    local sourceCalls,uiCalls,backgroundCalls=0,0,0
    Battle.draw=function(view,w,h)sourceCalls=sourceCalls+1;T.eq(w,240);T.eq(h,160);return baseDraw(view,w,h)end
    Ui.draw=function(w,h)uiCalls=uiCalls+1;return uiDraw(w,h)end
    Bg.draw=function(...)backgroundCalls=backgroundCalls+1;return bgDraw(...)end
    same(frame(canvas,function()b:draw()end),baseline,'wrapped native battle pixels match native rendering '..edition)
    T.eq(sourceCalls,1);T.eq(uiCalls,1);T.eq(backgroundCalls,1)
    Bg.draw=function()
      g.setColor(.4,.1,.7,1);g.rectangle('fill',0,0,240,160);return true
    end
    local replaced=frame(canvas,function()b:draw()end)
    T.check(replaced~=baseline,'background replacement reaches actual GPU pixels')
    -- Native text/menu pass still owns the opaque bottom rows.
    same(replaced:sub(240*128*4+1),baseline:sub(240*128*4+1),'native command UI survives background replacement '..edition)
    local before=Battle.getState();T.eq(before,Battle.getState())
    T.eq(before.player.mon.hp,b.player.mon.hp)
    local bound=g.getCanvas();local depth=g.getStackDepth and g.getStackDepth()
    Battle.draw=function()g.push();g.setCanvas(canvas);error('owned GPU callback failure')end
    local ok,why=pcall(b.draw,b);T.eq(ok,false);T.check(tostring(why):find('owned GPU callback failure',1,true)~=nil)
    T.eq(g.getCanvas(),bound);if depth then T.eq(g.getStackDepth(),depth)end
    Battle.draw,Ui.draw,Bg.draw=baseDraw,uiDraw,bgDraw
    local rendererState=require('src.render.Renderer')
    local captures=0
    Bg.draw=function(...)captures=captures+1;return bgDraw(...)end
    rendererState.frameSerial=(rendererState.frameSerial or 0)+1
    same(frame(canvas,function()baseDraw(game);b:draw()end),baseline,'captured battle keeps native pixels '..edition)
    T.eq(captures,1,'capture and screen share one native field draw')
    rendererState.frameSerial=rendererState.frameSerial+1
    same(frame(canvas,function()uiDraw();b:draw()end),baseline,'UI capture keeps native pixels '..edition)
    T.eq(captures,2,'UI capture and screen share one native field draw')
    rendererState.frameSerial=rendererState.frameSerial+1
    same(frame(canvas,function()b:draw()end),baseline,'next frame draws the native battle again '..edition)
    T.eq(captures,3,'capture suppression ends at the next renderer frame')
    rendererState.frameSerial=rendererState.frameSerial+1
    local preview=g.newCanvas(240,160,{format='rgba8',dpiscale=1,msaa=0})
    same(frame(canvas,function()
      g.setCanvas(preview);baseDraw(game);g.setCanvas(canvas);b:draw()
    end),baseline,'offscreen capture cannot suppress the main battle surface '..edition)
    T.eq(captures,5,'different render targets each receive their own native field pass')
    preview:release();Bg.draw=bgDraw
    game.stack:pop();Battle.reset();canvas:release();f.close();require('src.core.Game3').release()
  end
  T.finish()
  local report={passed=true,checks=T.checks,readbacks=readbacks,comparisons=comparisons,
    backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,
    playerProfilesUsed=false,gameplayProven=false,originalModLoaded=false,
    syntheticBattlerArt=true,
    engineRoot=root,nativeBattleSource=nativeBattleSource,
    scope='Actual native BattleState and Gen3Battle draws over synthetic imported Pokemon; five GBA editions. Source/UI/background wrappers and GPU error restoration; no original-mod boot or gameplay claim.'}
  local file=assert(io.open(assert(os.getenv('BATTLE_SOURCE_REPORT')),'w'))
  file:write(require('src.link.Json').encode(report));file:close()
  print('NATIVE_BATTLE_SOURCE_GPU_PASS',readbacks,comparisons);love.event.quit(0)
end
