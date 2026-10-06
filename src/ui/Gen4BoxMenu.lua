-- Platinum storage uses the shared safe transfer operations with a DS surface.
--
-- THE SURFACE IS THE CARTRIDGE'S (src/applications/pc_boxes/, ov19), layer by
-- layer, with every picture from src/import/Gen4BoxArt.lua (`gen4_box_art`):
--
--   BG3  the wallpaper -- its 21 x 20 map from tile column 11, four rows of its
--        tile 0 under it, tile 0x18 everywhere else (ov19_021D7A9C / 7D00) --
--        and the box name printed into its header plate, centred on x 172 at
--        y 13 in the wallpaper's own colours 2 / 1 (ov19_021D7C58)
--   OBJ  the thirty icons at (112 + 24 col, 40 + 24 row) (ov19_021D85C4) and
--        the PARTY PKMN / CLOSE BOX buttons at (183, 176) -- BG priority 2,
--        so BG2 covers them where it is opaque
--   BG2  the preview panel (map 0) or, with the party up, map 6 at tile 14
--   BG0  the previewed Pokemon's front picture centred on (44, 84)
--   BG2 windows (ov19_021DAADC): species at (2, 8), "No." + dex at (40, 24),
--        nickname at (2, 128) with the gender symbol at 70, "Lv." + level at
--        (0, 144), the item / types / nature / ability rotator at (8, 168),
--        the six markings at tile (4 + i, 19)
--   OBJ  the hand: (112 + 24 col, 40 + 24 row - 16) in the box, (168, 8) on
--        the header, (159, 160) / (235, 160) on the buttons, a party slot
--        - 16 (ov19_021D9D48); its shadow 24 below it in the box; the held
--        Pokemon 4 below the hand (ov19_021D8E00); the header arrows at
--        (108, 20) / (236, 20), sequences 6 / 7, or 8 / 9 on the header
--   BG1  the action menu: a standard window at tile (19, 3) 12 wide, its rows
--        bottom-aligned on tile 19, words at x 10 in (11, 12) on 15
--        (ov19_021DB57C), and the message box at (2, 21) 27 x 2 (ov19_021DB448)
--
-- The words are banks 18 (TEXT_BANK_POKEMON_STORAGE_SYSTEM: 24 + the
-- BoxMenuItem) and 19 (TEXT_BANK_BOX_MESSAGES).  A cache without
-- `gen4_box_art` still draws, from gen4_graphics' older `storage/*` pictures.
local Base=require('src.ui.Gen3BoxMenu')
local Boxes=require('src.pokemon.Boxes')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local Screens=require('src.ui.Screens')
local Bag=require('src.inventory.Bag')
local T=require('src.import.Gen4Text')
local PC={};PC.__index=PC;setmetatable(PC,{__index=Base});PC.isOpaque=true
PC.STORAGE_BANK,PC.MESSAGE_BANK=18,19
PC.BUTTON_ROW=6
-- the party slots (Unk_ov19_021E0234) and the EXIT button's cursor point
PC.PARTY_SLOTS={{144,28},{192,36},{144,68},{192,76},{144,108},{192,116}}
PC.PARTY_EXIT={192,184}
-- BoxMenuItem -> bank 18 entry (24 + the enum), for the words this port offers
PC.WORDS={JUMP=24,WALLPAPER=25,NAME=26,['HEADER CANCEL']=27,
 ['SCENERY 1']=28,['SCENERY 2']=29,['SCENERY 3']=30,ETCETERA=31,
 MOVE=58,SUMMARY=61,WITHDRAW=62,STORE=63,ITEM=64,MARK=65,RELEASE=66,CANCEL=67,
 CONFIRM=68,GIVE=70,TAKE=71,YES=78,NO=79}
PC.WALLPAPER_NAME=34      -- FOREST, the first of sixteen
local FALLBACK_INK={species={{255,247,255},{115,115,132}},nickname={{239,230,255},{90,90,107}},
 male={{148,230,239},{41,123,165}},female={{247,132,132},{197,41,41}},item={{255,247,255},{115,115,132}},
 menu={{16,25,33},{173,189,189}},menuFill={255,255,255},message={{107,107,99},{197,206,206}},
 backdrop={132,230,173},wallpaper={}}

function PC:uiSize() return 256,192 end
function PC:wantsFillScale() return true end
function PC:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end
function PC.new(game,opts)
 local self=Base.new(game,opts);setmetatable(self,PC);self.images={};self.icons={};self.message='';return self
end
function PC:iconFor(mon) return require('src.ui.Gen4PartyMenu').iconFor(self,mon) end

local function image(self,path)
 if not path then return nil end
 if self.images[path]==nil then
  local ok,img=pcall(Assets.image,path)
  self.images[path]=ok and img or false
  if self.images[path] then self.images[path]:setFilter('nearest','nearest') end
 end
 return self.images[path] or nil
end
-- an older cache's picture, gen4_graphics.screens
function PC:img(key)
 local rec=(((self.game.data.gen4_graphics or {}).screens) or {})[key]
 return image(self,type(rec)=='table' and rec.path or rec)
end
-- this screen's own art, gen4_box_art; returns the picture and its record
function PC:art(key)
 local rec=(self.game.data.gen4_box_art or {})[key]
 return image(self,type(rec)=='table' and rec.path or rec),type(rec)=='table' and rec or {}
end
function PC:sprite(key,x,y)
 local img,rec=self:art(key)
 if not img then return false end
 love.graphics.setColor(1,1,1,1)
 love.graphics.draw(img,math.floor(x+(rec.originX or -img:getWidth()/2)),math.floor(y+(rec.originY or -img:getHeight()/2)))
 return true
end
function PC:ink() return self.game.data.gen4_box_ink or FALLBACK_INK end
local function rgb(c) return {c[1]/255,c[2]/255,c[3]/255} end
-- print in an ink pair { letter, shadow } (0..255 triples)
local function say(text,x,y,pair)
 if not text or text=='' then return end
 Font.pushStyle({text=rgb(pair[1]),shadow=rgb(pair[2])})
 Font.draw(text,math.floor(x),math.floor(y))
 Font.popStyle()
end
function PC:word(bank,n,fallback)
 local text=T.resolve(self.game.data,bank,n,self.game)
 if type(text)~='string' or text=='' then return fallback end
 return text
end
function PC:label(key) return self:word(PC.STORAGE_BANK,PC.WORDS[key] or -1,key) end
function PC:say(n,fallback,...)
 T.buffer(self.game,...)
 return (self:word(PC.MESSAGE_BANK,n,fallback):gsub('[\v\f]+','\n'))
end

-- PCBoxes_InitInternal: box i starts on wallpaper i % 16 (MAX_DEFAULT_WALLPAPERS)
function PC:wallpaperOf(n)
 local save=self.game.save;n=n or save.currentBox or 1
 local box=Boxes.ensure(save)[n]
 local id=tonumber(box and box.wallpaper)
 if id then return math.floor(id)%32 end
 return (n-1)%16
end
function PC:wallpaperId() return self:wallpaperOf() end
function PC:boxNameOf(n)
 local saved=self.game.save.currentBox;self.game.save.currentBox=n
 local name=self:boxName();self.game.save.currentBox=saved
 return name
end
function PC:clampCursor() self.row=math.max(0,math.min(PC.BUTTON_ROW,self.row));self.col=math.max(1,math.min(6,self.col)) end

-- THE FRAME CLOCK: the cartridge's animations count vblanks, update() gets dt
function PC:frames(dt)
 local acc=(self.frameAcc or 0)+(dt or 1/60)*60+1e-6
 local n=math.floor(acc);self.frameAcc=acc-n-1e-6
 return n
end

-- BG3, THE WALLPAPER LAYER, AS THE CARTRIDGE KEEPS IT: a 512-pixel ring of 64
-- tile columns, all tile 0x18 in palette 9 at first (ov19_021D7A9C), with
-- each box's 23 columns written at `base` (ov19_021D8764: 21 of map with four
-- rows of tile 0 under it, two of tile 0) into one of two tile/palette slots
-- that alternate on every box change (unk_02; palettes 9 / 10).  A box change
-- writes the new box 23 columns along in the direction of travel and scrolls
-- BG3 184 pixels over 30 vblanks (ov19_021D7D70 / 7E6C), so what was there
-- before stays in the ring -- which is what the see-through item window at
-- tile (1, 21) shows: the 0x18 fill at first, other columns after a slide.
PC.SLIDE_FRAMES=30
PC.SLIDE_STEP=25122   -- (184 << 12) / 30, truncated as the C division does
function PC:bg3State()
 if not self.bg3 then
  local b={scroll=0,base=11,slot=0,cols={},slots={}}
  for c=0,63 do b.cols[c]=false end
  self.bg3=b
  local n=self.game.save.currentBox or 1
  self:bg3Write(0,11,n)
 end
 return self.bg3
end
function PC:bg3Write(slot,at,box)
 local b=self.bg3
 for x=0,22 do b.cols[(at+x)%64]={slot=slot,x=x} end
 b.slots[slot]={box=box,paper=self:wallpaperOf(box),at=at}
end
-- BoxGraphics_GetBoxMoveDirection: the shorter way round, a tie going left
function PC:moveDirection(old,new)
 local count=Boxes.count();local right,left
 if new>old then right,left=new-old,old+(count-new) else right,left=new+(count-old),old-new end
 return right>=left and -1 or 1
end
function PC:changeBox(delta)
 local save=self.game.save
 local prev=self:previewMon()
 self:bg3State()
 local old=save.currentBox or 1
 save.currentBox=(old-1+delta)%Boxes.count()+1
 if save.currentBox~=old then self:slideBox(old,save.currentBox,prev) end
end
-- BoxGraphics_ChangeToNewBox: ov19_021D7B4C(dir) then ov19_021D7D70(dir)
function PC:slideBox(old,new,prev)
 local b=self:bg3State()
 if self.slide then self:finishSlide() end
 local dir=self:moveDirection(old,new)
 local at=(b.base+23*dir)%64
 self:bg3Write(1-b.slot,at,new)
 self.slide={k=0,dir=dir,from=b.scroll,oldBox=old,preview=prev}
 b.base,b.slot=at,1-b.slot
end
function PC:finishSlide()
 local s=self.slide
 if not s then return end
 self.bg3.scroll=(s.from+184*s.dir)%512;self.slide=nil
end
-- the BG3 scroll and the icons' shift this vblank: the icons are one step
-- ahead of the scroll (unk_98 starts at 1)
function PC:slideShift()
 local s=self.slide
 if not s then return 0,0 end
 local step=PC.SLIDE_STEP*s.dir
 local bg=math.floor(math.max(0,math.min(s.k-1,PC.SLIDE_FRAMES-1))*step/4096)
 if s.k>PC.SLIDE_FRAMES then bg=184*s.dir end
 local icons=math.floor(-math.min(s.k,PC.SLIDE_FRAMES)*step/4096)
 return bg,icons
end
-- ov19_021D8350 / 8370: a wallpaper change fades the slot's palette to white
-- in eight steps three vblanks apart, reloads it, and fades back
function PC:setWallpaper(id)
 self:box().wallpaper=id
 local b=self:bg3State()
 self.paperFade={k=0,slot=b.slot,paper=id}
end
function PC:paperWhite(slot)
 local f=self.paperFade
 if not f or f.slot~=slot then return 0 end
 local level
 if f.k<=30 then level=math.min(8,math.floor(f.k/3)) else level=math.max(0,8-math.floor((f.k-30)/3)) end
 return level/8
end
function PC:previewMon()
 if self.held then return self.held.mon end
 if self.partyOpen then return self.game.save.party[self.partyIndex] end
 return (self:selected())
end
function PC:step()
 local s=self.slide
 if s then s.k=s.k+1;if s.k>PC.SLIDE_FRAMES then self:finishSlide() end end
 local f=self.paperFade
 if f then
  f.k=f.k+1
  if f.k==30 and self.bg3.slots[f.slot] then self.bg3.slots[f.slot].paper=f.paper end
  if f.k>=58 then self.paperFade=nil end
 end
 local j=self.jump
 if j then
  j.f=j.f+1
  if j.f==11 and not j.closing then self.message=self:say(8,'Jump to which Box?') end
  if j.closing then j.c=j.c+1;if j.c>=7 then self.jump=nil end end
 end
 if self.dialStep then self:dialStep() end
end
function PC:busy() return self.slide or self.paperFade end
function PC:rememberOrigin()
 if self.held and self.held.from and not self.held.box then self.held.box=self.game.save.currentBox end
end
function PC:returnHeld()
 local held=self.held
 if not held then return false end
 if held.from then self.game.save.boxes[held.box or self.game.save.currentBox][held.from]=held.mon;self.held=nil;return true end
 return Base.returnHeld(self)
end
function PC:placeDisplaced(held,mon)
 if held.from then self.game.save.boxes[held.box or self.game.save.currentBox][held.from]=mon
 else Base.placeDisplaced(self,held,mon) end
end
function PC:carry(slot)
 local held=self.held
 if held then
  local target=self:box()[slot];self:box()[slot]=held.mon;self.held=nil
  if target then self:placeDisplaced(held,target) end
 else Base.carry(self,slot);self:rememberOrigin() end
end
function PC:withdraw(slot)
 local mon=self:box()[slot];if not mon then return end
 if #self.game.save.party>=6 then self.message=self:say(5,'Your party’s full!');return end
 self:box()[slot]=nil;table.insert(self.game.save.party,mon)
end
local function usable(mon) return mon and not (mon.egg or mon.isEgg) and (mon.hp==nil or mon.hp>0) end
function PC:canRemoveParty(index,replacement)
 if usable(replacement) then return true end
 for i,mon in ipairs(self.game.save.party) do if i~=index and usable(mon) then return true end end
 return false
end
function PC:carryFromParty(index)
 if self.game.save.party[index] and not self:canRemoveParty(index,self.held and self.held.mon) then
  self.message=self:say(6,'That’s your last Pokémon!');return
 end
 return Base.carryFromParty(self,index)
end

-- THE MENU: { label, key } rows in the action window.  `key` is what
-- runAction acts on; `label` is the cartridge's word for it.
function PC:openMenu(keys,prompt,index)
 local rows={}
 for i,k in ipairs(keys) do
  if type(k)=='table' then rows[i]=k else rows[i]={label=self:label(k),key=k} end
 end
 self.menu=rows;self.action=index or 1;self.menuTop=1
 if prompt then self.message=prompt end
end
function PC:choose()
 if self.row==PC.BUTTON_ROW and not self.partyOpen then
  if self.col<=3 then self.partyOpen=true;self.partyIndex=1;return end
  return self:close()
 end
 if self.row==0 and not self.partyOpen then
  self:openMenu({'JUMP','WALLPAPER','NAME','HEADER CANCEL'},self:say(7,'What do you want to do?'));return
 end
 if self.partyOpen then
  if self.partyIndex==7 then self.partyOpen=nil;return end
  if self.opts.mode=='deposit' then
   local party=self.game.save.party;local slot=Boxes.firstFree(self:box())
   if #party<=1 or not self:canRemoveParty(self.partyIndex) then self.message=self:say(6,'That’s your last Pokémon!')
   elseif not slot then self.message=self:say(13,'The Box is full.')
   elseif party[self.partyIndex] then self:box()[slot]=table.remove(party,self.partyIndex) end
  else self:carryFromParty(self.partyIndex);self:rememberOrigin() end
  return
 end
 local mon,slot=self:selected()
 if self.held then self:carry(slot);return end
 if not mon then return end
 if self.opts.mode=='withdraw' then return self:withdraw(slot) end
 local prompt=self:say(0,self:nameOf(mon)..' is selected.',self:nameOf(mon))
 if self.opts.mode=='items' then self:openMenu({'TAKE','GIVE','CANCEL'},prompt)
 else self:openMenu({'MOVE','SUMMARY','WITHDRAW','MARK','RELEASE','CANCEL'},prompt) end
end
-- StateStack:pop calls exit as a lifecycle hook. It must not pop again.
function PC:exit()
 if self._exitNotified then return end
 self._exitNotified=true
 if self.opts.onCancel then self.opts.onCancel() end
end
function PC:close() self.game.stack:pop() end
function PC:closeMenu() self.menu=nil;self.message='' end
-- A on a menu row: a marking symbol toggles in place, anything else acts
function PC:pickMenuRow(i)
 local row=self.menu and self.menu[i]
 if not row then return end
 if row.mark then
  local m,b=self.markDraft or 0,2^row.mark
  self.markDraft=(math.floor(m/b)%2==1) and m-b or m+b
  return
 end
 return self:runAction(row.key)
end
function PC:runAction(action)
 local mon,slot=self:selected()
 self:closeMenu()
 if type(action)=='function' then return action() end
 if action=='MOVE' then self:carry(slot)
 elseif action=='SUMMARY' then Screens.push(self.game,'SummaryMenu',mon)
 elseif action=='WITHDRAW' then self:withdraw(slot)
 elseif action=='RELEASE' then
  if mon and (mon.egg or mon.isEgg) then self.message=self:say(31,'You can’t release an Egg.');return end
  self:openMenu({{label=self:label('YES'),key='CONFIRM RELEASE'},{label=self:label('NO'),key='CANCEL'}},self:say(2,'Release this Pokémon?'),2)
 elseif action=='CONFIRM RELEASE' then
  local name=mon and self:nameOf(mon);self:box()[slot]=nil
  if name then self.message=self:say(3,name..' was released.',name) end
 elseif action=='MARK' then
  -- BOX_MENU_CIRCLE .. BOX_MENU_DIAMOND, then CONFIRM and CANCEL: the six
  -- symbols toggle in the menu itself and only CONFIRM writes them back
  self.markTarget,self.markDraft=mon,tonumber(mon and mon.markings) or 0
  local rows={}
  for i=0,5 do rows[#rows+1]={label='',mark=i} end
  rows[#rows+1]={label=self:label('CONFIRM'),key='CONFIRM MARK'}
  rows[#rows+1]={label=self:label('CANCEL'),key='CANCEL'}
  self:openMenu(rows,self:say(1,'Mark your Pokémon.'))
 elseif action=='CONFIRM MARK' then
  if self.markTarget then self.markTarget.markings=self.markDraft end
  self.markTarget,self.markDraft=nil,nil
 elseif action=='PARTY' then self.partyOpen=true;self.partyIndex=1
 elseif action=='NAME' then
  Screens.push(self.game,'NamingScreen',{title='BOX NAME',kind='box',default=self:boxName(),maxLen=8,onDone=function(name)
   if name~='' then self.game.save.boxNames=self.game.save.boxNames or {};self.game.save.boxNames[self.game.save.currentBox]=name end
  end})
 elseif action=='JUMP' then
  local rows={}
  for n=1,Boxes.count() do
   local saved=self.game.save.currentBox;self.game.save.currentBox=n
   rows[n]={label=self:boxName(),key=function() self.game.save.currentBox=n end}
   self.game.save.currentBox=saved
  end
  self:openMenu(rows,self:say(8,'Jump to which Box?'),self.game.save.currentBox or 1)
 elseif action=='WALLPAPER' then
  local pages={}
  for p=0,3 do
   pages[#pages+1]={label=self:label(({'SCENERY 1','SCENERY 2','SCENERY 3','ETCETERA'})[p+1]),key=function()
    local rows={}
    for i=0,3 do
     local id=p*4+i
     rows[#rows+1]={label=self:word(PC.STORAGE_BANK,PC.WALLPAPER_NAME+id,'WALLPAPER '..id),key=function() self:box().wallpaper=id end}
    end
    rows[#rows+1]={label=self:label('CANCEL'),key='CANCEL'}
    self:openMenu(rows,self:say(10,'Pick the wallpaper.'))
   end}
  end
  pages[#pages+1]={label=self:label('CANCEL'),key='CANCEL'}
  self:openMenu(pages,self:say(9,'Please pick a theme.'))
 elseif action=='TAKE' and mon then
  local item=mon.heldItem or mon.item
  if item and item~=0 and Bag.add(self.game.save,item,1,self.game.data) then mon.heldItem=nil;mon.item=nil end
 elseif action=='GIVE' and mon then
  Screens.push(self.game,'BagMenu',{pick=true,onPick=function(id)
   local item=self.game.data.items[id]
   if not item or item.keyItem then return end
   if (self.game.save.inventory[id] or 0)<1 then return end
   local old=mon.heldItem or mon.item
   if old and old~=0 and not Bag.add(self.game.save,old,1,self.game.data) then return end
   Bag.remove(self.game.save,id,1);mon.heldItem=id;mon.item=nil
  end})
 end
end
function PC:update(dt)
 self.t=(self.t or 0)+(dt or 1/60);local input=self.game.input
 if self.menu then
  local n=#self.menu
  if input:wasPressed('up') then self.action=(self.action-2)%n+1
  elseif input:wasPressed('down') then self.action=self.action%n+1
  elseif input:wasPressed('a') then self:pickMenuRow(self.action)
  elseif input:wasPressed('b') then self:closeMenu() end
  return
 end
 if input:wasPressed('b') then
  self.message=''
  if self:returnHeld() then return end
  if self.partyOpen then self.partyOpen=nil;return end
  return self:close()
 end
 if input:wasPressed('select') then self.partyOpen=not self.partyOpen;self.partyIndex=1 end
 if input:wasPressed('l') then self:changeBox(-1) elseif input:wasPressed('r') then self:changeBox(1) end
 local moved=false
 if self.partyOpen then
  if input:wasPressed('up') then self.partyIndex=(self.partyIndex-2)%7+1;moved=true
  elseif input:wasPressed('down') then self.partyIndex=self.partyIndex%7+1;moved=true
  elseif input:wasPressed('left') or input:wasPressed('right') then
   if self.partyIndex<7 then self.partyIndex=self.partyIndex+(self.partyIndex%2==1 and 1 or -1) end;moved=true
  end
 else
  -- header (0), the five rows, the buttons (6), wrapping
  if input:wasPressed('up') then self.row=(self.row+6)%7;moved=true elseif input:wasPressed('down') then self.row=(self.row+1)%7;moved=true end
  if input:wasPressed('left') then
   if self.row==0 then self:changeBox(-1) elseif self.row==PC.BUTTON_ROW then self.col=self.col<=3 and 4 or 1 else self.col=(self.col+4)%6+1 end;moved=true
  end
  if input:wasPressed('right') then
   if self.row==0 then self:changeBox(1) elseif self.row==PC.BUTTON_ROW then self.col=self.col<=3 and 4 or 1 else self.col=self.col%6+1 end;moved=true
  end
 end
 if moved then self.message='' end
 if input:wasPressed('a') then self:choose() end
end

-- -------------------------------------------------------------------- draw --

-- the standard window frame (pl_winframe standard_system, which this screen
-- loads at BG1 tile 512 in palette 7) around a tile rect, from the font
-- record's frame sheet; its paper is the window's own colour 15
function PC:frame(tx,ty,tw,th,fill)
 local g=love.graphics
 g.setColor(fill[1]/255,fill[2]/255,fill[3]/255,1)
 g.rectangle('fill',tx*8,ty*8,tw*8,th*8)
 g.setColor(1,1,1,1)
 local frames=(self.game.data.font or {}).frames
 local sheet=frames and image(self,frames.image)
 if not sheet then return Font.drawBox(tx-1,ty-1,tw+2,th+2) end
 local iw,ih=sheet:getDimensions()
 self.frameQuads=self.frameQuads or {}
 local function q(i)
  if not self.frameQuads[i] then self.frameQuads[i]=g.newQuad((i%3)*8,math.floor(i/3)*8,8,8,iw,ih) end
  return self.frameQuads[i]
 end
 local x0,y0,x1,y1=(tx-1)*8,(ty-1)*8,(tx+tw)*8,(ty+th)*8
 g.draw(sheet,q(0),x0,y0);g.draw(sheet,q(2),x1,y0);g.draw(sheet,q(6),x0,y1);g.draw(sheet,q(8),x1,y1)
 for i=0,tw-1 do g.draw(sheet,q(1),(tx+i)*8,y0);g.draw(sheet,q(7),(tx+i)*8,y1) end
 for j=0,th-1 do g.draw(sheet,q(3),x0,(ty+j)*8);g.draw(sheet,q(5),x1,(ty+j)*8) end
end

-- font_special_chars tiles: 0-9 digits, 11-12 "Lv.", 13-14 "No."
function PC:special(strip,tile,count,x,y)
 local img=self:art(strip)
 if not img then return false end
 self.specialQuads=self.specialQuads or {}
 local key=strip..tile..':'..count
 if not self.specialQuads[key] then self.specialQuads[key]=love.graphics.newQuad(tile*8,0,count*8,8,img:getDimensions()) end
 love.graphics.setColor(1,1,1,1)
 love.graphics.draw(img,self.specialQuads[key],x,y)
 return true
end
-- CharCode_FromInt: `digits` cells, padded with spaces or zeros
function PC:number(strip,value,digits,zeros,x,y)
 local s=tostring(math.floor(value))
 if #s<digits then s=(zeros and '0' or ' '):rep(digits-#s)..s end
 for i=1,#s do
  local d=tonumber(s:sub(i,i))
  if d then self:special(strip,d,1,x+(i-1)*8,y) end
 end
end

function PC:dexNumber(mon)
 local def=self.game.data.pokemon and self.game.data.pokemon[mon.species]
 return tonumber(def and (def.nationalDex or def.dexNumber or def.national)) or tonumber(mon.species)
end

local ROTATE=84/60   -- 80 frames still, then a 4-frame scroll per line (ov19_021DACF8)
function PC:rotatorLines(mon)
 local data=self.game.data
 local item=data.items and data.items[mon.heldItem or mon.item]
 local lines={{text=item and item.name or self:say(20,'No item')}}
 local def=data.pokemon and data.pokemon[mon.species]
 if def and type(def.types)=='table' then lines[#lines+1]={types=def.types} end
 local nature=mon.nature
 if type(nature)~='string' and mon.personality then
  nature=((data.constants or {}).natureOrder or {})[mon.personality%25+1]
 end
 if type(nature)=='string' then lines[#lines+1]={text=nature} end
 local ability=mon.ability or (def and def.abilities and def.abilities[1])
 local rec=ability and data.abilities and data.abilities[ability]
 local name=(rec and rec.name) or (type(ability)=='string' and ability) or nil
 if name then lines[#lines+1]={text=name} end
 return lines
end

function PC:drawTypeIcon(typeName,x,y)
 local rec=((self.game.data.gen4_graphics or {}).battleObjects or {})['type_icons_'..tostring(typeName or ''):lower()]
 local img=image(self,type(rec)=='table' and rec.path or rec)
 if img then love.graphics.setColor(1,1,1,1);love.graphics.draw(img,x-16,y-8) end
end

function PC:drawPreview(mon,ink)
 local g=love.graphics
 local data=self.game.data
 local egg=mon.egg or mon.isEgg
 local path=require('src.pokemon.Sprites').path(data,mon.species,'front',{mon=mon,kind='summary'})
 local pic=image(self,path)
 if pic then
  local w,h=pic:getDimensions();g.setColor(1,1,1,1)
  g.draw(pic,math.floor(44-w/2),math.floor(84-h/2))
 end
 local def=data.pokemon and data.pokemon[mon.species]
 local species=egg and (mon.nickname or 'EGG') or (def and def.name) or tostring(mon.species)
 say(Font.fit(species,78),2,8,ink.species)
 say(Font.fit(self:nameOf(mon),68),2,128,ink.nickname)
 if not egg then
  local female=mon.gender=='female' or mon.gender==1
  local male=mon.gender=='male' or mon.gender==0
  if female then say(self:say(22,'♀'),70,128,ink.female) elseif male then say(self:say(21,'♂'),70,128,ink.male) end
  if self:special('special_name',13,2,40,24) then
   self:number('special_name',self:dexNumber(mon) or 0,3,true,56,24)
  end
  if self:special('special_level',11,2,0,144) then
   self:number('special_level',mon.level or 1,3,false,16,144)
  else say('Lv'..(mon.level or 1),0,144,ink.nickname) end
  -- the rotator: one line at a time in a 12 x 2 window at (8, 168)
  local lines=self:rotatorLines(mon)
  local line=lines[math.floor((self.t or 0)/ROTATE)%#lines+1]
  if line.types then
   self:drawTypeIcon(line.types[1],24,176)
   if line.types[2] and line.types[2]~=line.types[1] then self:drawTypeIcon(line.types[2],60,176) end
  else say(Font.fit(line.text,96),8,168,ink.item) end
 end
 local marks=tonumber(mon.markings) or 0
 for i=0,5 do
  local on=math.floor(marks/2^i)%2==1
  local img=self:art((on and 'marking_on_' or 'marking_off_')..i)
  if img then g.setColor(1,1,1,1);g.draw(img,32+8*i,152) end
 end
end

function PC:handPoint()
 if self.partyOpen then
  local p=PC.PARTY_SLOTS[self.partyIndex] or PC.PARTY_EXIT
  return p[1],p[2]-16,'party'
 end
 if self.row==0 then return 168,8,'header' end
 if self.row==PC.BUTTON_ROW then return self.col<=3 and 159 or 235,160,'button' end
 return 112+(self.col-1)*24,40+(self.row-1)*24-16,'box'
end

function PC:drawMenu(ink)
 local menu=self.menu
 local n=math.min(#menu,8)
 local top=math.max(1,math.min(self.action-n+1,#menu-n+1))
 if self.action<top then top=self.action end
 -- ov19_021DB684: the window sits on tile 19, (8 - n) * 2 tiles down from 3
 local ty=3+(8-n)*2
 self:frame(19,ty,12,n*2,ink.menuFill)
 for i=0,n-1 do
  local row=menu[top+i]
  local y=ty*8+i*16
  if row.mark then
   -- ov19_021DB638: the symbol from the 48 x 16 sheet at (44, 16 * i + 4),
   -- its set (top) or clear (bottom) half
   local img=self:art('marking_menu')
   if img then
    local on=math.floor((self.markDraft or 0)/2^row.mark)%2==1
    self.markQuads=self.markQuads or {}
    local key=row.mark..(on and 'on' or 'off')
    if not self.markQuads[key] then self.markQuads[key]=love.graphics.newQuad(row.mark*8,on and 0 or 8,8,8,img:getDimensions()) end
    love.graphics.setColor(1,1,1,1);love.graphics.draw(img,self.markQuads[key],19*8+44,y+4)
   end
  else say(Font.fit(row.label,84),19*8+10,y,ink.menu) end
  if top+i==self.action then
   Font.pushStyle({text=rgb(ink.menu[1]),shadow=rgb(ink.menu[2])})
   Font.drawCode(require('src.ui.Theme').cursor,19*8,y)
   Font.popStyle()
  end
 end
end

function PC:draw()
 local g=love.graphics
 local ink=self:ink()
 local bd=ink.backdrop or FALLBACK_INK.backdrop
 g.setColor(bd[1]/255,bd[2]/255,bd[3]/255,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 local paperId=self:wallpaperId()
 local paper=self:art(('wallpaper_%02d'):format(paperId))
 local fresh=paper~=nil
 if paper then g.draw(paper,0,0)
 else
  paper=self:img(('storage/wallpaper_%02d'):format(paperId));if paper then g.draw(paper,88,0) end
 end
 -- the box name, in the wallpaper's own colours 2 (letter) and 1 (shadow)
 local pair=(ink.wallpaper or {})[paperId] or {{99,99,99},{255,255,255}}
 local name=Font.fit(self:boxName(),144)
 say(name,172-Font.width(name)/2,13,pair)
 for slot=1,30 do self:drawIcon(self:box()[slot],112+(slot-1)%6*24,40+math.floor((slot-1)/6)*24) end
 local hx,hy,where=self:handPoint()
 -- the buttons sit under BG2 (BG priority 2)
 local pressed=0
 self:sprite('buttons_'..pressed,183,176)
 local main=self:art('main') or (not fresh and self:img('storage/main'))
 if main then g.draw(main,0,0) end
 if self.partyOpen then
  local panel=self:art('party_panel')
  if panel then g.draw(panel,112,0)
  else g.setColor(0.8,0.9,1,1);g.rectangle('fill',112,0,120,192);g.setColor(1,1,1,1) end
  for i=1,6 do
   local p=PC.PARTY_SLOTS[i]
   self:drawIcon(self.game.save.party[i],p[1],p[2])
  end
 end
 local mon
 if self.held then mon=self.held.mon
 elseif self.partyOpen then mon=self.game.save.party[self.partyIndex]
 else mon=self:selected() end
 if mon then self:drawPreview(mon,ink) end
 -- the header arrows: 6 / 7, or 8 / 9 with the hand on the header
 local onHeader=where=='header'
 self:sprite(('cursor_%02d'):format(onHeader and 8 or 6),108,20)
 self:sprite(('cursor_%02d'):format(onHeader and 9 or 7),236,20)
 -- the hand, its shadow on the slot, and what it carries
 if where=='box' then self:sprite('cursor_05',hx,hy+24) end
 if self.held then self:drawIcon(self.held.mon,hx,hy+4) end
 local hand=self.held and 2 or 0
 if not self:sprite(('cursor_%02d'):format(hand),hx,hy) then self:drawCursor(hand,hx,hy) end
 if self.menu then self:drawMenu(ink) end
 if self.message and self.message~='' then
  Font.drawDialogueBox(1,20,29,4)
  local y=168
  for line in (self.message..'\n'):gmatch('([^\n]*)\n') do
   say(Font.fit(line,216),16,y,ink.message);y=y+16
   if y>184 then break end
  end
 end
end
-- an older cache's hand (gen4_graphics storage/cursor_NN)
function PC:drawCursor(sequence,x,y)
 local key=('storage/cursor_%02d'):format(sequence);local img=self:img(key)
 if img then
  local rec=self.game.data.gen4_graphics.screens[key]
  if type(rec)~='table' then rec={} end
  love.graphics.draw(img,x+(rec.originX or -img:getWidth()/2),y+(rec.originY or 0))
 end
end
function PC:touchpressed(_,px,py)
 local r=require('src.render.Renderer').uiPresentation
 if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
 local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
 if self.menu then
  local n=math.min(#self.menu,8);local top=(3+(8-n)*2)*8
  local i=math.floor((y-top)/16)+1
  if x>=152 and i>=1 and i<=n then
   local first=math.max(1,math.min(self.action-n+1,#self.menu-n+1))
   self.action=first+i-1;self:pickMenuRow(self.action)
  end
 elseif self.partyOpen then
  for i,p in ipairs(PC.PARTY_SLOTS) do
   if math.abs(x-p[1])<20 and math.abs(y-p[2])<18 then self.partyIndex=i;self:choose();return true end
  end
  if y>=168 and x>=160 and x<224 then self.partyIndex=7;self:choose() end
 elseif y<32 then if x<120 then self:changeBox(-1) elseif x>224 then self:changeBox(1) else self.row=0;self:choose() end
 elseif y>=160 and x>=112 then self.row=PC.BUTTON_ROW;self.col=x<184 and 1 or 4;self:choose()
 elseif x>=100 and x<244 and y>=28 and y<148 then self.col=math.floor((x-100)/24)+1;self.row=math.floor((y-28)/24)+1;self:choose() end
 return true
end
return PC
