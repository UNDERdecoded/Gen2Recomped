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
 CONFIRM=68,GIVE=70,TAKE=71,['SET ON LEFT']=76,['SET ON RIGHT']=77,YES=78,NO=79}
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
  if j.closing then
   j.c=j.c+1
   if j.c>=PC.JUMP_CLOSE_FRAMES then self.jump=nil;self.message='' end
  else
   j.f=j.f+1
   -- BOX_SELECTOR_DISPLAY_MESSAGE_START: the question once the popup is up
   if j.f==PC.JUMP_OPEN_FRAMES then self.message=self:say(8,'Jump to which Box?') end
  end
 end
 if self.dialStep then self:dialStep() end
 self:subStep()
end
function PC:busy() return self.slide or self.paperFade end

-- THE JUMP POPUP (ov19_021DB8E4, BoxSelectorPopup in box_app_manager.c).
-- ov19_021DC0A0 opens BG1 map 3's 32 x 10 band out from tile row 10, one row
-- up and one down a frame (four frames, then whole on the fifth); the seven
-- thumbnails (box selection - 3 .. + 3, at x 32 + 32 i, y 88) come in on the
-- next frame in OBJ rows 13-15 faded seven-sevenths to white and lose a
-- seventh a frame; at 0 the name window (10, 6) 12 x 2 -- the name centred on
-- x 48 in TEXT_COLOR(2, 8, 7) -- and the counts window (3, 13) 26 x 1 --
-- two zero-padded digits per box, 32 apart -- go up.  Left / right (and L / R)
-- move the selection and redraw at once (ov19_021DBB70); A jumps, B does not.
-- ov19_021DC1CC closes it: everything off, then the band folds back in.
PC.JUMP_BAND_FRAMES=5
PC.JUMP_FADE=7
PC.JUMP_OPEN_FRAMES=PC.JUMP_BAND_FRAMES+1+PC.JUMP_FADE
PC.JUMP_CLOSE_FRAMES=7
function PC:openJump()
 self.jump={f=0,box=self.game.save.currentBox or 1}
 self.message=''
end
function PC:closeJump(target)
 local j=self.jump
 if not j or j.closing then return end
 j.closing=true;j.c=0
 local cur=self.game.save.currentBox or 1
 if target and target~=cur then
  local prev=self:previewMon()
  self:bg3State()
  self.game.save.currentBox=target
  self:slideBox(cur,target,prev)
 end
end
-- how many band rows are showing on each side of row 10
function PC:jumpBandRows()
 local j=self.jump
 if not j then return 0 end
 if j.closing then
  if j.c<=1 then return 5 end
  return math.max(0,5-(j.c-1))
 end
 return math.min(5,j.f)
end
-- the thumbnails' fade to white, 0..1, or nil before they are up
function PC:jumpFade()
 local j=self.jump
 if not j or j.closing then return nil end
 if j.f<=PC.JUMP_BAND_FRAMES then return nil end
 local level=math.max(0,PC.JUMP_FADE-(j.f-PC.JUMP_BAND_FRAMES-1))
 return level/PC.JUMP_FADE
end
function PC:updateJump(input)
 local j=self.jump
 if j.closing or j.f<PC.JUMP_OPEN_FRAMES then return end
 local count=Boxes.count()
 if input:wasPressed('left') or input:wasPressed('l') then j.box=(j.box-2)%count+1
 elseif input:wasPressed('right') or input:wasPressed('r') then j.box=j.box%count+1
 elseif input:wasPressed('a') then self:closeJump(j.box)
 elseif input:wasPressed('b') then self:closeJump(nil) end
end
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
 if self:compareMode() then
  -- BoxMenu_FillMonMenu, PC_MODE_COMPARE
  local c=self:compareState()
  local set=c.slot==0 and 'SET ON LEFT' or 'SET ON RIGHT'
  self:openMenu({{label=self:label(set),key='SET COMPARE'},'WITHDRAW','MARK','CANCEL'},prompt)
 elseif self.opts.mode=='items' then self:openMenu({'TAKE','GIVE','CANCEL'},prompt)
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
 elseif action=='SET COMPARE' then self:toggleCompareSlot()
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
  self:openJump()
 elseif action=='WALLPAPER' then
  local pages={}
  for p=0,3 do
   pages[#pages+1]={label=self:label(({'SCENERY 1','SCENERY 2','SCENERY 3','ETCETERA'})[p+1]),key=function()
    local rows={}
    for i=0,3 do
     local id=p*4+i
     rows[#rows+1]={label=self:word(PC.STORAGE_BANK,PC.WALLPAPER_NAME+id,'WALLPAPER '..id),key=function() self:setWallpaper(id) end}
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
  -- Giratina's Orb / Arceus's Plate (Gen45FormData.heldItem)
  pcall(require('src.pokemon.Gen45FormData').heldItem,self.game.data,mon)
 elseif action=='GIVE' and mon then
  Screens.push(self.game,'BagMenu',{pick=true,onPick=function(id)
   local item=self.game.data.items[id]
   if not item or item.keyItem then return end
   if (self.game.save.inventory[id] or 0)<1 then return end
   local old=mon.heldItem or mon.item
   if old and old~=0 and not Bag.add(self.game.save,old,1,self.game.data) then return end
   Bag.remove(self.game.save,id,1);mon.heldItem=id;mon.item=nil
   pcall(require('src.pokemon.Gen45FormData').heldItem,self.game.data,mon)
  end})
 end
end
function PC:update(dt)
 self.t=(self.t or 0)+(dt or 1/60);local input=self.game.input
 for _=1,self:frames(dt) do self:step() end
 if self.jump then self:updateJump(input);return end
 -- a box sliding in or a wallpaper fading takes no input until it is done
 if self:busy() then return end
 -- a touch dial up (TOUCH_BOX_JUMP / TOUCH_MARKINGS): the pad, A or B only
 -- closes it; while it opens, closes or turns nothing is read
 local s=self.subState
 if s and (s.task or s.dial~=PC.DIAL_NONE) then
  if not s.task and not s.items and not s.scroll and s.dial~=PC.DIAL_NONE then
   for _,k in ipairs({'up','down','left','right','a','b'}) do
    if input:wasPressed(k) then self:setDial(PC.DIAL_NONE);break end
   end
  end
  return
 end
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

-- ----------------------------------------------------------- bottom screen --
--
-- THE TOUCH SCREEN (ov19_021DCF88; compare mode's is ov19_021DEC04), drawn
-- through src/ui/SecondScreen.lua whenever a bottom screen is shown.  Sub BG:
--   SUB_3  `sub_bg` (map 124), the backdrop with the two dial wells
--   SUB_2  `sub_cover` (map 125, 512 wide) scrolled 0 / -128 / 128 by dial
--          (Unk_ov19_021E024C), alpha-blended over SUB_3 by the sine ramp of
--          ov19_021DD024 as a dial opens and closes
--   SUB_1  `sub_dials` (map 126, 512 wide) scrolled 0 / -96 / 88
--          (Unk_ov19_021E0258) over 8 frames (16 when switching dials)
--   SUB_0  the box names on the BOX dial, alpha 14 / 2 (ov19_021DE350)
--   OBJ    the corner buttons at (0, 184) and (256, 184) flipped, BG priority
--          3; the dial's items (box thumbnails, or the eight markings
--          buttons mirrored to the right) on the arc Unk_ov19_021E028C at the
--          eight stops Unk_ov19_021E0264, BG priority 2
-- Touch (box_app_manager.c): the corner circles (0 | 255, 184) r 40 open a
-- dial; a dial is a ring about (0 | 255, 192) between radii 56 and 88 whose
-- turn counts 0 / 1 / 2 steps past 4.219 / 33.75 degrees (touch_dial.c); the
-- markings buttons are circles r 16 at PC_MARKINGS_BUTTON1..6; the pad, A or
-- B closes a dial.  A box picked on the dial is jumped to 20 frames after
-- the stylus leaves the ring.
PC.ARC={
 106,200,106,194,106,190,105,186,105,184,105,182,105,180,105,178,105,176,104,174,104,172,
 104,170,104,168,103,166,103,164,103,163,102,161,102,159,101,157,101,155,100,153,100,151,99,150,
 98,148,98,146,97,144,96,142,96,141,95,139,94,137,94,136,93,134,92,132,91,131,90,129,89,127,
 88,126,87,124,86,123,86,121,85,120,83,118,82,117,81,115,80,114,79,112,78,111,77,110,76,108,
 75,107,73,106,72,104,71,103,70,102,68,101,67,100,66,99,65,98,63,97,62,95,61,95,59,94,58,93,
 56,92,55,91,54,90,52,89,51,88,49,88,48,87,46,86,45,86,43,85,42,84,40,84,39,83,37,83,36,82,
 34,82,33,82,31,81,30,81,28,81,26,80,25,80,23,80,22,80,20,80,19,80,17,80,16,80,16,78,16,76,
 16,74,16,72,16,70,16,68,16,66,16,64,16,63,16,61,16,60,16,58,16,57,16,55,16,54,16,52,16,51,
 16,49,16,48,16,46,16,45,16,43,16,42,16,40,16,39,16,38,16,36,16,34,16,32,16,30,16,28,16,26,
 16,24,16,22,16,20,16,18,16,16,16,14,16,12,16,10,16,8,16,6,16,4,16,2,16,0,16,-2,16,-4,16,-6,
 16,-8,16,-10,16,-12,16,-14,16,-16}
PC.STOPS={[0]=0x8F,0x7F,0x6A,0x4A,0x33,0x1F,0xC,0}
PC.DIAL_NONE,PC.DIAL_BOX,PC.DIAL_MARKS=0,1,2
PC.SUB1_X={[0]=0,-96,88}
PC.SUB2_X={[0]=0,-128,128}
PC.BUTTON={{0,184},{255,184}}
PC.BUTTON_R=40
PC.RING={inner=56,outer=88}
PC.MARK_BUTTONS={{152,168},{163,134},{184,104},{216,84},{240,52},{240,16}}
PC.MARK_R=16
PC.NAME_RECTS={{36,4},{36,36},{50,69},{92,92},{114,124},{124,156}}
PC.JUMP_DELAY=20
PC.XLU=6/16          -- G2_SetBlendAlpha(NONE, ALL, 6, 10): a filtered-out icon
-- ov19_021DD024: the blend ramp, sin(90 i / 16) * 16, 0 and 16 at the ends
PC.RAMP={[0]=0}
for i=1,14 do PC.RAMP[i]=math.floor(math.sin(math.rad(math.floor(math.floor(90*4096/16)*i/4096)))*16) end
PC.RAMP[15]=16
-- compare mode (ov19_021DEC04)
PC.COMPARE_DOTS={{128,54},{172,86},{155,136},{100,136},{84,86}}  -- cool beauty cute smart tough
PC.COMPARE_CENTRE={128,100}
PC.COMPARE_BUTTON={128,178,12}
PC.COMPARE_TEXT={nature=35,level=36,hp=37,attack=38,defense=39,spAttack=40,spDefense=41,speed=42,move=43,unknown=44}

function PC:bottomShown()
 local okS,SS=pcall(require,'src.ui.SecondScreen')
 if not okS or not self.game then return false end
 local mode=SS.mode(self.game)
 local combined=SS.combined and SS.combined(self.game)
 return (require('src.ui.SecondScreen').separateMode(mode) and not SS.stowed(self.game)) or combined or false,SS
end
function PC:bottomPoint(px,py)
 local shown,SS=self:bottomShown()
 if not shown then return nil end
 return SS.toLocal(self.game,px,py)
end
function PC:compareMode() return self.opts.mode=='compare' end
function PC:sub()
 if not self.subState then
  self.subState={dial=PC.DIAL_NONE,offset=0,markScroll=0,sub1=0,sub2=0,blend=16,cover=0,
   buttons={{seq=0,t=0},{seq=0,t=0}},names=false,items=nil,scroll=nil,jumpWait=nil}
  -- MOVE ITEMS: the right button is set to its press sequence once and
  -- left on its last cell (ov19_021DD224)
  if self.opts.mode=='items' then self.subState.buttons[2]={seq=1,t=16} end
 end
 return self.subState
end
-- BoxApp_GetMonSpriteTransparencyMask: MOVE ITEMS always 1 (no item -> faded)
function PC:markMask()
 if self.opts.mode=='items' then return 1 end
 return self.markFilter or 0
end
function PC:iconFaded(mon)
 local mask=self:markMask()
 if not mon or mask==0 then return false end
 if mask%2==1 then
  local item=mon.heldItem or mon.item
  if not item or item==0 then return true end
 end
 local marks=tonumber(mon.markings) or 0
 for i=0,5 do
  if math.floor(mask/2^(i+1))%2==1 and math.floor(marks/2^i)%2==0 then return true end
 end
 return false
end
-- BoxApp_SetMonSpriteTransparencyMask
function PC:toggleMarkFilter(kind)
 if kind==0 then self.markFilter=0 return end
 local m,b=self.markFilter or 0,2^(kind-1)
 self.markFilter=(math.floor(m/b)%2==1) and m-b or m+b
end
-- ov19_021DD9B8: the button of kind k lit?
function PC:markLit(kind)
 local mask=self:markMask()
 if kind==0 then return mask==0 end
 return math.floor(mask/2^(kind-1))%2==1
end
-- a corner button's cell for its sequence at tick t
local BUTTON_SEQS={[0]={{0,60}},{{1,8},{2,8}},{{3,4},{4,4}}}
local function seqCell(seq,t,loop)
 local frames=BUTTON_SEQS[seq] or BUTTON_SEQS[0]
 local total=0
 for _,f in ipairs(frames) do total=total+f[2] end
 if loop then t=t%total end
 local acc=0
 for _,f in ipairs(frames) do acc=acc+f[2];if t<acc then return f[1] end end
 return frames[#frames][1]
end
function PC:pressButton(i)
 self:sub().buttons[i]={seq=1,t=0}
end

-- ov19_021DD378: open, switch or close a dial
function PC:setDial(to)
 local s=self:sub()
 local from=s.dial
 if from==to then return end
 s.items,s.scroll,s.names,s.jumpWait=nil,nil,false,nil
 if to==PC.DIAL_NONE then
  s.task={kind='close',k=0,from=from}
 else
  if to==PC.DIAL_BOX then s.offset=(self.game.save.currentBox or 1)-1 else s.offset=0;s.markScroll=0 end
  self:pressButton(to)
  s.task={kind=from==PC.DIAL_NONE and 'open' or 'switch',k=0,to=to,frames=from==PC.DIAL_NONE and 8 or 16,
   sub1From=s.sub1}
 end
 s.dial=to
 s.drag=nil
end
function PC:subBusy()
 local s=self.subState
 return s and (s.task or s.items or s.scroll) and true or false
end
-- the item slide-in after a dial opens (ov19_021DDCC0 / ov19_021DDFFC)
function PC:startItems()
 local s=self:sub()
 s.items={k=0}
end
-- one vblank of the bottom screen's tasks
function PC:subStep()
 local s=self.subState
 if not s then return end
 for _,b in ipairs(s.buttons) do b.t=b.t+1 end
 local t=s.task
 if t then
  t.k=t.k+1
  local b=s.buttons[t.to or 0]
  local pressDone=not b or b.t>=16
  if t.kind=='open' then
   -- case 0: the press plays out; 1: SUB_1 scrolls 8 frames; 2-3: SUB_2
   -- is put in place and fades in over 16
   if not t.p then if pressDone then t.p=1;t.n=0 end
   elseif t.p==1 then
    t.n=t.n+1
    s.sub1=math.floor(t.sub1From+(PC.SUB1_X[t.to]-t.sub1From)*t.n/t.frames)
    if t.n>=t.frames then s.sub1=PC.SUB1_X[t.to];s.blend=0;s.cover=PC.SUB2_X[t.to];t.p=2;t.n=0 end
   else
    s.blend=PC.RAMP[math.min(15,t.n)];t.n=t.n+1
    if t.n>=16 then s.blend=16;s.buttons[t.to]={seq=0,t=0};s.task=nil;self:startItems() end
   end
  elseif t.kind=='switch' then
   if not t.p then if pressDone then t.p=1;t.n=15 end
   elseif t.p==1 then
    t.n=t.n-1;s.blend=PC.RAMP[t.n]
    if t.n<=0 then s.cover=PC.SUB2_X[t.to];t.p=2;t.n=0;t.sub1From=s.sub1 end
   elseif t.p==2 then
    t.n=t.n+1
    s.sub1=math.floor(t.sub1From+(PC.SUB1_X[t.to]-t.sub1From)*t.n/t.frames)
    if t.n>=t.frames then s.sub1=PC.SUB1_X[t.to];s.blend=0;t.p=3;t.n=0 end
   else
    s.blend=PC.RAMP[math.min(15,t.n)];t.n=t.n+1
    if t.n>=16 then s.blend=16;s.buttons[t.to]={seq=0,t=0};s.task=nil;self:startItems() end
   end
  else -- close (ov19_021DD670)
   if not t.p then t.p=1;t.n=15;t.sub1From=s.sub1 end
   if t.p==1 then
    t.n=t.n-1;s.blend=PC.RAMP[t.n]
    if t.n<=0 then s.cover=0;t.p=2;t.n=0 end
   elseif t.p==2 then
    t.n=t.n+1
    s.sub1=math.floor(t.sub1From+(0-t.sub1From)*t.n/8)
    if t.n>=8 then s.sub1=0;s.task=nil end
   end
  end
 end
 if s.items then
  s.items.k=s.items.k+1
  if s.items.k>48 then s.items=nil;s.names=(s.dial==PC.DIAL_BOX) end
 end
 if s.scroll then
  s.scroll.k=s.scroll.k+1
  if s.scroll.k>=s.scroll.frames then s.scroll=nil;s.names=(s.dial==PC.DIAL_BOX) end
 end
 -- TOUCH_BOX_JUMP_WAIT_FOR_INPUT_OR_JUMP: the jump, once the stylus is off
 if s.dial==PC.DIAL_BOX and s.jumpWait and not s.scroll and not self.slide then
  s.jumpWait=s.jumpWait+1
  if s.jumpWait>PC.JUMP_DELAY then
   s.jumpWait=nil
   local cur=self.game.save.currentBox or 1
   local target=s.offset+1
   if target~=cur then
    local prev=self:previewMon()
    self:bg3State()
    self.game.save.currentBox=target
    self:slideBox(cur,target,prev)
   end
  end
 end
 local c=self.compare
 if c and c.setPress then c.setPress.t=(c.setPress.t or 0)+1 end
end

-- WHERE AN ITEM IS: stop `p` (0..7, fractional between stops by index)
function PC.arcPoint(stop)
 stop=math.max(0,math.min(7,stop))
 local a=math.floor(stop)
 local b=math.min(7,a+1)
 local idx=PC.STOPS[a]+(PC.STOPS[b]-PC.STOPS[a])*(stop-a)
 idx=math.max(0,math.min(143,math.floor(idx)))
 return PC.ARC[idx*2+1],PC.ARC[idx*2+2]
end
-- the stop of each item now: box b (0-based) sits at offset + 4 - b, the
-- markings button of kind t at 6 - ((t - scroll) mod 8)
function PC:itemStop(base)
 local s=self.subState
 local stop=base
 if s.scroll then
  local f=s.scroll.k/s.scroll.frames
  stop=base-s.scroll.delta*(1-f)
 end
 if s.items then
  -- ov19_021DDCC0: the item for stop p leaves stop 0 at 2 (6 - p) and takes
  -- 6 p frames; ov19_021DDFFC: stop p leaves after 6 (6 - p), taking 6 p
  local p=math.floor(base+0.5)
  if p<1 or p>6 then return nil end
  local start=(s.dial==PC.DIAL_BOX) and 2*(6-p) or 6*(6-p)
  local f=math.max(0,math.min(1,(s.items.k-start)/math.max(1,6*p)))
  stop=p*f
 end
 return stop
end
function PC:boxOnStop(b)
 local s=self.subState
 local count=Boxes.count()
 local p=(s.offset+4-b)%count
 if p>count/2 then p=p-count end
 return p
end
function PC:markOnStop(kind)
 local s=self.subState
 return 6-((kind-s.markScroll)%8)
end

-- the dial's turn (touch_dial.c)
local function angleOf(cx,cy,x,y) return math.deg(math.atan2(y-cy,x-cx))%360 end
function PC:dialCentre()
 local s=self.subState
 return s.dial==PC.DIAL_MARKS and 255 or 0,192
end
function PC.dialSteps(initial,current,direction)
 local change=current-initial
 local sign=change<0 and -1 or 1
 change=math.abs(change)
 local i=0
 if change>=4.219 then i=1 end
 if change>=33.75 then i=2 end
 return i*sign*direction
end
function PC:inRing(x,y)
 local cx,cy=self:dialCentre()
 local d=(x-cx)^2+(y-cy)^2
 return d<PC.RING.outer^2 and d>=PC.RING.inner^2
end
function PC:dialScroll(delta)
 local s=self.subState
 if s.dial==PC.DIAL_BOX then
  s.offset=(s.offset+delta)%Boxes.count()
 else
  s.markScroll=(s.markScroll+delta)%8
 end
 s.names=false
 s.scroll={k=0,delta=delta,frames=6*math.abs(delta)}
end
function PC:dialEnd()
 local s=self.subState
 s.drag=nil
 if s.dial==PC.DIAL_BOX then
  s.jumpWait=((self.game.save.currentBox or 1)-1~=s.offset) and 0 or nil
 end
end
function PC:dialMove(x,y)
 local s=self.subState
 local d=s.drag
 if not d then return end
 if not (x and self:inRing(x,y)) then return self:dialEnd() end
 if s.scroll then return end
 local cx,cy=self:dialCentre()
 local amount=PC.dialSteps(d.angle,angleOf(cx,cy,x,y),cx<128 and 1 or -1)
 if amount~=d.amount then
  local delta=amount-d.amount
  d.amount=amount
  self:dialScroll(delta)
 end
end

-- compare mode's two slots (CompareModeHelper)
function PC:compareState()
 if not self.compare then self.compare={slot=0,mode=0,mons={},has={}} end
 return self.compare
end
-- what a slot shows: the cursor's Pokemon in the active slot, the one it was
-- last set to in the other
function PC:compareMon(slot)
 local c=self:compareState()
 if slot==c.slot then return (self:previewMon()) end
 return c.has[slot] and c.mons[slot] or nil
end
-- BOX_MENU_SET_ON_LEFT / RIGHT and the corner buttons: the active slot keeps
-- the cursor's Pokemon and the other slot becomes the active one
function PC:toggleCompareSlot()
 local c=self:compareState()
 local mon=self:previewMon()
 if not mon then return false end
 c.mons[c.slot]=mon;c.has[c.slot]=true
 c.setPress={slot=c.slot,t=0}
 c.slot=1-c.slot
 return true
end
function PC:nextCompareMode()
 local c=self:compareState()
 c.mode=(c.mode+1)%3
end

function PC:bottomTouch(x,y)
 if self:compareMode() then
  local c=self:compareState()
  for i,b in ipairs(PC.BUTTON) do
   if (x-b[1])^2+(y-b[2])^2<PC.BUTTON_R^2 then
    if c.slot==i-1 and self:previewMon() and not self.menu and not self.held then self:toggleCompareSlot() end
    return true
   end
  end
  local cb=PC.COMPARE_BUTTON
  if (x-cb[1])^2+(y-cb[2])^2<cb[3]^2 then c.pressed=true;self:nextCompareMode() end
  return true
 end
 local s=self:sub()
 if s.task or self.jump or self.menu or self:busy() then return true end
 local function button()
  for i,b in ipairs(PC.BUTTON) do
   if (x-b[1])^2+(y-b[2])^2<PC.BUTTON_R^2 then return i end
  end
 end
 local b=button()
 if s.dial==PC.DIAL_NONE then
  if b==1 then self:setDial(PC.DIAL_BOX)
  elseif b==2 then
   -- MOVE ITEMS has no markings dial (SEQ_SE_DP_BOX03)
   if self.opts.mode~='items' then self:setDial(PC.DIAL_MARKS) end
  end
  return true
 end
 if s.items or s.scroll then return true end
 if s.dial==PC.DIAL_BOX and b==2 then
  if self.opts.mode~='items' then self:setDial(PC.DIAL_MARKS) end
  return true
 end
 if s.dial==PC.DIAL_MARKS and b==1 then self:setDial(PC.DIAL_BOX);return true end
 if s.dial==PC.DIAL_MARKS then
  for i,p in ipairs(PC.MARK_BUTTONS) do
   if (x-p[1])^2+(y-p[2])^2<PC.MARK_R^2 then
    self:toggleMarkFilter((s.markScroll+i-1)%8)
    return true
   end
  end
 end
 if self:inRing(x,y) then
  local cx,cy=self:dialCentre()
  s.drag={angle=angleOf(cx,cy,x,y),amount=0}
  s.jumpWait=nil
 end
 return true
end

-- the 512-wide layer seen through a 256 window at scroll x
local function drawWrapped(self,img,scroll,alpha)
 if not img then return end
 local g=love.graphics
 local w,h=img:getDimensions()
 self.wrapQuads=self.wrapQuads or {}
 local x0=scroll%w   -- BG scroll: screen x shows map x + scroll
 g.setColor(1,1,1,alpha or 1)
 local done=0
 while done<256 do
  local sx=(x0+done)%w
  local n=math.min(256-done,w-sx)
  local key=tostring(img)..sx..':'..n
  if not self.wrapQuads[key] then self.wrapQuads[key]=g.newQuad(sx,0,n,math.min(h,192),w,h) end
  g.draw(img,self.wrapQuads[key],done,0)
  done=done+n
 end
 g.setColor(1,1,1,1)
end
function PC:subSprite(key,x,y,flip,alpha)
 local img,rec=self:art(key)
 if not img then return false end
 local ox,oy=rec.originX or -img:getWidth()/2,rec.originY or -img:getHeight()/2
 love.graphics.setColor(1,1,1,alpha or 1)
 if flip then love.graphics.draw(img,math.floor(x-ox),math.floor(y+oy),0,-1,1)
 else love.graphics.draw(img,math.floor(x+ox),math.floor(y+oy)) end
 love.graphics.setColor(1,1,1,1)
 return true
end
function PC:drawSubBox(n,x,y,ink)
 -- ov19_021DBBA8's thumbnail of box n (0-based), as the jump popup draws it
 local g=love.graphics
 if not self:sprite('jump_thumb',x,y) then return end
 local x0,y0=x-16,y-16
 local p=self:wallpaperOf(n+1);if p>=24 then p=p-8 end
 local c=(ink.jumpPaper or {})[p]
 if c then g.setColor(c[1]/255,c[2]/255,c[3]/255,1);g.rectangle('fill',x0+9,y0+10,14,12) end
 local box=Boxes.ensure(self.game.save)[n+1] or {}
 for slot=1,30 do
  local mon=box[slot]
  if mon then
   local colour
   if mon.egg or mon.isEgg then colour=(mon.species==490) and 1 or 8
   else
    local def=self.game.data.pokemon and self.game.data.pokemon[mon.species]
    colour=tonumber(def and def.bodyColor) or 0
   end
   local bc=(ink.jumpBody or {})[colour]
   if bc then
    g.setColor(bc[1]/255,bc[2]/255,bc[3]/255,1)
    g.rectangle('fill',x0+10+((slot-1)%6)*2,y0+11+math.floor((slot-1)/6)*2,2,2)
   end
  end
 end
 g.setColor(1,1,1,1)
end
function PC:drawBottom()
 local g=love.graphics
 local ink=self:ink()
 if self:compareMode() then return self:drawCompareBottom(ink) end
 local s=self:sub()
 local bd=ink.subBackdrop or {82,148,214}
 g.setColor(bd[1]/255,bd[2]/255,bd[3]/255,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 local bg=self:art('sub_bg')
 if bg then g.draw(bg,0,0) end
 -- OBJ priority 3: the corner buttons, under every BG but SUB_3
 for i=1,2 do
  local b=s.buttons[i]
  local cell=seqCell(b.seq,b.t,false)
  self:subSprite('sub_button_'..cell,i==1 and 0 or 256,184,i==2)
 end
 if s.blend>0 and s.cover~=0 then drawWrapped(self,self:art('sub_cover'),s.cover,s.blend/16) end
 -- OBJ priority 2: the dial's items
 if s.dial==PC.DIAL_BOX and not s.task then
  for b=0,Boxes.count()-1 do
   local p=self:boxOnStop(b)
   if p>=-2 and p<=9 then
    local stop=self:itemStop(p)
    if stop and (stop>0 and stop<7 or (s.items and stop>=0 and stop<=7)) then
     local x,y=PC.arcPoint(stop)
     self:drawSubBox(b,x,y,ink)
    end
   end
  end
 elseif s.dial==PC.DIAL_MARKS and not s.task then
  for kind=0,7 do
   local stop=self:itemStop(self:markOnStop(kind))
   if stop and (stop>0 and stop<7 or (s.items and stop>=0 and stop<=7)) then
    local x,y=PC.arcPoint(stop)
    self:subSprite('sub_mark_'..(kind*2+(self:markLit(kind) and 1 or 0)),256-x,y)
   end
  end
 end
 drawWrapped(self,self:art('sub_dials'),s.sub1,1)
 -- SUB_0: the six box names along the arc
 if s.dial==PC.DIAL_BOX and s.names then
  local pair=ink.subName or {{255,255,255},{90,90,107}}
  local count=Boxes.count()
  Font.pushStyle({text=rgb(pair[1]),shadow=rgb(pair[2])})
  g.setColor(1,1,1,14/16)
  for i,r in ipairs(PC.NAME_RECTS) do
   local n=(s.offset+3-(i-1))%count
   Font.draw(Font.fit(self:boxNameOf(n+1),100),r[1]+4,r[2]+2)
  end
  g.setColor(1,1,1,1)
  Font.popStyle()
 end
end

-- ov19_021DEC04's three pages
function PC:compareValues(mon)
 local stats=mon.stats or {}
 local data=self.game.data
 local nature=mon.nature
 if type(nature)~='string' and mon.personality then
  nature=((data.constants or {}).natureOrder or {})[mon.personality%25+1]
 end
 return nature,{mon.level or 1,tonumber(mon.maxHp) or tonumber(stats.hp) or 0,
  stats.attack or stats.atk or 0,stats.defense or stats.def or 0,
  stats.spAttack or stats.spatk or 0,stats.spDefense or stats.spdef or 0,stats.speed or stats.spe or 0}
end
function PC:drawCompareBottom(ink)
 local g=love.graphics
 local c=self:compareState()
 local bd=ink.cmpBackdrop or {173,222,247}
 g.setColor(bd[1]/255,bd[2]/255,bd[3]/255,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 local page=({[0]='cmp_battle','cmp_contest','cmp_moves'})[c.mode]
 local bg=self:art(page)
 if bg then g.draw(bg,0,0) end
 local pairs2={[0]=ink.cmpLeft or {{255,255,255},{90,90,107}},ink.cmpRight or {{255,255,255},{90,90,107}}}
 local function centred(text,tx,tw,y,slot)
  if not text or text=='' then return end
  text=Font.fit(tostring(text),tw*8)
  say(text,tx*8+math.floor((tw*8-Font.width(text))/2),y,pairs2[slot])
 end
 local function word(n,fallback) return self:word(PC.MESSAGE_BANK,n,fallback) end
 -- the column labels (13, 4) 6 x 16
 if c.mode==0 then
  local keys={'nature','level','hp','attack','defense','spAttack','spDefense','speed'}
  local fall={'NATURE','Lv.','HP','ATTACK','DEFENSE','SP. ATK','SP. DEF','SPEED'}
  for i,k in ipairs(keys) do centred(word(PC.COMPARE_TEXT[k],fall[i]),13,6,32+16*(i-1),0) end
 elseif c.mode==2 then
  centred(word(PC.COMPARE_TEXT.move,'MOVE'),13,6,32,0)
 end
 for slot=0,1 do
  local mon=self:compareMon(slot)
  local nx=slot==0 and 3 or 20
  if mon then
   local egg=mon.egg or mon.isEgg
   centred(egg and (mon.nickname or 'EGG') or self:nameOf(mon),nx,9,8,slot)
   local q=word(PC.COMPARE_TEXT.unknown,'???')
   if c.mode==0 then
    if egg then for i=0,7 do centred(q,nx,9,32+16*i,slot) end
    else
     local nature,values=self:compareValues(mon)
     centred(nature,nx,9,32,slot)
     for i,v in ipairs(values) do centred(tostring(math.floor(v)),nx,9,32+16*i,slot) end
    end
   elseif c.mode==2 then
    local mx=slot==0 and 1 or 20
    for i=1,4 do
     if egg then centred(q,mx,11,32+4+24*(i-1),slot)
     else
      local m=(mon.moves or {})[i]
      local id=(type(m)=='table' and (m.id or m.move)) or m
      local rec=id and id~=0 and (self.game.data.moves or {})[id]
      if id and id~=0 then centred(rec and rec.name or tostring(id),mx,11,32+4+24*(i-1),slot) end
     end
    end
   end
  end
 end
 -- the contest pentagon's dots: (centre + 10% of the way) + stat / 256 of the rest
 if c.mode==1 then
  local keys={'cool','beauty','cute','smart','tough'}
  for _,slot in ipairs({1-c.slot,c.slot}) do
   local mon=self:compareMon(slot)
   if mon and not (mon.egg or mon.isEgg) then
    local con=mon.contest or {}
    for i,k in ipairs(keys) do
     local t=PC.COMPARE_DOTS[i]
     local bx=PC.COMPARE_CENTRE[1]+(t[1]-PC.COMPARE_CENTRE[1])*0.1
     local by=PC.COMPARE_CENTRE[2]+(t[2]-PC.COMPARE_CENTRE[2])*0.1
     local v=math.max(0,math.min(255,tonumber(con[k]) or 0))
     self:subSprite('cmp_dot_'..slot,bx+(t[1]-bx)*v/256,by+(t[2]-by)*v/256)
    end
   end
  end
 end
 -- the slot buttons: the active one up, the other set (cell 2, after the
 -- press 1 x 8 / 2 x 16 when it was just set)
 for slot=0,1 do
  local cell=0
  if slot~=c.slot and c.has[slot] then
   cell=2
   if c.setPress and c.setPress.slot==slot and (c.setPress.t or 0)<8 then cell=1 end
  end
  self:subSprite((slot==0 and 'cmp_left_' or 'cmp_right_')..cell,slot==0 and 0 or 256,184,slot==1)
 end
 -- the mode toggle: 5 / 3 alternating, 5 / 4 while held (ov19_021DF930)
 local t=math.floor((self.t or 0)*60)
 local held=c.pressed
 local cell=(t%8<4) and 5 or (held and 4 or 3)
 self:subSprite('cmp_toggle_'..cell,128,176)
 -- the two Pokemon icons at (112, 10) and (144, 10)
 for slot=0,1 do
  local mon=self:compareMon(slot)
  if mon then self:drawIcon(mon,slot==0 and 112 or 144,10) end
 end
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
 local ability=require("src.pokemon.AbilityOf").pick(mon,def and def.abilities)
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

-- BG3 as the ring keeps it: each visible column is one of a slot's 23
-- (paper_NN, one 8-pixel column of it) or the 0x18 fill in slot 0's palette,
-- at the ring's scroll plus the slide's; a wallpaper fading out washes its
-- slot to white.  False with no `paper_NN` in the cache (an older one).
function PC:drawBG3()
 local g=love.graphics
 local b=self:bg3State()
 local first=b.slots[0] or b.slots[1]
 if not (first and self:art(('paper_%02d'):format(first.paper))) then return false end
 local bgShift=self:slideShift()
 local scroll=(b.scroll+(self.slide and bgShift or 0))%512
 self.paperQuads=self.paperQuads or {}
 for sx=0,256,8 do
  local ringX=(sx+scroll)%512
  local c=math.floor(ringX/8)
  local x=sx-(ringX%8)
  local col=b.cols[c]
  local img,qx,slot
  if col then
   slot=b.slots[col.slot]
   img=slot and self:art(('paper_%02d'):format(slot.paper));qx=col.x*8
  end
  if not img then
   slot=b.slots[0] or first
   img=self:art(('paper_fill_%02d'):format(slot.paper));qx=0
   col={slot=0}
  end
  if img then
   local w,h=img:getDimensions()
   local key=tostring(w)..':'..qx
   if not self.paperQuads[key] then self.paperQuads[key]=g.newQuad(qx,0,8,192,w,h) end
   g.setColor(1,1,1,1)
   g.draw(img,self.paperQuads[key],x,0)
   local white=self:paperWhite(col.slot)
   if white>0 then g.setColor(1,1,1,white);g.rectangle('fill',x,0,8,192);g.setColor(1,1,1,1) end
  end
 end
 return true
end

-- the popup over BG1 and its OBJ thumbnails (see PC.JUMP_*)
function PC:drawJump(ink)
 local g=love.graphics
 local j=self.jump
 local band=self:art('jump_band')
 local rows=self:jumpBandRows()
 if band and rows>0 then
  local w,h=band:getDimensions()
  g.setColor(1,1,1,1)
  -- the band's top `rows` rows above tile row 10, its bottom `rows` below
  g.draw(band,g.newQuad(0,0,256,rows*8,w,h),0,80-rows*8)
  g.draw(band,g.newQuad(0,80-rows*8,256,rows*8,w,h),0,80)
 end
 local fade=self:jumpFade()
 if not fade then return end
 local count=Boxes.count()
 local boxes=Boxes.ensure(self.game.save)
 local paperInk=ink.jumpPaper or {}
 local bodyInk=ink.jumpBody or {}
 for i=0,6 do
  local n=(j.box-1+i-3)%count+1
  local cx,cy=32+i*32,88
  if self:sprite('jump_thumb',cx,cy) then
   local x0,y0=cx-16,cy-16
   -- ov19_021DBBA8: the inside in the wallpaper's colour, a 2 x 2 dot per
   -- Pokemon in its body colour
   local p=self:wallpaperOf(n);if p>=24 then p=p-8 end
   local c=paperInk[p]
   if c then g.setColor(c[1]/255,c[2]/255,c[3]/255,1);g.rectangle('fill',x0+9,y0+10,14,12) end
   local box=boxes[n] or {}
   for slot=1,30 do
    local mon=box[slot]
    if mon then
     local colour
     if mon.egg or mon.isEgg then colour=(mon.species==490) and 1 or 8
     else
      local def=self.game.data.pokemon and self.game.data.pokemon[mon.species]
      colour=tonumber(def and def.bodyColor) or 0
     end
     local bc=bodyInk[colour]
     if bc then
      g.setColor(bc[1]/255,bc[2]/255,bc[3]/255,1)
      g.rectangle('fill',x0+10+((slot-1)%6)*2,y0+11+math.floor((slot-1)/6)*2,2,2)
     end
    end
   end
   if fade>0 then g.setColor(1,1,1,fade);g.rectangle('fill',x0,y0,32,32) end
   g.setColor(1,1,1,1)
  end
 end
 if fade>0 then return end
 -- the name window (10, 6) 12 x 2 on colour 7, and the counts (3, 13) 26 x 1 on 4
 local plate=ink.jumpPlate or {247,132,132}
 g.setColor(plate[1]/255,plate[2]/255,plate[3]/255,1);g.rectangle('fill',80,48,96,16)
 local name=self:boxNameOf(j.box)
 say(name,80+48-math.floor(Font.width(name)/2),48,ink.jumpName or {{255,255,255},{214,90,90}})
 local paper=ink.jumpCount or {230,165,90}
 g.setColor(paper[1]/255,paper[2]/255,paper[3]/255,1);g.rectangle('fill',24,104,208,8)
 g.setColor(1,1,1,1)
 for i=0,6 do
  local n=(j.box-1+i-3)%count+1
  local box=boxes[n] or {}
  local k=0
  for slot=1,30 do if box[slot] then k=k+1 end end
  self:number('special_jump',k,2,true,24+32*i,104)
 end
end

function PC:draw()
 local g=love.graphics
 local ink=self:ink()
 local bd=ink.backdrop or FALLBACK_INK.backdrop
 g.setColor(bd[1]/255,bd[2]/255,bd[3]/255,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 local paperId=self:wallpaperId()
 local fresh=self:drawBG3()
 if not fresh then
  local paper=self:img(('storage/wallpaper_%02d'):format(paperId));if paper then g.draw(paper,88,0) end
 end
 -- the box name, in the wallpaper's own colours 2 (letter) and 1 (shadow),
 -- and the thirty icons -- during a slide the old box's and the new one's,
 -- the new one 184 along in the direction of travel
 local bgShift,iconShift=self:slideShift()
 local s=self.slide
 local function boxLayer(n,dx,iconDx)
  local p=self:wallpaperOf(n)
  local pair=(ink.wallpaper or {})[p] or {{99,99,99},{255,255,255}}
  local name=Font.fit(self:boxNameOf(n),144)
  say(name,172-Font.width(name)/2+dx,13,pair)
  local box=Boxes.ensure(self.game.save)[n] or {}
  for slot=1,30 do
   local m=box[slot]
   self:drawIcon(m,112+(slot-1)%6*24+iconDx,40+math.floor((slot-1)/6)*24,self:iconFaded(m) and PC.XLU or 1)
  end
 end
 local cur=self.game.save.currentBox or 1
 if s then
  boxLayer(s.oldBox,-bgShift,iconShift)
  boxLayer(cur,184*s.dir-bgShift,184*s.dir+iconShift)
 else
  boxLayer(cur,0,0)
 end
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
   local m=self.game.save.party[i]
   self:drawIcon(m,p[1],p[2],self:iconFaded(m) and PC.XLU or 1)
  end
 end
 -- MOVE ITEMS (ov19_021DE3E8): the previewed Pokemon's item at half size
 -- (sequence 6) on its slot + (10, 8)
 if self.opts.mode=='items' and not self.held and not self.menu then
  local m=self:previewMon()
  local item=m and (m.heldItem or m.item)
  if item and item~=0 then
   local x,y
   if self.partyOpen then
    local p=PC.PARTY_SLOTS[self.partyIndex]
    if p then x,y=p[1]+10,p[2]+8 end
   elseif self.row>=1 and self.row<=5 then
    x,y=112+(self.col-1)*24+10,40+(self.row-1)*24+8
   end
   if x then self:drawItemIcon(item,x,y,0.5) end
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
 if self.jump then self:drawJump(ink) end
 if self.message and self.message~='' then
  Font.drawDialogueBox(1,20,29,4)
  local y=168
  for line in (self.message..'\n'):gmatch('([^\n]*)\n') do
   say(Font.fit(line,216),16,y,ink.message);y=y+16
   if y>184 then break end
  end
 end
 self:drawSubscreen()
end
-- the bottom screen through SecondScreen, when one is shown
function PC:drawSubscreen()
 local shown,SS=self:bottomShown()
 if not shown then return end
 SS.draw(self.game,function() self:drawBottom() end)
end
-- Gen3BoxMenu's icon, with the XLU of a filtered-out Pokemon
local ICON_PERIOD=0.32
function PC:drawIcon(mon,cx,cy,alpha)
 local img,frameH=self:iconFor(mon)
 if not img then return end
 local iw,ih=img:getDimensions()
 frameH=math.min(frameH or ih,ih)
 local frames=math.max(1,math.floor(ih/frameH))
 local frame=frames>1 and (math.floor(((self.t or 0)%(ICON_PERIOD*frames))/ICON_PERIOD)%frames) or 0
 self.quads=self.quads or {}
 local key=('%d:%d:%d'):format(iw,frameH,frame)
 if not self.quads[key] then self.quads[key]=love.graphics.newQuad(0,frame*frameH,iw,frameH,iw,ih) end
 love.graphics.setColor(1,1,1,alpha or 1)
 love.graphics.draw(img,self.quads[key],math.floor(cx-iw/2),math.floor(cy-frameH/2))
 love.graphics.setColor(1,1,1,1)
end
-- an item icon (gen4_graphics items/icon_NNN) centred at (x, y), scaled
function PC:drawItemIcon(item,x,y,scale)
 local def=self.game.data.items and self.game.data.items[item]
 local id=tonumber(def and def.id) or tonumber(item)
 local img=id and self:img(('items/icon_%03d'):format(id))
 if not img then return false end
 scale=scale or 1
 local w,h=img:getDimensions()
 love.graphics.setColor(1,1,1,1)
 love.graphics.draw(img,math.floor(x-w*scale/2),math.floor(y-h*scale/2),0,scale,scale)
 return true
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
function PC:touchpressed(id,px,py)
 -- the bottom screen first, when it is shown (SecondScreen.toLocal); a tap
 -- from the panel that misses it is still not a tap on the boxes
 local bx,by=self:bottomPoint(px,py)
 if bx then
  self.subPointer={id=id}
  return self:bottomTouch(bx,by)
 end
 if self.game.secondScreenInjecting then return true end
 if self.jump or self:busy() then return true end
 local s=self.subState
 if s and (s.task or s.dial~=PC.DIAL_NONE) then return true end
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
function PC:touchmoved(id,px,py)
 if not (self.subPointer and self.subPointer.id==id) then return false end
 local s=self.subState
 if s and s.drag then self:dialMove(self:bottomPoint(px,py)) end
 return true
end
function PC:touchreleased(id)
 if not (self.subPointer and self.subPointer.id==id) then return false end
 self.subPointer=nil
 local s=self.subState
 if s and s.drag then self:dialEnd() end
 if self.compare then self.compare.pressed=nil end
 return true
end
return PC
