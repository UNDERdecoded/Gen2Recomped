-- DisplayCaughtContestMonStats: the full-screen STOCK/THIS catch comparison.
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Comparison = {}
Comparison.__index = Comparison
Comparison.isOpaque = true

function Comparison.new(game, stock, candidate, onChoose)
  return setmetatable({game=game,stock=stock,candidate=candidate,
    choice=require("src.ui.ChoiceBox").new(game,onChoose,
      {tx=14,ty=7,tw=6,th=5})},Comparison)
end

function Comparison:update(dt) self.choice:update(dt) end

function Comparison:draw()
  love.graphics.setColor(1,1,1,1)
  love.graphics.rectangle("fill",0,0,160,144)
  for index,mon in ipairs({self.stock,self.candidate}) do
    local y=(index-1)*6
    Font.drawBox(0,y,15,6)
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",16,y*8,88,8)
    love.graphics.setColor(0,0,0,1)
    Font.draw(Strings(index==1 and " STOCK " or " THIS "),16,y*8)
    local codes=(self.game.data.field or {}).gen2BattleMenuMon or {0xE1,0xE2}
    for i,code in ipairs(codes) do Font.drawCode(code,72+(i-1)*8,y*8) end
    Font.draw(" ",72+#codes*8,y*8)
    -- Stock always uses the species name, not a nickname. THIS uses the
    -- wild enemy nickname; caught contest mons are not nicknamed until judging.
    local def=self.game.data.pokemon[mon.species]
    local name=(index==2 and mon.nickname) or (def and def.name) or mon.species
    Font.draw(name,8,(y+2)*8)
    local x=8+#Font.split(name)*8
    local level=mon.level or 0
    if level<100 then
      Font.drawCode(0x6E,x,(y+2)*8) -- PrintLevel's small Lv glyph
      x=x+8
    end
    Font.draw(tostring(level),x,(y+2)*8)
    Font.draw(Strings("HEALTH"),40,(y+4)*8)
    Font.draw(("%3d"):format(mon.maxHp or mon.maxHP or 0),88,(y+4)*8)
  end
  Font.drawBox(0,12,20,6)
  love.graphics.setColor(0,0,0,1)
  Font.draw(Strings("Switch POKéMON?"),8,112)
  self.choice:draw()
  love.graphics.setColor(1,1,1,1)
end

return Comparison
