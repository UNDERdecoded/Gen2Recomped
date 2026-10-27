-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local T=require('tests.harness')
love=require('tests.love_stub')
local Flash=require('src.world.Gen3Flash')
T.same(Flash.spans(0,7,5,3,2),{{y=0,height=2,left=0,right=0},{y=2,height=1,left=3,right=3},{y=3,height=2,left=0,right=0}})
T.same(Flash.spans(1,7,5,3,2),{{y=0,height=1,left=0,right=0},{y=1,height=3,left=2,right=4},{y=4,height=1,left=0,right=0}})
T.same(Flash.spans(2,7,5,3,2),{{y=0,height=5,left=1,right=5}},'window follows integer scanline update order')
local calls={};local rectangle=love.graphics.rectangle
love.graphics.rectangle=function(...)calls[#calls+1]={...}end
Flash.drawMask(24,240,160,120,80);local first=calls
local published=Flash.spans(24,240,160,120,80);published[1].left=239
calls={};Flash.drawMask(24,240,160,120,80)
T.same(calls,first,'mutable public spans cannot corrupt the native geometry cache')
love.graphics.rectangle=rectangle
local game={save={gen3FlashLevel=1},data={constants={gen3Flash={maxLevel=1,radii={200,200},screen={240,160}}}}}
require('src.core.GameVersion').set('firered')
T.eq(Flash.circle(game,240,160,120,80),nil,'a centred window covering the view needs no mask')
T.eq(Flash.circle(game,240,160,300,-20).radius,200,'camera pan cannot discard a still-visible mask')
T.finish('native integer Flash geometry and camera bounds')
