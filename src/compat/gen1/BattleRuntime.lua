-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observe real native stack admissions. Completed source views keep no save,
-- controller, imported dataset or borrowed GPU resource alive.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Views=require('src.compat.gen1.BattleView')
local R={};R.__index=R
local function owner()
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return host and host.currentMod or facade and facade._callbackOwner()
end
local function cohort(c)
  return c.game.data==c.data and c.game.save==c.save and c.game.mods==c.loader
    and c.game.stack==c.stack and Version.get()==c.edition
end
local function member(c)
  if c.retired or not cohort(c)then return false end
  for _,state in ipairs(c.stack.states or{})do if state==c.screen then return true end end
  return false
end
function R.new()return setmetatable({records=setmetatable({},{__mode='kv'})},R)end
function R:retire(c,completed)
  if not c or c.retired then return end
  c.views:retire();c.retired=true
  self.records[c.screen]=nil
  if self.current==c then self.current=nil end
  if completed then
    self.last=c.views.view
    self.lastSession=setmetatable({c.game,c.data,c.save,c.stack,c.loader},{__mode='v'})
    self.lastEdition=c.edition
  end
end
function R:bind(screen)
  local game=screen and Native.game(screen.game)
  if not(game and game==Native.game()and screen.isBattleState and screen.data==game.data and game.stack and game.save)then return end
  local c=self.records[screen]
  if c and member(c)then local who=owner();if who then c.users[who]=true end;return c end
  if c then self:retire(c,false)end
  c={screen=screen,game=game,data=game.data,save=game.save,stack=game.stack,loader=game.mods,edition=Version.get(),users={}}
  if not member(c)then return end
  if self.current and self.current~=c then self:retire(self.current,false)end
  c.views=Views.new(game,screen,function()return member(c)end)
  local who=owner();if who then c.users[who]=true end
  self.records[screen]=c;self.current=c;self.last=nil
  return c
end
function R:active(value)
  local game=Native.game(value)
  if value~=nil and game~=Native.game()then return nil end
  local last=self.lastSession
  if last and(not game or last[1]~=game or last[2]~=game.data or last[3]~=game.save
      or last[4]~=game.stack or last[5]~=game.mods or self.lastEdition~=Version.get())then
    self.last,self.lastSession,self.lastEdition=nil,nil,nil
  end
  if self.current and(not member(self.current)or self.current.game~=game)then self:retire(self.current,false)end
  if not game then return end
  for i=#(game.stack and game.stack.states or{}),1,-1 do
    local state=game.stack.states[i]
    if state.isBattleState and state.game==game then return self:bind(state)end
  end
end
function R:exit(screen)
  local c=self.records[screen]
  if c then self:retire(c,cohort(c))end
end
function R:release()
  if self.current then self:retire(self.current,false)end
  self.last,self.lastSession,self.lastEdition=nil,nil,nil
end
function R:poll()self:active()end
function R:releaseOwner(who)
  if self.current and self.current.users[who]then self:retire(self.current,false)end
end
R.member=member
return R
