package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local G=require('src.core.Game3')
local R=require('src.core.game3.runtime')
local F=require('tools.session-runtime.fixture')
local Fixed=require('src.core.FixedStep')
local Touch=require('src.core.TouchControls');Touch.pollTouches=function()end
local baseUpdate,baseDraw,baseBoot,baseReset,baseFixed=G.update,G.draw,G._handleBootAction,G.reset,G.fixedUpdate
local baseGC=G.stepGC
local Music=require('src.core.Music');local music=Music.update;local audio=0
Music.update=function()audio=audio+1 end
local Tilt=require('src.render.Tilt');local tilt=Tilt.update;Tilt.update=function()end
local Pipes=require('src.render.Pipelines');local pipes=Pipes.update;Pipes.update=function()end
local discord=package.loaded['src.core.DiscordPresence'];package.loaded['src.core.DiscordPresence']={update=function()end}
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 R.release();G.release();local f=F.new(edition);local native=f.game;local view=G.forNative(native)
 local stick,speed=native.updateCameraStick,native.logicSpeed
 native.updateCameraStick=function()end;native.logicSpeed=function()return 1 end
 Fixed:init(function(dt)native:step(dt)end)
 local gc,wrapped=0,0
 G.stepGC=function()gc=gc+1 end
 G.update=function(game,dt)
  wrapped=wrapped+1;T.eq(game,view,'real native frame enters the source facade')
  baseUpdate(game,dt);baseUpdate(game,dt)
 end
 local clock=native.save.playTime;local oldAudio=audio
 native:update(1/60)
 T.eq(wrapped,1);T.eq(f.nativeUpdates,1);T.eq(f.inputSteps,1)
 T.eq(native.save.playTime,clock+1/60);T.eq(audio,oldAudio+1,'audio retains its native real-time owner')
 T.eq(gc,1,'source collector seam replaces the single native GC step')
 G.update=function()wrapped=wrapped+1 end
 native:update(1/60)
 T.eq(wrapped,2);T.eq(f.nativeUpdates,1);T.eq(audio,oldAudio+1);T.eq(gc,1,'a held source frame never runs a hidden second base')
 G.update=baseUpdate
 native.updateCameraStick,native.logicSpeed=stick,speed
 -- Exact forwarding of nil-bearing results through captured native methods.
 local draws=0
 G.draw=function(game,...)T.eq(game,view);return baseDraw(game,...)end
 local a,b,c=G._dispatch('draw',native,function(owner,n)
  draws=draws+1;T.eq(owner,native);return n,nil,n+1
 end,17)
 T.eq(a,17);T.eq(b,nil);T.eq(c,18);T.eq(draws,1)
 G.draw=function(game)
  baseDraw(game,4);return baseDraw(game,99)
 end
 a,b,c=G._dispatch('draw',native,function(_,n)draws=draws+1;return n,nil,n+1 end)
 T.eq(a,4);T.eq(b,nil);T.eq(c,5);T.eq(draws,2,'repeated base calls retain the first native results')
 G.draw=function()error('intentional facade failure')end
 T.raises(function()G._dispatch('draw',native,function()error('unexpected native draw')end)end,'intentional facade failure')
 G.draw=function(game)return baseDraw(game,3)end
 T.eq(G._dispatch('draw',native,function(_,n)return n end),3,'failure cannot leak an active dispatch scope')
 G.draw=baseDraw
 -- A source wrapper may catch an error for cleanup, but cannot hide or
 -- retry a failing native body and report the frame as successful.
 local attempts=0
 G.draw=function(game)
  T.eq(pcall(baseDraw,game),false)
  T.eq(pcall(baseDraw,game),false)
  return 'caught'
 end
 T.raises(function()G._dispatch('draw',native,function()attempts=attempts+1;error('intentional native body failure')end)end,'intentional native body failure')
 T.eq(attempts,1);G.draw=baseDraw
 -- Exercise callbacks created by the actual native title factory. Only the
 -- screen constructor and disk reader are replaced with synthetic fixtures.
 local Screens=require('src.ui.Screens');local get=Screens.get
 local callbacks
 Screens.get=function()return {new=function(game,cb)T.eq(game,native);callbacks=cb;return {}end}end
 native:makeTitleState();Screens.get=get
 local new,continue=native.newGame,native.continueGame
 local boots=0;local loaded={synthetic=true};local pending
 native.newGame=function(owner)T.eq(owner,native);boots=boots+1;return 'new',nil,7 end
 native.continueGame=function(owner,value,recovered)
  T.eq(owner,native);T.eq(value,loaded);T.eq(recovered,true);boots=boots+1;return 'continued',nil,9
 end
 G._handleBootAction=function(game,action)pending={game,action}end
 callbacks.onNewGame();T.eq(boots,0,'source intro can defer the actual native new-game action')
 a,b,c=baseBoot(pending[1],pending[2]);T.eq(a,'new');T.eq(b,nil);T.eq(c,7);T.eq(boots,1)
 baseBoot(pending[1],pending[2]);T.eq(boots,1,'one title action can be adopted only once')
 local Save=require('src.core.SaveData');local load=Save.load
 Save.load=function()return loaded,true end
 callbacks.onContinue();T.eq(boots,1)
 a,b,c=baseBoot(pending[1],pending[2]);T.eq(a,'continued');T.eq(c,9);T.eq(boots,2)
 callbacks.onContinue();local stale=pending
 native.save={player=native.save.player,playTime=0,options={}}
 T.eq(baseBoot(stale[1],stale[2]),nil);T.eq(boots,2,'a save change retires an unconsumed intro action')
 Save.load=load;native.newGame,native.continueGame=new,continue
 G._handleBootAction=baseBoot;G.stepGC=baseGC
 -- A new mod loader on the same native Game cannot keep the old facade,
 -- deferred queue or source cleanup owner alive.
 local oldLoader=native.mods;local reset=0
 G.reset=function(game)reset=reset+1;T.eq(game.mods,oldLoader);return baseReset(game)end
 native.mods={exports={another=true}}
 local replacement=G.forNative(native)
 T.check(replacement~=view);T.eq(replacement.mods,native.mods);T.eq(reset,1)
 T.eq(G.native(view),nil)
 G.reset=baseReset
end
G.stepGC=baseGC;G.update=baseUpdate;G.draw=baseDraw
-- Importing and wrapping the source facade cannot redirect other generations.
for _,edition in ipairs({'gold','silver','crystal'})do
 R.release();G.release();local f=F.new(edition);local calls=0
 G.fixedUpdate=function()calls=calls+1;error('source fixed step reached a native generation')end
 local clock=f.game.save.playTime
 f.game:_step(1/60)
 T.eq(calls,0);T.eq(f.nativeUpdates,1);T.eq(f.game.save.playTime,clock+1/60)
 T.eq(G.forNative(f.game),nil);T.eq(R.isActive(),false)
end
G.fixedUpdate=baseFixed
Music.update=music;Tilt.update=tilt;Pipes.update=pipes
package.loaded['src.core.DiscordPresence']=discord
T.finish('native Game3 frame dispatch, delayed title adoption and generation isolation')
