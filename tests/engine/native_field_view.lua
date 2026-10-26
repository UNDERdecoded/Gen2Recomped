-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
require('tools.native-atlas.cpu-gpu').install(love)
local Field=require('src.core.game3.field_view')
local Native=require('src.core.game3.tileset_native')
local Host=require('src.mods.Runtime')
local Game3=require('src.core.Game3')
local Map=require('src.core.game3.map')
local body=Field.draw
T.eq(body(),false,'no invented field when no native player is admitted')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  local f=require('tools.field-view-runtime.fixture').new(edition)
  local game,world=f.game,f.world
  local retained,callbacks,frames=nil,0,0
  Host.currentMod='field_owner'
  local facade=assert(Game3.forNative(game))
  local ok,why=body(facade,240,160,{endUnderActors=function(upper)retained=upper;T.eq(upper(),true);callbacks=callbacks+1 end})
  assert(ok,why);T.eq(ok,true)
  T.eq(callbacks,1);T.eq(retained(),false,'upper-layer callback expires at the render boundary')
  T.eq(Field._viewW,240);T.eq(Field._viewH,160)
  T.check(Field._nativeBatches[f.native.pair]~=nil,'real owned bottom batches cover the native map')
  T.check(Field._nativeOverBatches[f.native.neighborPair]~=nil,'connected map retains its own source atlas')
  T.eq(world.map.def.width,3,'padded compatibility width cannot resize the native room')
  T.eq(Map.currentDef().midLayout.width,4);T.eq(Map.currentDef().midLayout.trueWidth,3)
  local batches=Field._nativeBatches;local first=batches[f.native.pair]
  T.eq(body(facade,240,160),true);T.eq(Field._nativeBatches,batches);T.eq(batches[f.native.pair],first,'stationary frames reuse GPU batches')
  local count=0
  for _,e in ipairs(world.entities)do e.draw=function()count=count+1 end end
  body(facade,240,160,{skipActors=true});T.eq(count,0,'terrain capture excludes native actors explicitly')
  body(facade,240,160,{actorsOnly=true});T.eq(count,3,'actor capture draws the actual native entities')
  T.eq(Field.setCameraPanning(7,-9),true)
  local x,y
  world.player.draw=function(_,cx,cy)x,y=cx,cy end
  body(facade,320,200,{actorsOnly=true})
  T.eq(x,math.floor(world.player.px+8-160)+7);T.eq(y,math.floor(world.player.py+8-100)-9)
  T.eq(Field.setFlashLevel(4),4);T.eq(game.save.gen3FlashLevel,4);T.eq(Field.flashRadius(),24)
  T.eq(Field.setFlashLevel(200),0);T.eq(Field.flashRadius(),nil)
  Field.animateFlashLevel(4,1);T.eq(game.save.gen3FlashLevel,1);T.eq(Field.flashRadius(),24)
  local before=game.save.gen3FlashRadius;body(facade,240,160,{actorsOnly=true});T.eq(game.save.gen3FlashRadius,before,'draw does not advance the native Flash task')
  require('src.world.Gen3Flash').tick(game);T.eq(Field.flashRadius(),25)
  Field.setFlashRadius(37);T.eq(Field.flashRadius(),37);Field.setFlashRadius(nil)
  local words={};for i=1,16 do words[i]=31 end
  local bank=game.data.map_tilesets.P.palettes[1][2][1]
  T.eq(Field.setBgPaletteOverride(0,words),true)
  local ts=Native.get(f.native.pair);T.check(ts.patchedSlots[0],'actual source atlas palette is patched')
  T.eq(game.data.map_tilesets.P.palettes[1][2][1],bank,'borrowed native colours are untouched')
  T.eq(Field.setBgPaletteOverride(0,nil),true);T.eq(ts.patchedSlots[0],nil)
  Field.setBgPaletteOverride(0,words);words[1]=0
  require('src.render.Assets').invalidate()
  T.eq(body(facade,240,160),true,'native asset reload reconstructs field batches')
  ts=assert(Native.get(f.native.pair))
  T.eq(ts._model.paletteOverrides[0][1][1],255,'active palette override survives reload with detached input words')
  Field.setBgPaletteOverride(0,nil)
  local nativeTick=require('src.render.TileRenderer').tick;local ticks=0
  require('src.render.TileRenderer').tick=function(...)ticks=ticks+1;return nativeTick(...)end
  Field.draw=function(view,w,h,opts)frames=frames+1;T.eq(view,facade);return body(view,w,h,opts)end
  world:drawWorld();T.eq(frames,1,'actual world draw enters the source replacement');T.eq(ticks,1,'one native tile cadence per presentation')
  Field.draw=function()return false,'synthetic field decline'end
  world:drawWorld();T.eq(ticks,2,'declining the source renderer does not tick again in native fallback')
  Field.draw=function(view,w,h)world:drawWorld();return body(view,w,h)end
  world:drawWorld();T.eq(ticks,3,'nested native presentation consumes the same native tile cadence')
  require('src.render.TileRenderer').tick=nativeTick
  Field.draw=function()love.graphics.push();love.graphics.setColor(.2,.3,.4,.5);error('field draw failure')end
  local push,pop=love.graphics.push,love.graphics.pop;local canvas=love.graphics.getCanvas()
  T.raises(function()world:drawWorld()end,'field draw failure','callback errors remain visible')
  T.eq(love.graphics.push,push);T.eq(love.graphics.pop,pop)
  T.eq(love.graphics.getCanvas(),canvas,'failed callback restores the caller target')
  Field.draw=body
  Host.currentMod=nil
  local held=Field._nativeBatches
  require('src.core.game3.asset_stream').cancelOwner('other_owner');T.eq(Field._nativeBatches,held,'another mod cannot retire the field owner')
  require('src.core.game3.asset_stream').cancelOwner('field_owner');T.check(Field._nativeBatches~=held,'owning mod teardown retires the batches')
  T.eq(body(facade,240,160),true)
  Field.setFlashRadius(37);world.map=f.native.neighbor
  T.eq(Field.flashRadius(),25,'map replacement retires the temporary radius and observes the native Flash task')
  world.map=f.native.map
  local live=Field._nativeBatches;game.save={options={},flags={}}
  T.eq(Field.setCameraPanning(0,0),true);T.check(Field._nativeBatches~=live,'save replacement retires the prior rendering cohort')
  f:release();Game3.release()
end
T.finish('native field draw admission, source atlas ownership, options and camera')
