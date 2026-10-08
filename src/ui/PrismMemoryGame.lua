local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local Sound=require('src.core.Sound')
local Screen={isOpaque=true};Screen.__index=Screen
function Screen.new(game,onDone)
 local self=setmetatable({game=game,onDone=onDone,stage='ask',cursor=1,yes=1,tries=5,matches={},removed={},shown={}},Screen)
 self.cfg=assert(game.data.field.gen2MemoryGame,'Prism memory-game ROM assets missing')
 local order={2,8,4,7,3,6,1,5};self.cards={}
 for i,count in ipairs(self.cfg.distributions[1])do for _=1,count do self.cards[#self.cards+1]=order[i] end end
 for i=#self.cards,2,-1 do local j=math.random(i);self.cards[i],self.cards[j]=self.cards[j],self.cards[i] end
 return self
end
function Screen:finish()
 self.game.stack:pop();if self.onDone then self.onDone(self.matches) end
end
function Screen:pick(index)
 if self.stage~='play' or self.removed[index] or self.first==index then return end
 self.shown[index]=true;Sound.play(self.game.data,'Sfx_Shine')
 if not self.first then self.first=index;return end
 self.second=index;self.stage='resolve';self.timer=64/60
end
function Screen:resolve()
 self.tries=self.tries-1
 local a,b=self.first,self.second
 if self.cards[a]==self.cards[b] then
  self.removed[a],self.removed[b]=true,true;self.matches[#self.matches+1]=self.cards[a]
  Sound.play(self.game.data,'Sfx_Present')
 else Sound.play(self.game.data,'Sfx_Wrong') end
 self.shown={};self.first=nil;self.second=nil
 self.stage=self.tries==0 and 'reveal' or 'play'
end
function Screen:update(dt)
 local input=self.game.input
 if self.stage=='resolve' then self.timer=self.timer-dt;if self.timer<=0 then self:resolve() end;return end
 if self.stage=='ask' then
  if input:wasPressed('up') or input:wasPressed('down') then self.yes=3-self.yes end
  if input:wasPressed('b') then return self:finish() end
  if input:wasPressed('a') then
   if self.yes==2 or (self.game.save.coins or 0)<25 then return self:finish() end
   self.game.save.coins=self.game.save.coins-25;self.stage='play'
  end
  return
 end
 if self.stage=='reveal' then if input:wasPressed('a') then self:finish() end;return end
 local col,row=(self.cursor-1)%9,math.floor((self.cursor-1)/9)
 if input:wasPressed('left') then col=math.max(0,col-1) elseif input:wasPressed('right') then col=math.min(8,col+1) end
 if input:wasPressed('up') then row=math.max(0,row-1) elseif input:wasPressed('down') then row=math.min(4,row+1) end
 self.cursor=row*9+col+1
 if input:wasPressed('a') then self:pick(self.cursor) end
end
function Screen:mousepressed(x,y,button)
 if button~=1 then return end
 if self.stage=='play' and x>=8 and x<152 and y>=16 and y<96 then self.cursor=math.floor((y-16)/16)*9+math.floor((x-8)/16)+1;self:pick(self.cursor) end
end
function Screen:tile(id,x,y)
 self.image=self.image or Assets.image(self.cfg.image);self.quads=self.quads or {}
 self.quads[id]=self.quads[id] or love.graphics.newQuad((id%16)*8,math.floor(id/16)*8,8,8,self.image:getDimensions())
 love.graphics.draw(self.image,self.quads[id],x,y)
end
function Screen:draw()
 love.graphics.setColor(1,1,1,1);love.graphics.rectangle('fill',0,0,160,144)
 if self.stage=='ask' then
  Font.drawBox(0,12,20,6)
  Font.draw(self.cfg.prompt or 'Want to play?',8,104)
  Font.draw(self.yes==1 and '>YES' or ' YES',112,112)
  Font.draw(self.yes==2 and '>NO' or ' NO',112,128)
  return
 end
 Font.draw('Turns',120,0)
 Font.draw(tostring(self.tries),152,8)
 for i,value in ipairs(self.cards)do
  local x,y=8+((i-1)%9)*16,16+math.floor((i-1)/9)*16
  if not self.removed[i] then
   local id=4+((self.stage=='reveal' or self.shown[i]) and value or 0)*4
   self:tile(id,x,y);self:tile(id+1,x+8,y);self:tile(id+2,x,y+8);self:tile(id+3,x+8,y+8)
  end
 end
 if self.stage=='play' then
  local x,y=8+((self.cursor-1)%9)*16,16+math.floor((self.cursor-1)/9)*16
  if self.cfg.cursor then love.graphics.draw(Assets.image(self.cfg.cursor),x-8,y)
  else love.graphics.setColor(0,0,0,1);love.graphics.rectangle('line',x,y,16,16) end
 end
 love.graphics.setColor(1,1,1,1)
 Font.drawBox(0,12,20,6)
 if self.stage=='reveal' then Font.draw('Press A.',8,104) end
end
return Screen
