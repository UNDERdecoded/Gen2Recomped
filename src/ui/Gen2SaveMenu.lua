-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native GSC save dialogue over the shared text printer and save pipeline.
local TextBox = require('src.render.TextBox')
local Chrome = require('src.ui.Gen2Chrome')
local Strings = require('src.core.Strings')
local SaveData = require('src.core.SaveData')
local Sound = require('src.core.Sound')
local M = {isOpaque=false, SAVING_FRAMES=16, SAVED_GAP_FRAMES=32,
  SAVED_TAIL_FRAMES=30, SFX_SAVE=0x25}
M.__index=M
M.SAVED_FRAMES=M.SAVED_GAP_FRAMES+M.SAVED_TAIL_FRAMES
M.OVERWRITE_PROMPT_SOURCE=Strings.source('There is already a\nsave file. Is it\vOK to overwrite?')
M.SAVING_PROMPT_SOURCE=Strings.source("SAVING… DON'T TURN\nOFF THE POWER.")
M.PANEL={x=4,y=0,w=16,h=10,labelX=5,labelDy=2,badgesX=17,badgesDy=4,
  dexX=16,dexDy=6,timeX=13,timeDy=8}
M.DOWN_ARROW='▼';M.ARROW_X=18;M.ARROW_Y=17
function M.pagesOf(text)
  local result={}
  for paragraph in (tostring(text)..'\f'):gmatch('(.-)\f') do
    local visible;local pos=1;local scroll=false
    while true do
      local split=paragraph:find('[\n\v]',pos)
      local line=paragraph:sub(pos,split and split-1 or #paragraph)
      if line~='' then
        if not visible then visible={line};result[#result+1]=visible
        elseif scroll then visible={visible[#visible],line,scrolled=true};result[#result+1]=visible
        elseif #visible==2 then visible={line};result[#result+1]=visible
        else visible[#visible+1]=line end
      end
      if not split then break end
      scroll=paragraph:sub(split,split)=='\v';pos=split+1
    end
  end
  return #result>0 and result or {{''}}
end
function M.new(game,opts)
  opts=opts or {}
  local existed=opts.existed
  if existed==nil then existed=SaveData.saveFileExists((opts.save or game.save).version)~=false end
  local self=setmetatable({game=game,save=opts.save or game.save,
    onDone=opts.onDone,writer=opts.writer,existed=existed,choice=1,timer=0},M)
  self:enterPhase('confirm')
  return self
end
function M:wantsFillScale() return true end
function M:playerName() return (self.save.player or {}).name or 'GOLD' end
function M:promptText()
  if self.phase=='overwrite' then return Strings(M.OVERWRITE_PROMPT_SOURCE) end
  if self.phase=='saving' then return Strings(M.SAVING_PROMPT_SOURCE) end
  if self.phase=='done' then
    return self.saved and Strings('%s saved\nthe game.',self:playerName()) or Strings('Could not save.')
  end
  return Strings('Would you like to\nsave the game?')
end
function M:enterPhase(phase)
  self.phase=phase;self.timer=0;self.typedPhase=phase
  -- Embedded stay text never pushes or pops a state. The menu owns its
  -- lifetime, while ordinary native glyph, page and scroll timing is shared.
  local timed=phase=='saving' or phase=='done'
  self.message=TextBox.new(self.game,self:promptText(),nil,{stay={},
    textSpeed=timed and 3 or nil,allowTextAcceleration=not timed})
  self.pages=M.pagesOf(self:promptText());self.page=1
end
function M:prompt() return self.pages[self.page] or self.pages[1] end
function M:yesNoVisible()
  return not self.finished and (self.phase=='confirm' or self.phase=='overwrite') and self.message.done==true
end
function M:finish(saved)
  if self.finished then return false end
  self.finished=true
  if self.onDone then self.onDone(saved==true) end
  return true
end
function M:accept()
  if not self:yesNoVisible() then return false end
  if self.choice==2 then return self:finish(false) end
  if self.phase=='confirm' and self.existed then self.choice=1;self:enterPhase('overwrite')
  else self:enterPhase('saving') end
  return true
end
function M:writeNow()
  if self.wrote then return self.saved end
  self.wrote=true
  local ok,result=pcall(function()
    if self.writer then return self.writer(self.save) end
    if self.game and self.game.save==self.save and self.game.writeSave then return self.game:writeSave() end
    return SaveData.save(self.save)
  end)
  self.saved=ok and not not result
  if not ok then
    self.writeError=tostring(result)
    require('src.core.Logger').warn('Gen2 save failed: %s',self.writeError)
  end
  return self.saved
end
function M.playSaveSfx(game,id)
  local data=game and game.data;local audio=data and data.audio
  local name=audio and audio.sfxOrder and audio.sfxOrder[(id or M.SFX_SAVE)+1]
  if name and audio.sfx and audio.sfx[name] then return Sound.play(data,name) end
end
function M:playSfx(id) return M.playSaveSfx(self.game,id) end
function M:playSfxNamed(name) return Sound.play(self.game.data,name) end
function M:update(dt)
  if self.finished then return end
  local alreadyTyped=self.message.done
  self.message:update(dt)
  local page=0
  for p=1,self.message.pageIndex do
    page=page+1
    local cont=(self.message.pages.contBefore or {})[p] or {}
    local limit=p==self.message.pageIndex and self.message.lineIndex or #self.message.pages[p]
    for line=2,limit do if cont[line] then page=page+1 end end
  end
  self.page=math.min(page,#self.pages)
  if not alreadyTyped then return end
  if self.phase=='saving' then
    self.timer=self.timer+1
    if self.timer==M.SAVING_FRAMES then self:writeNow() end
    if self.timer>=M.SAVING_FRAMES+M.SAVED_GAP_FRAMES then self:enterPhase('done') end
    return
  elseif self.phase=='done' then
    if self.saved and not self.rang then
      self.rang=true;self.saveSound=self:playSfx(M.SFX_SAVE);return
    end
    if self.saveSound and self.saveSound.isPlaying and self.saveSound:isPlaying() then
      self.soundWait=(self.soundWait or 0)+1
      -- A broken host audio source cannot imprison the save menu forever.
      if self.soundWait<600 then return end
    end
    self.timer=self.timer+1
    if self.timer>=M.SAVED_TAIL_FRAMES then self:finish(self.saved) end
    return
  end
  local input=self.game.input
  if input:wasPressed('up') or input:wasPressed('down') then self.choice=3-self.choice
  elseif input:wasPressed('a') then self:accept()
  elseif input:wasPressed('b') then self:finish(false) end
end
function M:drawPanel()
  local save=self.save;local badges=require('src.inventory.Badges').count(self.game.data,save)
  local caught=0
  for _ in pairs((save.pokedex or {}).owned or {}) do caught=caught+1 end
  local seconds=math.floor(SaveData.playSeconds(save))
  Chrome.box(4,0,16,10)
  Chrome.print(Strings('PLAYER %s',self:playerName()),5,2)
  Chrome.print(Strings('BADGES'),5,4);Chrome.print(Chrome.number(badges,2),17,4)
  Chrome.print(Strings('POKéDEX'),5,6);Chrome.print(Chrome.number(caught,3),16,6)
  Chrome.print(Strings('TIME'),5,8)
  Chrome.print(('%3d:%02d'):format(math.floor(seconds/3600),math.floor(seconds/60)%60),13,8)
  self.message:draw()
  if self:yesNoVisible() then
    Chrome.box(0,7,6,5);Chrome.print(Strings('YES'),2,8);Chrome.print(Strings('NO'),2,10)
    Chrome.cursor(1,self.choice==1 and 8 or 10)
  end
end
function M:draw() self:drawPanel() end
-- Native fallback also works when a presentation provider draws in window
-- coordinates. Keep the world visible around the cartridge-sized panel.
function M:drawsWidescreen() return false end
function M:drawWidescreen(width,height)
  return Chrome.withOverlayPanel(width,height,function() self:drawPanel() end)
end
return M
