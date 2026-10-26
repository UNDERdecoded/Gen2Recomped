-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Sprite=require('src.import.pmd.Sprite')
local meta={frameWidth=32,frameHeight=24,frameColumns=2,anchorX=16,anchorY=24,
  animations={{1,1,1,1,1,1,1,1}},sequences={{{1,2,3,4,0,0,0},{4,3,0,0,0,0,0}}}}
local entry={file='owned.png',frames=4,sprite=meta}
local def=Sprite.definition(entry)
T.eq(def.image,'asset_packs/pmd_red/sprites/owned.png','definition selects the published pack path')
T.eq(def.frameWidth,32,'definition retains native frame dimensions')
T.eq(def.cellColumns,2,'definition retains the consumer cell layout')
T.eq(def.cells[4][1].tile,3,'definition exposes zero-based tile cells')
T.eq(Sprite.frame(meta,0,'down',1),meta.sequences[1][1],'duration preserves the first frame')
T.eq(Sprite.frame(meta,0,'down',2),meta.sequences[1][2],'duration advances on its exact boundary')
T.eq(Sprite.frame(meta,0,'down',5),meta.sequences[1][1],'duration wraps after the whole sequence')
local oldImage,oldDraw=love.graphics.newImage,love.graphics.draw
love.graphics.newImage=function(path)
 if path=='asset_packs/pmd_red/sprites/owned.png'then
  return {getDimensions=function()return 64,48 end,getWidth=function()return 64 end,getHeight=function()return 48 end}
 end
 return oldImage(path)
end
local draw
love.graphics.draw=function(...)draw={...}end -- graphics IO capture only
local sprite=Sprite.new(entry)
T.eq(sprite.frames[3].x,32,'native quads use the row-major column')
T.eq(sprite.frames[3].y,24,'native quads use the row-major row')
sprite:step(true);sprite:step(true)
local pose,flip=sprite:getPoseGeometry('down')
T.eq(pose.x,32,'pose reports the animated atlas column')
T.eq(pose.y,24,'pose reports the animated atlas row')
T.eq(pose.anchorX,16,'pose retains the native anchor')
T.eq(flip,false,'pack direction frames do not inherit a native facing flip')
sprite.anchorX=20;sprite:draw(64,64,0,0,'down')
T.check(draw~=nil,'published pack frame reaches the real native fixed-frame renderer')
T.eq(draw[3],52,'a consumer anchor edit changes the native draw offset')
sprite:step(false);T.eq(sprite.pmdTicks,0,'stopping resets pack animation time')
love.graphics.newImage,love.graphics.draw=oldImage,oldDraw
local U=require('src.compat.gen2.Unown')
T.eq(U.monLetter({species='OTHER'}),nil,'Unown query rejects other species')
T.eq(U.monLetter({species='UNOWN',unownLetter='Z'}),26,'Unown query accepts a stored letter')
T.eq(U.monLetter({species='UNOWN',dvs={attack=0,defense=0,speed=0,special=0}}),1,
 'Unown query delegates the native DV selector')
local P=require('src.compat.game3.Pokemon')
T.eq(P.unownLetter(0),0,'GBA personality query is zero-based')
T.eq(P.unownLetter(0x03030303),255%28,'GBA personality query keeps two bits from each byte')
T.finish('published sprite-pack renderer and follower query adapters')
