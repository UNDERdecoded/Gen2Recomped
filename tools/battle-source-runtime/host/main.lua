io.stdout:setvbuf('no')
local root=assert(os.getenv('BATTLE_SOURCE_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
  local T=require('tests.harness').suite('native battle source GPU')
  local g=love.graphics
  local Battle=require('src.core.game3.battle')
  local Ui=require('src.core.game3.battle.ui')
  local Bg=require('src.core.game3.battle.bg')
  local baseDraw,uiDraw,bgDraw=Battle.draw,Ui.draw,Bg.draw
  local renderer,version,vendor,device=g.getRendererInfo()
  local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
  T.check(renderer:lower():find(backend,1,true)~=nil,'requested actual GPU backend')
  T.eq(love.filesystem.getIdentity(),os.getenv('POKEPORT_IDENTITY'),'owned QA profile')
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
    game.stack:pop();Battle.reset();canvas:release();f.close();require('src.core.Game3').release()
  end
  T.finish()
  local report={passed=true,checks=T.checks,readbacks=readbacks,comparisons=comparisons,
    backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,
    playerProfilesUsed=false,gameplayProven=false,originalModLoaded=false,
    scope='Actual native BattleState and Gen3Battle draws over synthetic imported Pokemon; five GBA editions. Source/UI/background wrappers and GPU error restoration; no original-mod boot or gameplay claim.'}
  local file=assert(io.open(assert(os.getenv('BATTLE_SOURCE_REPORT')),'w'))
  file:write(require('src.link.Json').encode(report));file:close()
  print('NATIVE_BATTLE_SOURCE_GPU_PASS',readbacks,comparisons);love.event.quit(0)
end
