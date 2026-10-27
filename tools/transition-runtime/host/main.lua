io.stdout:setvbuf('no')
local root=assert(os.getenv('TRANSITION_ENGINE'));local baseline=assert(os.getenv('TRANSITION_BASELINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
  local g=love.graphics;local renderer,version,vendor,device=g.getRendererInfo()
  local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'));assert(renderer:lower():find(backend,1,true))
  local identity=assert(os.getenv('POKEPORT_IDENTITY'));assert(love.filesystem.getIdentity()==identity)
  local T=require('tests.harness').suite('native transition GPU bridge')
  local Source=require('src.core.game3.battle_transition')
  local Native=require('src.render.BattleTransition');local Renderer=require('src.render.Renderer')
  local Old=assert(loadfile(baseline..'/src/render/BattleTransition.lua'))()
  local V=require('src.core.GameVersion');local Stack=require('src.core.StateStack')
  local readbacks,cases=0,0
  local function read(canvas)
    local data=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
    local bytes=data:getString();data:release();readbacks=readbacks+1;return bytes
  end
  local function canvas(w,h)return g.newCanvas(w,h,{format='rgba8',dpiscale=1,msaa=0})end
  local function pattern(c,mirror)
    local w,h=c:getDimensions();g.push('all');g.origin();g.setCanvas(c);g.setShader();g.setScissor();g.setBlendMode('replace','premultiplied')
    g.clear(.13,.2,.37,1)
    for y=0,h-1 do
      local row=mirror and h-y-1 or y
      g.setColor((row%17)/17,(math.floor(row/17)%13)/13,(row%29)/29,1);g.rectangle('fill',0,y,w,1)
    end
    g.setColor(1,.1,.2,1);g.rectangle('fill',0,mirror and h-7 or 0,w,7)
    g.setColor(.1,.2,1,1);g.rectangle('fill',0,mirror and 0 or h-7,w,7);g.pop()
  end
  local function copy(a,b)
    g.push('all');g.origin();g.setCanvas(b);g.setShader();g.setScissor();g.setColor(1,1,1,1)
    g.setBlendMode('replace','premultiplied');g.draw(a,0,0);g.pop()
  end
  for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
    V.set(edition);Source.release()
    local game={data={maps={}},save={},mods={},renderer={}}
    game.stack=setmetatable({states={{isOverworld=true}}},{__index=Stack});package.loaded['src.core.Game']=game
    local styles={};local seen={}
    for _,style in pairs(require('src.compat.gen1.TransitionCatalog').new(edition).styles)do
      if not seen[style]and not Native.STYLES[style].draw then seen[style]=true;styles[#styles+1]=style end
    end
    table.sort(styles)
    for _,style in ipairs(styles)do
      local state=Native.new(game,nil,{style=style});game.stack:push(state)
      local old=Old.new(game,nil,{})
      old.style,old.def,old.wipeLen=state.style,state.def,state.wipeLen
      for _,size in ipairs({{240,160},{320,200},{480,320}})do
        local w,h=size[1],size[2];local source=canvas(w,h);pattern(source)
        local original=read(source);local expected,actual=canvas(w,h),canvas(w,h)
        for _,frame in ipairs({0,1,math.floor(state.wipeLen/2),state.wipeLen-1,state.wipeLen})do
          state.phase,old.phase='wipe','wipe';state.t,old.t=frame,frame
          state.frame=frame
          copy(source,expected);copy(source,actual)
          local packet={};game.renderer=packet
          g.push('all');g.origin();g.setCanvas(expected);g.setShader();g.setScissor();g.setBlendMode('alpha','alphamultiply')
          old:draw()
          if packet.battleWipe then Renderer.drawBattleWipe(packet,packet.battleWipe,w,h,math.floor((w-240)/2),math.floor((h-160)/2),240,160,1,1,source)end
          if packet.screenVeil then local v=packet.screenVeil;g.setColor(v[1],v[1],v[1],v[2]);g.rectangle('fill',0,0,w,h)end
          g.pop()
          g.push('all');g.origin();g.setCanvas(actual);g.setShader();g.setBlendMode('alpha','alphamultiply')
          T.eq(Source.drawWorld(actual,w,h),true);g.pop()
          T.eq(read(actual),read(expected),edition..' '..style..' '..w..'x'..h..' frame '..frame)
          cases=cases+1
        end
        T.eq(read(source),original,'native world inputs remain unchanged')
        source:release();expected:release();actual:release()
      end
      state:complete(false);collectgarbage('collect')
    end
    -- Explicitly marked legacy orientation is normalized once before hooks.
    local state=Native.new(game,nil,{style=require('src.compat.gen1.TransitionCatalog').new(edition).styles[8]})
    game.stack:push(state);state.phase='wipe';state.t=7;state.frame=7
    local upright,mirrored,expected=canvas(320,200),canvas(320,200),canvas(320,200)
    pattern(upright);pattern(mirrored,true);copy(upright,expected)
    g.push('all');g.setBlendMode('alpha','alphamultiply');Source.drawWorld(expected,320,200);g.pop()
    local r={worldOverride=mirrored,worldOverrideMirrored=true,setWorldOverride=Renderer.setWorldOverride}
    g.push('all');g.setBlendMode('alpha','alphamultiply');T.eq(Source._compositeWorld(r),true);g.pop()
    T.eq(read(r.worldOverride),read(expected),'one explicit orientation correction')
    local owned=r.worldOverride
    local negative={worldOverride=mirrored,worldOverrideMirrored=false,setWorldOverride=Renderer.setWorldOverride}
    Source._compositeWorld(negative)
    T.check(read(negative.worldOverride)~=read(expected),'orientation negative must distinguish the fixture')
    Source.release();T.raises(function()owned:getDimensions()end,'released','owned transition targets retire')
    T.eq(mirrored:getWidth(),320,'borrowed input survives teardown')
    game.stack:pop();upright:release();mirrored:release();expected:release()
  end
  T.finish()
  local result={status='pass',checks=T.checks,frameComparisons=cases,readbacks=readbacks,backend=backend,renderer=renderer,version=version,vendor=vendor,device=device,
    identity=identity,playerProfilesUsed=false,originalTaskParity=false,fullRendererAcceptance=false}
  local f=assert(io.open(assert(os.getenv('TRANSITION_OUT'))..'/result.json','w'));f:write(require('src.link.Json').encode(result));f:close()
  print('GPU transition pass',cases,readbacks);love.event.quit(0)
end
