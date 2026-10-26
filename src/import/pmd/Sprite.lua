-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Consume a published sprite pack through the native renderer. No ROM reader.
local Sprite={}
local directions={down=1,right=3,up=5,left=7}
local function positive(value,label)
  assert(type(value)=='number'and value%1==0 and value>0 and value<=65536,label)
  return value
end
function Sprite.definition(entry)
  local meta=assert(entry.sprite,'sprite pack metadata is required')
  local count=positive(entry.frames,'sprite pack frame count is required')
  local def={image='asset_packs/pmd_red/sprites/'..assert(entry.file),
    frames=count,walker=true,trueColor=true,cells={}}
  for _,axis in ipairs({'Width','Height','Columns'})do
    local value=positive(meta['frame'..axis],'invalid sprite pack frame '..axis)
    def['frame'..axis],def['cell'..axis]=value,value
  end
  def.anchorX,def.anchorY=meta.anchorX,meta.anchorY
  for n=0,count-1 do def.cells[n+1]={{tile=n,dx=0,dy=0}}end
  return def
end
function Sprite.frame(meta,animation,direction,ticks)
  local animations=assert(meta.animations,'sprite animations are required')
  local group=assert(animations[(animation or 0)+1]or animations[1],'sprite animation is empty')
  local frames=assert(meta.sequences[group[directions[direction]or 1]],'sprite direction is missing')
  local duration=0
  for _,frame in ipairs(frames)do duration=duration+positive(frame[2],'invalid sprite frame duration')end
  if duration==0 then return {1,1,0,0,0,0,0}end
  local cursor=(tonumber(ticks)or 0)%duration
  for _,frame in ipairs(frames)do
    cursor=cursor-frame[2]
    if cursor<0 then return frame end
  end
end
local function active(self,facing)
  return Sprite.frame(self._packAnimation,0,facing,self.pmdTicks)
end
local function step(self,moving)
  self.pmdTicks=moving and self.pmdTicks+1 or 0
end
local function draw(self,px,py,cx,cy,facing,phase,flip,top)
  local frame=active(self,facing)
  local native=require('src.render.SpriteRenderer')
  self.offsetX,self.offsetY=self.anchorX-8,self.anchorY-16
  -- Fixed-frame rendering keeps the native full-color/depth behavior. Pack
  -- anchor offsets replace the native cell-centered defaults on this instance.
  return native.drawFixedFrame(self,px+(frame[3]or 0),py+(frame[4]or 0),cx,cy,frame[1]-1,false)
end
local function geometry(self,index)
  local def=self.def
  return {image=self.image,quad=self.frames[index],
    x=index%def.frameColumns*def.frameWidth,
    y=math.floor(index/def.frameColumns)*def.frameHeight,
    width=def.frameWidth,height=def.frameHeight,
    anchorX=self.anchorX,anchorY=self.anchorY}
end
local function pose(self,facing)
  local frame=active(self,facing)
  local out=geometry(self,frame[1]-1)
  out.anchorX=out.anchorX-(frame[3]or 0)
  out.anchorY=out.anchorY-(frame[4]or 0)
  return out,false
end
function Sprite.new(entry,metadata)
  local Native=require('src.render.SpriteRenderer')
  local def=Sprite.definition(entry)
  -- Avoid creating vertical-strip quads beyond a row-major pack sheet.
  local count=def.frames;def.frames=1
  local renderer=Native.new(def);def.frames=count
  local w,h=renderer.image:getDimensions()
  assert(def.frameColumns*def.frameWidth<=w and math.ceil(count/def.frameColumns)*def.frameHeight<=h,
    'sprite pack frames exceed its image')
  for n=0,count-1 do
    renderer.frames[n]=love.graphics.newQuad(n%def.frameColumns*def.frameWidth,
      math.floor(n/def.frameColumns)*def.frameHeight,def.frameWidth,def.frameHeight,w,h)
  end
  renderer.anchorX,renderer.anchorY=tonumber(def.anchorX)or 0,tonumber(def.anchorY)or 0
  renderer.offsetX,renderer.offsetY=renderer.anchorX-8,renderer.anchorY-16
  renderer.cellYBias=0
  renderer._packAnimation=metadata or entry.sprite
  renderer.pmdTicks=0
  renderer.step,renderer.draw=step,draw
  renderer.getFrameGeometry,renderer.getPoseGeometry=geometry,pose
  return renderer
end
return Sprite
