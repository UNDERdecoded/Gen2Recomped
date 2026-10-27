-- Gen2 status/move-screen contracts over this engine's actual Pokemon.
-- Layout and input follow Gen1Recomp 535a5ec0 src/ui/gen2/SummaryMenu.lua;
-- existing engine/Gen1 rights remain applicable (NOTICE.md).
-- Native-owner integration: Roxas2712 (LICENSE-ROXAS2712.md).
local Font = require('src.render.Font')
local Strings = require('src.core.Strings')
local TypeChart = require('src.battle.TypeChart')
local Pokemon = require('src.pokemon.Pokemon')
local Growth = require('src.pokemon.Growth')
local WaitSfx = require('src.ui.Gen2WaitPlaySFX')
local M = {}
function M.install(Summary)
  function Summary:speciesDef()
    return self.mon and self.pokemon and self.pokemon[self.mon.species]
  end
  function Summary:moveDef(id)
    if type(id)=='table' then id=id.id end
    return id and self.moves and self.moves[id] or nil
  end
  function Summary:moveList() return self.mon and self.mon.moves or {} end
  function Summary:moveName(entry)
    local def=entry and self:moveDef(entry.id)
    return def and def.name or entry and entry.id
  end
  function Summary:growth()
    local def=self:speciesDef()
    return def and self.game.data.growth_rates and self.game.data.growth_rates[def.growthRate]
  end
  function Summary:expToNext()
    local mon,def=self.mon,self:speciesDef()
    if not(mon and def)or mon.level>=100 then return 0 end
    return math.max(0,Growth.expForLevel(def.growthRate,mon.level+1,self.game.data.growth_rates)-(mon.exp or 0))
  end
  function Summary:otName()
    return self.mon.ot or self.mon.otName or (self.save and self.save.player or {}).name or 'GOLD'
  end
  function Summary:otId() return self.mon.otId or (self.save and self.save.player or {}).id or 0 end
  function Summary:itemName()
    local item=self.mon.item;local def=item and self.items and self.items[item]
    return def and def.name or item
  end
  function Summary:typeNames()
    local def=self:speciesDef();local types=self.mon.types or def and def.types or {}
    local a,b=types[1],types[2]
    return a and TypeChart.displayName(a,self.game.data),b and b~=a and TypeChart.displayName(b,self.game.data)or nil
  end
  function Summary:close()
    if self.closed then return end
    self.closed=true
    if self.onClose then self.onClose() else self.game.stack:pop() end
  end
  function Summary:turnPage(delta) self.page=(self.page-1+delta)%3+1 end
  function Summary:switchMon(delta) return self:moveMon(delta) end
  function Summary:switchMonPastEggs(delta)
    local target=self.index+delta
    while self.party[target] and require('src.pokemon.Party').isEgg(self.party[target])do target=target+delta end
    if not self.party[target]then return false end
    return self:moveMon(target-self.index)
  end
  function Summary:swapMoves(from,to)
    local moves=self:moveList()
    if from==to or not(moves[from] and moves[to])then return false end
    moves[from],moves[to]=moves[to],moves[from]
    return true
  end
  function Summary:playSwapSfx()
    local Sound=require('src.core.Sound');local data=self.game.data
    local sfx=data.audio and data.audio.sfx
    -- The importer already installs native labels and shared-role aliases.
    if sfx and sfx.Sfx_SwitchPokemon then Sound.play(data,'Sfx_SwitchPokemon')end
  end
  function Summary:tickRepeatSfx()
    if not self.repeatSfx then return false end
    if WaitSfx.waiting(self.repeatSfx,self.game)then return true end
    self.repeatSfx=nil;self:playSwapSfx();return false
  end
  function Summary:updateMoveDetail(input)
    local moves=self:moveList();local count=math.max(1,#moves)
    if input:wasPressed('up')then self.moveIndex=self.moveIndex>1 and self.moveIndex-1 or count
    elseif input:wasPressed('down')then self.moveIndex=self.moveIndex<count and self.moveIndex+1 or 1
    elseif input:wasPressed('a')then
      if self.swapFrom then
        if self:swapMoves(self.swapFrom,self.moveIndex)then
          self:playSwapSfx();self.repeatSfx=WaitSfx.arm('Sfx_SwitchPokemon')
        end
        self.swapFrom=nil
      elseif moves[self.moveIndex]then self.swapFrom=self.moveIndex end
    elseif input:wasPressed('right')then if not self.swapFrom then self:switchMonPastEggs(1)end
    elseif input:wasPressed('left')then if not self.swapFrom then self:switchMonPastEggs(-1)end
    elseif input:wasPressed('b')or input:wasPressed('select')then
      if self.swapFrom then self.moveIndex=self.swapFrom;self.swapFrom=nil
      elseif self.moveScreen then self:close()
      else self.moveDetail=false end
    end
  end
  function Summary:moveDetailPlacements()
    local out={};local function put(text,x,y)out[#out+1]={text=text,x=x,y=y}end
    local mon=self.mon;local name=mon.nickname or mon.name or(self:speciesDef()or{}).name or mon.species
    put(name,5,1)
    if require('src.ui.LevelDisplay').visible(mon,'summary',self.game)then
      put('<LV>'..tostring(mon.level),5+Font.width(name)/8,1)
    end
    local moves=self:moveList()
    for slot=1,4 do
      local move=moves[slot];local y=3+(slot-1)*2
      put(move and self:moveName(move)or'-',2,y)
      if move then
        put(Strings('PP'),10,y+1);put(('%2d/%2d'):format(move.pp or 0,Pokemon.maxPP(self:moveDef(move.id),move)),13,y+1)
      else put('--',10,y+1)end
    end
    put('┌─────┐',0,10);put(self.swapFrom and'│     └'or'│'..Strings('TYPE/')..'└',0,11)
    if self.swapFrom then put(Strings('Where?'),1,12);return out end
    local move=moves[self.moveIndex];local def=move and self:moveDef(move.id)
    put(def and TypeChart.displayName(def.type,self.game.data)or'---',2,12)
    put(Strings('ATTACK/'),11,12)
    put(def and(def.power or 0)>=2 and('%3d'):format(def.power)or'---',16,12)
    local y=14
    for line in ((def and def.description or'')..'<NEXT>'):gmatch('(.-)<NEXT>')do
      if y>16 then break end
      if line~=''then put(line,1,y)end;y=y+2
    end
    return out
  end
  function Summary:drawMoveDetail()
    local Chrome=require('src.ui.Gen2Chrome');Chrome.clear()
    Chrome.textbox(0,1,18,9);Chrome.textbox(0,11,18,5)
    local placements=self:moveDetailPlacements()
    -- Name/level and the TYPE plaque deliberately replace border cells.
    Chrome.paletteFill(40,8,math.min(120,Font.width(placements[1].text)+32),8)
    Chrome.paletteFill(0,80,56,16)
    if self.index>1 then Chrome.print('◀',16,0)end
    if self.index<#self.party then Chrome.print('▶',18,0)end
    for _,v in ipairs(placements)do
      -- The native border table owns these cells. A reduced font need not
      -- advertise Unicode box characters in its text charmap.
      if v.x==0 and v.y==10 then
        local b=Font.BORDER;love.graphics.setColor(1,1,1,1)
        Font.drawCode(b.tl,0,80)
        for x=1,5 do Font.drawCode(b.t or b.h,x*8,80)end
        Font.drawCode(b.tr,48,80)
      elseif v.x==0 and v.y==11 then
        local b=Font.BORDER;love.graphics.setColor(1,1,1,1)
        Font.drawCode(b.l or b.v,0,88);Font.drawCode(b.bl,48,88)
        if not self.swapFrom then Chrome.print(Strings('TYPE/'),1,11)end
      else Chrome.print(v.text,v.x,v.y)end
    end
    local count=#self:moveList()
    if count>0 then
      if self.swapFrom then Chrome.cursor(1,3+(self.swapFrom-1)*2,true)end
      Chrome.cursor(1,3+(math.min(self.moveIndex,count)-1)*2)
    end
  end
end
return M
