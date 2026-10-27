-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local G=require('src.core.Game3')
local Heal=require('src.core.game3.pokecenter_heal')
local Presentation=require('src.world.Gen3HealingPresentation')
local Assets=require('src.render.Assets');local image=Assets.image
local pictures={A={},B={},glow={}};local loads=0
Assets.image=function(path)loads=loads+1;return assert(pictures[path])end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 G.release();local f=require('tools.session-runtime.fixture').new(edition);local g,w=f.game,f.world
 T.eq(Heal.isActive(),false);T.eq(#Heal.spriteSnapshot(),0)
 g.data.constants.gen3HealMachine={monitor={images={'A','B'},x=-8,y=-20},glow={image='glow',x=2,y=3,offsets={{0,0},{4,0},{0,4}}}}
 local ha={px=80,py=96,visible=true,lit=2,timer=11};w.healAnim=ha
 T.eq(Heal.isActive(),true)
 local native=Presentation.snapshot(g,w,ha);local source=Heal.spriteSnapshot()
 T.eq(#native,3);T.eq(#source,3);T.eq(source[1].image,pictures.A)
 for i,s in ipairs(source)do
  T.eq(s.image,native[i].image);T.eq(s.kind,native[i].kind)
  T.eq(s.x+f.player.px-112,native[i].x);T.eq(s.y+f.player.py-72,native[i].y)
 end
 local count=loads;Heal.spriteSnapshot();T.eq(loads,count,'native borrowed art is reused')
 source[1].x=999;T.eq(ha.px,80);T.eq(ha.timer,11,'snapshot cannot step native healing')
 ha.visible=false;T.eq(Heal.spriteSnapshot()[1].image,pictures.B)
 ha.lit=8;T.eq(#Heal.spriteSnapshot(),4,'ball list follows the actual cartridge offset count')
 w.healAnim=nil;T.eq(Heal.isActive(),false);T.eq(#Heal.spriteSnapshot(),0)
 G.release()
end
Assets.image=image
T.finish('native healing sprite snapshots retain anchors, art and one clock')
