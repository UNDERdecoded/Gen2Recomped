package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Source=require('src.core.game3.field_move_show_mon')
T.eq(package.loaded['src.core.Game'],nil);T.eq(Source.isActive(),false)
love=require('tests.love_stub')
local read,imageFile,created=require('tools.sprite-runtime.cpu-gpu').install(love)
local makeImage=love.graphics.newImage
love.graphics.newImage=function(value,...)
 if type(value)=='string'then
  local data=love.image.newImageData(value);local image=makeImage(data,...);data:release();return image
 end
 return makeImage(value,...)
end
local Native=require('src.world.Gen3FieldMove')
local Host=require('src.mods.Runtime')
local base={start=Source.start,step=Source.step,draw=Source.draw}
local function fixture(edition)
 Source.release()
 local f=require('tools.session-runtime.fixture').new(edition);local g=f.game
 g.data.pokemon={TEST={spriteFront='field-test-front.png',name='TEST',trueColor=true}}
 g.data.constants.speciesOrder={[1]='TEST'};imageFile('field-test-front.png',64,64,string.rep('\255',64*64*4))
 local strip={width=256,height=80,indexed=string.rep('\1',256*80),palette={}}
 for i=1,16 do strip.palette[i]=i*37 end
 g.data.constants.gen3FieldMovePresentation={schema=1,edition=edition,romSha1=require('src.core.GameVersion').info(edition).sha1,strips={outdoors=strip,indoors=strip}}
 Source._observeMod('field-owner');g.mods.exports['field-owner']={}
 return f
end
local nativeCry=require('src.core.Sound').playCry
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 local f=fixture(edition);local g=f.game;local calls,starts,steps,cries=0,0,0,{}
 local guard
 require('src.core.Sound').playCry=function(_,species,opts)cries[#cries+1]={species,opts}end
 Source.start=function(mon,opts,done)
  starts=starts+1;guard=done;done()
  local ok=base.start(mon,opts,function()done();done()end);base.start(mon,opts,done);return ok
 end
 Source.step=function()steps=steps+1;local result=base.step();base.step();return result end
 Host.currentMod='field-owner'
 T.eq(Native.show(g,{species='TEST'},function()calls=calls+1 end),true);Host.currentMod=nil
 local state=g.stack:top();T.eq(getmetatable(state),Native);T.eq(starts,1);T.eq(calls,0,'premature source callback cannot run the HM continuation')
 T.eq(Source._fx.phase,'pose');local metadata=Source._fx;metadata.phase=99;T.eq(Source._fx.phase,'pose')
 Source.step();Source.step();T.eq(state.frame,0,'arbitrary source ticks cannot drive the state')
 local beforeSteps=steps
 local modal={};g.stack:push(modal);state:update();T.eq(state.frame,0)
 Host.currentMod='field-peer';T.eq(Source.reset(),false);Host.currentMod=nil
 T.eq(g.stack:top(),modal,'covered reset cannot pop another screen');g.stack:pop()
 local ticks=0
 while Source.isActive()and ticks<256 do g.stack:update(1/60);ticks=ticks+1 end
 T.check(ticks<256);T.eq(calls,1);T.eq(#cries,1);T.eq(cries[1][1],'TEST');T.eq(g.stack:top(),f.world)
 T.eq(f.player.fieldMove,nil);T.eq(f.player.fieldMovePose,nil);T.eq(f.player._gen3FieldMovePoseOwner,nil)
 T.eq(steps-beforeSteps,ticks);guard();guard();T.eq(calls,1)
 local after=state.frame;state:update();T.eq(state.frame,after)
 T.eq(Source._fx,nil)
 Source.start=base.start;Source.step=base.step
 Host.currentMod='source-owner';T.eq(Source.start({species=1,isShiny=true},{pose=false,noDuck=true},function()calls=calls+1 end),true);Host.currentMod=nil
 state=g.stack:top();T.eq(Source._fx.shiny,true);T.eq(Source._fx.species,1);T.eq(Source._fx.phase,1)
 T.eq(f.player.fieldMove,nil,'a no-pose request leaves the native pose alone')
 while Source.isActive()do g.stack:update(1/60)end
 T.eq(calls,2);T.eq(cries[2][2].noDuck,true);T.eq(cries[2][2].volume,125)
 Host.currentMod='source-owner';T.eq(Source.start(1,{pose=true}),true);Host.currentMod=nil
 local abandoned=g.stack:top();local owned=abandoned.sprite
 Source.cancelOwner('another-owner');T.eq(Source.isActive(),true)
 local cover={};g.stack:push(cover)
 Source.cancelOwner('source-owner');T.eq(g.stack:top(),cover);g.stack:pop();T.eq(Source.isActive(),false);T.eq(abandoned.completed,false)
 T.check(not pcall(owned.getWidth,owned));T.eq(calls,2)
 T.eq(Native.show(g,{species='TEST'},function()calls=calls+1 end),true)
 state=g.stack:top();local wrappedNative=state.onDone
 state.onDone=function()return wrappedNative()end
 Source.release()
 while not state.done do g.stack:update(1/60)end
 T.eq(calls,3,'detaching observers preserves a native HM continuation')
 T.eq(Native.show(g,{species='TEST'},function()calls=calls+1 end),true)
 state=g.stack:top();g.save={};state:update();T.eq(g.stack:top(),f.world)
 T.eq(calls,3,'a retired save cannot receive the old continuation')
 T.eq(state.done,true)
 T.eq(Native.show(g,{species='TEST'},function()calls=calls+1 end),true)
 state=g.stack:top();local admittedStack=g.stack;local foreign={}
 g.stack=setmetatable({states={foreign}},{__index=require('src.core.StateStack')})
 T.eq(Source.isActive(),false);state:update()
 T.eq(g.stack:top(),foreign,'retiring an old admission cannot remove a foreign screen')
 T.eq(#admittedStack.states,1,'retire the admission from its actual original stack')
 T.eq(calls,3);g.stack=admittedStack
 -- A public sprite replacement cannot transfer ownership of that image.
 f=fixture(edition);g=f.game
 T.eq(Native.show(g,{species='TEST'},nil,{presentation='cartridge',pose=false}),true)
 state=g.stack:top();local original=state.sprite
 local borrowed=love.graphics.newImage(love.image.newImageData('field-test-front.png'));state.sprite=borrowed
 T.eq(state:complete(false),true);T.check(not pcall(original.getWidth,original));T.eq(borrowed:getWidth(),64);borrowed:release()
 -- Preparation failure returns to the caller before locking or pushing.
 g.data.constants.gen3FieldMovePresentation=nil
 T.eq(Source.start(1,{pose=true}),false);T.eq(g.stack:top(),f.world);T.eq(f.player.fieldMove,nil)
 Source.release()
end
-- Held callback observations must not retain a completed battle/field payload.
local f=fixture('emerald');local saved;local weak=setmetatable({},{__mode='v'})
local function launch()
 local payload={large={}};weak[1]=payload
 T.eq(Native.show(f.game,{species='TEST'},function()T.check(payload.large~=nil)end),true)
 saved=f.game.stack:top().onDone
end
launch();while Source.isActive()do f.game.stack:update(1/60)end
collectgarbage('collect');collectgarbage('collect');T.eq(weak[1],nil,'retained callback observations release captured payloads');saved()
Source.release()
T.eq(Native.show(f.game,{species='TEST'}),true)
T.eq(f.game.stack:top().effect,nil,'an inactive cached facade cannot change native field-move presentation')
f.game.stack:top():complete(false)
require('src.core.Sound').playCry=nativeCry
Source.release();Source.start=base.start;Source.step=base.step;Source.draw=base.draw
T.finish('native field-move admissions, clocks and continuations')
