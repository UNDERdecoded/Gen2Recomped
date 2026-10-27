-- Gen2 name selection and blocking player portrait movement.
-- Adapted from Gen1Recomp src/ui/gen2/NamePick.lua at
-- 535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91; existing provenance/licenses apply.
-- Original integration contributions (c) 2026 Roxas2712; offered to UNDERdecoded under
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
local Chrome = require('src.ui.Gen2Chrome')
local Font = require('src.render.Font')
local Strings = require('src.core.Strings')
local Screens = require('src.ui.Screens')
local Palette = require('src.render.Gen2PaletteDraw')
local M = {isOpaque=true}; M.__index=M
local PRESETS={gold={'GOLD','HIRO','TAYLOR','KARL'},silver={'SILVER','KAMON','OSCAR','MAX'},crystal={'CHRIS','MAT','ALLAN','JON'}}
local FEMALE={crystal={'KRIS','AMANDA','JUANA','JODI'}}
function M.presetsFor(gender,data)
  local field=data and data.field or {}
  local forms=field.playerForms
  local form=forms and forms[gender]
  if form and type(form.names)=='table' and #form.names>0 then return form.names end
  local names=field.boot and field.boot.namePresets and field.boot.namePresets.player
  if type(names)=='table' and #names>0 then return names end
  local version=require('src.core.GameVersion').get()
  return ((gender=='female' or gender=='girl') and FEMALE[version]) or PRESETS[version] or PRESETS.gold
end
function M.new(game,opts)
  opts=opts or {}
  local self=setmetatable({game=game,onDone=opts.onDone,pic=opts.pic,picColors=opts.picColors,
    picTrueColor=opts.picTrueColor,gender=opts.gender or (game and game.save and game.save.player and game.save.player.gender),
    title=opts.title,prompt=opts.prompt,maxLength=opts.maxLength,cursor=1,picX=6,slide='in'},M)
  self.items={Strings.source('NEW NAME')}
  for _,name in ipairs(opts.presets or M.presetsFor(self.gender,game and game.data))do self.items[#self.items+1]=name end
  local font=opts.font or (game and game.data and game.data.font)
  self.fontOk=font and pcall(Font.load,{font=font}) or false
  return self
end
function M:choose(name)
  if self._completed then return false end
  self._completed=true
  if self.onDone then self.onDone(name)end
  return true
end
function M:defaultName()
  return self.items[2] or M.presetsFor(self.gender,self.game and self.game.data)[1]
end
function M:openNaming()
  if self._completed or self.game.stack:top()~=self then return end
  local screen
  screen=Screens.push(self.game,'Gen2NamingScreen',{
    type='player',gender=self.gender,prompt=self.prompt,maxLength=self.maxLength,
    onDone=function(name)
      if self._completed or self.game.stack:top()~=screen then return end
      self.game.stack:pop()
      if self.game.stack:top()~=self then return end
      self:choose(name and name~='' and name or self:defaultName())
    end,
  })
  return screen
end
function M:update()
  if self._completed then return end
  if self.slide=='in' then
    if self.picX<13 then self.picX=self.picX+1 else self.slide=nil end
    return
  elseif self.slide=='out' then
    if self.picX>6 then self.picX=self.picX-1
    else self.slide=nil;self:choose(self.pendingName)end
    return
  end
  local input=self.game and self.game.input;if not input then return end
  if input:wasPressed('up')then self.cursor=(self.cursor-2)%#self.items+1
  elseif input:wasPressed('down')then self.cursor=self.cursor%#self.items+1
  elseif input:wasPressed('a') or input:wasPressed('start')then
    if self.cursor==1 then
      if self.fontOk then self:openNaming()else self:choose(self:defaultName())end
    else self.pendingName=self.items[self.cursor];self.slide='out'end
  end
end
function M:wantsFillScale()return true end
function M:drawsWidescreen()return true end
function M:drawPic()
  if not self.pic then return end
  local G=love.graphics;local w,h=self.pic:getDimensions()
  local x,y=self.picX*8,32+56-h
  local function body()G.setColor(1,1,1,1);G.draw(self.pic,x,y)end
  if self.picColors and not self.picTrueColor and Palette.available()then Palette.with(self.picColors,body)else body()end
  if self.picTrueColor then require('src.render.PaletteFX').markTrueColor(x,y,w,h)end
end
function M:drawPanel()
  Chrome.clear();self:drawPic()
  if self.slide=='in' then return end
  local title=Strings(self.title or 'NAME')
  Chrome.textbox(0,0,9,10)
  Chrome.paletteFill(16,0,Font.width(title),8)
  Chrome.print(title,2,0)
  for i,label in ipairs(self.items)do Chrome.print(i==1 and Strings(label)or label,2,2+(i-1)*2)end
  Chrome.cursor(1,2+(self.cursor-1)*2)
end
function M:draw()self:drawPanel()end
function M:drawWidescreen(w,h)
  Chrome.letterbox(w,h,1,1,1)
  local G=love.graphics;local scale=Chrome.fitScale(w,h)
  G.push('all');G.translate(Chrome.fitOrigin(w,h,scale));G.scale(scale,scale)
  self:drawPanel();G.pop()
end
M.PRESETS=PRESETS;M.PRESETS_FEMALE=FEMALE
return M
