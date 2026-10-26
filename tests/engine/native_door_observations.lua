-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local G=require('src.core.Game3')
local Doors=require('src.core.game3.doors')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 G.release();local f=require('tools.session-runtime.fixture').new(edition)
 T.eq(Doors.getActiveAnim(),nil);T.eq(Doors.isBusy(),false);T.eq(Doors.draw(),false)
 local slide={mapId=f.world.map.id,room=1,step=3,timer=1};f.world.gymDoorSlide=slide
 local a=assert(Doors.getActiveAnim());T.eq(a.x,1);T.eq(a.y,104);T.eq(a.frame,1);T.eq(a.nativeFrame,2)
 T.eq(Doors.getActiveAnim(f.canonical,7,104).x,7,'both native simultaneously animated cells can be observed')
 T.eq(Doors.getActiveAnim('OTHER'),nil);T.eq(Doors.getActiveAnim(nil,2,104),nil)
 a.frame=99;T.eq(Doors.getActiveAnim().frame,1,'source pose cannot rewrite native animation')
 T.eq(slide.step,3);T.eq(slide.timer,1,'observation cannot advance the native task')
 f.world.gymDoorSlide.mapId='RETIRED';T.eq(Doors.getActiveAnim(),nil)
 f.world.gymDoorSlide=nil;T.eq(Doors.isBusy(),false)
 G.release()
end
T.finish('native door slide observations and map retirement')
