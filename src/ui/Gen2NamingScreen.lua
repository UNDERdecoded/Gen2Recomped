-- Original contributions (c) 2026 Roxas2712; offered to UNDERdecoded under
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Native Gen2 name entry. The public screen leaves completion to its caller;
-- ordinary NamingScreen admissions use this same owner with native dismissal.
local Font = require('src.render.Font')
local Strings = require('src.core.Strings')
local Runtime = require('src.mods.Runtime')
local Chrome = require('src.ui.Gen2Chrome')
local Assets = require('src.render.Assets')
local M = { isOpaque=true }
M.TYPES = {
  player={prompt=Strings.source('YOUR NAME?'),maxLength=7,sprite='SPRITE_CHRIS',spriteFemale='SPRITE_KRIS'},
  rival={prompt=Strings.source("RIVAL'S NAME?"),maxLength=7,sprite='SPRITE_RIVAL'},
  mom={prompt=Strings.source("MOTHER'S NAME?"),maxLength=7,sprite='SPRITE_MOM'},
  box={prompt=Strings.source('BOX NAME?'),maxLength=8,isBox=true},
  nickname={prompt=Strings.source('NICKNAME?'),maxLength=10},
}
local function limit(n, fallback)
  n=tonumber(n)
  if not n or n~=n or n==math.huge or n==-math.huge then return fallback end
  return math.max(1,math.floor(n))
end
local function split(text, count)
  local out={}
  for _,span in ipairs(Font.split(type(text)=='string' and text or ''))do
    if #out>=count then break end
    out[#out+1]=text:sub(span.from,span.to)
  end
  return out
end
M.__index=function(self,key)
  if key=='text'then return table.concat(self.glyphs) end
  if key=='maxLen'then return self.maxLength end
  if key=='title'then return self.prompt end
  return M[key]
end
M.__newindex=function(self,key,value)
  if key=='text'then rawset(self,'glyphs',split(value,self.maxLength))
  elseif key=='maxLen'then rawset(self,'maxLength',limit(value,self.maxLength))
  elseif key=='title'then rawset(self,'prompt',value)
  else rawset(self,key,value)end
end
local function alphabet(lower)
  local rows={{},{},{}}
  for i=0,25 do rows[math.floor(i/9)+1][i%9+1]=string.char((lower and 97 or 65)+i)end
  rows[3][9]=' '
  return rows
end
local function board(lower,box)
  local rows=alphabet(lower)
  local symbols={'×','(',')',':',';','[',']','<PK>','<MN>'}
  if box then
    rows[4]=lower and {'é',"'d","'l","'m","'r","'s","'t","'v",'0'} or symbols
    rows[5]=lower and {'1','2','3','4','5','6','7','8','9'} or {'-','?','!','♂','♀','/','.',',','&'}
  else rows[4]=lower and symbols or {'-','?','!','/','.',',',' ',' ',' '}end
  return rows
end
local boards={ normal={board(false,false),board(true,false)},box={board(false,true),board(true,true)} }
local function sameGrid(grid)return grid end
function M:rows()
  local data=self.game and self.game.data or {}
  local authored=data.gen2Naming and data.gen2Naming[self.isBox and 'box' or 'normal']
  local base=authored and authored[self.lower and 2 or 1] or boards[self.isBox and 'box' or 'normal'][self.lower and 2 or 1]
  if Runtime.wantsHook('ui.naming.grid')then
    local hooked=Runtime.call('ui.naming.grid',sameGrid,base,{lower=self.lower,title=self.prompt,maxLen=self.maxLength,box=self.isBox,game=self.game})
    if type(hooked)=='table'and #hooked>0 then return hooked end
  end
  return base
end
function M:keyboardTop()return self.isBox and 6 or 8 end
function M:bottomRow()return #self:rows() end
function M:onBottomRow()return self.row==self:bottomRow() end
function M:bottomTarget()return self.col<3 and 1 or self.col<6 and 2 or 3 end
function M:characterAt(col,row)
  local line=self:rows()[row+1]
  local ch=line and line[col+1]
  return ch~='' and ch or nil
end
function M:cursorCharacter()
  if self:onBottomRow()then return ({'CASE','DEL','END'})[self:bottomTarget()]end
  return self:characterAt(self.col,self.row)
end
function M:addCharacter(ch)
  if type(ch)~='string' or ch=='' or #self.glyphs>=self.maxLength then return false end
  -- One cell can carry a charmap ligature or a Unicode character. Never cut
  -- its bytes or count it as several name slots.
  local cells=split(ch,self.maxLength-#self.glyphs)
  for _,cell in ipairs(cells)do self.glyphs[#self.glyphs+1]=cell end
  return #cells>0
end
function M:deleteCharacter()return table.remove(self.glyphs) end
function M:toggleCase()self.lower=not self.lower end
function M:moveHorizontal(delta)
  if self:onBottomRow()then self.col=((self:bottomTarget()-1+delta)%3)*3
  else self.col=(self.col+delta)%9 end
end
function M:moveVertical(delta)
  self.row=(self.row+delta)%(self:bottomRow()+1)
  if self:onBottomRow()then self.col=(self:bottomTarget()-1)*3 end
end
function M:jumpToEnd()self.row=self:bottomRow();self.col=6 end
function M:accept()
  local name=self.text
  if self._popOnDone then
    if self._completed or self.game.stack:top()~=self then return false end
    self._completed=true;self.game.stack:pop()
    if name==''then name=self.default or (self.presets and self.presets[1]) or ''end
  end
  if self.onDone then self.onDone(name)end
  return true
end
M.confirm=M.accept
function M.playerSprite(gender)
  return (gender=='female' or gender=='girl')and M.TYPES.player.spriteFemale or M.TYPES.player.sprite
end
function M.new(game,opts)
  opts=opts or {};local kind=M.TYPES[opts.type or 'player']or M.TYPES.player
  local self=setmetatable({game=game,kind=kind,glyphs={},maxLength=limit(opts.maxLength,kind.maxLength),
    prompt=opts.prompt or Strings(kind.prompt),gender=opts.gender or (game and game.save and game.save.player and game.save.player.gender),
    isBox=opts.isBox or kind.isBox or false,lower=false,row=0,col=0,clock=0,
    onDone=opts.onDone,onCancel=opts.onCancel,mon=opts.mon,monName=opts.monName,
    presets=opts.presets,default=opts.default,_popOnDone=opts._popOnDone==true,
    iconColors=opts.iconColors,palette=opts.palette,
  },M)
  self.text=opts.initial or ''
  local data=game and game.data or {}
  self.gfx=opts.menuGfx or data.gen2MenuGfx
  if self.gfx and self.gfx.naming then self.gfx=self.gfx.naming end
  self.tiles={}
  for _,key in ipairs({'border','middleLine','underLine','cursor'})do
    local path=self.gfx and self.gfx[key]
    if path then local ok,img=pcall(Assets.image,path);if ok then self.tiles[key]=img end end
  end
  if opts.iconPath then local ok,img=pcall(Assets.image,opts.iconPath);if ok then self.iconImage=img end end
  if self.mon then self:loadMonHeader(data,self.mon)end
  if not self.iconImage and not self.mon then
    local form=(data.field and data.field.playerForms or {})[self.gender]
    local id=kind==M.TYPES.player and ((form and form.walk)or M.playerSprite(self.gender))or kind.sprite
    local def=data.sprites and data.sprites[id]
    if def and def.image then
      local ok,img=pcall(Assets.image,def.image)
      if ok then self.iconImage=img;self.iconTrueColor=def.trueColor end
    end
  end
  return self
end
-- Preserve the unqualified screen's pop-before-callback contract while giving
-- native scripts, catches and introductions the real Gen2 input model.
function M.native(game,opts)
  opts=opts or {};local args={}
  for k,v in pairs(opts)do args[k]=v end
  args.type=args.type or (args.kind=='mon' and 'nickname')or args.kind
    or (tonumber(args.maxLen)==10 and 'nickname')or (tonumber(args.maxLen)==8 and 'box')or 'player'
  args.prompt=args.prompt or args.title;args.maxLength=args.maxLength or args.maxLen
  args._popOnDone=true
  return M.new(game,args)
end
function M:setChoosing(on)
  if on then
    self.choosing=true;self.isOpaque=false
    -- A presenter may wrap the class draw methods without reading native
    -- preset state. This owner has no keyboard surface until NEW NAME, so
    -- suppress drawing on the instance, after constructor decoration.
    self._presetDrawState={draw=rawget(self,'draw'),wide=rawget(self,'drawWidescreen')}
    self.draw=function()end;self.drawWidescreen=function()end
  else
    self.choosing=nil;self.isOpaque=true
    local previous=self._presetDrawState
    if previous then
      rawset(self,'draw',previous.draw);rawset(self,'drawWidescreen',previous.wide)
      self._presetDrawState=nil
    end
  end
end
function M:enter()
  if not(self.presets and #self.presets>0)then return end
  self:setChoosing(true)
  local items={{label=Strings('NEW NAME'),onSelect=function()self:setChoosing(false)end}}
  for _,preset in ipairs(self.presets)do
    items[#items+1]={label=preset,onSelect=function()
      self:setChoosing(false);self.text=preset;self:accept()
    end}
  end
  self.game.stack:push(require('src.ui.Menu').new(self.game,items,{tx=4,ty=0,tw=12,th=#items*2+2,cancelable=false}))
end
function M:update()
  self.clock=self.clock+1
  local input=self.game and self.game.input;if not input or self._completed then return end
  if input:wasPressed('left')then self:moveHorizontal(-1)
  elseif input:wasPressed('right')then self:moveHorizontal(1)
  elseif input:wasPressed('up')then self:moveVertical(-1)
  elseif input:wasPressed('down')then self:moveVertical(1)
  elseif input:wasPressed('select')then self:toggleCase()
  elseif input:wasPressed('start')then self:jumpToEnd()
  elseif input:wasPressed('b')then self:deleteCharacter()
  elseif input:wasPressed('a')then
    if self:onBottomRow()then
      local target=self:bottomTarget()
      if target==1 then self:toggleCase()elseif target==2 then self:deleteCharacter()else self:accept()end
    else
      self:addCharacter(self:characterAt(self.col,self.row))
      if #self.glyphs>=self.maxLength then self:jumpToEnd()end
    end
  end
end
function M:loadMonHeader(data,mon)
  local def=data.pokemon and data.pokemon[mon.species]
  self.monName=self.monName or mon.name or (def and def.name)or mon.species
  self.monGender=mon.gender;self.monIcon=true
  local entry=data.icons and data.icons.bySpecies and data.icons.bySpecies[mon.species]
  if type(entry)=='table'then entry=entry.image end
  if type(entry)=='string'then
    local path,trueColor=require('src.pokemon.Sprites').iconPath(data,mon,entry,{kind='naming'})
    if path then local ok,img=pcall(Assets.image,path);if ok then self.iconImage=img end end
    self.iconTrueColor=trueColor
  end
end
function M:genderGlyph()return self.monGender=='male'and '♂'or self.monGender=='female'and '♀'or nil end
M.ICON_FRAME_STEPS=18
function M:iconFrame()return self.monIcon and math.floor(self.clock/M.ICON_FRAME_STEPS)%2 or 0 end
function M:iconOrigin()return 16,self.monIcon and 12 or 16 end
function M:wantsFillScale()return not self.choosing end
function M:drawsWidescreen()return not self.choosing end
function M:paperColor()return self.palette and require('src.render.Gen2PaletteDraw').color(self.palette,1)or Chrome.DEFAULT_BOX_PALETTE[1]end
function M:drawBackdrop()
  local G=love.graphics;local p=self:paperColor();G.setColor(p[1]/255,p[2]/255,p[3]/255,1)
  G.rectangle('fill',0,0,160,144)
  if self.tiles.border then
    local function draw()
      G.setColor(1,1,1,1)
      for y=0,17 do for x=0,19 do G.draw(self.tiles.border,x*8,y*8)end end
    end
    local Pal=require('src.render.Gen2PaletteDraw')
    if self.palette and Pal.available()then Pal.with(self.palette,draw)else draw()end
  end
end
function M:clearPanel(tx,ty,tw,th)
  local G=love.graphics;local p=self:paperColor();G.setColor(p[1]/255,p[2]/255,p[3]/255,1)
  G.rectangle('fill',tx*8,ty*8,tw*8,th*8);G.setColor(0,0,0,1)
end
function M:drawEntry(tx,ty)
  for i=1,self.maxLength do
    local col=(i-1)%16;local row=math.floor((i-1)/16)
    local x,y=(tx+col)*8,(ty+row*2)*8
    if self.mailMode then x,y=8+col*8,24+row*12 end
    Font.draw(self.glyphs[i]or '-',x,y)
  end
end
function M:cursorTile()
  if self:onBottomRow()then return 2+(self:bottomTarget()-1)*6,self:keyboardTop()+self:bottomRow()*2,5 end
  return 2+self.col*2,self:keyboardTop()+self.row*2,1
end
function M:drawCursorTile(quad,x,y,flipX,flipY)
  love.graphics.draw(self.tiles.cursor,quad,x,y,0,flipX and -1 or 1,flipY and -1 or 1,flipX and 8 or 0,flipY and 8 or 0)
end
function M:drawCursorBox(tx,ty,width)
  local G=love.graphics;local image=self.tiles.cursor
  if not image then Chrome.cursor(tx-1,ty);return end
  local w,h=image:getDimensions()
  if w<8 or h<8 then Chrome.cursor(tx-1,ty);return end
  if not self.cursorQuads then
    self.cursorQuads={corner=G.newQuad(0,0,8,8,w,h),edge=G.newQuad(0,h>=16 and 8 or 0,8,8,w,h)}
  end
  G.setColor(1,1,1,1)
  local x,y=tx*8,ty*8;local corner,edge=self.cursorQuads.corner,self.cursorQuads.edge
  local right=x+math.max(0,(width or 1)-1)*8
  self:drawCursorTile(corner,x-1,y-1,false,false);self:drawCursorTile(corner,right,y-1,true,false)
  self:drawCursorTile(corner,x-1,y,false,true);self:drawCursorTile(corner,right,y,true,true)
  for col=1,(width or 1)-2 do
    self:drawCursorTile(edge,x+col*8,y-1,false,false);self:drawCursorTile(edge,x+col*8,y,false,true)
  end
end
function M:drawPanel()
  self:drawBackdrop();self:clearPanel(1,1,18,self.mailMode and 5 or self.isBox and 4 or 6)
  self:clearPanel(1,self:keyboardTop(),18,self.isBox and 9 or 7);self:clearPanel(1,16,18,1)
  if self.monName then
    Chrome.printThrough(Strings("%s'S",self.monName),5,2,self.palette)
    Chrome.printThrough(Strings(self.prompt),5,4,self.palette)
  else Chrome.printThrough(Strings(self.prompt),5,2,self.palette)end
  local gender=self:genderGlyph();if gender then Chrome.printThrough(gender,1,2,self.palette)end
  self:drawEntry(5,self.isBox and 4 or 6)
  if self.iconImage then
    local G=love.graphics;local w,h=self.iconImage:getDimensions()
    local y=self:iconFrame()*16;if y+16>h then y=0 end
    local quad=self.iconQuad
    if not quad then quad=G.newQuad(0,y,math.min(16,w),math.min(16,h),w,h);self.iconQuad=quad
    elseif quad.setViewport then quad:setViewport(0,y,math.min(16,w),math.min(16,h),w,h)end
    local function draw()G.setColor(1,1,1,1);G.draw(self.iconImage,quad,self:iconOrigin())end
    local colors=self.iconColors;local Pal=require('src.render.Gen2PaletteDraw')
    if colors and not(self.iconTrueColor and Pal.mode=='gbc')then Pal.with(colors,draw)else draw()end
  end
  for ri,row in ipairs(self:rows())do for ci,ch in ipairs(row)do
    if ch~=''and ch~=' 'then Chrome.printThrough(Strings(ch),ci*2,self:keyboardTop()+(ri-1)*2,self.palette)end
  end end
  local labels={self.lower and Strings('UPPER')or Strings('lower'),Strings('DEL'),Strings('END')}
  for i,label in ipairs(labels)do Chrome.printThrough(label,i==1 and 2 or 3+(i-1)*6,self:keyboardTop()+self:bottomRow()*2,self.palette)end
  local function cursor()self:drawCursorBox(self:cursorTile())end
  local Pal=require('src.render.Gen2PaletteDraw')
  if self.palette and Pal.available()then Pal.with(self.palette,cursor)else cursor()end
end
function M:draw()if not self.choosing then self:drawPanel()end end
function M:drawWidescreen(w,h)
  if self.choosing then return end
  Chrome.withPanel(w,h,1,1,1,function()self:drawPanel()end)
end
return M
