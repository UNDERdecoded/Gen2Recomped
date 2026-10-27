-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Fade=require('src.ui.game3.fade')
local Layer=require('src.render.FieldFade')
local Transition=require('src.render.Transition')
local Host=require('src.mods.Runtime')
local Stream=require('src.core.game3.asset_stream')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Stream.shutdown();require('src.core.Game3').release()
 local f=require('tools.session-runtime.fixture').new(edition);local g,w=f.game,f.world
 g.mods.mods={fade_owner={enabled=true},peer={enabled=true}}
 local gameUpdate=w.update;w.update=function()error('source fade cannot pump a second field clock')end
 Host.currentMod='fade_owner'
 T.eq(Fade.isActive(),false);T.eq(Fade.t,0)
 local done=0
 T.eq(Fade.begin(Fade.MODE.TO_BLACK,2,function()done=done+1 end),true)
 local owned=g.stack:top();T.eq(getmetatable(owned),Layer)
 T.eq(Fade.lockInput,true);T.eq(Fade._dir,1)
 for step=1,32 do
  g.stack:update(1/60);T.eq(Fade.t,math.floor(step/2),'source palette step follows native fixed ticks')
 end
 T.eq(done,1);T.eq(Fade.t,16);T.eq(Fade.isActive(),false);T.eq(g.stack:top(),owned,'covered palette remains until its owner clears it')
 for _=1,130 do g.stack:update(1/60)end
 T.eq(Fade.t,16,'an owned hold does not trigger the native abandoned-script watchdog')
 Host.currentMod='peer';T.eq(Fade.clear(),false);T.eq(Fade.begin(0,1),false);T.eq(g.stack:top(),owned)
 Host.currentMod='fade_owner';T.eq(Fade.begin(Fade.MODE.FROM_BLACK,1,function()done=done+1 end),true)
 for _=1,16 do g.stack:update(1/60)end
 T.eq(done,2);T.eq(Fade.t,0);T.eq(g.stack:top(),w);T.eq(owned.sourceRetired,true)
 T.eq(Fade.begin(Fade.MODE.TO_WHITE,1,function()done=done+100 end),true)
 local old=g.stack:top();g.renderer={};old:draw();T.check(g.renderer.screenVeil~=nil)
 collectgarbage('collect');Stream.cancelOwner('fade_owner')
 T.eq(g.stack:top(),w);T.eq(g.renderer.screenVeil,nil,'unload releases the owned window veil')
 T.eq(old.sourceRetired,true);T.eq(old.game,nil);old:update(1/60);old:draw();T.eq(done,2)
 -- Native fades remain native, including script runner progress and cleanup.
 w.update=gameUpdate
 local script=Layer.new(g,w,'white');w.fadeOverlay=script
 script.ramp={from=0,to=1,frames=4,t=0}
 g.stack:push(script)
 T.eq(Fade.isActive(),true);T.eq(Fade.mode,3);T.eq(Fade._dir,1)
 T.eq(Fade.clear(),false);T.eq(Fade.begin(0,1),false,'a source request cannot replace a native script fade')
 script.ramp.t=2;script.alpha=.5;T.eq(Fade.t,8)
 g.stack:removeAll({script});T.eq(w.fadeOverlay,nil)
 local warp=Transition.new(g);g.stack:push(warp);warp.t=math.floor(warp.frames/2)
 T.eq(Fade.isActive(),true);T.eq(Fade.t,math.floor(warp:alpha()*16+.5));T.eq(Fade.mode,1)
 warp.phase='in';T.eq(Fade._dir,-1);T.eq(Fade.mode,0)
 g.stack:removeAll({warp});T.eq(Fade.lockInput,false)
 local flash=Transition.whiteFlash(g);g.stack:push(flash);T.eq(Fade.t,16);T.eq(Fade.mode,2);g.stack:removeAll({flash})
 local back=Transition.battleReturn(g);g.stack:push(back);T.eq(Fade.mode,2);T.eq(Fade._dir,-1);g.stack:removeAll({back})
 T.raises(function()Fade.t=10 end,'read-only');T.raises(function()Fade.begin(1,0)end,'invalid native fade speed')
 Host.currentMod=nil;Stream.shutdown();require('src.core.Game3').release()
end
T.finish('native fade observations, owned palette steps and foreign-owner isolation')
