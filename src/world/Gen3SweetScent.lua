-- Native Sweet Scent sequence: red blend 0 -> 8, 65-frame hold, encounter,
-- and on failure blend 8 -> 0 before the cartridge's failure message.
-- The rectangle reconstructs the blend; it does not emulate palette masks.
local Scent={}
Scent.__index=Scent
function Scent.failureText(data)
  for _,text in pairs(data.text or {}) do
    if type(text)=="string" and text:match("^Looks like") and text:find("nothing here",1,true) then return text end
  end
  return "Looks like there’s nothing here…"
end
function Scent.show(game,ow)
  local self=setmetatable({game=game,ow=ow,phase="in",frames=0,blend=0},Scent)
  require("src.core.Sound").playNamedEffect(game.data,"M_SWEET_SCENT")
  game.stack:push(self)
  return self
end
function Scent:uiSize() return require("src.ui.Theme").uiSize() end
function Scent:update()
  if self.done then return end
  self.frames=self.frames+1
  if self.phase=="in" then
    self.blend=math.min(8,math.floor(self.frames/5))
    if self.frames>=40 then self.phase="hold";self.frames=0 end
  elseif self.phase=="hold" and self.frames>=65 then
    -- The encounter pushes a battle. Remove this state first, so finishing
    -- the effect can never pop the battle that its callback just created.
    self.game.stack:pop()
    if self.ow:gen2SweetScentEncounter(true) then self.done=true
    else self.phase="out";self.frames=0;self.game.stack:push(self) end
  elseif self.phase=="out" then
    self.blend=math.max(0,8-math.floor(self.frames/5))
    if self.frames>=40 then
      self.done=true;self.game.stack:pop()
      self.game.stack:push(require("src.render.TextBox").new(self.game,Scent.failureText(self.game.data)))
    end
  end
end
function Scent:draw()
  local g=love.graphics
  local w,h=self:uiSize()
  g.setColor(1,0,0,self.blend/16);g.rectangle("fill",0,0,w,h);g.setColor(1,1,1,1)
end
function Scent:keypressed() end
return Scent
