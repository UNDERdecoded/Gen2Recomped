-- HGSS OakSpeech's main path, tutorial branches, gender/name confirmation
-- and five cartridge shrink pictures. Rival naming belongs to the later
-- police event in Elm's lab, not to this application.
local Assets=require('src.render.Assets')
local Font=require('src.render.Font')
local Screens=require('src.ui.Screens')
local SecondScreen=require('src.ui.SecondScreen')
local Oak={};Oak.__index=Oak;Oak.isOpaque=true
function Oak:uiSize() return 256,192 end
function Oak:wantsFillScale() return true end
function Oak:wantsEdgeBleed() return false end
function Oak.new(game,onDone)
  return setmetatable({game=game,onDone=onDone,art=game.data.gen4_hgss_oak_art or {},
    phase='topics',choice=1,gender='boy',pages={},page=1,frame=0,cache={},bottom=false},Oak)
end
function Oak:enter()
  self:say(7,'topics')
  self:music('SEQ_GS_STARTING')
end
function Oak:music(name)
  local songs=(self.game.data.audio or {}).songs or {}
  if songs[name] then pcall(require('src.core.Music').play,self.game.data,name) end
end
function Oak:text(id)
  local text=(self.art.text or {})[id] or ''
  -- the player's name goes in slot 0 (BufferPlayerName) and the shared Gen 4
  -- markup expands it, dropping {YESNO}/{ALN_CENTER}; the \v/\f page breaks
  -- stay for say() to split on
  require('src.import.Gen4Text').buffer(self.game,(self.game.save.player or {}).name or '')
  local ok,plain=pcall(require('src.script.Commands').gen4Markup,text,self.game)
  -- one value: gsub's count would ride into {text(44),text(45),text(46)}
  return ok and type(plain)=='string' and plain or text
end
function Oak:say(id,phase)
  self.message=id;self.phase=phase;self.page=1;self.pages={};self.choice=1;self.bottom=nil
  for page in (self:text(id)..'\v'):gmatch('([^\v\f\r]*)[\v\f\r]') do
    page=page:gsub('^%s+',''):gsub('%s+$','')
    if page~='' then
      if phase=='lesson' or phase=='topics' then self.pages[#self.pages+1]=page
      else
        local lines={}
        for line in (page..'\n'):gmatch('([^\n]*)\n') do lines[#lines+1]=line end
        for first=1,#lines,2 do self.pages[#self.pages+1]=table.concat(lines,'\n',first,math.min(first+1,#lines)) end
      end
    end
  end
end
function Oak:finish()
  if self.done then return end
  self.done=true;self.game.stack:pop()
  -- SEQ_GS_STARTING2 is the speech's own song: the field that starts next
  -- plays the bedroom's header BGM (FieldBGM_GetEffective -> SEQ_GS_T_WAKABA).
  -- The overworld cued it on its push, under this screen, so cue it again.
  local ow=self.game.overworld
  local mapId=(ow and ow.map and ow.map.id) or (self.game.save.player or {}).map
  if mapId then
    pcall(require('src.core.Music').playMap,self.game.data,mapId,self.game.save.onBike,
      ow and ow.player and ow.player.surfing)
  end
  if self.onDone then self.onDone() end
end
function Oak:greeting()
  local now=os.date('*t');local hhmm=now.hour*100+now.min
  local id=hhmm<400 and 5 or hhmm<1100 and 1 or hhmm<1600 and 2 or hhmm<1900 and 3 or 4
  self:say(id,'greeting')
end
function Oak:pickGender(gender)
  self.gender=gender;self:say(gender=='boy' and 38 or 39,'confirmGender')
end
function Oak:askName()
  local player=self.game.save.player
  player.gender=self.gender
  local avatar=self.game.overworld and self.game.overworld.player
  if avatar and avatar.refreshForm then avatar:refreshForm(self.game.data) end
  Screens.push(self.game,'NamingScreen',{kind='player',female=self.gender=='girl',
    title=self:text(40),presets={self.gender=='girl' and 'Lyra' or 'Ethan'},
    maxLen=(self.game.data.constants or {}).playerNameLength or 7,
    onDone=function(name)
      player.name=name;self:say(self.gender=='boy' and 41 or 42,'confirmName')
    end})
end
function Oak:advance()
  if self.phase=='topics' then
    if self.choice==3 then return self:greeting() end
    self.lesson=self.choice==1 and {9,10,11,12,13,15,16,17,23,26} or {28,29,30,31,32,33}
    self.lessonIndex=1;return self:say(self.lesson[1],'lesson')
  end
  if self.page<#self.pages then self.page=self.page+1;return end
  local p=self.phase
  if p=='lesson' then
    self.lessonIndex=self.lessonIndex+1
    if self.lesson[self.lessonIndex] then self:say(self.lesson[self.lessonIndex],'lesson')
    else self:say(7,'topics') end
  elseif p=='greeting' then self:music('SEQ_GS_STARTING2');self:say(6,'welcome')
  elseif p=='welcome' then self:say(34,'inhabited')
  elseif p=='inhabited' then self.phase='release';self.elapsed=0;self.bottom=false
  elseif p=='alongside' then self:say(36,'yourself')
  elseif p=='yourself' then self:say(37,'genderQuestion')
  elseif p=='genderQuestion' then self.phase='gender';self.choice=1
  elseif p=='gender' then self:pickGender(self.choice==1 and 'boy' or 'girl')
  elseif p=='confirmGender' then
    if self.choice==2 then self:say(37,'genderQuestion') else self:say(40,'name') end
  elseif p=='name' then self:askName()
  elseif p=='confirmName' then
    if self.choice==2 then self:say(37,'genderQuestion') else self:say(43,'ending') end
  elseif p=='ending' then self.phase='shrink';self.elapsed=0;self.bottom=false
  end
end
function Oak:choices()
  if self.phase=='topics' then return {self:text(44),self:text(45),self:text(46)} end
  if self.phase=='gender' then return {'boy','girl'} end
  if (self.phase=='confirmGender' or self.phase=='confirmName') and self.page>=#self.pages then
    return {self:text(47),self:text(48)}
  end
end
function Oak:update(dt)
  local ticks=require('src.ui.HgssClock').step(self,self.game,dt)
  self.frame=self.frame+ticks
  local i=self.game.input;local tap=self.tap;self.tap=nil
  if i:wasPressed('l') or i:wasPressed('select') then
    local current=self.bottom
    if current==nil then current=self:choices()~=nil end
    self.bottom=not current
  end
  if self.phase=='release' then
    local previous=self.elapsed;self.elapsed=self.elapsed+ticks
    if previous<50 and self.elapsed>=50 then pcall(require('src.core.Sound').playCry,self.game.data,183) end
    if self.elapsed>=90 then self:say(35,'alongside') end
    return
  elseif self.phase=='shrink' then
    self.elapsed=self.elapsed+ticks
    if self.elapsed>=30+5*9 then self:finish() end
    return
  end
  local choices=self:choices()
  if choices then
    if i:wasPressed('up') or i:wasPressed('left') then self.choice=(self.choice-2)%#choices+1 end
    if i:wasPressed('down') or i:wasPressed('right') then self.choice=self.choice%#choices+1 end
  end
  if tap or i:wasPressed('a') then self:advance() end
end
function Oak:image(key,x,y)
  local rec=self.art[key];local path=type(rec)=='table' and rec.path or rec
  if not path then return end
  if self.cache[path]==nil then self.cache[path]=Assets.image(path) or false end
  local image=self.cache[path]
  if image then
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,(x or 0)+(type(rec)=='table' and rec.originX or 0),
      (y or 0)+(type(rec)=='table' and rec.originY or 0))
  end
end
function Oak:mon(seq,t)
  local frames=(self.art.sequences or {})[seq] or {};local total=0
  for _,f in ipairs(frames) do total=total+math.max(1,f.duration) end
  if total==0 then return end
  t=seq==1 and math.min(t,total-1) or t%total
  for _,f in ipairs(frames) do
    t=t-math.max(1,f.duration)
    if t<0 then
      local rec=self.art[f.key]
      if rec then
        local path=rec.path
        if self.cache[path]==nil then self.cache[path]=Assets.image(path) or false end
        local image=self.cache[path]
        if image then
          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(image,160+(f.x or 0),80+(f.y or 0),f.rotation or 0,
            f.scaleX or 1,f.scaleY or 1,-(rec.originX or 0),-(rec.originY or 0))
        end
      end
      return
    end
  end
end
function Oak:panel(sub)
  local g=love.graphics;local p=self.phase;local choices=self:choices()
  g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  if sub then
    self:image(p=='gender' and 'gender' or p=='topics' and 'topics' or 'bottom')
    if choices then
      if p=='gender' then
        -- Native gender board contains both full avatars; select by side.
        self:image('boy_cursor',64,104);self:image('girl_cursor',192,104)
        g.setColor(1,1,1,1);g.rectangle('line',self.choice==1 and 4 or 132,4,120,180)
      else
        for n,text in ipairs(choices) do
          local y=32+(n-1)*48
          if self.choice==n then g.setColor(1,1,1,1);g.polygon('fill',12,y+2,18,y+6,12,y+10) end
          Font.draw(text,24,y)
        end
      end
    end
    return
  end
  self:image((p=='topics' or p=='lesson') and 'background_1' or 'background_0')
  if p=='shrink' then
    local f=math.floor(math.max(0,self.elapsed-30)/9)
    self:image(f==0 and self.gender..'_1' or self.gender..'_shrink_'..math.min(4,f))
    return
  end
  if p~='topics' and p~='lesson' and p~='greeting' then self:image('oak',
    (p=='inhabited' or p=='release' or p=='alongside') and -32 or 0,0) end
  if p=='release' then
    if self.elapsed<30 then self:mon(3,self.elapsed) else self:mon(1,self.elapsed-30) end
  elseif p=='alongside' then self:mon(2,self.frame) end
  if p=='topics' or p=='lesson' then
    local y=24
    for line in ((self.pages[self.page] or '')..'\n'):gmatch('([^\n]*)\n') do Font.draw(line,24,y);y=y+16 end
  elseif p~='release' then
    Font.drawDialogueBox(1,18,29,6)
    local y=152
    for line in ((self.pages[self.page] or '')..'\n'):gmatch('([^\n]*)\n') do
      if y>=184 then break end
      Font.draw(line,16,y);y=y+16
    end
  end
end
function Oak:draw()
  local dual=SecondScreen.separate(self.game)
  -- Automatically show the controls when a choice is needed. L/SELECT also
  -- exposes the other panel; all choices accept directions and A.
  local sub=self.bottom
  if sub==nil then sub=self:choices()~=nil end
  sub=not dual and sub
  self:panel(sub)
  if dual then
    SecondScreen.draw(self.game,function() self:panel(true) end)
    self.game.secondScreenPointerOwner=self
  end
end
function Oak:touchpressed(id,x,y)
  local px,py=SecondScreen.toLocal(self.game,x,y)
  if not px then
    local r=require('src.render.Renderer').uiPresentation
    if not r then return false end
    px,py=(x-r.x)/r.scaleX,(y-r.y)/r.scaleY
  end
  if px<0 or py<0 or px>=256 or py>=192 then return false end
  local choices=self:choices()
  if choices then
    self.choice=self.phase=='gender' and (px<128 and 1 or 2)
      or math.max(1,math.min(#choices,math.floor((py-16)/48)+1))
  end
  self.tap=true;return true
end
return Oak
