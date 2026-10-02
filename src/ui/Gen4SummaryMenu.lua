-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's SUMMARY PAGES.
--
-- THE WORDS ARE ALL BANK 455's, and finding that bank is the part worth
-- recording: "To Next Lv." occurs exactly once in all 1,127 message banks, and
-- around it sit the six page titles, every field label, the twenty-five nature
-- lines and the twenty-five characteristic lines.  Two other banks looked like
-- this one -- 326 and 336 both carry "Exp. Points", "Nature" and "Item" -- and
-- both are DEBUG menus, full of "Random value", "HP rnd" and "msg location".
-- Three common words in common is not an identification; a phrase that occurs
-- once is.
--
-- THE ROWS ARE MEASURED off the pages themselves.  Each page is a panel of
-- stripes and a stripe boundary is a row: on `page_info` the colour changes at
-- y = 40, 56, 72, 88, 104, 120, 136 -- a sixteen-pixel pitch, one row per
-- label -- and on `page_battle_moves` at 50, 82, 114, 146, which is the four
-- move rows at a pitch of thirty-two.  The white value boxes sit at x = 180.
--
-- Info, memo, skills, condition, battle moves and ribbons have page behavior.
-- Contest move details still need their own implementation.
--
-- THE POKEMON'S PICTURE is drawn from `PICTURE` below.  The screen had declared
-- a slot for it since it was written and never drawn into it, so every summary
-- page in Sinnoh was a page of numbers with an empty plate beside them.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Party = require("src.pokemon.Party")
local Sprites = require("src.pokemon.Sprites")
local Strings = require("src.core.Strings")
local Growth = require("src.pokemon.Growth")

local Gen4SummaryMenu = {}
Gen4SummaryMenu.__index = Gen4SummaryMenu
Gen4SummaryMenu.isOpaque = true

local W, H = 256, 192
local fitted
-- Main-screen text windows from Platinum's summary window templates.
local INFO_WINDOWS = {
  {112,40,192,40,48}, {112,56,184,56,64}, {112,72,184,72,64},
  {112,88,184,88,64}, {112,104,200,104,32},
  {112,120,192,136,48}, {112,152,192,168,48},
}
local SKILL_WINDOWS = {
  {144,32,184,32,56,'centre'}, {112,56,200,56,24,'right'},
  {112,72,200,72,24,'right'}, {112,88,200,88,24,'right'},
  {112,104,200,104,24,'right'}, {112,120,200,120,24,'right'},
}
Gen4SummaryMenu.INFO_WINDOWS = INFO_WINDOWS
Gen4SummaryMenu.SKILL_WINDOWS = SKILL_WINDOWS

local FALLBACK_LAYOUT = {
  label = { x = 112 }, value = { x = 180 },
  name = { x = 24, y = 24 }, picture = { x = 52, y = 104, plate = 64 },
  info = { first = 40, pitch = 16, rows = 7 },
  skills = { first = 40, pitch = 16, rows = 6, ability = 144, abilityText = 162 },
  moves = { first = 32, pitch = 32, rows = 4 },
}

-- WHERE THE POKEMON GOES.  Both numbers are the cartridge's and both are
-- stated twice; the derivation is written out in `Gen4Menus.SUMMARY_LAYOUT`,
-- which is where an import gets them from.  Repeated here so a cache that
-- predates the picture being drawn at all still puts it in the right place.
Gen4SummaryMenu.PICTURE = { x = 52, y = 104, plate = 64 }

-- THE SPRITE IS 80 SQUARE AND THE PLATE UNDER IT IS 64, so the Pokemon
-- overhangs its plate on every side.  Not a scale: the cartridge draws the
-- pokegra cell at 1:1 (MON_AFFINE_SCALE(1)) and lets it overflow.
Gen4SummaryMenu.PICTURE_SIZE = 80

-- AN EGG IS NOT A SPECIES ROW.  pl_otherpoke files the two eggs under species
-- 0, so they land in `gen4_species_sprites.forms` rather than on any
-- `data.pokemon` row.  The key is `Gen4Otherpoke.key`'s own format,
-- ("%03d_%s_%s"):format(species, name, form), and tools/gen4_summary_check.lua
-- asserts this string against that function so the spelling cannot drift.
-- Manaphy eggs select the separately extracted form using species 490.
Gen4SummaryMenu.EGG_KEY = "000_egg_base"

function Gen4SummaryMenu:uiSize() return W, H end
function Gen4SummaryMenu:wantsFillScale() return true end
function Gen4SummaryMenu:wantsEdgeBleed() return false end

function Gen4SummaryMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

-- The caller hands over the Pokemon itself, which is the shape every other
-- summary screen in this port is pushed with.
function Gen4SummaryMenu.new(game, arg)
  local self = setmetatable({}, Gen4SummaryMenu)
  self.game = game
  if arg and arg.species ~= nil then
    self.mon = arg
  else
    self.mon = arg and arg.mon
    self.onCancel = arg and arg.onCancel
    self.choose = arg and arg.choose
    self.readOnlyMoves = arg and arg.readOnlyMoves
  end
  self.page = 1
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  local record = ((game.data or {}).gen4_menus or {}).summary
  if not record then
    Logger.warn("gen4 summary: this cache carries no summary text -- "
                .. "falling back to the engine's own words")
  end
  self.text = (record and record.text) or {}
  local pages = (record and record.pages) or {
    { key = "info", art = "summary/page_info" },
    { key = "skills", art = "summary/page_skills" },
    { key = "moves", art = "summary/page_battle_moves" },
  }
  self.pages={}
  local hasMemo=false
  for _,page in ipairs(pages) do if page.key=='memo' then hasMemo=true end end
  for _,page in ipairs(pages) do
    self.pages[#self.pages+1]=page
    if page.key=='info' and not hasMemo then
      self.pages[#self.pages+1]={key='memo',art='summary/page_memo',
        title=self.text.memo or Strings('TRAINER MEMO')}
    end
  end
  local function addPage(key,after,art,title)
    for _,page in ipairs(self.pages) do if page.key==key then return end end
    for i,page in ipairs(self.pages) do
      if page.key==after then
        table.insert(self.pages,i+1,{key=key,art=art,title=self.text[key] or title});return
      end
    end
  end
  addPage('condition','skills','summary/page_condition',Strings('CONDITION'))
  addPage('ribbons','moves','summary/page_ribbons',Strings('RIBBONS'))
  addPage('exit','ribbons','summary/page_exit','')
  local order={info=1,memo=2,skills=3,moves=4,condition=5,contestMoves=6,ribbons=7,exit=8}
  table.sort(self.pages,function(a,b) return (order[a.key] or 99)<(order[b.key] or 99) end)
  self:ensureVisiblePage()
  self.layout = (record and record.layout) or FALLBACK_LAYOUT
  self.natures = (record and record.natures) or {}
  return self
end

function Gen4SummaryMenu:word(key, fallback)
  local text = self.text[key]
  if type(text) ~= "string" or text == "" then return fallback or "" end
  -- The cartridge's colour codes pick a palette row this port has no text
  -- style for yet; dropped rather than printed as `{COLOR 2}`.
  return (text:gsub("{COLOR %d+}", ""))
end

-- One loader, by PATH.  The page art arrives as an art key and the Pokemon's
-- picture as a path off the species row, so the key lookup is the wrapper and
-- this is the part both share.
function Gen4SummaryMenu:image(path)
  if type(path) ~= "string" or path == "" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4SummaryMenu:img(key)
  local rec = self.art[key]
  return self:image((type(rec) == "table" and rec.path) or rec)
end

function Gen4SummaryMenu:close()
  if self.cry and self.cry.stop then self.cry:stop() end
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4SummaryMenu:visiblePages()
  local pages={}
  for i,page in ipairs(self.pages) do
    if not Party.isEgg(self.mon) or page.key=='memo' or page.key=='exit' then pages[#pages+1]=i end
  end
  return pages
end

function Gen4SummaryMenu:ensureVisiblePage()
  local pages=self:visiblePages()
  for _,i in ipairs(pages) do if self.page==i then return end end
  self.page=pages[1] or 1
end

function Gen4SummaryMenu:changePage(delta)
  local pages=self:visiblePages()
  for at,i in ipairs(pages) do
    if self.page==i then self.page=pages[(at-1+delta)%#pages+1];return end
  end
  self:ensureVisiblePage()
end

function Gen4SummaryMenu:update()
  local input = self.game.input
  if not input then return end
  if self.moveMode then
    if input:wasPressed('up') then self.moveIndex=(self.moveIndex-2)%5+1
    elseif input:wasPressed('down') then self.moveIndex=self.moveIndex%5+1
    elseif input:wasPressed('a') then self:selectMove()
    elseif input:wasPressed('b') then self:backFromMove()
    end
    return
  end
  local n = #self.pages
  if self.ribbonMode then
    local count=#self:ribbonList()
    if input:wasPressed('b') then self.ribbonMode=nil
    elseif count>0 then
      local delta=input:wasPressed('right') and 1 or input:wasPressed('left') and -1
        or input:wasPressed('up') and -4 or input:wasPressed('down') and 4
      if delta then self.ribbonIndex=((self.ribbonIndex or 1)-1+delta)%count+1 end
    end
    return
  end
  if input:wasPressed("right") then
    self:changePage(1)
  elseif input:wasPressed("left") then
    self:changePage(-1)
  elseif input:wasPressed('up') then
    self:changePokemon(-1)
  elseif input:wasPressed('down') then
    self:changePokemon(1)
  elseif input:wasPressed('a') and self.pages[self.page].key=='moves' then
    self.moveMode=true;self.moveIndex=1
  elseif input:wasPressed('a') and self.pages[self.page].key=='ribbons' then
    if #self:ribbonList()>0 then self.ribbonMode=true;self.ribbonIndex=1 end
  elseif input:wasPressed("b")
         or (input:wasPressed('a') and self.pages[self.page].key=='exit') then
    self:close()
  end
end

-- ------------------------------------------------------------------- draw --

function Gen4SummaryMenu:speciesDef()
  local mon = self.mon
  local data = self.game.data
  if not (mon and data and data.pokemon) then return nil end
  return require('src.pokemon.Gen4Forms').definition(data,mon)
end

function Gen4SummaryMenu:row(page, i)
  local box = self.layout[page] or FALLBACK_LAYOUT[page]
  return box.first + (i - 1) * box.pitch + 4
end

function Gen4SummaryMenu:memoLines()
  local mon=self.mon
  local data=self.game.data
  local bank=data.text or {}
  local function word(index)
    local text=bank[('TEXT_B0455_%05d'):format(index)]
    return type(text)=='string' and text:gsub('{COLOR %d+}','') or nil
  end
  local function date(prefix)
    local record=type(mon[prefix..'Date'])=='table' and mon[prefix..'Date'] or {}
    local year=tonumber(record.year or mon[prefix..'Year'])
    local month=tonumber(record.month or mon[prefix..'Month'])
    local day=tonumber(record.day or mon[prefix..'Day'])
    local months={'Jan.','Feb.','Mar.','Apr.','May','Jun.','Jul.','Aug.','Sep.','Oct.','Nov.','Dec.'}
    if not (year and month and day and months[month] and day>=1 and day<=31) then return nil end
    local template=word(49)
    if not template then return nil end
    template=template:match('([^\n]+)')
    return template:gsub('{STRVAR_1 74 1 0}',months[month])
      :gsub('{STRVAR_1 51 2 0}',tostring(math.floor(day)))
      :gsub('{STRVAR_1 51 0 0}',('%02d'):format(year%100))
  end
  local function locationName(location)
    if type(location)~='string' then return nil end
    local map=(data.maps or {})[location]
    return map and (map.name or map.displayName) or location
  end
  if Party.isEgg(mon) then
    local period=require('src.pokemon.DayCare').EGG_STEP_PERIOD
    local cycles=tonumber(mon.eggCycles)
      or (mon.eggSteps and math.ceil(mon.eggSteps/period))
      or tonumber(mon.friendship) or 41
    local index=cycles<=5 and 105 or cycles<=10 and 106 or cycles<=40 and 107 or 108
    local lines={}
    local origin=locationName(mon.eggLocation)
    local obtained=date('egg')
    if obtained then lines[#lines+1]={y=40,text=obtained} end
    if origin and word(101) then
      local template=word(101)
      local y=56
      for text in template:gmatch('[^\n]+') do
        if not text:find('{STRVAR_1 74',1,true) then
          lines[#lines+1]={y=y,text=text:gsub('{STRVAR_1 4 8 0}',origin)};y=y+16
        end
      end
    end
    local y=112
    for text in tostring(word(index) or ''):gmatch('[^\n]+') do
      lines[#lines+1]={y=y,text=text};y=y+16
    end
    return lines
  end
  local nature=mon.personality and mon.personality%25
  if nature==nil then
    for i,name in ipairs((data.constants or {}).natureOrder or {}) do
      if name==mon.nature then nature=i-1;break end
    end
  end
  local lines={}
  local function add(y,text) if text then lines[#lines+1]={y=y,text=text} end end
  if nature then
    add(40,word(24+nature) or ((self.natures[nature+1] or ''):gsub('{COLOR %d+}','')))
  end
  local player=(self.game.save or {}).player or {}
  local traded=mon.otId~=nil and player.id~=nil and mon.otId~=player.id
  local fateful=mon.fatefulEncounter==true or mon.fatefulEncounter==1
      or mon.fateful==true or mon.fateful==1
  if mon.hatched or (mon.metLevel==0 and mon.eggLocation) then
    local index=fateful and (traded and 59 or 58) or (traded and 53 or 52)
    local text=word(index)
    local at=0
    for line in tostring(text or ''):gmatch('[^\n]+') do
      at=at+1
      if at==1 then add(56,date('egg'))
      elseif at==2 then add(72,locationName(mon.eggLocation))
      elseif at==4 then add(104,date('met'))
      elseif at==5 then add(120,locationName(mon.metLocation))
      else add(56+(at-1)*16,line) end
    end
    self.memoExtraLines=fateful and 4 or 3
  else
   add(56,date('met'))
   add(72,locationName(mon.metLocation))
   if mon.metLevel then
    local index=fateful and (traded and 57 or 56) or (traded and 50 or 49)
    local text=word(index)
    local at=0
    for line in tostring(text or ''):gmatch('[^\n]+') do
      at=at+1
      if at>2 then add(88+(at-3)*16,line:gsub('{STRVAR_1 52 3 0}',tostring(mon.metLevel))) end
    end
    self.memoExtraLines=math.max(0,at-3)
   else
    self.memoExtraLines=0
   end
  end
  if type(mon.ivs)=='table' then
    local names={'hp','attack','defense','speed','spAttack','spDefense'}
    local aliases={nil,'atk','def','spe','spatk','spdef'}
    local start=(tonumber(mon.personality) or 0)%6
    local best,bestValue=start,-1
    for step=0,5 do
      local slot=(start+step)%6
      local value=tonumber(mon.ivs[names[slot+1]] or mon.ivs[aliases[slot+1]]) or 0
      if value>bestValue then best,bestValue=slot,value end
    end
    add(120+(self.memoExtraLines or 0)*16,word(71+best*5+bestValue%5))
  end
  if nature then
    local raised=math.floor(nature/5)
    local flavor={0,4,2,1,3}
    local y=136+(self.memoExtraLines or 0)*16
    if y<192 then add(y,word(raised==nature%5 and 70 or 65+flavor[raised+1])) end
  end
  return lines
end

function Gen4SummaryMenu:drawMemo()
  for _,line in ipairs(self:memoLines()) do
    fitted(line.text,112,line.y,136)
  end
end

function Gen4SummaryMenu:backFromMove()
  if self.swapMove then self.swapMove=nil
  else self.moveMode=nil;self.moveIndex=nil end
end

function Gen4SummaryMenu:selectMove()
  local index=self.moveIndex
  if index==5 then self.swapMove=nil;self:backFromMove();return end
  local moves=self.mon.moves or {}
  if not moves[index] then return end
  if self.readOnlyMoves then return end
  if self.swapMove then
    moves[index],moves[self.swapMove]=moves[self.swapMove],moves[index]
    self.swapMove=nil
  else self.swapMove=index end
end

function Gen4SummaryMenu:touchpressed(_,px,py)
  local r=require('src.render.Renderer').uiPresentation
  if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
  local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
  if not self.moveMode and not self.ribbonMode and y>=16 and y<32 then
    for _,tab in ipairs(self:pageTabs()) do
      if x>=tab.x and x<tab.x+tab.width then self.page=tab.page;return true end
    end
  end
  local page=self.pages[self.page]
  if page.key=='ribbons' and x>=116 and x<244 and y>=36 and y<116 then
    local ribbons=self:ribbonList()
    local index=math.min(self.ribbonIndex or 1,math.max(1,#ribbons))
    local scroll=math.max(0,math.floor((index-1)/4)-1)*4
    local slot=math.floor((x-116)/32)+math.floor((y-36)/40)*4+1
    if ribbons[scroll+slot] then self.ribbonIndex=scroll+slot;self.ribbonMode=true end
  elseif page.key=='exit' and x>=144 and x<216 and y>=80 and y<104 then self:close()
  elseif self.ribbonMode and x<104 then self.ribbonMode=nil
  elseif page.key=='moves' and x>=128 and y>=32 then
    local index=math.floor((y-32)/32)+1
    if index<=5 then
      if not self.moveMode then self.moveMode=true;self.moveIndex=index
      else self.moveIndex=index;self:selectMove() end
    end
  elseif self.moveMode and x<128 then self:backFromMove()
  elseif x<104 and y>=56 and y<152 and not Party.isEgg(self.mon) then
    if self.cry and self.cry.stop then self.cry:stop() end
    self.cry=require('src.core.Sound').playCry(self.game.data,self.mon.species)
  end
  return true
end

function Gen4SummaryMenu:mousepressed(x,y,button)
  if button==1 then return self:touchpressed('mouse',x,y) end
end

function Gen4SummaryMenu:changePokemon(delta)
  self.ribbonIndex=1
  local party=(self.game.save or {}).party or {}
  if #party<2 then return end
  for i,mon in ipairs(party) do
    if mon==self.mon then
      self.mon=party[(i-1+delta)%#party+1]
      self:ensureVisiblePage()
      if self.cry and self.cry.stop then self.cry:stop() end
      if not Party.isEgg(self.mon) then
        self.cry=require('src.core.Sound').playCry(self.game.data,self.mon.species)
      end
      return
    end
  end
end

function Gen4SummaryMenu:ribbonList()
  local out={}
  local seen={}
  local definitions=require('src.ui.Gen4RibbonData')
  for id,held in pairs(self.mon.ribbons or {}) do
    local number=tonumber(id)
    if held and held~=0 and number and definitions[number] and not seen[number] then
      out[#out+1]=number;seen[number]=true
    end
  end
  table.sort(out);return out
end

function Gen4SummaryMenu:drawRibbons()
  local g=love.graphics
  local ribbons=self:ribbonList()
  local index=math.min(self.ribbonIndex or 1,math.max(1,#ribbons))
  local scroll=math.max(0,math.floor((index-1)/4)-1)*4
  for slot=1,8 do
    local id=ribbons[scroll+slot]
    if id then
      local rec=require('src.ui.Gen4RibbonData')[id]
      local icon=self:img(('summary/ribbon_%02d'):format(id)) or self:img(rec.art)
      if icon then
        local w,h=icon:getDimensions()
        g.draw(icon,132+(slot-1)%4*32,56+math.floor((slot-1)/4)*40,0,1,1,w/2,h/2)
      end
    end
  end
  fitted(tostring(#ribbons),208,168,40,'centre')
  if self.ribbonMode and ribbons[index] then
    g.setColor(.98,1,1,1);g.rectangle('fill',0,144,256,48);g.setColor(1,1,1,1)
    local slot=index-scroll-1
    local cursor=self:img('summary/ribbon_cursor')
    if cursor then local w,h=cursor:getDimensions();g.draw(cursor,132+slot%4*32,56+math.floor(slot/4)*40,0,1,1,w/2,h/2) end
    local rec=require('src.ui.Gen4RibbonData')[ribbons[index]]
    local texts=self.game.data.text or {}
    local name=texts[('TEXT_B0535_%05d'):format(rec.name)] or rec.key
    fitted(name,8,144,240)
    local description=rec.description
    if rec.special then
      local value=(self.mon.specialRibbons or {})[rec.special]
      if value then description=146+value end
    end
    local text=description and texts[('TEXT_B0535_%05d'):format(description)]
    local y=160
    for line in tostring(text or ''):gmatch('[^\n]+') do
      if y<192 then fitted(line,8,y,240) end;y=y+16
    end
  end
end

function Gen4SummaryMenu:conditionVertices()
  local condition=self.mon.contest or {}
  local bounds={
    {'cool',5138,735,5138,3784,0,12},
    {'beauty',5538,383,8344,965,11,2},
    {'cute',5380,-106,7079,-2955,7,-11},
    {'smart',4803,-106,3106,-2955,-7,-11},
    {'tough',4645,383,1843,965,-11,2},
  }
  local pixels=96/(16*math.tan(0x5C1*2*math.pi/65536))/4096
  local vertices={}
  for _,b in ipairs(bounds) do
    local stat=math.max(0,math.min(255,tonumber(condition[b[1]]) or 0))
    local x=stat==255 and b[4] or b[2]+b[6]*stat
    local y=stat==255 and b[5] or b[3]+b[7]*stat
    vertices[#vertices+1]=128+x*pixels;vertices[#vertices+1]=96-y*pixels
  end
  return vertices
end

function Gen4SummaryMenu:drawCondition()
  local g=love.graphics
  g.setColor(8/31,1,15/31,20/31);g.polygon('fill',self:conditionVertices());g.setColor(1,1,1,1)
  Font.draw(self:word('sheen','SHEEN'),112,160)
  local sheen=math.max(0,math.min(255,tonumber((self.mon.contest or {}).sheen) or 0))
  local count=sheen==255 and 12 or math.floor(math.floor(12*256/255)*sheen/256)
  local icon=self:img('summary/sheen_00')
  if icon then
    local w,h=icon:getDimensions()
    for i=1,count do g.draw(icon,152+(i-1)*8,168,0,1,1,w/2,h/2) end
  end
end

function Gen4SummaryMenu:dexNumber()
  local species=self.mon.species
  local orders=(self.game.data.gen4_dex or {}).orders
  local mode=((self.game.save or {}).pokedex or {}).national and 'national' or 'sinnoh'
  if orders and orders[mode] then
    for number,id in ipairs(orders[mode]) do if id==species then return number end end
    return nil
  end
  local def=self:speciesDef()
  return tonumber(def and (def.dexNumber or def.number)) or tonumber(species)
end

fitted = function(text,x,y,width,align)
  text=tostring(text)
  local pixels=Font.width(text)
  local scale=math.min(1,width/math.max(1,pixels))
  local g=love.graphics
  local offset=align=='centre' and (width-pixels*scale)/2 or align=='right' and width-pixels*scale or 0
  g.push();g.translate(x+offset,y);g.scale(scale,1)
  Font.draw(text,0,0);g.pop()
end

function Gen4SummaryMenu:field(page, i, label, value)
  local row = (page == 'skills' and SKILL_WINDOWS or INFO_WINDOWS)[i]
  fitted(label,row[1],row[2],row[3]-row[1]-4)
  if value ~= nil then
    fitted(value,row[3],row[4],row[5],row[6] or 'centre')
  end
end

function Gen4SummaryMenu:drawTypeBadge(typeName,x,y)
  local key='type_icons_'..tostring(typeName or ''):lower()
  local rec=((self.game.data.gen4_graphics or {}).battleObjects or {})[key]
  local image=self:image(type(rec)=='table' and rec.path or rec)
  if image then
    love.graphics.setColor(1,1,1,1);love.graphics.draw(image,x,y)
    return true
  end
  return false
end

function Gen4SummaryMenu:drawInfo()
  local mon, def = self.mon, self:speciesDef()
  local number = self:dexNumber()
  self:field("info", 1, self:word("dexNo", Strings("Pokédex No.")),
             number and ("%03d"):format(number) or self:word('unknown','???'))
  self:field("info", 2, self:word("name", Strings("Name")),
             (def and def.name) or tostring(mon.species))
  local types = def and def.types
  local typeText = "?"
  if type(types) == "table" then
    typeText = tostring(types[1] or "?")
    if types[2] and types[2] ~= types[1] then
      typeText = typeText .. "/" .. tostring(types[2])
    end
  end
  self:field("info", 3, self:word("types", Strings("Type")))
  local dual=types and types[2] and types[2]~=types[1]
  local typeX=dual and 183 or 200
  if not (types and self:drawTypeBadge(types[1],typeX,72)) then
    fitted(typeText,184,72,64,'centre')
  elseif dual then
    self:drawTypeBadge(types[2],217,72)
  end
  local player = (self.game.save or {}).player or {}
  self:field("info", 4, self:word("ot", "OT"),
             tostring(mon.otName or mon.ot or player.name or ""))
  self:field("info", 5, self:word("idNo", Strings("ID No.")),
             ("%05d"):format((tonumber(mon.otId or player.id) or 0) % 65536))
  self:field("info", 6, self:word("expPoints", Strings("Exp. Points")),
             tostring(math.floor(tonumber(mon.exp) or 0)))
  self:field("info", 7, self:word("toNextLv", Strings("To Next Lv.")),
             tostring(math.max(0,(tonumber(mon.level) or 1)>=100 and 0 or
               Growth.expForLevel(def and def.growthRate,(tonumber(mon.level) or 1)+1)
                 -(tonumber(mon.exp) or 0))))
end

function Gen4SummaryMenu:drawSkills()
  local mon = self.mon
  local stats = mon.stats or {}
  local hp = tonumber(mon.hp) or 0
  local max = tonumber(mon.maxHp) or tonumber(mon.maxhp) or tonumber(stats.hp) or 0
  self:field("skills", 1, self:word("hp", "HP"),
             ("%d%s%d"):format(hp, self:word("slash", "/"), max))
  self:field("skills", 2, self:word("attack", Strings("Attack")),
             tostring(stats.attack or stats.atk or "-"))
  self:field("skills", 3, self:word("defense", Strings("Defense")),
             tostring(stats.defense or stats.def or "-"))
  self:field("skills", 4, self:word("spAtk", "Sp. Atk"),
             tostring(stats.spAttack or stats.spatk or stats.specialAttack or "-"))
  self:field("skills", 5, self:word("spDef", "Sp. Def"),
             tostring(stats.spDefense or stats.spdef or stats.specialDefense or "-"))
  self:field("skills", 6, self:word("speed", Strings("Speed")),
             tostring(stats.speed or stats.spe or "-"))

  local box = self.layout.skills or FALLBACK_LAYOUT.skills
  Font.draw(self:word("ability", Strings("Ability")), self.layout.label.x, box.ability)
  local def = self:speciesDef()
  local ability = mon.ability or (def and def.abilities and def.abilities[1])
  if ability then
    local list = self.game.data.abilities
    local record = list and list[ability]
    if not record then
      local id=tonumber(ability)
      if not id then
        for number,name in pairs(require('src.import.Gen4Abilities').NAMES) do
          if name==ability then id=number;break end
        end
      end
      local text=self.game.data.text or {}
      if id then
        record={name=text[('TEXT_B0610_%05d'):format(id)],
          description=text[('TEXT_B0612_%05d'):format(id)]}
      end
    end
    fitted(tostring((record and record.name) or ability),168,144,88)
    local description=record and (record.description or record.desc)
    if type(description)=='string' then
      local line,y='',160
      for word in description:gmatch('%S+') do
        local nextLine=line=='' and word or line..' '..word
        if Font.width(nextLine)>144 and line~='' then
          Font.draw(line,112,y);y=y+16;line=word
        else line=nextLine end
        if y>=192 then break end
      end
      if y<192 then Font.draw(Font.fit(line,144),112,y) end
    end
  end
end

function Gen4SummaryMenu:drawMoves()
  local mon = self.mon
  local moves = mon.moves or {}
  local box = self.layout.moves or FALLBACK_LAYOUT.moves
  for i = 1, box.rows do
    local y = 32 + (i - 1) * 32
    local entry = moves[i]
    if entry then
      local id = (type(entry) == "table" and (entry.id or entry.move)) or entry
      local record = self.game.data.moves and self.game.data.moves[id]
      Font.beginTwoTone({1,1,1,1},{.38,.38,.38,1})
      fitted((record and record.name) or id,169,y+2,87)
      Font.endTwoTone()
      if record then self:drawTypeBadge(record.type,128,y) end
      local pp = type(entry) == "table" and entry.pp or nil
      local maxPp = record and record.pp
      if maxPp and type(entry)=='table' then
        maxPp=maxPp+math.min(3,math.max(0,tonumber(entry.ppUps) or 0))*math.floor(maxPp/5)
      end
      if pp or maxPp then
        fitted(("%s%s%s"):format(tostring(pp or "-"), self:word("slash", "/"),
                                    tostring(maxPp or "-")),
                  200,y+16,56,'centre')
      end
      Font.draw(self:word("pp", "PP"),184,y+16)
    else
      Font.draw(self:word("dashesLong", "---"),169,y+2)
    end
  end
  if self.moveMode then
    Font.draw(self:word('cancel','Cancel'),169,162)
    local cursor=self:img('summary/move_cursor_00')
    if cursor then love.graphics.draw(cursor,128,32+(self.moveIndex-1)*32) end
    if self.swapMove then
      local marked=self:img('summary/move_cursor_01') or cursor
      if marked then love.graphics.draw(marked,128,32+(self.swapMove-1)*32) end
    end
  end
end

function Gen4SummaryMenu:drawMoveDetails()
  local g=love.graphics
  -- The move-info tile atlas contains battle and contest panels. Only the
  -- battle rectangle is copied; drawing the entire atlas also paints the
  -- contest graph and off-screen tiles over the summary.
  g.setColor(.81,.84,.76,1);g.rectangle('fill',0,20,104,172);g.setColor(1,1,1,1)
  local panel=self:img('summary/move_info')
  if panel then
    local w,h=panel:getDimensions()
    local quad=love.graphics.newQuad(0,40,132,152,w,h)
    g.draw(panel,quad,0,40)
  end
  local entry=(self.mon.moves or {})[self.moveIndex]
  local id=type(entry)=='table' and (entry.id or entry.move) or entry
  local record=id and (self.game.data.moves or {})[id]
  Font.draw(self:word('category','Category'),8,64)
  Font.draw(self:word('power','Power'),8,80)
  Font.draw(self:word('accuracy','Accuracy'),8,96)
  if not record then return end
  fitted(Strings(record.class or ''),80,64,48,'centre')
  fitted((record.power or 0)>1 and record.power or '---',96,80,24,'centre')
  fitted((record.accuracy or 0)>0 and record.accuracy or '---',96,96,24,'centre')
  local y=112
  for paragraph in tostring(record.description or ''):gmatch('[^\n]+') do
    local line=''
    for word in paragraph:gmatch('%S+') do
      local candidate=line=='' and word or line..' '..word
      if Font.width(candidate)>120 and line~='' then
        if y<192 then Font.draw(line,8,y) end
        y=y+16;line=word
      else line=candidate end
    end
    if y<192 then Font.draw(Font.fit(line,120),8,y) end
    y=y+16
  end
end

-- A cache imported before any of this carries the PLATE'S TOP-LEFT under
-- `picture` rather than the sprite's centre, and the two cannot be told apart
-- by their values.  `plate` is what marks the new shape -- and the fallback is
-- the cartridge's own pair, so an old cache lands in the right place anyway
-- rather than eight pixels up and to the left of it.
function Gen4SummaryMenu:pictureSpot()
  local spot = self.layout.picture
  if type(spot) == "table" and tonumber(spot.plate) then return spot end
  return Gen4SummaryMenu.PICTURE
end

-- The picture, and whether it is mirrored.
--
-- IT IS MIRRORED, AND THAT IS THE CARTRIDGE'S DOING:
-- `monSprite.flip = SpeciesData_GetFormValue(.., SPECIES_DATA_FLIP_SPRITE) ^ 1`
-- (3d_anim.c 337), so the summary reverses every species whose flag is CLEAR
-- -- 480 of the 508 personal records -- and leaves the twenty-eight that are
-- set alone.
--
-- WHAT THE FLAG IS NOT is a facing: the pictures say so outright.  Torterra
-- has it SET and Bulbasaur CLEAR, and both are drawn facing left, so it cannot
-- mean "this art happens to point the other way".
--
-- WHAT IT READS AS is "do not reverse this one", and the members that settle
-- it are the ones a mirror would FALSIFY: UNOWN, whose sprite is a LETTER;
-- SPINDA, whose spots are the whole point of it; the Poliwag line's spiral;
-- Teddiursa's crescent.  Stated as a reading and not a derivation, because the
-- twenty-eight are not all obvious from outside the art team -- Torterra and
-- Chimchar are in the set and I cannot say why.  The CONSEQUENCE is what
-- matters here and it is not in doubt: those species come up facing the other
-- way from the rest of the party, on the cartridge as well as here.
--
-- The byte has been in the cache the whole time: Gen4Species.parse reads it as
-- `flipSprite` off the top bit of the byte that carries bodyColor, and nothing
-- had ever read it back.  On a Gen 1-3 cache there is no such field, and
-- `not nil` is true -- which would mirror Kanto -- so the mirror is asked for
-- only where the field EXISTS, and the caller says which.
function Gen4SummaryMenu:pictureArt()
  local mon, data = self.mon, self.game.data
  if not (mon and data) then return nil, false end
  if Party.isEgg(mon) then
    -- No flip: an egg has no personal record to read a flag out of, and it is
    -- drawn facing nowhere.
    local forms = (data.gen4_species_sprites or {}).forms or {}
    local species=tonumber(mon.species) or tonumber((data.pokemon or {})[mon.species] and data.pokemon[mon.species].id)
    local key=species==490 and '000_egg_manaphy' or Gen4SummaryMenu.EGG_KEY
    local rec = forms[key]
    return self:image(type(rec) == "table" and rec.front or nil), false
  end
  local path = Sprites.path(data, mon.species, "front",
                            { mon = mon, kind = "summary" })
  local def = data.pokemon and data.pokemon[mon.species]
  local flip = def ~= nil and def.flipSprite ~= nil and not def.flipSprite
  return self:image(path), flip
end

function Gen4SummaryMenu:drawPicture()
  local image, flip = self:pictureArt()
  if not image then return end
  local spot = self:pictureSpot()
  local w, h = image:getDimensions()
  love.graphics.setColor(1, 1, 1, 1)
  -- Drawn from its own centre so the mirror turns it about the middle of the
  -- plate rather than sliding it a picture's width to the left.
  love.graphics.draw(image, spot.x, spot.y, 0, flip and -1 or 1, 1, w / 2, h / 2)
end

function Gen4SummaryMenu:statusIndex()
  if Party.isEgg(self.mon) then return nil end
  if tonumber(self.mon.hp)==0 then return 6 end
  local status=tostring(self.mon.status or ''):upper()
  local indices={PAR=1,PARALYSIS=1,FRZ=2,FREEZE=2,SLP=3,SLEEP=3,
    PSN=4,TOX=4,POISON=4,TOXIC=4,BRN=5,BURN=5}
  return indices[status]
end

function Gen4SummaryMenu:drawStatus()
  local index=self:statusIndex()
  local icon=index and self:img(('summary/status_%02d'):format(index))
  if icon then
    local w,h=icon:getDimensions()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(icon,80,52,0,1,1,w/2,h/2)
  end
end

function Gen4SummaryMenu:drawSpecialIndicators()
  if Party.isEgg(self.mon) then return end
  local function draw(key,x,y)
    local icon=self:img(key)
    if icon then
      local w,h=icon:getDimensions()
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(icon,x,y,0,1,1,w/2,h/2)
    end
  end
  local ball=tonumber(self.mon.caughtBall or self.mon.ball or self.mon.pokeball)
  if not ball then
    local names={MASTER_BALL=1,ULTRA_BALL=2,GREAT_BALL=3,POKE_BALL=4,SAFARI_BALL=5,
      NET_BALL=6,DIVE_BALL=7,NEST_BALL=8,REPEAT_BALL=9,TIMER_BALL=10,LUXURY_BALL=11,
      PREMIER_BALL=12,DUSK_BALL=13,HEAL_BALL=14,QUICK_BALL=15,CHERISH_BALL=16}
    ball=names[self.mon.ball or self.mon.pokeball]
  end
  if ball and ball>=1 and ball<=16 then draw(('summary/ball_%02d'):format(ball),16,32) end
  if require('src.pokemon.Pokemon').isShiny(self.mon) then
    draw('summary/special_00',98,72)
  end
  local virus=tonumber(self.mon.pokerus or self.mon.gen4Pokerus or self.mon.gen3Pokerus) or 0
  if virus>0 and virus%16==0 then draw('summary/special_01',98,132) end
  if virus%16>0 and not self:statusIndex() then draw('summary/pokerus_active',76,48) end
end

function Gen4SummaryMenu:pageTabs()
  local ids={info=0,memo=1,skills=2,moves=3,condition=4,ribbons=6,exit=7}
  local tabs={}
  local visible=self:visiblePages()
  local x=188-(24+(#visible-1)*16)/2
  for _,i in ipairs(visible) do
    local page=self.pages[i]
    local selected=i==self.page
    local width=selected and 24 or 16
    tabs[#tabs+1]={page=i,x=x,width=width,sequence=(ids[page.key] or 0)+(selected and 8 or 0)}
    x=x+width
  end
  return tabs
end

function Gen4SummaryMenu:drawPageTabs()
  if self.moveMode or self.ribbonMode then return end
  for _,tab in ipairs(self:pageTabs()) do
    local key=('summary/tab_%02d'):format(tab.sequence)
    local icon=self:img(key)
    if icon then
      local rec=self.art[key]
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(icon,tab.x+(type(rec)=='table' and rec.originX or 0),
        24+(type(rec)=='table' and rec.originY or 0))
    end
  end
end

function Gen4SummaryMenu:draw()
  local g = love.graphics
  g.setColor(0.08, 0.09, 0.14, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local page = self.pages[self.page] or self.pages[1]
  local back = page and self:img(self.moveMode and 'summary/page_battle_moves_select_mode' or page.art)
  if back then g.draw(back, 0, 0) else Font.drawBox(0, 0, 32, 24) end

  if not self.mon then
    Font.draw(self:word("unknown", "???"), 100, 90)
    return
  end

  -- The Pokemon itself, on every page: the cartridge only ever takes it down
  -- for the move-info sub-mode, which scrolls the whole left column away and
  -- is not a page this port draws.
  self:drawPicture()
  self:drawStatus()
  self:drawSpecialIndicators()

  -- The title, and the name and level in the bar the art leaves for them.
  if page and page.title then
    Font.draw(tostring(page.title), 8, 0)
  end
  local def = self:speciesDef()
  local name = Party.isEgg(self.mon) and Strings('Egg')
    or self.mon.nickname or (def and def.name) or tostring(self.mon.species)
  Font.beginTwoTone({1,1,1,1},{.38,.38,.38,1})
  fitted(name,24,24,64)
  Font.endTwoTone()
  if not Party.isEgg(self.mon) and not self.mon.hideGender then
    local gender=require('src.pokemon.DayCare').gender(self.game.data,self.mon)
    if gender=='male' or gender=='female' then
      local colour=gender=='male' and {0.1,0.45,1,1} or {1,0.2,0.25,1}
      Font.beginTwoTone(colour,{.38,.38,.38,1})
      fitted(self:word(gender,gender=='male' and '♂' or '♀'),88,24,8,'right')
      Font.endTwoTone()
    end
  end
  local level = tonumber(self.mon.level) or 1
  if not Party.isEgg(self.mon) then Font.draw(("Lv%d"):format(level),8,40) end
  if not Party.isEgg(self.mon) and not self.ribbonMode then
    Font.draw(self:word('item',Strings('Item')),8,160)
    local held=self.mon.item or self.mon.heldItem
    local item=held and self.game.data.items and self.game.data.items[held]
    fitted((item and item.name) or self:word('none',Strings('None')),8,176,96)
  end

  local key = page and page.key or "info"
  if key == "info" then self:drawInfo()
  elseif key == 'memo' then self:drawMemo()
  elseif key == 'condition' then self:drawCondition()
  elseif key == 'ribbons' then self:drawRibbons()
  elseif key == "skills" then self:drawSkills()
  elseif key=='exit' then
    local text=(self.game.data.text or {}).TEXT_B0455_00162 or Strings('Close window.')
    Font.beginTwoTone({1,1,1,1},{.38,.38,.38,1})
    fitted(text,144,88,72,'centre');Font.endTwoTone()
  elseif key=='moves' then self:drawMoves() end
  if self.moveMode then self:drawMoveDetails() end
  self:drawPageTabs()
  g.setColor(1, 1, 1, 1)
end

return Gen4SummaryMenu
