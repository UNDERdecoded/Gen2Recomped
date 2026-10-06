-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's POKEDEX, which was the last screen on the reported fault list
-- still falling back to Kanto's: "neither is the pokedex, or the pokemon party
-- menu or the bag theyre looking like gen1 still".  The party menu and the bag
-- were fixed by the module list; this one was not, and was deliberately left
-- alone afterwards, because THE ART COMPOSED BLANK and a Gen 4 Pokedex drawn
-- on it would have been a black screen where Kanto's at least showed something.
--
-- The composition is fixed now -- see `Gen4Dex`, and `Gen4Graphics.stamp` for
-- the thing the planner could not express -- so this is the screen.
--
-- Native entry/list/search companion art and ROM-backed search are available;
-- search transitions and habitat/cry/size/form presentations remain incomplete.
--
-- WHAT THE PAGE SAYS IS THE CARTRIDGE'S TOO, including the three things the
-- species table does not carry: Platinum stores height, weight and the
-- category line as pre-formatted STRINGS, one per species, and the `dex` stage
-- now carries all three.  Nothing on this page is computed from a number this
-- port chose how to round.

local Assets = require("src.render.Assets")

-- `NATIONAL_DEX_COUNT (MAX_SPECIES - 2)` from pokeplatinum's
-- `include/constants/species.h`; `MAX_SPECIES` is `SPECIES_BAD_EGG` = 495.
local NATIONAL_DEX_COUNT = 493
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Sprites = require("src.pokemon.Sprites")
local Forms = require("src.pokemon.Gen4Forms")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")
local Search = require('src.ui.Gen4DexSearch')

local Gen4Pokedex = {}
Gen4Pokedex.__index = Gen4Pokedex
Gen4Pokedex.isOpaque = true

local W, H = 256, 192

-- The list page, ov21_021D5AEC.c: nine plates around the selected entry, which
-- is always slot 4.  Slot k shows display index current+k-4.  {x, y, sprite
-- palette row of buttons.NCLR}; drawn far to near.
local LIST_SLOTS = {
  [0] = { 185, 22, 9 }, { 181, 26, 9 }, { 177, 42, 8 }, { 175, 58, 7 },
  { 170, 82, 0 }, { 175, 106, 7 }, { 177, 122, 8 }, { 181, 138, 9 }, { 185, 142, 9 },
}
local LIST_SELECTED = 4
local LIST_DRAW_ORDER = { 0, 8, 1, 7, 2, 6, 3, 5, 4 }
local LIST_PAGE = 5
-- one step's counter runs from 640 down by 60 a frame; held steps speed up
-- by x1.6, at most four times
local LIST_SCROLL, LIST_SCROLL_STEP, LIST_HOLD_GAIN, LIST_HOLD_MAX = 640, 60, 1.6, 4
local LIST_PREVIEW = { x = 56, y = 80 }
local LIST_INK_FALLBACK = {
  [0] = '636363', [7] = '635a6b', [8] = '635a7b', [9] = '5a528c',
}

-- Where the entry page's words go, when the cache has no layout of its own.
-- Every number is `Gen4Dex.LAYOUT`'s; they are repeated here only so a cache
-- imported before the `dex` stage still lands its text somewhere sensible.
local FALLBACK_LAYOUT = {
  sprite = { x = 48, y = 72 },
  nameNumber = { x = 172, y = 32 },
  category = { x = 114, y = 44 },
  heightLabel = { x = 152, y = 88 },
  heightValue = { x = 184, y = 88 },
  weightLabel = { x = 152, y = 104 },
  weightValue = { x = 184, y = 104 },
  entry = { centre = 128, y = 136, maxWidth = 240, overflowX = 8 },
  footprint = { x = 96, y = 64, size = 48 },
}

-- The sprite's position is the CENTRE on hardware -- `PokemonSprite` is an
-- OAM object and its x/y are its middle -- so an 80x80 picture drawn from its
-- top-left has to be offset by half of itself.
local SPRITE_SIZE = 80

function Gen4Pokedex:uiSize() return W, H end
function Gen4Pokedex:wantsFillScale() return true end
function Gen4Pokedex:wantsEdgeBleed() return false end

function Gen4Pokedex:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4Pokedex.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4Pokedex)
  self.game = game
  self.onCancel = opts.onCancel
  self.cache = {}
  self.art = (game.data or {}).gen4_dex or nil
  if not self.art then
    Logger.warn("gen4 pokedex: this cache carries no `gen4_dex` record -- the "
                .. "entry page is drawn in the engine's own frame")
  end

  self.national = ((game.save or {}).pokedex or {}).national and true or false
  self.entries = self:listing()
  self.index = 1
  self.top = 1
  self.tab = 1
  self.page = "list"
  self.scroll = 0
  self.form = 0
  return self
end

-- ------------------------------------------------------------------ data --

-- Prefer the ROM's Sinnoh order until the National Dex is granted. Old
-- caches without the ordered lists retain their previous national fallback.
function Gen4Pokedex:listing()
  local data = self.game.data or {}
  local mons = data.pokemon or {}
  local out = {}
  local orders=self.art and self.art.orders
  local order=orders and orders[self.national and 'national' or 'sinnoh']
  if order then
    self.numbers={}
    for number,id in ipairs(order) do
      if mons[id] then out[#out+1]=id;self.numbers[id]=number end
    end
    return self:trimListing(out)
  end
  -- `x or 493` CANNOT CATCH A ZERO, and the zero is what arrives.
  --
  -- `Data.lua` derives `dexSize` as the highest `def.dex` across the species
  -- table.  A GEN 4 CACHE CARRIES NO `dex` FIELD AT ALL -- measured, 0 of
  -- 508 species have one, which is the same fact the comment above this
  -- function states from the other side: Platinum numbers its species in
  -- national order, so there is nothing separate to read.  So `highest`
  -- stays 0 and `dexSize` is written as 0.
  --
  -- In Lua only `nil` and `false` are falsy, so `0 or 493` is 0, the loop
  -- `for id = 1, 0` runs no times, and `entries` is EMPTY.  The screen then
  -- draws a correct listing of nothing and refuses to open any entry page,
  -- because `status(species())` is asked about a nil species.  Measured:
  -- `index=1 species=nil` on every tick with the whole dex marked seen.
  --
  -- 493 is the cartridge's own number, not a guess: `species.h` has
  -- `NATIONAL_DEX_COUNT (MAX_SPECIES - 2)` with `MAX_SPECIES SPECIES_BAD_EGG`
  -- = 495, and Arceus -- the last species with a dex number -- is 493.  The
  -- cache's ids run to 507 because the 14 rows above 493 are alternate
  -- FORMS, which is why the highest id is the wrong upper bound here.
  local size = tonumber((data.constants or {}).dexSize)
  if not size or size < 1 then size = NATIONAL_DEX_COUNT end
  for id = 1, size do
    if mons[id] then out[#out + 1] = id end
  end
  return self:trimListing(out)
end

-- PopulateDisplayPokedex_Blanks keeps gaps before the last encountered entry,
-- but does not append the rest of the unseen regional/national list.
function Gen4Pokedex:trimListing(entries)
  local last = 0
  for i,id in ipairs(entries) do if self:status(id) then last = i end end
  for i = #entries, last + 1, -1 do entries[i] = nil end
  return entries
end

function Gen4Pokedex:species()
  return self.entries[self.index]
end

function Gen4Pokedex:def(species)
  return (self.game.data.pokemon or {})[species or self:species()]
end

-- Seen and caught, from the save the rest of the engine already keeps.
function Gen4Pokedex:status(species)
  if species == nil then return nil end
  local dex = (self.game.save or {}).pokedex or {}
  local id = Forms.species(species)
  local function known(t)
    t = t or {}
    return t[species] or (id and (t[id] or t['SPECIES_'..id]))
  end
  local owned = known(dex.owned)
  if owned then return "owned" end
  if known(dex.seen) then return "seen" end
  return nil
end

-- ---------------------------------------------------------------- pictures --

function Gen4Pokedex:img(entry)
  local path = (type(entry) == "table" and entry.path) or entry
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4Pokedex:layout()
  return (self.art and self.art.layout) or FALLBACK_LAYOUT
end

-- ------------------------------------------------------------------ input --

function Gen4Pokedex:stopCry()
  if self.cry and self.cry.stop then self.cry:stop() end
  self.cry=nil
  self.cryRunning=false;self.cryPointer=nil
  self.cryCooldown=nil
end

function Gen4Pokedex:close()
  self.wheelPointer=nil
  if self.wheelCanvas and self.wheelCanvas.release then self.wheelCanvas:release() end
  self.wheelCanvas=nil
  self:stopCry()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4Pokedex:move(delta)
  local count = #self.entries
  if count == 0 then return end
  self:stopCry()
  self.form=0
  local index = (self.index - 1 + delta) % count + 1
  if self.page == 'entry' then
    -- Entry pages navigate the native caught-status array, which omits blanks.
    local step = delta < 0 and -1 or 1
    for _ = 1, count do
      if self:status(self.entries[index]) then break end
      index = (index - 1 + step) % count + 1
    end
  end
  local before = self.index
  self.index = index
  if not self:tabAvailable(self.tab) then self.tab = 1 end
  if self.page == 'list' and index ~= before then
    -- a one-entry step slides the plates; anything else only fades the
    -- preview back in
    local change = index - before
    self.listAnim = { counter = LIST_SCROLL, dir = (change == 1 or change == -1) and change or 0, speed = 1 }
  end
end

-- One list step from the pad; `key` is remembered so a held key repeats.
function Gen4Pokedex:listStep(delta, key, repeats)
  local count = #self.entries
  if count == 0 then return end
  self:move(delta)
  if self.listAnim then
    self.listAnim.key = key
    self.listAnim.repeats = repeats or 0
    self.listAnim.speed = LIST_HOLD_GAIN ^ math.min(repeats or 0, LIST_HOLD_MAX)
  end
end

function Gen4Pokedex:updateListAnim(frames)
  local a = self.listAnim
  if not a then return end
  a.counter = a.counter - LIST_SCROLL_STEP * a.speed * frames
  if a.counter > 0 then return end
  self.listAnim = nil
  local input = self.game.input
  if a.key and a.dir ~= 0 and input and input.isDown and input:isDown(a.key) then
    local target = self.index + a.dir
    -- a held key stops at the ends rather than wrapping
    if target >= 1 and target <= #self.entries then
      self:listStep(a.dir, a.key, (a.repeats or 0) + 1)
    end
  end
end

-- Native entry buttons gate size comparisons on capture and form comparison
-- on the Pokédex form-detection upgrade (ov21_021E29DC.c).
function Gen4Pokedex:tabAvailable(tab)
  if tab == 4 then return self:status(self:species()) == 'owned' end
  if tab == 5 then return ((self.game.save or {}).pokedex or {}).canDetectForms == true end
  return tab >= 1 and tab <= 3
end

function Gen4Pokedex:cycleTab(step)
  local tab = self.tab
  for _ = 1, 5 do
    tab = (tab - 1 + step) % 5 + 1
    if self:tabAvailable(tab) then self:setTab(tab); return end
  end
end

function Gen4Pokedex:setTab(tab)
  if not self:tabAvailable(tab) then return false end
  if tab~=self.tab then self:stopCry();self.scroll=0 end
  self.tab=tab
  return true
end

function Gen4Pokedex:bottomVisible()
  if SecondScreen.stowed(self.game) then return false end
  return SecondScreen.mode(self.game)~='swap' or SecondScreen.raised(self.game)
end

function Gen4Pokedex:backToList()
  self.searchPointer,self.searchPressed=nil,nil
  self:stopCry();self.wheelPointer=nil;self.page,self.scroll='list',0
end

function Gen4Pokedex:openEntry()
  if not self:status(self:species()) then return false end
  self.wheelPointer=nil;self.page='entry';self.tab=1;self.form=0;self:playCry()
  return true
end

function Gen4Pokedex:openSearch()
  if self.filtered then return false end
  self:stopCry();self.wheelPointer=nil
  self.searchSelection=Search.defaults();self.searchField=1;self.searchError=nil;self.page='search'
  self.searchTypePage,self.searchTypeSlot,self.searchCursor=0,3,nil
  self.searchPointer,self.searchPressed=nil,nil
end

function Gen4Pokedex:changeSearch(delta)
  local field=self.searchField
  self.searchSelection[field]=(self.searchSelection[field]-1+delta)%#Search.CHOICES[field]+1
  if field==3 or field==4 then
    local other=field==3 and 4 or 3
    if self.searchSelection[field]~=1 and self.searchSelection[field]==self.searchSelection[other] then
      self.searchSelection[field]=(self.searchSelection[field]-1+delta)%#Search.CHOICES[field]+1
    end
  end
  self.searchError=nil
end

function Gen4Pokedex:applySearch()
  local entries,why=Search.results(self,self.searchSelection)
  if not entries or #entries==0 then
    self.searchError=why=='missing data' and 'REIMPORT ROM FOR SEARCH DATA' or 'NONE FOUND'
    return false
  end
  self:stopCry();self.entries=entries;self.filtered=true
  self.page='list';self.index,self.top,self.scroll=1,1,0
  return true
end

function Gen4Pokedex:cancelResults()
  if not self.filtered then self:close();return end
  local species=self:species()
  self.filtered=nil;self.entries=self:listing();self.index,self.top=1,1
  for i,id in ipairs(self.entries) do if id==species then self.index=i;break end end
  self.listAnim=nil
end

function Gen4Pokedex:toggleDex()
  local dex=(self.game.save or {}).pokedex or {}
  local orders=self.art and self.art.orders
  if not dex.national or not (orders and orders.sinnoh and orders.national) then return false end
  if self.filtered then return false end
  self:stopCry()
  self.national=not self.national
  self.entries=self:listing()
  self.index,self.top,self.scroll,self.form=1,1,0,0
  return true
end

function Gen4Pokedex:update(dt)
  local frames=(type(dt)=='number' and dt>0) and math.min(dt*60,4) or 1
  if self.page=='list' then self:updateListAnim(frames) else self.listAnim=nil end
  if self.page=='entry' and self.tab==3 and self.cryRunning and self.cry and self.cry.isPlaying then
    local ok,playing=pcall(self.cry.isPlaying,self.cry)
    if ok and not playing then
      if self.cryLoop then
        self.cryCooldown=(self.cryCooldown or 10)-1
        if self.cryCooldown<=0 then self:playCry() end
      else self.cryRunning=false end
    end
  end
  local input = self.game.input
  if not input then return end

  if self.page=='search' then
    local buttons=Search.buttons(self)
    self.searchCursor=self.searchCursor or 7
    for _,dir in ipairs({'up','down','left','right'}) do
      if input:wasPressed(dir) then self.searchCursor=Search.navigate(buttons,self.searchCursor,dir);return end
    end
    if input:wasPressed('a') then Search.activate(self,buttons[self.searchCursor])
    elseif input:wasPressed('start') then self:applySearch()
    elseif input:wasPressed('b') then self:backToList() end
    return
  end

  if self.page == "entry" then
    if input:wasPressed("l") then self:cycleTab(-1)
    elseif input:wasPressed("r") or input:wasPressed("select") then self:cycleTab(1)
    elseif input:wasPressed("up") then self.scroll = math.max(0, self.scroll - 1)
    elseif input:wasPressed("down") then self.scroll = self.scroll + 1
    elseif input:wasPressed("left") then self:move(-1); self.scroll = 0
    elseif input:wasPressed("right") then self:move(1); self.scroll = 0
    elseif input:wasPressed("a") then
      if self.tab == 3 then self:pressCryPlay()
      elseif self.tab == 1 then self:playCry()
      elseif self.tab == 4 then self.sizeWeight=not self.sizeWeight
      elseif self.tab == 5 then self.form = ((self.form or 0) + 1) % #self:forms() end
    elseif input:wasPressed("b") or input:wasPressed("start") then self:backToList() end
    return
  end

  if input:wasPressed("up") then self:listStep(-1,'up')
  elseif input:wasPressed("down") then self:listStep(1,'down')
  elseif input:wasPressed("left") then self:listStep(-LIST_PAGE)
  elseif input:wasPressed("right") then self:listStep(LIST_PAGE)
  elseif input:wasPressed("select") then self:toggleDex()
  elseif input:wasPressed("x") then if not self.filtered then self:openSearch() end
  elseif input:wasPressed("a") then
    -- ONLY A SEEN SPECIES HAS A PAGE.  The cartridge draws the entry for an
    -- unseen one as an empty frame rather than refusing to open it, but it
    -- also never lets the cursor rest on one that is not in the listing; this
    -- port lists everything, so the refusal is here instead of a page with
    -- nothing on it.
    self:openEntry()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:cancelResults()
  end
end

function Gen4Pokedex:touchpressed(id,px,py)
  if self:bottomVisible() then
    local x,y=SecondScreen.toLocal(self.game,px,py)
    if x then
      if self.page=='list' then return self:listTouch(id,x,y) end
      if self.page=='search' then
        if self.searchPointer then return true end
        self.searchPointer=id
        return self:searchTouch(x,y)
      end
      if y>=8 and y<40 then
        for i=1,6 do
          if math.abs(x-(28+(i-1)*40))<20 then
            if i==6 then self:backToList() else self:setTab(i) end
            return true
          end
        end
      end
      if self.tab==3 then
        if self.cryPointer then return true end
        if x>=156 and x<204 and y>=107 and y<155 then self:pressCryPlay();self.cryPointer=id
        elseif x>=214 and x<246 and y>=150 and y<182 then self.cryLoop=not self.cryLoop;self.cryPointer=id end
      elseif self.tab==4 and y>=128 then self.sizeWeight=not self.sizeWeight
      elseif self.tab==5 and y>=128 then self.form=((self.form or 0)+1)%#self:forms() end
      return true
    end
    -- A secondary-panel event must never be reinterpreted as a top-screen tap.
    return false
  end
  local r=require('src.render.Renderer').uiPresentation
  if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
  local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
  if self.page=='search' then return self:searchTouch(x,y,false)
  elseif self.page=='entry' then
    if y >= 176 then
      local tab = math.min(5, math.floor(x / (W / 5)) + 1)
      self:setTab(tab)
    elseif self.tab == 5 and y >= 128 then self.form = ((self.form or 0) + 1) % #self:forms()
    elseif self.tab == 4 and y >= 128 then self.sizeWeight=not self.sizeWeight
    elseif self.tab == 3 or x < 96 then self:playCry() end
  elseif math.abs(x-LIST_PREVIEW.x)<32 and math.abs(y-LIST_PREVIEW.y)<32 then
    -- the preview is the selected entry
    self:openEntry()
  elseif self:listPlateAt(x,y) then
    local slot=self:listPlateAt(x,y)
    if slot==LIST_SELECTED then self:openEntry() else self:move(slot-LIST_SELECTED) end
  elseif y>=160 then
    if x<64 then self:move(-LIST_PAGE)
    elseif x>=192 then self:move(LIST_PAGE)
    elseif x<128 then self:openSearch()
    else self:cancelResults() end
  end
  return true
end

function Gen4Pokedex:searchTouch(x,y,companion)
  if companion~=false then
    for i,b in ipairs(Search.buttons(self)) do
      if x>=b.x-b.w/2 and x<b.x+b.w/2 and y>=b.y-b.h/2 and y<b.y+b.h/2 then
        self.searchCursor=i;self.searchPressed=b;Search.activate(self,b);return true
      end
    end
    return true
  end
  if y>=176 then
    if x<128 then self:backToList() else self:applySearch() end
  elseif y>=48 then
    self.searchField=y<72 and 1 or y<96 and 2 or y<114 and 3 or y<136 and 4 or 5
    self:changeSearch(x<128 and -1 or 1)
  end
  return true
end

-- Native lower hitboxes (ov21_021D76B0): wheel center 248,104, r104.
function Gen4Pokedex:listTouch(id,x,y)
  if self.wheelPointer then return true end
  if x<96 and y>=16 then
    if y<64 then if not self.filtered then self:openSearch() end
    elseif y<112 then self:toggleDex()
    else self:openEntry() end
  elseif x>=116 and x<180 and y<16 then self:cancelResults()
  elseif x>=116 and x<132 and y>=56 and y<72 then
    for i,species in ipairs(self.entries) do if self:status(species) then self:move(i-self.index);break end end
  elseif x>=116 and x<132 and y>=138 and y<154 then self:move(#self.entries-self.index)
  elseif (x-248)^2+(y-104)^2<104^2 then
    self.wheelPointer=id;self.wheelAngle=math.atan2(y-104,x-248);self.wheelRemainder=0
  end
  return true
end

function Gen4Pokedex:touchmoved(id,px,py)
  if self.page=='search' and id==self.searchPointer then return true end
  if id~=self.wheelPointer or self.page~='list' then return false end
  local x,y=SecondScreen.toLocal(self.game,px,py)
  if not x then return true end
  if (x-248)^2+(y-104)^2<64 then return true end
  local angle=math.atan2(y-104,x-248)
  local delta=(angle-self.wheelAngle+math.pi)%(2*math.pi)-math.pi
  self.wheelAngle=angle;self.wheelRotation=(self.wheelRotation or 0)+delta
  self.wheelRemainder=self.wheelRemainder+delta
  local step=math.rad(25)
  local steps=self.wheelRemainder>0 and math.floor(self.wheelRemainder/step) or math.ceil(self.wheelRemainder/step)
  if steps~=0 then
    -- Clockwise native arc advances toward the beginning, without wrapping.
    local target=math.max(1,math.min(#self.entries,self.index-steps))
    self:move(target-self.index);self.wheelRemainder=self.wheelRemainder-steps*step
  end
  return true
end

function Gen4Pokedex:touchreleased(id)
  if id==self.cryPointer then self.cryPointer=nil;return true end
  if id==self.searchPointer then self.searchPointer,self.searchPressed=nil,nil;return true end
  if id~=self.wheelPointer then return false end
  self.wheelPointer=nil;self.wheelRemainder=0
  return true
end

-- ------------------------------------------------------------------- draw --

-- The list's own pictures: a fresh import files them with the rest of the dex
-- art in `gen4_graphics.screens`; tools/gen4_dex_art_extract adds them to an
-- older cache's `gen4_dex.listArt` instead.
function Gen4Pokedex:listArt(key)
  local record=((self.game.data.gen4_graphics or {}).screens or {})[key]
  if not record then record=((self.art or {}).listArt or {})[key] end
  local image=record and self:img(record)
  return image,record
end

-- Draws a sprite picture at its OAM position (picture origin = cell extent).
function Gen4Pokedex:drawListSprite(key,x,y,alpha)
  local image,record=self:listArt(key)
  if not image then return false end
  love.graphics.setColor(1,1,1,alpha or 1)
  love.graphics.draw(image,x+(record.originX or -math.floor(image:getWidth()/2)),
    y+(record.originY or -math.floor(image:getHeight()/2)))
  return true
end

local function hexColour(hex)
  hex=tostring(hex or '000000')
  return { (tonumber(hex:sub(1,2),16) or 0)/255, (tonumber(hex:sub(3,4),16) or 0)/255,
    (tonumber(hex:sub(5,6),16) or 0)/255, 1 }
end

local function drawInk(text,x,y,ink,shadow)
  local two=Font.beginTwoTone and Font.beginTwoTone(hexColour(ink),hexColour(shadow))
  Font.draw(text,x,y)
  if two then Font.endTwoTone() end
end

-- Where each slot is this frame: its table position, or on the way there
-- from its neighbour's while a step is sliding.
function Gen4Pokedex:listSlotPosition(k)
  local slot=LIST_SLOTS[k]
  local a=self.listAnim
  if not (a and a.dir~=0 and a.counter>0) then return slot[1],slot[2],slot[3] end
  local t=(LIST_SCROLL-a.counter)/LIST_SCROLL
  local from=LIST_SLOTS[k+a.dir]
  local fx,fy,frow
  if from then fx,fy,frow=from[1],from[2],from[3]
  else
    local other=LIST_SLOTS[k-a.dir]
    fx,fy,frow=2*slot[1]-other[1],2*slot[2]-other[2],slot[3]
  end
  local x=math.floor(fx+(slot[1]-fx)*t+0.5)
  local y=math.floor(fy+(slot[2]-fy)*t+0.5)
  return x,y,(t<0.5 and frow or slot[3])
end

-- The plate under a top-screen point, nearest first.
function Gen4Pokedex:listPlateAt(px,py)
  for i=#LIST_DRAW_ORDER,1,-1 do
    local k=LIST_DRAW_ORDER[i]
    if self.entries[self.index+k-LIST_SELECTED] then
      local x,y=LIST_SLOTS[k][1],LIST_SLOTS[k][2]
      local _,record=self:listArt('dex/list_plate_r'..LIST_SLOTS[k][3])
      local ox,oy=record and record.originX or -64,record and record.originY or -16
      local w,h=record and record.width or 128,record and record.height or 32
      if px>=x+ox and px<x+ox+w and py>=y+oy and py<y+oy+h then return k end
    end
  end
  return nil
end

-- The number a plate shows: the Sinnoh or National number per mode for a
-- known entry (bank entry 100 "---" when it has none), the list position for
-- a never-seen gap.
function Gen4Pokedex:listNumber(at,id)
  if not self:status(id) then return ('%03d'):format(at) end
  local n
  if self.numbers then n=self.numbers[id] else n=id end
  if not n then return Search.label(self,100,'---') end
  return ('%03d'):format(n)
end

function Gen4Pokedex:drawList()
  local g = love.graphics
  local art = self.art or {}
  local ink = art.listInk or {}
  g.setColor(1, 1, 1, 1)

  -- BG3
  local main = self:listArt('dex/list_main')
  if main then g.draw(main, 0, 0)
  else
    g.setColor(0.08, 0.14, 0.24, 1);g.rectangle("fill", 0, 0, W, H);g.setColor(1, 1, 1, 1)
  end

  -- the preview, fading in after a step
  local a = self.listAnim
  local alpha = a and math.max(0, math.min(1, (LIST_SCROLL - a.counter) / LIST_SCROLL)) or 1
  local species = self:species()
  if species then
    local drawn = false
    if self:status(species) then
      local path = Sprites.path(self.game.data, species, "front", { kind = "dex", mon = self:displayMon() })
      local image = path and self:img(path)
      if image then
        local iw, ih = image:getDimensions()
        g.setColor(1, 1, 1, alpha)
        g.draw(image, LIST_PREVIEW.x - SPRITE_SIZE / 2, LIST_PREVIEW.y - SPRITE_SIZE / 2, 0, SPRITE_SIZE / iw, SPRITE_SIZE / ih)
        drawn = true
      end
    else
      drawn = self:drawListSprite('dex/list_unseen', LIST_PREVIEW.x, LIST_PREVIEW.y, alpha)
    end
    if not drawn and not self:status(species) then Font.draw('?', LIST_PREVIEW.x - 4, LIST_PREVIEW.y - 8) end
  end

  -- the plates, far to near
  for _, k in ipairs(LIST_DRAW_ORDER) do
    local at = self.index + k - LIST_SELECTED
    local id = self.entries[at]
    if id then
      local x, y, row = self:listSlotPosition(k)
      self:drawListSprite('dex/list_plate_r'..row, x, y)
      local state = self:status(id)
      if state == 'owned' then self:drawListSprite('dex/list_ball_r'..row, x - 54, y) end
      local name
      if state then
        local def = self:def(id)
        name = def and def.name or tostring(id)
      else
        name = Search.label(self, 99, '-----')
      end
      local rowInk = (ink.rows or {})[row] or {}
      local inkHex = rowInk.ink or LIST_INK_FALLBACK[row]
      local shadowHex = rowInk.shadow or inkHex
      local bx, by = x - 64, y - 8
      drawInk(self:listNumber(at, id), bx + 22, by, inkHex, shadowHex)
      drawInk(Font.fit(tostring(name), 78), bx + 49, by, inkHex, shadowHex)
    end
  end

  -- the scroll thumb
  local count = #self.entries
  if count > 0 then
    self:drawListSprite('dex/list_thumb', 248, 58 + math.floor((self.index - 1) * 54 / count))
  end

  -- BG2, the header and footer bars
  local mode = self.national and 'national' or 'sinnoh'
  local frame = self:listArt('dex/list_frame_'..mode..(self.filtered and '_filtered' or ''))
    or self:listArt('dex/list_frame_'..mode)
  g.setColor(1, 1, 1, 1)
  if frame then g.draw(frame, 0, 0) end

  -- BG1, the counters
  local counterInk = (self.filtered and ink.counterFiltered or ink.counter) or {}
  local cInk = counterInk.ink or 'ffffff'
  local cShadow = counterInk.shadow or (self.filtered and '000000' or '101921')
  if self.filtered then
    drawInk(Search.label(self, 109, 'RESULTS'), 8, 152, cInk, cShadow)
    drawInk(('%03d'):format(count), 48, 170, cInk, cShadow)
  else
    local words = art.words or {}
    local seen, owned = 0, 0
    for _, id in ipairs(self.entries) do
      local state = self:status(id)
      if state then seen = seen + 1 end
      if state == "owned" then owned = owned + 1 end
    end
    drawInk(Search.label(self, 0, words.seen or Strings("SEEN")), 8, 152, cInk, cShadow)
    drawInk(Search.label(self, 1, words.obtained or Strings("OBTAINED")), 128, 152, cInk, cShadow)
    drawInk(('%03d'):format(seen), 48, 170, cInk, cShadow)
    drawInk(('%03d'):format(owned), 180, 170, cInk, cShadow)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4Pokedex:drawEntry()
  local g = love.graphics
  local art = self.art or {}
  local L = self:layout()
  local species = self:species()
  local def = self:def(species)
  local caught = self:status(species) == 'owned'
  local textSpecies = caught and species or 0

  local mode=self.national and 'national' or 'sinnoh'
  local page = self:screenArt('dex/entry_'..mode) or self:img(art.entry)
  if page then
    g.setColor(1, 1, 1, 1)
    g.draw(page, 0, 0)
  else
    g.setColor(0.10, 0.16, 0.26, 1)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end

  -- The Pokemon, centred on the position the app gives its sprite.
  local path = species and Sprites.path(self.game.data, species, "front",
                                        { kind = "dex", mon = self:displayMon() })
  local image = path and self:img(path)
  if image then
    local iw, ih = image:getDimensions()
    g.setColor(1, 1, 1, 1)
    g.draw(image, L.sprite.x - SPRITE_SIZE / 2, L.sprite.y - SPRITE_SIZE / 2,
           0, SPRITE_SIZE / iw, SPRITE_SIZE / ih)
  end

  local words = art.words or {}
  local categoryBox = self:screenArt('pokedex/type_icons_17')
  if categoryBox then
    g.setColor(1,1,1,1)
    -- Cell 17's OAM extent is (-86,-36), not half of its 160x52 crop.
    g.draw(categoryBox,192,52,0,1,1,86,36)
  end
  local heading=Font.fit(("%03d  %s"):format((self.numbers and self.numbers[species]) or species or 0,(def and def.name) or "?"),136)
  Font.draw(heading,L.nameNumber.x-math.floor(Font.width(heading)/2),L.nameNumber.y)

  local category = (art.category or {})[textSpecies]
  if category then
    Font.draw(category, L.category.x + math.max(0, math.floor((136 - Font.width(category))/2)), L.category.y)
  end

  Font.draw(words.height or "HT", L.heightLabel.x, L.heightLabel.y)
  Font.draw((art.height or {})[textSpecies] or "???",
            L.heightValue.x, L.heightValue.y)
  Font.draw(words.weight or "WT", L.weightLabel.x, L.weightLabel.y)
  Font.draw((art.weight or {})[textSpecies] or "???",
            L.weightValue.x, L.weightValue.y)

  -- The entry text.  The cartridge centres it on x = 128 and drops to x = 8
  -- when it is wider than 240 -- its own overflow rule, kept rather than
  -- replaced by a clamp.
  local entry = caught and ((def and def.dexEntry) or "") or (art.unknownEntry or "")
  local lines = {}
  for line in (tostring(entry) .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  local maxLines = 3
  local width = 0
  for _,line in ipairs(lines) do width = math.max(width, Font.width(line)) end
  local textX = (width < L.entry.maxWidth)
    and (L.entry.centre - math.floor(width / 2)) or L.entry.overflowX
  if self.scroll > math.max(0, #lines - maxLines) then
    self.scroll = math.max(0, #lines - maxLines)
  end
  for i = 1, maxLines do
    local line = lines[self.scroll + i]
    if line then
      Font.draw(line, textX, L.entry.y + (i - 1) * 10)
    end
  end

  -- The banner, on its own layer over the page, exactly as the app draws it.
  local banner = self:screenArt('dex/banner_'..mode) or self:img(art.banner)
  if banner then
    g.setColor(1, 1, 1, 1)
    g.draw(banner, 0, 0)
  end
  g.setColor(1, 1, 1, 1)
end

local TABS = { 'INFO', 'AREA', 'CRY', 'SIZE', 'FORMS' }
function Gen4Pokedex:playCry()
  self:stopCry()
  if not self:status(self:species()) then return end
  self.cry = require('src.core.Sound').playCry(self.game.data, self:species(),{isolated=true})
  self.cryRunning=self.cry~=nil
end
function Gen4Pokedex:pressCryPlay()
  if self.cryLoop and self.cryRunning then self:stopCry() else self:playCry() end
end
function Gen4Pokedex:displayMon()
  -- InfoMain uses PokedexSort_DefaultForm: the first form encountered, even
  -- when that was an alternate form rather than form zero.
  return { species = self:species(), form = Forms.seen(self.game.save.pokedex, self:species())[1] or 0 }
end
function Gen4Pokedex:forms()
  local species = self:species()
  local out = {}
  local forms=(self:def() or {}).forms or {}
  for _,name in ipairs(Forms.seen(self.game.save.pokedex,species)) do
    local record=forms[name]
    if record and (record.spriteFront or record.front) then out[#out+1]=name end
  end
  -- Existing saves may have species knowledge but no per-form encounter history.
  if #out==0 then out[1]=false end
  return out
end
function Gen4Pokedex:areas()
  local out, seen = {}, {}
  local species = self:species()
  local function contains(t)
    if type(t) ~= 'table' then return false end
    for _,v in pairs(t) do
      if type(v) == 'table' and (v.species == species or contains(v)) then return true end
    end
    return false
  end
  for id,map in pairs(self.game.data.maps or {}) do
    local area = (self.game.data.encounters or {})[map.encounters]
    local found = area and (tonumber(area.grassRate) or 0) > 0 and contains(area.grass)
    if area then
      for _, method in ipairs({'surf','oldRod','goodRod','superRod'}) do
        local block = area[method]
        if block and (tonumber(block.rate) or 0) > 0 and contains(block.slots) then found = true end
      end
      if (tonumber(area.grassRate) or 0) > 0 then
        for _, method in ipairs({'day','night','swarm','radar'}) do
          for _, id in ipairs(area[method] or {}) do if id == species then found = true end end
        end
        for _, slots in pairs(area.dualSlot or {}) do
          for _, id in ipairs(slots) do if id == species then found = true end end
        end
      end
    end
    if found then
      local label = map.label or id
      if not seen[label] then seen[label]=true;out[#out+1]=label end
    end
  end
  table.sort(out);return out
end
function Gen4Pokedex:screenArt(key)
  local screens = ((self.game.data.gen4_graphics or {}).screens or {})
  return self:img(screens[key])
end
function Gen4Pokedex:drawDetails()
  if self.tab == 1 then
    self:drawEntry()
    if self:status(self:species()) ~= 'owned' then return end
    local mon = self:displayMon()
    local id = self:species()
    if id == 487 and Forms.personalIndex(id, mon.form) ~= id then id = 11 end
    local footprint = self:screenArt(('dex/footprint_%03d'):format(id))
    if footprint then
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(footprint, 120, 88, 0, 1, 1, footprint:getWidth()/2, footprint:getHeight()/2)
    end
    local types = (Forms.definition(self.game.data, mon) or {}).types or {}
    for i = 1, 2 do
      if types[i] and (i == 1 or types[2] ~= types[1]) then self:drawType(types[i], i == 1 and 170 or 220, 72) end
    end
    return
  end
  local g=love.graphics
  g.setColor(0.85,0.9,0.95,1);g.rectangle('fill',0,0,W,H);g.setColor(1,1,1,1)
  local key = self.tab==2 and 'pokedex/area_map' or self.tab==3 and 'pokedex/cry_button'
    or self.tab==4 and (self.sizeWeight and 'pokedex/weight_check_main' or 'pokedex/height_check_main') or 'pokedex/forms_sub'
  local bg=self:screenArt(key);if bg then g.draw(bg,0,0) end
  local def=self:def();Font.draw((def and def.name) or '?',8,8)
  if self.tab==2 then
    local locations=self:areas()
    self.scroll=math.min(self.scroll,math.max(0,#locations-8))
    if #locations==0 then Font.draw('AREA UNKNOWN',48,80) end
    for i=1,8 do if locations[self.scroll+i] then Font.draw(Font.fit(locations[self.scroll+i],232),12,28+(i-1)*17) end end
  elseif self.tab==3 then
    Font.draw('A: PLAY CRY',72,144)
    local bar=self:screenArt('pokedex/cry_bar_00');if bar then g.draw(bar,112-bar:getWidth()/2,88-bar:getHeight()/2) end
  elseif self.tab==4 then
    if self:status(self:species())=='owned' then
      Font.draw('HEIGHT '..(((self.art or {}).height or {})[self:species()] or '?'),24,120)
      Font.draw('WEIGHT '..(((self.art or {}).weight or {})[self:species()] or '?'),24,144)
    end
  elseif self.tab==5 then
    local forms=self:forms();local form=forms[(self.form or 0)%#forms+1]
    local record=form and def.forms[form]
    local path=record and (record.spriteFront or record.front) or Sprites.path(self.game.data,self:species(),'front',{kind='dex'})
    local image=path and self:img(path)
    if image then g.draw(image,88,48,0,80/image:getWidth(),80/image:getHeight()) end
    Font.draw('A: NEXT FORM',64,144)
  end
end
local TYPE_ANIM = { NORMAL=0, FIRE=1, GRASS=2, WATER=3, ELECTRIC=4,
  ROCK=5, FIGHTING=6, GHOST=7, MYSTERY=7, GROUND=8, STEEL=9, POISON=10,
  BUG=11, DARK=12, ICE=13, FLYING=14, PSYCHIC=15, DRAGON=16 }
function Gen4Pokedex:drawType(name, x, y)
  local sequence = TYPE_ANIM[tostring(name):upper()]
  if sequence == nil then return end
  local image = self:screenArt(('pokedex/type_icons_%02d'):format(sequence))
  if image then
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,x,y,0,1,1,image:getWidth()/2,image:getHeight()/2)
  end
end
function Gen4Pokedex:drawTabs()
  local g=love.graphics
  for i,label in ipairs(TABS) do
    local available = self:tabAvailable(i)
    g.setColor(available and (i==self.tab and 0.7 or 0.9) or 0.5,0.8,0.85,1)
    g.rectangle('fill',(i-1)*W/5,176,W/5,16);g.setColor(1,1,1,1)
    if i ~= 5 or available then Font.draw(label,(i-1)*W/5+4,178) end
  end
end
function Gen4Pokedex:draw()
  self.game.secondScreenDrawnThisFrame=true
  if self.page=='search' then
    self:drawSearch(false)
    if self:bottomVisible() then SecondScreen.draw(self.game,function() self:drawSearch(true) end) end
    return
  end
  if self.page == "entry" then
    self:drawDetails()
    if self:bottomVisible() then
      SecondScreen.draw(self.game,function() self:drawBottom() end)
    else self:drawTabs() end
    return
  end
  self:drawList()
  if self:bottomVisible() then SecondScreen.draw(self.game,function() self:drawListBottom() end)
  -- between the two counts, which sit at x 48 and 180 on that line
  elseif not self.filtered then Font.draw('X: SEARCH',96,170) end
end

function Gen4Pokedex:drawNativeSprite(key,x,y)
  local record=((self.game.data.gen4_graphics or {}).screens or {})[key]
  local image=self:screenArt(key)
  if not image then return false end
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(image,x+(record and record.originX or -image:getWidth()/2),y+(record and record.originY or -image:getHeight()/2))
  return true
end

function Gen4Pokedex:drawListBottom()
  local g=love.graphics
  g.setColor(0.85,0.9,0.95,1);g.rectangle('fill',0,0,W,H);g.setColor(1,1,1,1)
  local mode=self.filtered and 'filtered' or (self.national and 'national' or 'sinnoh')
  -- Compose the rotating affine layer into its own bounded canvas so an inset
  -- cannot spill wheel pixels onto the main screen.
  local wheel=self:screenArt('dex/list_wheel')
  if wheel then
    if not self.wheelCanvas then self.wheelCanvas=g.newCanvas(W,H,{dpiscale=1});self.wheelCanvas:setFilter('nearest','nearest') end
    local previous=g.getCanvas();g.push('all');g.setCanvas(self.wheelCanvas);g.origin();g.setScissor();g.clear(0,0,0,0)
    g.draw(wheel,248,104,self.wheelRotation or 0,1,1,128,104)
    g.setCanvas(previous);g.pop();g.draw(self.wheelCanvas,0,0)
  end
  local bg=self:screenArt('dex/list_panel_'..mode);if bg then g.draw(bg,0,0) end
  local words=(self.art or {}).words or {}
  local buttons={{2,48,40,words.search or 'SEARCH'},{0,48,88,words.switch or 'SWITCH'},{1,48,152,'CHECK'},
    {3,124,64},{4,124,146},{5,124,8,self.filtered and 'CANCEL' or 'QUIT'}}
  for i,b in ipairs(buttons) do
    local visible=i~=1 or not self.filtered
    if i==2 then visible=not self.filtered and ((self.game.save or {}).pokedex or {}).national end
    if visible then
      self:drawNativeSprite(('dex/list_button_%02d'):format(b[1]),b[2],b[3])
      if b[4] then Font.draw(b[4],b[2]+(i==6 and 10 or -40),b[3]-(i==6 and 8 or 14)) end
    end
  end
end

function Gen4Pokedex:drawSearch(companion)
  local g=love.graphics
  g.setColor(0.85,0.9,0.95,1);g.rectangle('fill',0,0,W,H);g.setColor(1,1,1,1)
  local field=self.searchField
  if companion then self:drawSearchBottom();return end
  if not companion then
    local key=({'order','name','type','type','form'})[field]
    local bg=self:screenArt('dex/search_'..key);if bg then g.draw(bg,0,0) end
    local message=self.searchError
    if message=='NONE FOUND' then message=Search.label(self,93,message) end
    message=message or Search.label(self,({90,87,88,88,89})[field],'SEARCH POKEMON')
    local lines={};for line in (message..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
    for i,line in ipairs(lines) do
      line=Font.fit(line,208)
      Font.draw(line,24+math.floor((208-Font.width(line))/2),8+math.floor((32-#lines*16)/2)+(i-1)*16)
    end
  end
  for i=1,5 do
    local value=Search.CHOICES[i][self.searchSelection[i]]
    if i==1 then value=Search.ORDER_LABELS[self.searchSelection[i]] end
    if i==1 then value=Search.label(self,80+self.searchSelection[i],value)
    elseif i==2 and self.searchSelection[i]>1 then value=Search.label(self,52+self.searchSelection[i],value)
    elseif (i==3 or i==4) and self.searchSelection[i]>1 then value=Search.label(self,Search.TYPE_LABEL_IDS[self.searchSelection[i]],value) end
    if value=='none' then value='----' end
    local y=({52,77,102,120,164})[i]
    if i==5 and self.searchSelection[5]>1 then
      self:drawNativeSprite(('dex/search_shape_%02d'):format(self.searchSelection[5]-1),128,164)
    elseif i~=5 then Font.draw(value,88+math.max(0,math.floor((80-Font.width(value))/2)),y) end
  end
  if not self:bottomVisible() then
    Font.draw('CANCEL',8,176);Font.draw('SEARCH',184,176)
  end
end

function Gen4Pokedex:drawSearchBottom()
  local g=love.graphics
  local bg=self:screenArt('dex/search_panel');if bg then g.draw(bg,0,0) end
  for i,b in ipairs(Search.buttons(self)) do
    local pressed=self.searchPressed
    local held=pressed and pressed.action==b.action and pressed.value==b.value
    local frame=held and 2 or b.selected and 3 or 0
    local key=('dex/search_buttons_%02d_%02d'):format(b.sequence,frame)
    if not self:drawNativeSprite(key,b.x,b.y) then
      g.setColor(b.selected and 1 or 0.85,0.9,0.65,1);g.rectangle('fill',b.x-b.w/2,b.y-16,b.w,32);g.setColor(1,1,1,1)
    end
    if b.icon~=nil then self:drawNativeSprite(('dex/search_button_forms_%02d_%02d'):format(b.icon,frame),b.x,b.y)
    elseif b.label then Font.draw(b.label,b.x-math.floor(Font.width(b.label)/2),b.y-6-(frame==2 and 4 or frame==3 and 2 or 0)) end
    if self.searchCursor==i then
      g.setColor(0.2,0.25,0.35,1);g.rectangle('line',b.x-b.w/2+2,b.y-14,b.w-4,28);g.setColor(1,1,1,1)
    end
  end
end

function Gen4Pokedex:drawBottom()
  local g=love.graphics
  g.setColor(0.85,0.9,0.95,1);g.rectangle('fill',0,0,W,H);g.setColor(1,1,1,1)
  local mode=self.national and 'national' or 'sinnoh'
  local bg=self:screenArt('dex/panel_'..mode)
  if bg then g.draw(bg,0,0) end
  if self.tab==3 then
    local wheel=self:screenArt('dex/cry_wheel');if wheel then g.draw(wheel,0,0) end
    local panel=self:screenArt('dex/cry_panel');if panel then g.draw(panel,0,0) end
    self:drawNativeSprite('dex/cry_control_04',64,67)
    self:drawNativeSprite('dex/cry_control_01',51,157)
    self:drawNativeSprite(self.cryRunning and 'dex/cry_control_02' or 'dex/cry_control_03',180,131)
    self:drawNativeSprite(self.cryLoop and 'dex/cry_control_05' or 'dex/cry_control_06',230,166)
    local text=Search.label(self,41,'CHORUS');Font.draw(text,64-math.floor(Font.width(text)/2),84)
  end
  for i=1,6 do
    if i~=5 or self:tabAvailable(5) then
      local key=('dex/page_button_%02d'):format(i-1)
      local record=((self.game.data.gen4_graphics or {}).screens or {})[key]
      local image=self:screenArt(key) or self:screenArt(('pokedex/page_buttons_%02d'):format(i-1))
      local x=28+(i-1)*40
      if image then
        g.draw(image,x+(record and record.originX or -image:getWidth()/2),24+(record and record.originY or -image:getHeight()/2))
      else Font.draw(i==6 and 'BACK' or TABS[i],x-16,20) end
    end
  end
end

return Gen4Pokedex
