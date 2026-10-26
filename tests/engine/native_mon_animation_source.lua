-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Source=require('src.core.game3.mon_anim')
local Native=require('src.pokemon.MonAnim')
local Pictures=require('src.pokemon.PicAnim')
local Host=require('src.mods.Runtime')
local original=package.loaded['src.core.Game']
T.eq(Source.enabled(),false)
T.eq(Source.newSprite(4),nil)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 local game=f.game;package.loaded['src.core.Game']=game
 game.data.constants=game.data.constants or{}
 game.data.constants.speciesOrder={[4]='CHARMANDER'}
 game.data.constants.gen3MonAnim={anims={CHARMANDER={anim='H_SHAKE',delay=3}}}
 local rec={sheet='unused-synthetic-strip.png',width=64,height=64,count=2,
   play={{frame=1,dur=2},{frame=2,dur=3}},idle={{frame=0,dur=1}}}
 game.data.pokemon.CHARMANDER.picAnim=rec
 T.eq(Source.enabled(),true)
 Host.currentMod='motion_owner';local sprite=assert(Source.newSprite(4));Host.currentMod=nil
 T.eq(Source.summary(sprite,4,false),sprite)
 local motion=assert(Native.new(game.data,'CHARMANDER'));motion:restart()
 local frames=assert(Pictures.new(game.data,'CHARMANDER'));frames:start()
 for tick=0,70 do
  local native=motion:transform();local source=Source.transform(sprite)
  T.eq(source.x2,native.dx);T.eq(source.y2,native.dy)
  T.eq(source.sx,native.sx);T.eq(source.sy,native.sy);T.eq(source.rotation,native.rot)
  T.eq(source.frame,frames:frame());T.eq(sprite.frames,tick)
  Source.step(sprite);motion:update(1/60);frames:update(1/60)
 end
 T.eq(Source.done(sprite),true)
 T.eq(Source.framePic(4,1,true),nil,'a missing shiny strip cannot flash the normal palette')
 T.eq(Source.summary(sprite,4,true),sprite)
 require('src.core.game3.asset_stream').cancelOwner('other_owner');T.eq(Source.step(sprite),true)
 require('src.core.game3.asset_stream').cancelOwner('motion_owner');T.eq(Source.step(sprite),false)
 T.eq(Source.done(sprite),true)
 local swapped=assert(Source.newSprite(4));Source.summary(swapped,4)
 require('src.core.GameVersion').set(edition=='firered'and'emerald'or'firered')
 T.eq(Source.step(swapped),false,'edition replacement retires the presentation lease')
 require('src.core.GameVersion').set(edition)
 local retired=assert(Source.newSprite(4));Source.summary(retired,4)
 game.data={pokemon={}};T.eq(Source.step(retired),false,'dataset replacement retires the presentation lease')
 f.close()
end
Source._service.release();package.loaded['src.core.Game']=original
T.finish('native motion and frame-player presentation adapter; native timing only')
