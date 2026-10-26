-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local _,imageFile=require('tools.sprite-runtime.cpu-gpu').install(love)
local Source=require('src.core.game3.field_move_show_mon')
local Native=require('src.world.Gen3FieldMove')
local Host=require('src.mods.Runtime')
local Renderer=require('src.render.Renderer')
T.eq(Source.isActive(),false,'requiring the bridge does not invent a native admission')
local saved={start=Source.start,step=Source.step,draw=Source.draw}
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  Source.release()
  local fixture=require('tools.session-runtime.fixture').new(edition)
  local game=fixture.game;local stack=game.stack
  game.data.pokemon={[1]={name='TEST',spriteFront='assets/generated/field-mon.png'}}
  imageFile('assets/generated/field-mon.png',16,16,string.rep(string.char(17,31,47,255),256))
  local completions=0
  local mon={species=1}
  local starts,steps,draws=0,0,0
  Source.start=function(...)starts=starts+1;return saved.start(...)end
  Source.step=function(...)steps=steps+1;local a,b=saved.step(...);saved.step(...);return a,b end
  Source.draw=function(...)draws=draws+1;local a,b=saved.draw(...);saved.draw(...);return a,b end
  local shown,state=Native.show(game,mon,function()completions=completions+1;return 'continued',nil,7 end)
  T.eq(shown,true);T.eq(starts,1,'native entry reaches the existing public start wrapper once')
  local theme=require('src.ui.Theme');local previousBox=theme.textBox
  for _,box in ipairs{{tx=0,ty=0,tw=20,th=18},{tx=0,ty=0,tw=32,th=24}}do
    theme.textBox=box
    local width,height=state:uiSize();T.eq(width,240,'dialogue themes cannot resize a native field cut-in');T.eq(height,160)
  end
  theme.textBox=previousBox
  T.eq(Source.isActive(),true);T.eq(fixture.player.fieldMove,true)
  T.eq(Native.show(game,mon),false,'one native field-move admission cannot overlap another')
  Source.release();T.eq(Source.isActive(),true,'observer teardown preserves an engine-owned field move')
  local retained=state.onDone
  T.eq(retained(),false,'a retained callback cannot finish before its native admission')
  T.eq(completions,0)
  local before=state.t;saved.step();T.eq(state.t,before,'source calls outside the phase cannot advance native logic')
  stack:update(1/60);T.eq(state.t,before+1,'duplicate base calls advance the real native tick once')
  T.eq(steps,1)
  local age=state.frame
  Renderer.frameSerial=(Renderer.frameSerial or 0)+1
  state:draw();T.eq(state.frame,age,'native drawing cannot advance animation')
  T.eq(draws,1)
  local cover={};stack:push(cover)
  T.eq(state:finish(),false,'covered field moves cannot pop another native screen')
  state:update();T.eq(state.t,before+1,'direct updates cannot advance a covered admission')
  T.eq(stack:top(),cover);stack:pop()
  for i=1,100 do stack:update(1/60)end
  T.eq(completions,1,'real native completion calls the pending callback once')
  T.eq(Source.isActive(),false);T.eq(state.sprite,nil,'native exit releases its owned image')
  T.eq(fixture.player.fieldMove,nil);T.eq(fixture.player.fieldMovePose,nil)
  local a,b,c=retained();T.eq(a,'continued');T.eq(b,nil);T.eq(c,7);T.eq(completions,1,'retained callbacks cannot replay')
  Source.start=saved.start;Source.step=saved.step;Source.draw=saved.draw
  Host.currentMod='source-owner'
  T.eq(Source.start(1,{pose=false},function()completions=completions+1 end),true)
  Host.currentMod=nil
  state=stack:top();T.eq(state.player,nil,'source pose=false does not change the native player')
  local cancelCallback=state.onDone
  local payload=setmetatable({},{__mode='v'})
  do
    local held={};payload[1]=held
    Source.reset()
    Host.currentMod='source-owner'
    Source.start(1,{pose=true},(function(value)return function()return value end end)(held))
    Host.currentMod=nil
  end
  state=stack:top();local heldCallback=state.onDone
  stack:push(cover);Source.cancelOwner('source-owner')
  T.eq(stack:top(),cover,'owner retirement preserves a covering native screen')
  T.eq(Source.isActive(),false);T.eq(fixture.player.fieldMove,nil)
  collectgarbage('collect');collectgarbage('collect')
  T.eq(payload[1],nil,'even peer-held wrappers release cancelled callback captures')
  T.eq(heldCallback(),false);T.eq(cancelCallback(),false)
  stack:pop();stack:update(1/60);T.eq(stack:top(),fixture.world,'cancelled covered admission retires when uncovered')
  local count=completions
  Native.show(game,mon,function()completions=completions+1 end)
  state=stack:top();local stale=state.onDone
  local oldSave=setmetatable({game.save},{__mode='v'})
  game.save={};state:update()
  T.eq(stack:top(),fixture.world,'save replacement retires the exact native admission')
  T.eq(stale(),false);T.eq(completions,count)
  collectgarbage('collect');collectgarbage('collect')
  T.eq(oldSave[1],nil,'peer-held callbacks cannot retain an entire retired save cohort')
  Native.show(game,mon,function()error('deliberate continuation error')end)
  state=stack:top();local failed=state.onDone
  T.raises(function()state:finish()end,'deliberate continuation error','callback failure remains observable')
  T.raises(failed,'deliberate continuation error','retained callback preserves error without replay')
  T.eq(stack:top(),fixture.world);T.eq(state.sprite,nil)
  -- The normal draw and an explicit source draw share one render admission.
  Native.show(game,mon,nil,{pose=false});state=stack:top()
  state.phase='in';state.t=1
  local rectangles=0;local rectangle=love.graphics.rectangle
  love.graphics.rectangle=function(...)rectangles=rectangles+1;return rectangle(...)end
  Renderer.frameSerial=(Renderer.frameSerial or 0)+1
  saved.draw();local external=rectangles
  T.check(external>0,'explicit source draw paints the actual native effect')
  state:draw();T.eq(rectangles,external,'native UI does not paint the same externally drawn cut-in again')
  Renderer.frameSerial=Renderer.frameSerial+1
  state:draw();T.check(rectangles>external,'a following frame retains the ordinary native draw')
  love.graphics.rectangle=rectangle
  state:cancel()
  local nested,again,invocations
  invocations=0
  Native.show(game,mon,function()invocations=invocations+1;nested=again();return 'native-result'end)
  state=stack:top()
  again=state.onDone
  -- Reentrant continuations retain the already-executing guard, not a new
  -- native admission or a second callback execution.
  state:finish();T.eq(nested,false);T.eq(invocations,1);T.eq(again(),'native-result')
  game.data.pokemon[2]={name='REPLACEMENT',spriteFront='assets/generated/field-mon-two.png'}
  imageFile('assets/generated/field-mon-two.png',16,16,string.rep(string.char(91,73,53,255),256))
  Source.start=function(_,_,callback)return saved.start({species=2},{pose=false},callback)end
  local changed
  Native.show(game,mon,function()changed=true end)
  state=stack:top();T.eq(state.mon.species,2,'native start wrappers configure the actual admitted Pokemon')
  T.eq(state.player,nil,'native start wrappers can disable their native pose')
  T.eq(state.spritePath,'assets/generated/field-mon-two.png','configured picture uses the native art resolver')
  state:finish();T.eq(changed,true)
  Source.start=function()return false end
  T.eq(Native.show(game,mon,function()error('vetoed field move continued')end),false,'explicit native start veto retires its provisional admission')
  T.eq(stack:top(),fixture.world);T.eq(fixture.player.fieldMove,nil)
  Source.start=saved.start
  Host.currentMod='completed-owner';Source.start(1,{},function()return {}end);Host.currentMod=nil
  state=stack:top();local completedCallback=state.onDone
  state:finish();T.eq(type(completedCallback()),'table')
  Source.cancelOwner('completed-owner');T.eq(completedCallback(),false,'retired source callbacks cannot replay cached results')
  T.eq(Source.start(1,{noDuck=true}),false,'unimplemented cry options are not silently accepted')
  T.eq(Source.start({},{}),false,'missing real picture cannot create a fake successful effect')
end
Source.release();T.finish('native field-move admission, one clock, explicit draw and continuation lifetime')
