local V=...
local Assets=require('src.render.Assets')
local ImageWriter=require('src.import.ImageWriter')
local Fruit={}
local cache={}
function Fruit.sprite(map,entity,sprite)
  if require('src.core.GameVersion').get()~='polishedcrystal'
     or not (entity.def and entity.def.fruitTree) then return sprite end
  local frame=entity.fixedFrame or entity.def.frame or 2
  local key=map.id..':'..entity.cellX..':'..entity.cellY..':'..frame
  if cache[key]then return cache[key]end
  local raw=V.require('PolishedAtlas').forMap(map) or Assets.imageData(map.tileset.image)
  local color=V.require('TerrainAtlas').forMap(map)
    or (map.renderer and map.renderer.image) or Assets.image(map.tileset.image)
  local mask=love.image.newImageData(16,16)
  local perRow=map.tileset.tilesPerRow or raw:getWidth()/8
  local canvas=love.graphics.newCanvas(16,16,{dpiscale=1})
  love.graphics.push('all');love.graphics.origin();love.graphics.setShader()
  love.graphics.setScissor();love.graphics.setDepthMode();love.graphics.setCanvas(canvas)
  love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1)
  for dy=0,1 do for dx=0,1 do
    local tile=map:tileAt(entity.cellX*2+dx,entity.cellY*2+dy)
    local sx,sy=tile%perRow*8,math.floor(tile/perRow)*8
    mask:paste(raw,dx*8,dy*8,sx,sy,8,8)
    love.graphics.draw(color,love.graphics.newQuad(sx,sy,8,8,color:getDimensions()),dx*8,dy*8)
  end end
  love.graphics.setCanvas()
  local pixels=canvas:newImageData()
  ImageWriter.matteColor0(mask)
  pixels:mapPixel(function(x,y,r,g,b)
    local _,_,_,a=mask:getPixel(x,y);return r,g,b,a
  end)
  love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0)
  love.graphics.draw(love.graphics.newImage(pixels))
  local overlay=sprite:resolveImage()
  love.graphics.draw(overlay,love.graphics.newQuad(0,frame*16,16,16,overlay:getDimensions()),0,0)
  love.graphics.setCanvas();love.graphics.pop()
  local image=love.graphics.newImage(canvas:newImageData());image:setFilter('nearest','nearest')
  local def={id='POLISHED_FRUIT',image='polished-fruit:'..key,
    frames=1,walker=false,trueColor=true,billboardTexture=image}
  local proxy={def=def,resolveImage=function()return image end}
  cache[key]=proxy
  return proxy
end
function Fruit.invalidate()cache={}end
Assets.register(Fruit.invalidate)
return Fruit
