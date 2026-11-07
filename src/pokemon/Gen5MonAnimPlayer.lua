-- Live Nitro multi-cell playback. The import retains NCER/NANR/NMCR/NMAR;
-- draw each body part with its ROM affine transform, without baking frames.
local Decoder=require("src.import.Gen5MonAnim")
local Assets=require("src.render.Assets")
local Player={};Player.__index=Player
Player.aligned={}
function Player.new(data,species,mon,side)
 local def=data.pokemon and data.pokemon[species]
 local record=def and def.gen5Animation
 -- Black / White's other forms play their own bundle (gen5-form-sprites-v1);
 -- a form without one is drawn still rather than as the base form
 local form=type(mon)=="table" and tonumber(mon.form) or 0
 if form>0 and def and def.gen5FormSprites then
  local fr=def.gen5FormSprites[form]
  if fr then record=fr.animation end
  if fr and not record then return nil end
 end
 if not record or not record.path then return nil end
 if require("src.pokemon.Sprites").formIndex(def,mon)then return nil end
 local bytes=love.filesystem.read(Assets.resolve(record.path))
 local arc=bytes and Decoder.unpack(bytes)
 if not arc then return nil end
 local shiny=mon and require("src.pokemon.Pokemon").isShiny(mon)
 local female=mon and require("src.pokemon.Pokemon").genderOf(data,mon)=="female"
 local set=Decoder.load(arc,record.species,side or "front",shiny,female)
 if not set then return nil end
 local machine=Decoder.machine(set,0)
 if not machine then return nil end
 local rasters={}
 -- the alignment is a search (Decoder.align); the same Pokemon in the next
 -- battle lines up the same way, so it is worked out once a session
 local alignKey=record.path.."|"..tostring(record.species).."|"..tostring(side or "front").."|"..tostring(shiny and true).."|"..tostring(female)
 local at=Player.aligned[alignKey]
 local ox,oy
 if at then ox,oy=at[1],at[2]
 else ox,oy=Decoder.align(set,machine.state(),rasters);Player.aligned[alignKey]={ox,oy} end
 local self=setmetatable({liveMultiCell=true,set=set,machine=machine,paused=true,clock=0,cells={},
   ox=ox or Decoder.ORIGIN[1],oy=oy or Decoder.ORIGIN[2],dirty=true},Player)
 for id,cell in pairs(set.cells.cells)do
  local raster=rasters[id] or Decoder.rasterCell(cell,set.sheet,set.cells.mappingMode)
  if raster then
   local rgba=Decoder.rgba(raster.px,raster.w,raster.h,set.palette)
   local image=love.graphics.newImage(require("src.import.ImageWriter").fromRGBA8(raster.w,raster.h,rgba))
   image:setFilter("nearest","nearest")
   self.cells[id]={image=image,x=raster.x0,y=raster.y0}
  end
 end
 self.canvas=love.graphics.newCanvas(96,96);self.canvas:setFilter("nearest","nearest")
 return self
end
function Player:start()self.paused=false end
function Player:update(dt)
 if self.paused then return end
 self.clock=self.clock+(dt or 0)*60
 while self.clock>=1 do self.machine.tick();self.clock=self.clock-1;self.dirty=true end
end
function Player:frame()return self.paused and 0 or 1 end
function Player:image()
 if self.paused then return nil end
 if not self.dirty then return self.canvas end
 local g=love.graphics
 -- push("all") saves the canvas and pop() puts it back: no manual restore.
 -- Handing getCanvas()'s list back to setCanvas crashed under the
 -- DramaticShapes mod, whose setCanvas wrapper takes a Canvas, not a list
 -- ("bad argument to setCanvas: Canvas expected", first BW battle).
 g.push("all");g.setCanvas(self.canvas);g.clear(0,0,0,0);g.origin();g.setShader()
 g.setScissor();g.setStencilTest();g.setDepthMode();g.setColor(1,1,1,1);g.setBlendMode("alpha")
 g.translate(self.ox,self.oy)
 for _,part in ipairs(self.machine.state())do
  local cell=self.cells[part.cell]
  if cell then
   local top=part.top
   g.push();g.translate(top.tx,top.ty);g.rotate(top.rot);g.scale(top.sx,top.sy)
   g.translate(part.tx,part.ty);g.rotate(part.rot);g.scale(part.sx,part.sy)
   g.draw(cell.image,cell.x,cell.y);g.pop()
  end
 end
 g.pop();self.dirty=false
 return self.canvas
end
return Player
