-- Native-resolution lower-screen save companion for Gen 1-3.
-- This is intentionally separate from the desktop save editor: it mutates the
-- running game's live save through the same engine modules, but lays controls
-- out for a touch screen which is present throughout play.

local SecondScreen = require("src.ui.SecondScreen")
local Boxes = require("src.pokemon.Boxes")
local Bag = require("src.inventory.Bag")
local Party = require("src.pokemon.Party")
local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")
local Badges = require("src.inventory.Badges")
local GameVersion = require("src.core.GameVersion")

local M = {}
local state = {
  tab = 1, box = 1, bagPage = 1, itemPage = 1, itemQty = 1,
  host = nil, hits = {}, editor = nil, itemPicker = false,
  nameEditor = false, nameDraft = "", fonts = {}, fontKey = nil,
  catalogData = nil, moveIds = nil, itemIds = nil, speciesIds = nil,
  speciesPicker = nil, speciesPage = 1,
  panelW = nil, panelH = nil, panelCandidateW = nil, panelCandidateH = nil,
  panelCandidateCount = 0,
}
local TABS = { "PARTY", "BOXES", "BAG", "PLAYER" }

local W, H = 640, 360
local PAL = {
  bg={0.035,0.055,0.09,1}, panel={0.07,0.10,0.15,1},
  panel2={0.10,0.14,0.21,1}, line={0.20,0.32,0.46,1},
  blue={0.10,0.38,0.72,1}, blue2={0.16,0.52,0.88,1},
  green={0.13,0.55,0.36,1}, red={0.72,0.18,0.22,1},
  gold={0.88,0.64,0.16,1}, text={0.95,0.97,1,1},
  muted={0.62,0.70,0.80,1}, faint={0.38,0.48,0.60,1},
}

local function clamp(v,a,b) return math.max(a, math.min(b,v)) end
local function setColor(c) love.graphics.setColor(c[1],c[2],c[3],c[4] or 1) end
local function roundRect(x,y,w,h,r,c)
  setColor(c); love.graphics.rectangle("fill",x,y,w,h,r,r)
end
local function stroke(x,y,w,h,r,c)
  setColor(c); love.graphics.rectangle("line",x,y,w,h,r,r)
end

local function ensureFonts()
  local key = tostring(W).."x"..tostring(H)
  if state.fontKey == key then return end
  state.fontKey = key
  local base = clamp(math.floor(H/30), 13, 24)
  state.fonts = {
    tiny = love.graphics.newFont(math.max(11, base-2)),
    small = love.graphics.newFont(base),
    medium = love.graphics.newFont(base+3),
    large = love.graphics.newFont(base+8),
  }
end
local function text(s,x,y,font,c)
  ensureFonts(); love.graphics.setFont(state.fonts[font or "small"])
  setColor(c or PAL.text); love.graphics.print(tostring(s),x,y)
end
local function textRight(s,x,y,w,font,c)
  ensureFonts(); love.graphics.setFont(state.fonts[font or "small"])
  local sw=love.graphics.getFont():getWidth(tostring(s))
  text(s,x+w-sw,y,font,c)
end
local function textCenter(s,x,y,w,font,c)
  ensureFonts(); love.graphics.setFont(state.fonts[font or "small"])
  local sw=love.graphics.getFont():getWidth(tostring(s))
  text(s,x+(w-sw)/2,y,font,c)
end

local function hit(x,y,w,h,fn)
  state.hits[#state.hits+1]={x=x,y=y,w=w,h=h,fn=fn}
end
local function button(label,x,y,w,h,fn,opt)
  opt=opt or {}
  roundRect(x,y,w,h,opt.radius or math.max(6,H*.018),opt.color or PAL.panel2)
  stroke(x,y,w,h,opt.radius or math.max(6,H*.018),opt.border or PAL.line)
  textCenter(label,x,y+(h-(state.fonts.small and state.fonts.small:getHeight() or 14))/2,w,
             opt.font or "small",opt.text or PAL.text)
  if fn then hit(x,y,w,h,fn) end
end

local function generation()
  return GameVersion.generation and GameVersion.generation(GameVersion.get()) or 1
end
local function speciesName(game,mon)
  if not mon then return "-" end
  local d=game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return (d and (d.name or d.displayName)) or tostring(mon.species or "?")
end
local function moveName(game,id)
  if not id then return "---" end
  local d=game.data and game.data.moves and game.data.moves[id]
  return (d and (d.name or d.displayName)) or tostring(id)
end
local function itemName(game,id)
  local d=game.data and game.data.items and game.data.items[id]
  return (d and (d.name or d.displayName or d.key)) or tostring(id)
end
local function sortedKeys(t)
  local out={}
  for k in pairs(t or {}) do out[#out+1]=k end
  table.sort(out,function(a,b) return tostring(a)<tostring(b) end)
  return out
end
local function ensureCatalog(game)
  if state.catalogData == game.data then return end
  state.catalogData=game.data
  state.moveIds=sortedKeys(game.data and game.data.moves)
  state.speciesIds={}
  for _,id in ipairs(sortedKeys(game.data and game.data.pokemon)) do
    local def=game.data.pokemon[id]
    if type(def)=="table" and type(def.baseStats)=="table" then
      state.speciesIds[#state.speciesIds+1]=id
    end
  end
  state.itemIds={}
  for _,id in ipairs(sortedKeys(game.data and game.data.items)) do
    if not (type(id)=="string" and Bag.isBadge and Bag.isBadge(id)) then
      state.itemIds[#state.itemIds+1]=id
    end
  end
end

local function boxes(game)
  Boxes.load(game.data)
  return Boxes.ensure(game.save)
end

local function recalc(game,mon)
  if not mon then return end
  local def=game.data and game.data.pokemon and game.data.pokemon[mon.species]
  if not def then return end
  if type(mon.ivs)=="table" and Stats.calcGen3 then
    mon.stats=Stats.calcGen3(def,mon.level or 1,mon.ivs,mon.evs,mon.nature)
  else
    mon.stats=Stats.calc(def,mon.level or 1,mon.dvs or {},mon.statExp)
  end
  mon.hp=clamp(tonumber(mon.hp) or (mon.stats.hp or 1),0,mon.stats.hp or 1)
end
local function setLevel(game,mon,delta)
  if not mon then return end
  local def=game.data.pokemon[mon.species]; if not def then return end
  mon.level=clamp(math.floor((mon.level or 1)+delta),1,100)
  mon.exp=Growth.expForLevel(def.growthRate,mon.level)
  recalc(game,mon)
end
local function setHP(game,mon,delta)
  if not mon then return end
  recalc(game,mon)
  mon.hp=clamp((mon.hp or 0)+delta,0,(mon.stats and mon.stats.hp) or 1)
end
local function syncHpDv(d)
  d.hp=(d.attack%2)*8+(d.defense%2)*4+(d.speed%2)*2+(d.special%2)
end
local function adjustIndividual(game,mon,key,delta)
  if type(mon.ivs)=="table" then
    mon.ivs[key]=clamp((mon.ivs[key] or 0)+delta,0,31)
  else
    mon.dvs=mon.dvs or {attack=0,defense=0,speed=0,special=0}
    mon.dvs[key]=clamp((mon.dvs[key] or 0)+delta,0,15)
    syncHpDv(mon.dvs)
  end
  recalc(game,mon)
  Pokemon.syncIdentity(game.data,mon)
end
local function cycleMove(game,mon,slot,delta)
  ensureCatalog(game)
  local ids=state.moveIds or {}; if #ids==0 then return end
  mon.moves=mon.moves or {}
  local current=mon.moves[slot] and mon.moves[slot].id
  local at=1
  for i,id in ipairs(ids) do if id==current then at=i break end end
  at=((at-1+delta)%#ids)+1
  local id=ids[at]; local def=game.data.moves[id]
  mon.moves[slot]={id=id,pp=(def and def.pp) or 0}
end

local function openMon(mon,origin,index,box)
  if not mon then return end
  state.editor={mon=mon,origin=origin,index=index,box=box}
end

local function openSpeciesPicker(mode, origin, index, box, mon)
  state.speciesPicker={
    mode=mode, origin=origin, index=index, box=box, mon=mon,
  }
  state.speciesPage=1
end

local function createMon(game,id,level)
  local ok, mon=pcall(Pokemon.new,game.data,id,level or 5)
  if not (ok and mon) then return nil end
  game.save.player=game.save.player or {}
  mon.ot=game.save.player.name or game.save.playerName
  mon.otId=game.save.player.id
  return mon
end

local function applySpecies(game, picker, id)
  if not (picker and id) then return end
  if picker.mode=="change" and picker.mon then
    local mon=picker.mon
    local def=game.data.pokemon[id]
    if not def then return end
    mon.species=id
    mon.exp=Growth.expForLevel(def.growthRate,mon.level or 1)
    recalc(game,mon)
    Pokemon.syncIdentity(game.data,mon)
    state.speciesPicker=nil
    return
  end

  local mon=createMon(game,id,5)
  if not mon then return end
  if picker.origin=="party" then
    game.save.party=game.save.party or {}
    if #game.save.party < Party.MAX then
      table.insert(game.save.party,mon)
      state.editor={mon=mon,origin="party",index=#game.save.party}
      state.speciesPicker=nil
    end
  elseif picker.origin=="box" then
    local bs=boxes(game); local box=bs[picker.box or state.box]
    local slot=picker.index or Boxes.firstFree(box)
    if slot and slot<=Boxes.capacity() and not box[slot] then
      box[slot]=mon
      state.editor={mon=mon,origin="box",index=slot,box=picker.box or state.box}
      state.speciesPicker=nil
    end
  end
end

local function drawHeader()
  local hh=H*.13
  roundRect(0,0,W,hh,0,{0.04,0.07,0.12,1})
  local pad=W*.018; local gap=W*.008
  local tw=(W-2*pad-gap*3)/4
  for i,label in ipairs(TABS) do
    local x=pad+(i-1)*(tw+gap)
    button(label,x,H*.025,tw,H*.078,function()
      state.tab=i; state.editor=nil; state.itemPicker=false; state.nameEditor=false
    end,{color=i==state.tab and PAL.blue or PAL.panel2,
          border=i==state.tab and PAL.blue2 or PAL.line,font="medium"})
  end
end

local function drawParty(game)
  local party=game.save.party or {}
  local top=H*.16; local pad=W*.025; local gap=W*.018
  text("Party",pad,top,"large")
  text(#party.."/"..Party.MAX,pad+W*.16,top+H*.018,"medium",PAL.muted)
  if #party < Party.MAX then
    button("+ ADD POKEMON",W*.72,top,W*.255,H*.085,function()
      openSpeciesPicker("add","party")
    end,{color=PAL.green,font="small"})
  end
  local y0=top+H*.105
  local cols=2; local rows=3
  local cw=(W-2*pad-gap)/2; local ch=(H-y0-H*.045-gap*2)/3
  for i=1,6 do
    local c=(i-1)%cols; local r=math.floor((i-1)/cols)
    local x=pad+c*(cw+gap); local y=y0+r*(ch+gap)
    local mon=party[i]
    roundRect(x,y,cw,ch,12,mon and PAL.panel2 or PAL.panel)
    stroke(x,y,cw,ch,12,mon and PAL.line or PAL.faint)
    if mon then
      text(speciesName(game,mon),x+cw*.05,y+ch*.15,"medium")
      text("Lv "..tostring(mon.level or "?"),x+cw*.05,y+ch*.53,"small",PAL.muted)
      local hp=(mon.hp or 0); local mx=(mon.stats and mon.stats.hp) or math.max(hp,1)
      textRight("HP "..hp.."/"..mx,x,y+ch*.53,cw-cw*.05,"small",
                hp<=mx*.2 and PAL.red or PAL.green)
      textRight("EDIT",x,y+ch*.12,cw-cw*.05,"tiny",PAL.blue2)
      hit(x,y,cw,ch,function() openMon(mon,"party",i) end)
    else
      textCenter("EMPTY",x,y+ch*.31,cw,"small",PAL.faint)
      textCenter("tap ADD above",x,y+ch*.57,cw,"tiny",PAL.faint)
    end
  end
end

local function drawBoxes(game)
  local bs=boxes(game); local count=Boxes.count(); local cap=Boxes.capacity()
  state.box=clamp(state.box or game.save.currentBox or 1,1,count)
  local box=bs[state.box]
  local pad=W*.022; local top=H*.16
  button("<",pad,top,W*.07,H*.09,function() state.box=state.box==1 and count or state.box-1 end)
  textCenter("BOX "..state.box.." / "..count,pad+W*.08,top+H*.015,W*.28,"large")
  button(">",pad+W*.37,top,W*.07,H*.09,function() state.box=state.box==count and 1 or state.box+1 end)
  textRight(Boxes.used(box).."/"..cap,W*.55,top+H*.025,W*.18,"medium",PAL.muted)
  if Boxes.used(box)<cap then
    button("+ ADD",W*.78,top,W*.19,H*.085,function()
      openSpeciesPicker("add","box",Boxes.firstFree(box),state.box)
    end,{color=PAL.green})
  end
  local gridY=top+H*.12; local cols=(cap>20) and 6 or 5
  local rows=math.ceil(cap/cols); local gap=W*.008
  local cw=(W-2*pad-gap*(cols-1))/cols
  local ch=(H-gridY-H*.035-gap*(rows-1))/rows
  for i=1,cap do
    local c=(i-1)%cols; local r=math.floor((i-1)/cols)
    local x=pad+c*(cw+gap); local y=gridY+r*(ch+gap)
    local mon=box[i]
    roundRect(x,y,cw,ch,8,mon and PAL.panel2 or PAL.panel)
    stroke(x,y,cw,ch,8,mon and PAL.line or PAL.faint)
    if mon then
      textCenter(speciesName(game,mon):sub(1,10),x,y+ch*.20,cw,"tiny")
      textCenter("Lv"..tostring(mon.level or "?"),x,y+ch*.55,cw,"tiny",PAL.muted)
      hit(x,y,cw,ch,function() openMon(mon,"box",i,state.box) end)
    else
      textCenter("+ "..tostring(i),x,y+ch*.38,cw,"tiny",PAL.faint)
      hit(x,y,cw,ch,function() openSpeciesPicker("add","box",i,state.box) end)
    end
  end
end

local function bagIds(game)
  game.save.inventory=game.save.inventory or {}
  return Bag.order(game.save)
end
local function drawBag(game)
  ensureCatalog(game)
  if state.itemPicker then
    local ids=state.itemIds or {}; local pad=W*.025
    text("Add item",pad,H*.17,"large")
    button("BACK",W*.83,H*.155,W*.14,H*.085,function() state.itemPicker=false end)
    local pageSize=8; local pages=math.max(1,math.ceil(#ids/pageSize))
    state.itemPage=clamp(state.itemPage,1,pages)
    local y0=H*.27; local rowH=H*.072; local gap=H*.012
    for row=1,pageSize do
      local idx=(state.itemPage-1)*pageSize+row; local id=ids[idx]
      if not id then break end
      local y=y0+(row-1)*(rowH+gap)
      roundRect(pad,y,W*.70,rowH,8,PAL.panel2); stroke(pad,y,W*.70,rowH,8,PAL.line)
      text(itemName(game,id),pad+W*.018,y+rowH*.22,"small")
      button("ADD x"..state.itemQty,W*.76,y,W*.20,rowH,function()
        Bag.add(game.save,id,state.itemQty,game.data)
      end,{color=PAL.green})
    end
    button("-",pad,H*.90,W*.07,H*.07,function() state.itemQty=clamp(state.itemQty-1,1,99) end)
    text("Qty "..state.itemQty,pad+W*.09,H*.91,"medium")
    button("+",pad+W*.21,H*.90,W*.07,H*.07,function() state.itemQty=clamp(state.itemQty+1,1,99) end)
    button("< PAGE",W*.50,H*.90,W*.14,H*.07,function() state.itemPage=math.max(1,state.itemPage-1) end)
    textCenter(state.itemPage.."/"..pages,W*.65,H*.91,W*.10,"small",PAL.muted)
    button("PAGE >",W*.76,H*.90,W*.19,H*.07,function() state.itemPage=math.min(pages,state.itemPage+1) end)
    return
  end

  local ids=bagIds(game); local pad=W*.025
  text("Bag",pad,H*.17,"large")
  text(#ids.." item types",pad+W*.12,H*.19,"small",PAL.muted)
  button("+ ADD ITEM",W*.78,H*.155,W*.19,H*.085,function() state.itemPicker=true end,{color=PAL.blue})
  local pageSize=7; local pages=math.max(1,math.ceil(#ids/pageSize))
  state.bagPage=clamp(state.bagPage,1,pages)
  local y0=H*.29; local rowH=H*.075; local gap=H*.012
  for row=1,pageSize do
    local idx=(state.bagPage-1)*pageSize+row; local id=ids[idx]
    if not id then break end
    local y=y0+(row-1)*(rowH+gap)
    roundRect(pad,y,W*.94,rowH,8,PAL.panel2); stroke(pad,y,W*.94,rowH,8,PAL.line)
    text(itemName(game,id),pad+W*.018,y+rowH*.22,"small")
    textRight("x"..tostring(game.save.inventory[id] or 0),W*.50,y+rowH*.22,W*.16,"small",PAL.gold)
    button("-",W*.70,y+H*.006,W*.07,rowH-H*.012,function() Bag.remove(game.save,id,1) end)
    button("+",W*.79,y+H*.006,W*.07,rowH-H*.012,function() Bag.add(game.save,id,1,game.data) end,{color=PAL.green})
    button("DROP",W*.88,y+H*.006,W*.085,rowH-H*.012,function()
      local qty=game.save.inventory[id] or 0; if qty>0 then Bag.remove(game.save,id,qty) end
    end,{color=PAL.red,font="tiny"})
  end
  button("<",pad,H*.91,W*.08,H*.065,function() state.bagPage=math.max(1,state.bagPage-1) end)
  textCenter(state.bagPage.."/"..pages,pad+W*.10,H*.92,W*.12,"small",PAL.muted)
  button(">",pad+W*.23,H*.91,W*.08,H*.065,function() state.bagPage=math.min(pages,state.bagPage+1) end)
end

local function toggleBadge(game,entry)
  Badges.toggle(game.save, entry, GameVersion.get())
end

local KEY_ROWS={"ABCDEFG","HIJKLMN","OPQRSTU","VWXYZ"}
local function drawNameEditor(game)
  local pad=W*.04
  text("Edit trainer name",pad,H*.16,"large")
  roundRect(pad,H*.25,W*.92,H*.12,10,PAL.panel2); stroke(pad,H*.25,W*.92,H*.12,10,PAL.blue2)
  textCenter(state.nameDraft,pad,H*.275,W*.92,"large")
  local y=H*.41
  for _,row in ipairs(KEY_ROWS) do
    local n=#row; local gap=W*.01; local bw=(W-2*pad-gap*(n-1))/n
    for i=1,n do
      local ch=row:sub(i,i); local x=pad+(i-1)*(bw+gap)
      button(ch,x,y,bw,H*.095,function()
        if #state.nameDraft<7 then state.nameDraft=state.nameDraft..ch end
      end,{font="medium"})
    end
    y=y+H*.115
  end
  button("BACKSPACE",pad,H*.88,W*.24,H*.075,function()
    state.nameDraft=state.nameDraft:sub(1,math.max(0,#state.nameDraft-1))
  end)
  button("CLEAR",pad+W*.27,H*.88,W*.18,H*.075,function() state.nameDraft="" end,{color=PAL.red})
  button("CANCEL",W*.57,H*.88,W*.17,H*.075,function() state.nameEditor=false end)
  button("SAVE",W*.77,H*.88,W*.19,H*.075,function()
    game.save.player=game.save.player or {}
    local name=state.nameDraft~="" and state.nameDraft or "PLAYER"
    game.save.player.name=name; game.save.playerName=name
    state.nameEditor=false
  end,{color=PAL.green})
end

local function drawPlayer(game)
  if state.nameEditor then return drawNameEditor(game) end
  game.save.player=game.save.player or {}
  local p=game.save.player; local pad=W*.025
  text("Player",pad,H*.17,"large")
  roundRect(pad,H*.27,W*.45,H*.18,12,PAL.panel2); stroke(pad,H*.27,W*.45,H*.18,12,PAL.line)
  text("TRAINER",pad+W*.025,H*.295,"tiny",PAL.muted)
  text(p.name or game.save.playerName or "PLAYER",pad+W*.025,H*.34,"large")
  button("EDIT NAME",pad+W*.28,H*.335,W*.14,H*.075,function()
    state.nameDraft=tostring(p.name or game.save.playerName or "PLAYER"):sub(1,7)
    state.nameEditor=true
  end,{color=PAL.blue})

  roundRect(W*.51,H*.27,W*.465,H*.18,12,PAL.panel2); stroke(W*.51,H*.27,W*.465,H*.18,12,PAL.line)
  text("MONEY",W*.535,H*.295,"tiny",PAL.muted)
  text("$"..tostring(game.save.money or 0),W*.535,H*.34,"large",PAL.gold)
  local by=H*.47; local bw=W*.105; local gap=W*.012
  local moneyButtons={{"-1000",-1000},{"-100",-100},{"+100",100},{"+1000",1000}}
  for i,b in ipairs(moneyButtons) do
    button(b[1],pad+(i-1)*(bw+gap),by,bw,H*.075,function()
      game.save.money=clamp((tonumber(game.save.money) or 0)+b[2],0,999999)
    end,{color=b[2]<0 and PAL.panel2 or PAL.green})
  end
  button("MAX",pad+4*(bw+gap),by,bw,H*.075,function() game.save.money=999999 end,{color=PAL.gold})

  local badges=Badges.list(game.data,GameVersion.get())
  text("Badges  "..Badges.count(game.data,game.save,GameVersion.get()).."/"..#badges,
       pad,H*.59,"medium")
  local cols=math.min(8,math.max(4,#badges)); local gapB=W*.008
  local cb=(W-2*pad-gapB*(cols-1))/cols; local ch=H*.105
  for i,entry in ipairs(badges) do
    local c=(i-1)%cols; local r=math.floor((i-1)/cols)
    local x=pad+c*(cb+gapB); local y=H*.66+r*(ch+H*.015)
    local on=Badges.has(game.save,entry)
    button((entry.name or entry.id or tostring(i)):sub(1,10),x,y,cb,ch,
      function() toggleBadge(game,entry) end,
      {color=on and PAL.green or PAL.panel2,border=on and PAL.green or PAL.line,font="tiny"})
  end
  text("Version: "..tostring(GameVersion.get()),pad,H*.93,"small",PAL.faint)
end

local function drawMonEditor(game)
  local e=state.editor; local mon=e and e.mon
  if not mon then state.editor=nil return end
  ensureCatalog(game)
  local pad=W*.025
  button("< BACK",pad,H*.025,W*.13,H*.075,function() state.editor=nil end)
  text(speciesName(game,mon),pad+W*.16,H*.03,"large")
  text("Lv "..tostring(mon.level or 1),pad+W*.16,H*.09,"medium",PAL.gold)
  button("CHANGE SPECIES",W*.43,H*.025,W*.20,H*.075,function()
    openSpeciesPicker("change",e.origin,e.index,e.box,mon)
  end,{color=PAL.blue,font="tiny"})
  button("DELETE",W*.64,H*.025,W*.085,H*.075,function()
    if e.origin=="party" then
      local party=game.save.party or {}
      if party[e.index]==mon then table.remove(party,e.index) end
    else
      local bs=boxes(game); local box=bs[e.box]
      if box and box[e.index]==mon then box[e.index]=nil end
    end
    state.editor=nil
  end,{color=PAL.red,font="tiny"})

  local actionLabel=e.origin=="party" and "DEPOSIT TO BOX" or "WITHDRAW TO PARTY"
  button(actionLabel,W*.73,H*.025,W*.245,H*.075,function()
    if e.origin=="party" then
      local party=game.save.party or {}; local live=party[e.index]
      if live==mon then
        game.save.currentBox=state.box
        local used=Boxes.deposit(game.save,mon)
        if used then table.remove(party,e.index); state.editor=nil end
      end
    else
      game.save.party=game.save.party or {}
      if #game.save.party<Party.MAX then
        local bs=boxes(game); local box=bs[e.box]; if box[e.index]==mon then
          box[e.index]=nil; table.insert(game.save.party,mon); state.editor=nil
        end
      end
    end
  end,{color=e.origin=="party" and PAL.blue or PAL.green,font="tiny"})

  -- Level and HP cards.
  local top=H*.18; local cardW=W*.30
  roundRect(pad,top,cardW,H*.20,12,PAL.panel2); stroke(pad,top,cardW,H*.20,12,PAL.line)
  text("LEVEL",pad+W*.02,top+H*.025,"tiny",PAL.muted)
  text(tostring(mon.level or 1),pad+W*.02,top+H*.075,"large")
  local bx=pad+W*.105
  for i,b in ipairs({{"-5",-5},{"-1",-1},{"+1",1},{"+5",5}}) do
    button(b[1],bx+(i-1)*W*.047,top+H*.08,W*.042,H*.075,function() setLevel(game,mon,b[2]) end,{font="tiny"})
  end

  roundRect(pad+cardW+W*.02,top,cardW,H*.20,12,PAL.panel2)
  stroke(pad+cardW+W*.02,top,cardW,H*.20,12,PAL.line)
  recalc(game,mon)
  local hp=mon.hp or 0; local maxhp=(mon.stats and mon.stats.hp) or 1
  text("HP",pad+cardW+W*.04,top+H*.025,"tiny",PAL.muted)
  text(hp.." / "..maxhp,pad+cardW+W*.04,top+H*.075,"large",hp<=maxhp*.2 and PAL.red or PAL.green)
  button("-1",pad+cardW+W*.20,top+H*.08,W*.045,H*.075,function() setHP(game,mon,-1) end,{font="tiny"})
  button("+1",pad+cardW+W*.25,top+H*.08,W*.045,H*.075,function() setHP(game,mon,1) end,{font="tiny"})

  local statX=W*.66; local statW=W*.315
  roundRect(statX,top,statW,H*.20,12,PAL.panel2); stroke(statX,top,statW,H*.20,12,PAL.line)
  local st=mon.stats or {}
  local gen=generation()
  local labels=gen>=2 and {{"ATK","attack"},{"DEF","defense"},{"SPD","speed"},{"SPA","spatk"},{"SDF","spdef"}}
                       or {{"ATK","attack"},{"DEF","defense"},{"SPD","speed"},{"SPC","special"}}
  for i,row in ipairs(labels) do
    local yy=top+H*.018+(i-1)*H*.034
    text(row[1],statX+W*.015,yy,"tiny",PAL.muted)
    textRight(tostring(st[row[2]] or 0),statX+W*.10,yy,statW-W*.12,"tiny",PAL.text)
  end

  -- IV/DV editor.
  local indY=H*.42; text(type(mon.ivs)=="table" and "INDIVIDUAL VALUES" or "DETERMINANT VALUES",
                         pad,indY,"medium")
  local keys=type(mon.ivs)=="table"
      and {{"HP","hp"},{"ATK","attack"},{"DEF","defense"},{"SPD","speed"},{"SPA","spatk"},{"SDF","spdef"}}
       or {{"ATK","attack"},{"DEF","defense"},{"SPD","speed"},{"SPC","special"}}
  local iw=(W*.60-W*.02)/2; local ih=H*.075
  for i,row in ipairs(keys) do
    local col=(i-1)%2; local rr=math.floor((i-1)/2)
    local x=pad+col*(iw+W*.02); local y=indY+H*.065+rr*(ih+H*.012)
    local source=type(mon.ivs)=="table" and mon.ivs or mon.dvs
    roundRect(x,y,iw,ih,8,PAL.panel2); stroke(x,y,iw,ih,8,PAL.line)
    text(row[1],x+W*.012,y+ih*.25,"small",PAL.muted)
    text(tostring((source and source[row[2]]) or 0),x+W*.09,y+ih*.25,"medium")
    button("-",x+iw-W*.12,y+H*.008,W*.05,ih-H*.016,function() adjustIndividual(game,mon,row[2],-1) end,{font="small"})
    button("+",x+iw-W*.06,y+H*.008,W*.05,ih-H*.016,function() adjustIndividual(game,mon,row[2],1) end,{font="small",color=PAL.green})
  end

  -- Move editor on the right.
  local mx=W*.66; local my=H*.42; local mw=W*.315
  text("MOVES",mx,my,"medium")
  for slot=1,4 do
    local y=my+H*.065+(slot-1)*H*.105
    local m=mon.moves and mon.moves[slot]
    roundRect(mx,y,mw,H*.09,8,PAL.panel2); stroke(mx,y,mw,H*.09,8,PAL.line)
    button("<",mx+W*.008,y+H*.008,W*.045,H*.074,function() cycleMove(game,mon,slot,-1) end,{font="small"})
    textCenter(moveName(game,m and m.id),mx+W*.06,y+H*.018,mw-W*.12,"small")
    if m then textCenter("PP "..tostring(m.pp or 0),mx+W*.06,y+H*.052,mw-W*.12,"tiny",PAL.muted) end
    button(">",mx+mw-W*.053,y+H*.008,W*.045,H*.074,function() cycleMove(game,mon,slot,1) end,{font="small",color=PAL.blue})
  end
end

local function drawSpeciesPicker(game)
  ensureCatalog(game)
  local p=state.speciesPicker
  if not p then return end
  local ids=state.speciesIds or {}
  local pad=W*.025
  text(p.mode=="change" and "Change Pokemon species" or "Add Pokemon",pad,H*.055,"large")
  button("CANCEL",W*.82,H*.045,W*.155,H*.08,function() state.speciesPicker=nil end)

  local pageSize=12
  local pages=math.max(1,math.ceil(#ids/pageSize))
  state.speciesPage=clamp(state.speciesPage,1,pages)
  local cols=3
  local gap=W*.012
  local cw=(W-2*pad-gap*(cols-1))/cols
  local y0=H*.17
  local ch=H*.155
  for n=1,pageSize do
    local idx=(state.speciesPage-1)*pageSize+n
    local id=ids[idx]
    if not id then break end
    local col=(n-1)%cols
    local row=math.floor((n-1)/cols)
    local x=pad+col*(cw+gap)
    local y=y0+row*(ch+H*.018)
    local def=game.data.pokemon[id]
    local label=(def and (def.name or def.displayName)) or tostring(id)
    button(label,x,y,cw,ch,function() applySpecies(game,p,id) end,
      {color=PAL.panel2,border=PAL.line,font="small"})
  end

  button("< PAGE",pad,H*.89,W*.16,H*.075,function()
    state.speciesPage=math.max(1,state.speciesPage-1)
  end)
  textCenter(state.speciesPage.." / "..pages,W*.40,H*.905,W*.20,"medium",PAL.muted)
  button("PAGE >",W*.79,H*.89,W*.185,H*.075,function()
    state.speciesPage=math.min(pages,state.speciesPage+1)
  end)
end

local function draw(game)
  ensureFonts(); state.hits={}
  setColor(PAL.bg); love.graphics.rectangle("fill",0,0,W,H)
  -- subtle launcher-like panel wash
  setColor({0.04,0.12,0.22,0.28}); love.graphics.rectangle("fill",0,0,W,H*.42)
  if state.speciesPicker then return drawSpeciesPicker(game) end
  if state.editor then return drawMonEditor(game) end
  drawHeader()
  if state.tab==1 then drawParty(game)
  elseif state.tab==2 then drawBoxes(game)
  elseif state.tab==3 then drawBag(game)
  else drawPlayer(game) end
end

local function touch(_,x,y)
  for i=#state.hits,1,-1 do
    local h=state.hits[i]
    if x>=h.x and y>=h.y and x<h.x+h.w and y<h.y+h.h then
      return h.fn()
    end
  end
end

local function hostFor(game)
  if not state.host then
    local h={
      secondScreenAlways=true, secondScreenNativePanel=true,
      data={}, save={options={secondScreenMode="display"}},
    }
    function h.touchpressed(_,_,x,y) touch(h.game,x,y) end
    function h.touchmoved() end
    function h.touchreleased() end
    state.host=h
  end
  state.host.game=game
  local pw,ph=SecondScreen.panelSize()

  -- The Java heartbeat is asynchronous. During reconnect / Presentation
  -- discovery it can briefly fall back to the DS protocol size (256x192).
  -- Reallocating a native companion canvas on every heartbeat made the lower
  -- panel visibly flash between sizes. Require repeated identical dimensions
  -- before accepting a change, and ignore the known fallback once a native
  -- size has been latched.
  local plausible = pw and ph and pw >= 256 and ph >= 192
  local fallback = pw == 256 and ph == 192
  if plausible and not (state.panelW and fallback) then
    if pw == state.panelCandidateW and ph == state.panelCandidateH then
      state.panelCandidateCount = state.panelCandidateCount + 1
    else
      state.panelCandidateW, state.panelCandidateH = pw, ph
      state.panelCandidateCount = 1
    end
    local need = state.panelW and 20 or 3
    if state.panelCandidateCount >= need
       and (pw ~= state.panelW or ph ~= state.panelH) then
      state.panelW, state.panelH = pw, ph
      state.fontKey = nil
    end
  end

  local useW = state.panelW or W
  local useH = state.panelH or H
  state.host.secondScreenLogicalWidth=useW
  state.host.secondScreenLogicalHeight=useH
  state.host.secondScreenSurfaceWidth=useW
  state.host.secondScreenSurfaceHeight=useH
  W,H=useW,useH
  return state.host
end

function M.tick(game)
  local gen=generation()
  if gen>=4 or not SecondScreen.deviceReady() then return false end
  local h=hostFor(game)
  local ok=pcall(SecondScreen.draw,h,function() draw(game) end)
  pcall(SecondScreen.flush,h)
  return ok
end

return M
