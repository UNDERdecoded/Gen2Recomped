-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Inset choice windows use native input, font, frame and stack ownership.
local Font=require('src.render.Font')
local Theme=require('src.ui.Theme')
local C={};C.__index=C
function C.new(game,options,index,onChoose,layout)
 layout=layout or{};assert(type(options)=='table'and#options>0,'choice options required')
 local rows={};local max=0
 for i,v in ipairs(options)do assert(type(v)=='string','invalid choice label');rows[i]=v;max=math.max(max,Font.width(v))end
 local cols=math.max(1,math.min(#rows,math.floor(tonumber(layout.cols)or 1)))
 local width=math.ceil(max/8)+3
 local c=setmetatable({game=game,options=rows,index=math.max(1,math.min(#rows,(index or 0)+1)),onChoose=onChoose,
  cols=cols,colTiles=width,tx=layout.left or Theme.choiceBox.tx,ty=layout.top or Theme.choiceBox.ty,
  tw=width*cols+1,th=math.ceil(#rows/cols)*2+2,ignoreB=layout.ignoreBPress==true},C)
 return c
end
function C:update()
 local input=self.game.input;local n=#self.options
 if input:wasPressed('a')then self.onChoose(self.index-1);return end
 if input:wasPressed('b')and not self.ignoreB then self.onChoose(127);return end
 local delta=input:wasPressed('down')and self.cols or input:wasPressed('up')and-self.cols
  or input:wasPressed('right')and 1 or input:wasPressed('left')and-1
 if delta then self.index=(self.index-1+delta)%n+1 end
end
function C:draw()
 local ok,err=require('src.render.GraphicsScope').call(function()
  Font.drawBox(self.tx,self.ty,self.tw,self.th)
  love.graphics.setColor(0,0,0,1)
  for i,label in ipairs(self.options)do
   local x=(self.tx+2+(i-1)%self.cols*self.colTiles)*8
   local y=(self.ty+1+math.floor((i-1)/self.cols)*2)*8
   Font.draw(label,x,y)
   if i==self.index then Font.drawCode(Theme.cursor,x-8,y)end
  end
 end)
 if not ok then error(err,0)end
end
function C:uiSize()return Theme.uiSize()end
return C
