-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's SUMMARY PAGES (src/applications/pokemon_summary_screen/).
--
-- THE WORDS ARE ALL BANK 455's, and finding that bank is the part worth
-- recording: "To Next Lv." occurs exactly once in all 1,127 message banks, and
-- around it sit the six page titles, every field label, the twenty-five nature
-- lines and the twenty-five characteristic lines.  Two other banks looked like
-- this one -- 326 and 336 both carry "Exp. Points", "Nature" and "Item" -- and
-- both are DEBUG menus.  Three common words in common is not an
-- identification; a phrase that occurs once is.
--
-- THE SCREEN IS LAYERED THE WAY THE CARTRIDGE LAYERS IT (main.c SetupBgs):
--
--   BG3 (priority 3)  the page tilemap, `summary/page_<name>` from
--                     gen4_graphics, plus the HP / EXP bar tiles main.c writes
--                     into it at run time (summary_art hp_* / exp_bar)
--   OBJ priority 3    status, Pokerus, markings, shiny, tab arrows, sheen,
--                     ribbons -- drawn UNDER everything below
--   BG0 (priority 2)  3D: the Pokemon's picture and the condition graph
--   BG2 (priority 1)  move_info.NSCR, 512 x 512, scrolled to (0,0) for the
--                     battle move panel, (0,256) for the contest one and
--                     (256,56) for the ribbon panel -- the cartridge's own
--                     art for all three; nothing here is a filled rectangle
--   BG1 (priority 0)  the text windows (window.c's templates), printed in
--                     tiles_main.NCLR row 15: labels white 15/14, values
--                     black 1/2, gender / OT blue 3/4 and red 5/6
--   OBJ priority 0    tabs, caught ball, type and category icons, move
--                     cursor, A button, the species icon
--
-- Every sprite is drawn at the cartridge's position plus its cell's origin
-- (src/import/Gen4SummaryArt.lua), in the palette row its template names.
--
-- THE POKEMON'S PICTURE is drawn from `PICTURE` below.  The screen had declared
-- a slot for it since it was written and never drawn into it, so every summary
-- page in Sinnoh was a page of numbers with an empty plate beside them.
--
-- THE TOUCH SCREEN (subscreen.c) is a button per page, eight around the rings
-- or five before the Contest Hall (the contest pages are hidden until
-- FLAG_CONTEST_HALL_VISITED, as TryHideContestPages does), each with the
-- cartridge's own rectangle.  A tap presses it (anim 2) with the tap circle
-- on it, sets up its page, and holds the pad off until the stylus lets go;
-- the button then stays lit (anim 1) until the pad changes page.  Touches
-- reach it through SecondScreen.toLocal, the same door the Poketch uses.
--
-- THE CONDITION GRAPH GROWS out of its centre over four frames and then
-- lights the condition flashes on the highest stat (3d_anim.c).

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

-- window.c's templates, in pixels: { labelX, labelY, valueX, valueY, valueW, align }
local INFO_WINDOWS = {
  {112,40,192,40,48}, {112,56,184,56,64}, {112,72,184,72,64},
  {112,88,184,88,64}, {112,104,200,104,32},
  {112,120,192,136,48}, {112,152,192,168,48},
}
-- SKILLS: HP at (18,4) over (23,4) w7; the five stats at (16, 7..15) over
-- (25, 7..15) w3, right-aligned
local SKILL_WINDOWS = {
  {144,32,184,32,56,'centre'}, {128,56,200,56,24,'right'},
  {128,72,200,72,24,'right'}, {128,88,200,88,24,'right'},
  {128,104,200,104,24,'right'}, {128,120,200,120,24,'right'},
}
Gen4SummaryMenu.INFO_WINDOWS = INFO_WINDOWS
Gen4SummaryMenu.SKILL_WINDOWS = SKILL_WINDOWS

-- sprites.c's positions
Gen4SummaryMenu.POS = {
  tabsCentre = 188, tabY = 24, focusedTab = 24, tab = 16,
  arrowLeft = -12, arrowRight = -4,
  infoType1 = { 199, 80 }, infoType2 = { 233, 80 }, infoTypeSolo = { 216, 80 },
  movesType1 = { 63, 52 }, movesType2 = { 97, 52 },
  moveType = { 151, 42 }, category = { 108, 72 },
  moveCursor = { 194, 48 }, pitch = 32,
  battleIcon = { 24, 48 }, contestIcon = { 32, 68 },
  ball = { 16, 32 }, status = { 80, 52 }, pokerus = { 76, 48 },
  shiny = { 98, 72 }, cured = { 98, 132 },
  markings = { 48, 150 }, sheen = { 152, 168 },
  ribbon = { 132, 56 }, ribbonStep = { 32, 40 },
  ribbonUp = { 180, 32 }, ribbonDown = { 180, 120 },
  hpBar = { 192, 48 }, expBar = { 184, 184 },
}
local POS = Gen4SummaryMenu.POS

-- main.c's BG2 scroll for each panel
Gen4SummaryMenu.PANEL = { moves = { 0, 0 }, contestMoves = { 0, 256 }, ribbons = { 256, 56 } }

-- bank 455 entries the windows print (window.c PrintStaticWindows et al.)
local B = {
  item = 4, none = 6, info = 7, unknown = 22, memo = 23, skills = 109,
  condition = 126, sheen = 127, battleMoves = 128, battleInfo = 129,
  pp = 135, cancel = 146, power = 147, accuracy = 148, category = 149,
  switch = 152, twoDashes = 153, threeDashes = 154, ok = 155,
  hmForget = 156, contestMoves = 157, contestInfo = 158, appeal = 160,
  promptExit = 161, closeWindow = 162, ribbons = 179, ribbonInfo = 180,
  ribbonCancel = 181, ribbonCount = 182, slash = 117, male = 1, female = 2,
}
Gen4SummaryMenu.BANK = B

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

-- the condition graph (3d_anim.c sConditionRectBounds): four quads, each
-- vertex { stat, minX, minY, maxX, maxY, stepX, stepY } in fx16, drawn in
-- GX_RGB(8, 31, 15) at polygon alpha 20/31 and one polygon id, so where they
-- overlap the DS draws them once -- their union, not a sum
local Q = {
  { {'cool',5138,735,5138,3784,0,12}, {'beauty',5538,383,8344,965,11,2},
    {'cute',5380,-106,7079,-2955,7,-11}, {nil,5138,300,5138,300,0,0} },
  { {'tough',4645,383,1843,965,-11,2}, {'cool',5045,735,5045,3784,0,12},
    {nil,5045,300,5045,300,0,0}, {'smart',4803,-106,3106,-2955,-7,-11} },
  { {'tough',4645,383,1843,965,-11,2}, {nil,5045,300,5045,300,0,0},
    {'cute',5299,-106,7079,-2955,7,-11}, {'smart',4803,-106,3106,-2955,-7,-11} },
  { {nil,5138,300,5138,300,0,0}, {'beauty',5538,383,8344,965,11,2},
    {'cute',5380,-106,7079,-2955,7,-11}, {'smart',4884,-106,3106,-2955,-7,-11} },
}
Gen4SummaryMenu.CONDITION_QUADS = Q
Gen4SummaryMenu.CONDITION_COLOUR = { 8 / 31, 1, 15 / 31, 20 / 31 }

function Gen4SummaryMenu:uiSize() return W, H end
function Gen4SummaryMenu:wantsFillScale() return true end
function Gen4SummaryMenu:wantsEdgeBleed() return false end

function Gen4SummaryMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

local function unit(c, fallback)
  c = type(c) == "table" and c or fallback
  return { c[1] / 255, c[2] / 255, c[3] / 255 }
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
    if arg and arg.showContest ~= nil then self.showContestOverride = arg.showContest end
  end
  self.page = 1
  self.t = 0
  self.cache = {}
  local data = game.data or {}
  self.art = (data.gen4_graphics or {}).screens or {}
  -- the sprites, bars and bottom screen (src/import/Gen4SummaryArt.lua)
  self.summaryArt = data.gen4_summary_art or {}
  local okArt, SummaryArt = pcall(require, "src.import.Gen4SummaryArt")
  local ink = data.gen4_summary_ink
  if type(ink) ~= "table" or not ink.black then ink = okArt and SummaryArt.ink(nil) or {} end
  self.ink = {
    black = { text = unit(ink.black, { 16, 25, 33 }), shadow = unit(ink.blackShadow, { 173, 189, 189 }) },
    white = { text = unit(ink.white, { 255, 255, 255 }), shadow = unit(ink.whiteShadow, { 82, 82, 82 }) },
    blue = { text = unit(ink.blue, { 0, 115, 255 }), shadow = unit(ink.blueShadow, { 123, 189, 239 }) },
    red = { text = unit(ink.red, { 239, 33, 16 }), shadow = unit(ink.redShadow, { 255, 173, 189 }) },
  }
  local record = (data.gen4_menus or {}).summary
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
  for _,page in ipairs(pages) do self.pages[#self.pages+1]=page end
  local function addPage(key,art,title)
    for _,page in ipairs(self.pages) do if page.key==key then return end end
    self.pages[#self.pages+1]={key=key,art=art,title=title}
  end
  addPage('memo','summary/page_memo',self:b455(B.memo,Strings('TRAINER MEMO')))
  addPage('condition','summary/page_condition',self:b455(B.condition,Strings('CONDITION')))
  addPage('contestMoves','summary/page_contest_moves',self:b455(B.contestMoves,Strings('CONTEST MOVES')))
  addPage('ribbons','summary/page_ribbons',self:b455(B.ribbons,Strings('RIBBONS')))
  addPage('exit','summary/page_exit',nil)
  -- SUMMARY_PAGE_*: the order the cartridge tabs through them, and the tab
  -- sprite each one is
  local order={info=0,memo=1,skills=2,moves=3,condition=4,contestMoves=5,ribbons=6,exit=7}
  Gen4SummaryMenu.PAGE_ID=order
  table.sort(self.pages,function(a,b) return (order[a.key] or 99)<(order[b.key] or 99) end)
  for _,page in ipairs(self.pages) do
    if page.key=='contestMoves' and not page.title then page.title=self:b455(B.contestMoves,'') end
  end
  self:ensureVisiblePage()
  self.layout = (record and record.layout) or FALLBACK_LAYOUT
  self.natures = (record and record.natures) or {}
  return self
end

-- one string of bank 455, colour codes dropped
function Gen4SummaryMenu:b455(index, fallback)
  local text = ((self.game.data or {}).text or {})[('TEXT_B0455_%05d'):format(index)]
  if type(text) ~= "string" or text == "" then return fallback end
  return (text:gsub("{COLOR %d+}", ""))
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

-- a Gen4SummaryArt picture and its record
function Gen4SummaryMenu:sart(key)
  local rec = self.summaryArt[key]
  return self:image(type(rec) == "table" and rec.path or rec), type(rec) == "table" and rec or {}
end

-- a sprite at the cartridge's position: the cell's origin is added
function Gen4SummaryMenu:sprite(key, x, y, flip)
  local img, rec = self:sart(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  local ox, oy = tonumber(rec.originX) or 0, tonumber(rec.originY) or 0
  if flip then
    love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else
    love.graphics.draw(img, x + ox, y + oy)
  end
  return true
end

function Gen4SummaryMenu:close()
  if self.cry and self.cry.stop then self.cry:stop() end
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- THE CONTEST PAGES WAIT FOR THE CONTEST HALL.  TryHideContestPages (main.c)
-- clears CONDITION, CONTEST MOVES and RIBBONS out of the page flags unless
-- the caller set `showContest`, which every caller fills from
-- PokemonSummaryScreen_ShowContestData = SystemFlag_CheckContestHallVisited:
-- FLAG_CONTEST_HALL_VISITED, system flag 0x978, set by the Hearthome hall's
-- own script and stored here as every Gen 4 flag is, FLAG_G4_%04X.  Before
-- that the summary is five pages, and the touch screen is the five-button
-- layout (`SUB_LAYOUTS.noContest`).  A caller can still force it either way
-- with `showContest` in the options.
Gen4SummaryMenu.CONTEST_HALL_FLAG = "FLAG_G4_0978"
Gen4SummaryMenu.CONTEST_PAGES = { condition = true, contestMoves = true, ribbons = true }

function Gen4SummaryMenu:showContest()
  if self.showContestOverride ~= nil then return self.showContestOverride and true or false end
  local flags = (self.game.save or {}).flags or {}
  return flags[Gen4SummaryMenu.CONTEST_HALL_FLAG] and true or false
end

function Gen4SummaryMenu:visiblePages()
  local pages={}
  local contest=self:showContest()
  for i,page in ipairs(self.pages) do
    if (contest or not Gen4SummaryMenu.CONTEST_PAGES[page.key])
       and (not Party.isEgg(self.mon) or page.key=='memo' or page.key=='exit') then
      pages[#pages+1]=i
    end
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
  -- ChangePage: PokemonSummaryScreen_UpdateSubscreenButtonGfx puts every
  -- touch button back in its resting face before the page changes
  self.subLit=nil
  for at,i in ipairs(pages) do
    if self.page==i then self.page=pages[(at-1+delta)%#pages+1];return end
  end
  self:ensureVisiblePage()
end

function Gen4SummaryMenu:pageKey()
  local page=self.pages[self.page] or self.pages[1]
  return page and page.key or 'info'
end

function Gen4SummaryMenu:update(dt)
  self.t = (self.t or 0) + 1
  self:stepGraph()
  if self.tapT then self.tapT=self.tapT+1 end
  -- SUMMARY_STATE_SUBSCREEN_INPUT: while a touch button is down the pad is
  -- not read at all
  if self.subPress then self:stepSubscreen(); return end
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
  local key=self:pageKey()
  if input:wasPressed("right") then
    self:changePage(1)
  elseif input:wasPressed("left") then
    self:changePage(-1)
  elseif input:wasPressed('up') then
    self:changePokemon(-1)
  elseif input:wasPressed('down') then
    self:changePokemon(1)
  elseif input:wasPressed('a') and (key=='moves' or key=='contestMoves') then
    self.moveMode=true;self.moveIndex=1
  elseif input:wasPressed('a') and key=='ribbons' then
    if #self:ribbonList()>0 then self.ribbonMode=true;self.ribbonIndex=1 end
  elseif input:wasPressed("b")
         or (input:wasPressed('a') and key=='exit') then
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

-- text in a style
function Gen4SummaryMenu:say(style, text, x, y, width, align)
  Font.pushStyle(self.ink[style] or self.ink.black)
  if width then fitted(text, x, y, width, align) else Font.draw(tostring(text), x, y) end
  Font.popStyle()
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

-- the memo window (14,5) w17: SUMMARY_TEXT_BLACK
function Gen4SummaryMenu:drawMemo()
  for _,line in ipairs(self:memoLines()) do
    self:say('black',line.text,112,line.y,136)
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

-- ------------------------------------------------------- the touch screen --

-- WHERE A POINTER LANDED ON THE BOTTOM SCREEN, in its own 256 x 192, or nil.
-- Only while the bottom screen is actually shown -- the same question
-- `drawSubscreen` asks -- so a tap can never press a button nobody can see.
function Gen4SummaryMenu:bottomPoint(px,py)
  local okS,SS=pcall(require,'src.ui.SecondScreen')
  if not okS then return nil end
  local mode=SS.mode(self.game)
  if not ((mode=='display' or mode=='inset') and not SS.stowed(self.game)) then return nil end
  return SS.toLocal(self.game,px,py)
end

-- subscreen.c: sSubscreenButtons_<type> (tile position) and
-- sSubscreenRectangles_<type> (TouchScreenRect top, bottom, left, right,
-- inclusive).  The five-button layout is drawn with SUB_0 scrolled 4 to the
-- left (PokemonSummaryScreen_SetSubscreenType), which its rectangles already
-- allow for; the tap circle moves with it.
Gen4SummaryMenu.SUB_LAYOUTS = {
  normal = { scroll = 0, buttons = {
    { key = 'info', x = 1, y = 4, rect = { 32, 71, 8, 47 } },
    { key = 'memo', x = 2, y = 10, rect = { 80, 119, 16, 55 } },
    { key = 'skills', x = 5, y = 15, rect = { 120, 159, 40, 79 } },
    { key = 'moves', x = 10, y = 18, rect = { 144, 183, 80, 119 } },
    { key = 'condition', x = 17, y = 18, rect = { 144, 183, 136, 175 } },
    { key = 'contestMoves', x = 22, y = 15, rect = { 120, 159, 176, 215 } },
    { key = 'ribbons', x = 25, y = 10, rect = { 80, 119, 200, 239 } },
    { key = 'exit', x = 26, y = 4, rect = { 32, 71, 208, 247 } },
  } },
  noContest = { scroll = 4, buttons = {
    { key = 'info', x = 2, y = 9, rect = { 72, 111, 12, 51 } },
    { key = 'memo', x = 6, y = 15, rect = { 120, 159, 44, 83 } },
    { key = 'skills', x = 14, y = 18, rect = { 144, 183, 108, 147 } },
    { key = 'moves', x = 22, y = 15, rect = { 120, 159, 172, 211 } },
    { key = 'exit', x = 26, y = 9, rect = { 72, 111, 204, 243 } },
  } },
}
-- the tap circle: frame 0 for 3 ticks, frame 1 for 2, hidden on frame 2
Gen4SummaryMenu.TAP_FRAMES = { 3, 2 }
-- DrawSubscreenButtonAnim: the press (anim 2) holds three frames after the
-- page is set up, and then until the stylus leaves the button
Gen4SummaryMenu.SUB_PRESS_FRAMES = 5

-- SUMMARY_MODE_SELECT_MOVE / FEED_POFFIN have no buttons at all
function Gen4SummaryMenu:subLayout()
  if self.choose or self.feedPoffin then return nil end
  return Gen4SummaryMenu.SUB_LAYOUTS[self:showContest() and 'normal' or 'noContest']
end

function Gen4SummaryMenu:subButtonAt(x,y)
  local layout=self:subLayout()
  if not (layout and x and y) then return nil end
  for i,b in ipairs(layout.buttons) do
    local r=b.rect
    if y>=r[1] and y<=r[2] and x>=r[3] and x<=r[4] then return i,b end
  end
  return nil
end

function Gen4SummaryMenu:pageIndex(key)
  for i,page in ipairs(self.pages) do if page.key==key then return i end end
  return nil
end

-- CheckSubscreenPressAndSetButton + the INIT_ANIM / SETUP_PAGE steps: every
-- button back to rest, this one pressed, the circle on it, and the page it
-- names set up (an egg only moves to MEMO or EXIT)
function Gen4SummaryMenu:pressSubButton(index)
  local layout=self:subLayout()
  local b=layout and layout.buttons[index]
  if not b then return false end
  self.subLit=nil
  self.subPress={index=index,frame=0,key=b.key}
  self.tapT=0
  local egg=Party.isEgg(self.mon)
  if not egg or b.key=='memo' or b.key=='exit' then
    local page=self:pageIndex(b.key)
    if page then self.page=page end
  end
  return true
end

-- RUN_ANIM: once the press has shown, the button lets go when the stylus is
-- no longer held on it -- lit (anim 1), or back at rest for an egg's refused
-- page -- and a released EXIT leaves the screen
function Gen4SummaryMenu:stepSubscreen()
  local p=self.subPress
  if not p then return end
  p.frame=p.frame+1
  if p.frame<Gen4SummaryMenu.SUB_PRESS_FRAMES then return end
  local held=self.pointer and self:subButtonAt(self.pointer.x,self.pointer.y)
  if held==p.index then return end
  self.subPress=nil
  local egg=Party.isEgg(self.mon)
  self.subLit=(not egg or p.key=='memo' or p.key=='exit') and p.index or nil
  if p.key=='exit' then self:close() end
end

function Gen4SummaryMenu:touchmoved(id,px,py)
  if not (self.pointer and self.pointer.id==id) then return false end
  self.pointer.x,self.pointer.y=self:bottomPoint(px,py)
  return true
end

function Gen4SummaryMenu:touchreleased(id)
  if not (self.pointer and self.pointer.id==id) then return false end
  self.pointer=nil
  return true
end

function Gen4SummaryMenu:touchpressed(id,px,py)
  local bx,by=self:bottomPoint(px,py)
  if bx then
    self.pointer={id=id,x=bx,y=by}
    -- the buttons are only read from the page's own input state, never
    -- while a move or ribbon is being looked at, or mid-press
    if not (self.moveMode or self.ribbonMode or self.subPress) then
      local index=self:subButtonAt(bx,by)
      if index then self:pressSubButton(index) end
    end
    return true
  end
  -- a panel tap that is not the bottom screen's is nobody's
  if self.game.secondScreenInjecting then return true end
  local r=require('src.render.Renderer').uiPresentation
  if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
  local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
  if not self.moveMode and not self.ribbonMode and y>=16 and y<32 then
    for _,tab in ipairs(self:pageTabs()) do
      if x>=tab.x-8 and x<tab.x-8+tab.width then self.page=tab.page;return true end
    end
  end
  local key=self:pageKey()
  if key=='ribbons' and x>=116 and x<244 and y>=36 and y<116 then
    local ribbons=self:ribbonList()
    local index=math.min(self.ribbonIndex or 1,math.max(1,#ribbons))
    local scroll=self:ribbonScroll(index)
    local slot=math.floor((x-116)/32)+math.floor((y-36)/40)*4+1
    if ribbons[scroll+slot] then self.ribbonIndex=scroll+slot;self.ribbonMode=true end
  elseif key=='exit' and x>=144 and x<216 and y>=80 and y<104 then self:close()
  elseif self.ribbonMode and x<104 then self.ribbonMode=nil
  elseif (key=='moves' or key=='contestMoves') and x>=128 and y>=32 then
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

-- the first ribbon shown: the page holds three rows, the info panel covers
-- the third, so the cursor's row is kept within the top two
function Gen4SummaryMenu:ribbonScroll(index)
  return math.max(0,math.floor(((index or 1)-1)/4)-1)*4
end

function Gen4SummaryMenu:drawRibbonSprites()
  local g=love.graphics
  local ribbons=self:ribbonList()
  local index=math.min(self.ribbonIndex or 1,math.max(1,#ribbons))
  local scroll=self.ribbonMode and self:ribbonScroll(index) or 0
  local slots=self.ribbonMode and 8 or 12
  for slot=1,slots do
    local id=ribbons[scroll+slot]
    if id then
      local rec=require('src.ui.Gen4RibbonData')[id]
      local icon=self:img(('summary/ribbon_%02d'):format(id)) or self:img(rec.art)
      if icon then
        local w,h=icon:getDimensions()
        g.setColor(1,1,1,1)
        g.draw(icon,POS.ribbon[1]+(slot-1)%4*POS.ribbonStep[1],
          POS.ribbon[2]+math.floor((slot-1)/4)*POS.ribbonStep[2],0,1,1,w/2,h/2)
      end
    end
  end
end

function Gen4SummaryMenu:drawRibbonCursor()
  local ribbons=self:ribbonList()
  local index=math.min(self.ribbonIndex or 1,math.max(1,#ribbons))
  local scroll=self:ribbonScroll(index)
  local slot=index-scroll-1
  self:sprite('ribbon_cursor',POS.ribbon[1]+slot%4*POS.ribbonStep[1],POS.ribbon[2]+math.floor(slot/4)*POS.ribbonStep[2])
  if scroll>0 then self:sprite('ribbon_arrow_1',POS.ribbonUp[1],POS.ribbonUp[2]) end
  if scroll+8<#ribbons then self:sprite('ribbon_arrow_0',POS.ribbonDown[1],POS.ribbonDown[2]) end
end

-- the ribbon page's text: the count, or the info panel's name, description
-- and "n/max"
function Gen4SummaryMenu:drawRibbonText()
  local ribbons=self:ribbonList()
  if not self.ribbonMode then
    self:say('black',self:b455(B.ribbonCount,'No. of Ribbons:'),112,168,96)
    self:say('black',tostring(#ribbons),208,168,40)
    return
  end
  local index=math.min(self.ribbonIndex or 1,math.max(1,#ribbons))
  if not ribbons[index] then return end
  local rec=require('src.ui.Gen4RibbonData')[ribbons[index]]
  local texts=self.game.data.text or {}
  self:say('white',texts[('TEXT_B0535_%05d'):format(rec.name)] or rec.key,8,144,168)
  local description=rec.description
  if rec.special then
    local value=(self.mon.specialRibbons or {})[rec.special]
    if value then description=146+value end
  end
  local text=description and texts[('TEXT_B0535_%05d'):format(description)]
  local y=160
  for line in tostring(text or ''):gmatch('[^\n]+') do
    if y<192 then self:say('black',line,8,y,240) end;y=y+16
  end
  -- PrintRibbonIndexAndMax: right-aligned to x 56 of the (24,15) window
  local s=('%d/%d'):format(index,#ribbons)
  self:say('black',s,192+56-Font.width(s),120)
end

-- THE GRAPH GROWS (3d_anim.c).  PokemonSummaryScreen_InitConditionRects puts
-- all four corners of each quad on its centre corner -- the one no stat
-- moves, quad 1's fourth, quad 2's third, quad 3's second, quad 4's first --
-- and InitMaxAndDeltaConditionRects makes a step of a quarter of the way
-- (FX_F32_TO_FX16, so truncated).  UpdateConditionRectsOrFlash then draws the
-- start and three steps, snaps to the real shape on the fourth frame
-- (SPIDER_GRAPH_STATE_FINISH_DRAW) and lights the condition flashes after it.
Gen4SummaryMenu.GRAPH_CENTRE = { 4, 3, 2, 1 }
Gen4SummaryMenu.GRAPH_STEPS = 4

local function towardZero(v) return v<0 and math.ceil(v) or math.floor(v) end

-- the condition graph, as the 3D engine draws it: the four quads' union.
-- `frame` is the grow animation's (nil: grown)
function Gen4SummaryMenu:conditionQuads(frame)
  local condition=self.mon.contest or {}
  local pixels=96/(16*math.tan(0x5C1*2*math.pi/65536))/4096
  local quads={}
  local growing=frame and frame<Gen4SummaryMenu.GRAPH_STEPS
  for qi,quad in ipairs(Q) do
    local c=quad[Gen4SummaryMenu.GRAPH_CENTRE[qi]]
    local v={}
    for _,b in ipairs(quad) do
      local stat=b[1] and math.max(0,math.min(255,tonumber(condition[b[1]]) or 0)) or 0
      local x=stat==255 and b[4] or b[2]+b[6]*stat
      local y=stat==255 and b[5] or b[3]+b[7]*stat
      if growing then
        x=c[2]+towardZero((x-c[2])/4)*frame
        y=c[3]+towardZero((y-c[3])/4)*frame
      end
      v[#v+1]=128+x*pixels;v[#v+1]=96-y*pixels
    end
    quads[#quads+1]=v
  end
  return quads
end

-- one animation step a frame on the CONDITION page, restarted whenever the
-- page or the Pokemon changes (SetupPageFromSubscreenButton and the Pokemon
-- change both re-run InitConditionRects)
function Gen4SummaryMenu:stepGraph()
  local on=self:pageKey()=='condition' and self.mon or nil
  if on~=self.graphFor then
    self.graphFor=on
    self.graphFrame=on and 0 or nil
  elseif self.graphFrame then
    self.graphFrame=self.graphFrame+1
  end
end

-- sConditionFlashCoordBounds: { maxX, maxY, minX, minY } per contest type,
-- and the flash's animation (condition_flash_anim, looping)
Gen4SummaryMenu.FLASH_BOUNDS = {
  { 'cool', 180, 57, 180, 90 }, { 'beauty', 213, 85, 184, 93 }, { 'cute', 200, 125, 182, 97 },
  { 'smart', 159, 125, 178, 97 }, { 'tough', 146, 85, 176, 93 },
}
Gen4SummaryMenu.FLASH_FRAMES = { 8, 2, 2, 2, 2, 2, 2, 2, 64 }

-- DrawConditionFlash: a flash on every stat equal to the highest, unless it
-- is 0, at min + (max - min) * stat / 256 along its spoke
function Gen4SummaryMenu:conditionFlashes()
  local c=self.mon.contest or {}
  local function stat(k) return math.max(0,math.min(255,math.floor(tonumber(c[k]) or 0))) end
  local high=0
  for _,f in ipairs(Gen4SummaryMenu.FLASH_BOUNDS) do high=math.max(high,stat(f[1])) end
  local out={}
  for _,f in ipairs(Gen4SummaryMenu.FLASH_BOUNDS) do
    local v=stat(f[1])
    if v~=0 and v==high then
      local function along(maxV,minV)
        if maxV>=minV then return minV+math.floor((maxV-minV)*v/256) end
        return minV-math.floor((minV-maxV)*v/256)
      end
      out[#out+1]={x=along(f[2],f[4]),y=along(f[3],f[5])}
    end
  end
  return out
end

function Gen4SummaryMenu:drawConditionFlashes()
  local frame=self.graphFrame
  if frame and frame<Gen4SummaryMenu.GRAPH_STEPS then return end
  -- the flash animation runs from the frame the graph finished
  local t=frame and frame-Gen4SummaryMenu.GRAPH_STEPS or (self.t or 0)
  local total=0
  for _,d in ipairs(Gen4SummaryMenu.FLASH_FRAMES) do total=total+d end
  t=t%total
  local f=0
  for i,d in ipairs(Gen4SummaryMenu.FLASH_FRAMES) do
    if t<d then f=i-1;break end
    t=t-d
  end
  for _,at in ipairs(self:conditionFlashes()) do
    self:sprite('condition_flash_'..f,at.x,at.y)
  end
end

-- kept for callers that want the five corners: cool, beauty, cute, smart, tough
function Gen4SummaryMenu:conditionVertices()
  local q=self:conditionQuads()
  return { q[1][1],q[1][2], q[1][3],q[1][4], q[1][5],q[1][6], q[3][7],q[3][8], q[2][1],q[2][2] }
end

function Gen4SummaryMenu:drawConditionGraph()
  local g=love.graphics
  if not self.graphCanvas then
    local ok,c=pcall(g.newCanvas,W,H)
    self.graphCanvas=ok and c or false
  end
  local col=Gen4SummaryMenu.CONDITION_COLOUR
  local quads=self:conditionQuads(self.graphFrame)
  if not self.graphCanvas then
    g.setColor(col[1],col[2],col[3],col[4])
    for _,v in ipairs(quads) do g.polygon('fill',v) end
    g.setColor(1,1,1,1)
    return
  end
  g.push('all')
  g.setCanvas(self.graphCanvas)
  g.origin()
  g.setScissor()
  g.clear(0,0,0,0)
  g.setColor(col[1],col[2],col[3],1)
  for _,v in ipairs(quads) do g.polygon('fill',v) end
  g.pop()
  g.setColor(1,1,1,col[4])
  g.draw(self.graphCanvas,0,0)
  g.setColor(1,1,1,1)
end

-- sheen (sprites.c DrawSheenSprites): 12 x sheen / 255 sparkles that light in
-- turn every ten frames, all go dark, then flash together
function Gen4SummaryMenu:sheenCount()
  local sheen=math.max(0,math.min(255,tonumber((self.mon.contest or {}).sheen) or 0))
  if sheen==0 then return 0 end
  return sheen==255 and 12 or math.floor(math.floor(12*256/255)*sheen/256)
end

function Gen4SummaryMenu:drawSheen()
  local count=self:sheenCount()
  if count==0 then return end
  local frames=0
  while self.summaryArt['sheen_'..frames] do frames=frames+1 end
  if frames==0 then return end
  -- one cycle: 8 idle, count*10 lighting, 32 dark, a flash, 32 idle
  local period=8+count*10+32+frames+32
  local t=(self.t or 0)%period
  for i=1,count do
    local start=8+(i-1)*10
    local f
    if t>=start and t<start+frames then f=t-start
    elseif t>=8+count*10+32 and t<8+count*10+32+frames then f=t-(8+count*10+32) end
    if f then self:sprite('sheen_'..f,POS.sheen[1]+(i-1)*8,POS.sheen[2]) end
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
  local offset=align=='centre' and math.floor((width-pixels*scale)/2) or align=='right' and width-pixels*scale or 0
  g.push();g.translate(x+offset,y);g.scale(scale,1)
  Font.draw(text,0,0);g.pop()
end

function Gen4SummaryMenu:field(page, i, label, value, style)
  local row = (page == 'skills' and SKILL_WINDOWS or INFO_WINDOWS)[i]
  self:say('white',label,row[1],row[2],row[3]-row[1]-4)
  if value ~= nil then
    self:say(style or 'black',value,row[3],row[4],row[5],row[6] or 'centre')
  end
end

-- TYPE ICONS: pl_batt_obj's own, in type_icon.c's palette rows
local function typeKey(t)
  local name=tostring(t or ''):lower()
  local alias={electr='electric',fight='fighting',psychc='psychic',['???']='mystery',['?']='mystery'}
  return 'type_'..(alias[name] or name)
end

function Gen4SummaryMenu:drawType(typeName,x,y)
  if self:sprite(typeKey(typeName),x,y) then return true end
  -- an older cache: the battle sheet's own picture, centred
  local rec=((self.game.data.gen4_graphics or {}).battleObjects or {})['type_icons_'..tostring(typeName or ''):lower()]
  local image=self:image(type(rec)=='table' and rec.path or rec)
  if image then
    love.graphics.setColor(1,1,1,1);love.graphics.draw(image,x-16,y-8)
    return true
  end
  return false
end

function Gen4SummaryMenu:monTypes()
  local def=self:speciesDef()
  local types=def and def.types
  if type(types)~='table' then return nil end
  return types[1],(types[2] and types[2]~=types[1]) and types[2] or nil
end

function Gen4SummaryMenu:drawInfo()
  local mon, def = self.mon, self:speciesDef()
  local number = self:dexNumber()
  local shiny = require('src.pokemon.Pokemon').isShiny(mon)
  self:field("info", 1, self:word("dexNo", Strings("Pokédex No.")),
             number and ("%03d"):format(number) or self:word('unknown','???'), shiny and 'red' or 'black')
  self:field("info", 2, self:word("name", Strings("Name")),
             (def and def.name) or tostring(mon.species))
  self:field("info", 3, self:word("types", Strings("Type")))
  local player = (self.game.save or {}).player or {}
  local otFemale = mon.otGender == 1 or mon.otGender == 'female'
    or (mon.otGender == nil and (player.gender == 1 or player.gender == 'female'))
  self:field("info", 4, self:word("ot", "OT"),
             tostring(mon.otName or mon.ot or player.name or ""), otFemale and 'red' or 'blue')
  self:field("info", 5, self:word("idNo", Strings("ID No.")),
             ("%05d"):format((tonumber(mon.otId or player.id) or 0) % 65536))
  self:field("info", 6, self:word("expPoints", Strings("Exp. Points")),
             tostring(math.floor(tonumber(mon.exp) or 0)))
  local level=tonumber(mon.level) or 1
  local exp=tonumber(mon.exp) or 0
  local nextExp=level<100 and Growth.expForLevel(def and def.growthRate,level+1) or exp
  self:field("info", 7, self:word("toNextLv", Strings("To Next Lv.")),
             tostring(math.max(0,level>=100 and 0 or nextExp-exp)))
end

-- the bars main.c writes into BG3 (DrawHealthBar / DrawExperienceProgressBar)
local function pixelCount(cur,max,size)
  if not max or max<=0 then return 0 end
  local p=math.floor(cur*size/max)
  if p==0 and cur>0 then p=1 end
  return math.max(0,math.min(size,p))
end

function Gen4SummaryMenu:drawBar(key,x,y,tiles,pixels)
  local img=self:sart(key)
  if not img then return end
  local iw,ih=img:getDimensions()
  love.graphics.setColor(1,1,1,1)
  for i=0,tiles-1 do
    local n=math.min(8,math.max(0,pixels-i*8))
    love.graphics.draw(img,love.graphics.newQuad(n*8,0,8,8,iw,ih),x+i*8,y)
  end
end

function Gen4SummaryMenu:drawExpBar()
  local mon,def=self.mon,self:speciesDef()
  local level=tonumber(mon.level) or 1
  local cur,max=0,0
  if level<100 then
    local rate=def and def.growthRate
    local base=Growth.expForLevel(rate,level) or 0
    max=(Growth.expForLevel(rate,level+1) or base)-base
    cur=math.max(0,(tonumber(mon.exp) or 0)-base)
  end
  self:drawBar('exp_bar',POS.expBar[1],POS.expBar[2],7,pixelCount(cur,max,56))
end

function Gen4SummaryMenu:hpValues()
  local stats=self.mon.stats or {}
  local hp=tonumber(self.mon.hp) or 0
  local max=tonumber(self.mon.maxHp) or tonumber(self.mon.maxhp) or tonumber(stats.hp) or 0
  return hp,max
end

function Gen4SummaryMenu:drawHpBar()
  local hp,max=self:hpValues()
  local px=pixelCount(hp,max,48)
  local key=(hp==max or px>24) and 'hp_green' or px>=10 and 'hp_yellow' or px>0 and 'hp_red' or 'hp_green'
  self:drawBar(key,POS.hpBar[1],POS.hpBar[2],6,px)
end

-- PrintCurrentAndMaxInfo: the slash centred on `cx`, the current value
-- right-aligned against it and the maximum left-aligned after it
function Gen4SummaryMenu:curMax(cur,max,cx,y)
  local slash=self:b455(B.slash,'/')
  local sw=Font.width(slash)
  local left=cx-math.floor(sw/2)
  Font.pushStyle(self.ink.black)
  Font.draw(slash,left,y)
  local c=tostring(cur)
  Font.draw(c,left-Font.width(c),y)
  Font.draw(tostring(max),left+sw,y)
  Font.popStyle()
end

function Gen4SummaryMenu:drawSkills()
  local mon = self.mon
  local stats = mon.stats or {}
  local hp,max=self:hpValues()
  self:field("skills", 1, self:word("hp", "HP"))
  self:curMax(hp,max,184+28,32)
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

  -- ability label (14,18), name (21,18), description (14,20) w18 h4
  self:say('white',self:word("ability", Strings("Ability")),112,144,48)
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
    self:say('black',tostring((record and record.name) or ability),168,144,88)
    local description=record and (record.description or record.desc)
    if type(description)=='string' then
      local y=160
      for line in self:wrap(description,144) do
        if y<192 then self:say('black',line,112,y,144) end;y=y+16
      end
    end
  end
end

-- the cartridge's own line breaks when it has them, a word wrap when not
function Gen4SummaryMenu:wrap(text,width)
  local lines={}
  for paragraph in tostring(text or ''):gmatch('[^\n]+') do
    if Font.width(paragraph)<=width then lines[#lines+1]=paragraph
    else
      local line=''
      for word in paragraph:gmatch('%S+') do
        local candidate=line=='' and word or line..' '..word
        if Font.width(candidate)>width and line~='' then lines[#lines+1]=line;line=word
        else line=candidate end
      end
      if line~='' then lines[#lines+1]=line end
    end
  end
  local i=0
  return function() i=i+1;return lines[i] end
end

function Gen4SummaryMenu:moveRecord(entry)
  local id=(type(entry)=='table' and (entry.id or entry.move)) or entry
  return id and (self.game.data.moves or {})[id],id
end

local CONTEST={[0]='cool','beauty','cute','smart','tough'}

-- PrintMoveNameAndPP, per (21, 4+4i) window
function Gen4SummaryMenu:drawMoves(contest)
  local moves = self.mon.moves or {}
  for i = 1, 4 do
    local y = 32 + (i - 1) * 32
    local entry = moves[i]
    local record,id = self:moveRecord(entry)
    if entry and id and id~=0 then
      self:say('white',(record and record.name) or id,169,y+2,87)
      if record then
        if contest then self:drawType(CONTEST[tonumber(record.contestType) or 0],POS.moveType[1],POS.moveType[2]+(i-1)*POS.pitch)
        else self:drawType(record.type,POS.moveType[1],POS.moveType[2]+(i-1)*POS.pitch) end
      end
      local pp = type(entry) == "table" and entry.pp or nil
      local maxPp = record and record.pp
      if maxPp and type(entry)=='table' then
        maxPp=maxPp+math.min(3,math.max(0,tonumber(entry.ppUps) or 0))*math.floor(maxPp/5)
      end
      self:say('black',self:b455(B.pp,self:word("pp","PP")),184,y+16)
      self:curMax(pp or maxPp or '-',maxPp or '-',168+60,y+16)
    else
      -- MOVE_NONE's own name from the move-name bank
      local none=(self.game.data.moves or {})[0]
      self:say('white',(none and none.name) or '-',169,y+2)
      local dashes=self:b455(B.twoDashes,'--')
      self:say('black',dashes,168+60-math.floor(Font.width(dashes)/2),y+16)
    end
  end
  if self.moveMode then
    self:say('white',self:b455(B.cancel,self:word('cancel','CANCEL')),168,162)
  end
end

-- the cursor sprites over the move list (priority 0)
function Gen4SummaryMenu:drawMoveCursor()
  if not self.moveMode then return end
  if self.swapMove then
    self:sprite('move_cursor_1',POS.moveCursor[1],POS.moveCursor[2]+(self.swapMove-1)*POS.pitch)
  end
  self:sprite('move_cursor_0',POS.moveCursor[1],POS.moveCursor[2]+(self.moveIndex-1)*POS.pitch)
end

-- BG2: move_info.NSCR at the panel's scroll
function Gen4SummaryMenu:drawPanel(which)
  local at=Gen4SummaryMenu.PANEL[which]
  local panel=self:img('summary/move_info')
  if not (at and panel) then return end
  local w,h=panel:getDimensions()
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(panel,love.graphics.newQuad(at[1],at[2],W,H,w,h),0,0)
end

function Gen4SummaryMenu:selectedMove()
  local entry=(self.mon.moves or {})[self.moveIndex or 0]
  local record,id=self:moveRecord(entry)
  if not id or id==0 then return nil end
  return record,id
end

-- the battle move panel's text (PrintBattleMoveAttributes) and sprites
function Gen4SummaryMenu:drawBattleDetails()
  local record=self:selectedMove()
  if not record then return end
  self:say('white',self:b455(B.category,self:word('category','CATEGORY')),8,64)
  self:say('white',self:b455(B.power,self:word('power','POWER')),8,80)
  self:say('white',self:b455(B.accuracy,self:word('accuracy','ACCURACY')),8,96)
  local three=self:b455(B.threeDashes,'---')
  local power=tonumber(record.power) or 0
  local accuracy=tonumber(record.accuracy) or 0
  self:say('black',power>1 and power or three,96,80,24,'centre')
  self:say('black',accuracy>0 and accuracy or three,96,96,24,'centre')
  local y=112
  for line in self:wrap(record.description,120) do
    if y<192 then self:say('black',line,8,y,120) end;y=y+16
  end
end

function Gen4SummaryMenu:drawBattleSprites()
  local record=self:selectedMove()
  local t1,t2=self:monTypes()
  if t1 then self:drawType(t1,POS.movesType1[1],POS.movesType1[2]) end
  if t2 then self:drawType(t2,POS.movesType2[1],POS.movesType2[2]) end
  if record then
    local class=tostring(record.class or ''):lower()
    self:sprite('category_'..class,POS.category[1],POS.category[2])
  end
  self:drawMonIcon(POS.battleIcon[1],POS.battleIcon[2])
end

-- the contest move panel: hearts (DrawAppealHeart into BG2), APPEAL POINTS,
-- the effect's two lines, and the condition dots
function Gen4SummaryMenu:appealHearts()
  local record=self:selectedMove()
  if not record then return 0 end
  local effects=((self.game.data.gen4_contest or {}).effects) or {}
  local e=effects[tonumber(record.contestEffect) or 0]
  return math.floor((e and tonumber(e.appeal) or 0)/10)
end

function Gen4SummaryMenu:drawContestDetails()
  local hearts=self:appealHearts()
  for i=0,5 do
    local img=self:sart(i<hearts and 'heart_filled' or 'heart_empty')
    if img then love.graphics.setColor(1,1,1,1);love.graphics.draw(img,(2+i*2)*8,47*8-256) end
  end
  local record=self:selectedMove()
  if not record then return end
  self:say('black',self:b455(B.appeal,'APPEAL POINTS'),16,104,96,'centre')
  local effect=tonumber(record.contestEffect) or 0
  local text=effect>0 and ((self.game.data.text or {})[('TEXT_B0210_%05d'):format(46+effect-1)]) or nil
  local y=144
  for line in tostring(text or ''):gmatch('[^\n]+') do
    if y<192 then self:say('black',line,8,y,120) end;y=y+16
  end
end

-- CalcContestStatDotPos
local DOTS={ {'cool',88,88,49,73,0}, {'beauty',110,88,65,73,1}, {'cute',103,88,92,73,3},
  {'smart',72,87,92,73,2}, {'tough',65,87,65,73,4} }
Gen4SummaryMenu.CONTEST_DOTS=DOTS
local function dotPos(stat,max,min)
  stat=stat+44
  if min>max then return min-math.floor((min-max)*stat*65536/300/65536) end
  return min+math.floor((max-min)*stat*65536/300/65536)
end
Gen4SummaryMenu.dotPos=dotPos

function Gen4SummaryMenu:drawContestSprites()
  local c=self.mon.contest or {}
  for _,d in ipairs(DOTS) do
    local v=math.max(0,math.min(255,tonumber(c[d[1]]) or 0))
    self:sprite('contest_dot_'..d[6],dotPos(v,d[2],d[3]),dotPos(v,d[4],d[5]))
  end
  self:drawMonIcon(POS.contestIcon[1],POS.contestIcon[2])
end

-- the species icon (pl_poke_icon), mirrored like the picture
function Gen4SummaryMenu:drawMonIcon(x,y)
  local data=self.game.data or {}
  local icons=data.icons
  local mon=self.mon
  local def=data.pokemon and data.pokemon[mon.species]
  local entry=(icons and icons.bySpecies and icons.bySpecies[mon.species]) or (def and def.icon)
  if Party.isEgg(mon) and icons and icons.bySpecies then
    entry=icons.bySpecies[mon.species==490 and 495 or 494] or entry
  end
  local path,frameH
  if type(entry)=='table' then path,frameH=entry.image,tonumber(entry.frameHeight)
  elseif type(entry)=='string' then path=entry end
  local img=self:image(path)
  if not img then return end
  local iw,ih=img:getDimensions()
  frameH=math.min(frameH or tonumber(icons and icons.frameHeight) or 32,ih)
  local flip=def~=nil and def.flipSprite~=nil and not def.flipSprite and not Party.isEgg(mon)
  love.graphics.setColor(1,1,1,1)
  local q=love.graphics.newQuad(0,0,iw,frameH,iw,ih)
  if flip then love.graphics.draw(img,q,x+iw/2,y-frameH/2,0,-1,1)
  else love.graphics.draw(img,q,x-iw/2,y-frameH/2) end
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
-- WHAT THE FLAG IS NOT is a facing: Torterra has it SET and Bulbasaur CLEAR,
-- and both are drawn facing left.  WHAT IT READS AS is "do not reverse this
-- one" -- UNOWN, SPINDA, the Poliwag line's spiral, Teddiursa's crescent.
--
-- The byte has been in the cache the whole time: Gen4Species.parse reads it as
-- `flipSprite`.  On a Gen 1-3 cache there is no such field, and `not nil` is
-- true -- which would mirror Kanto -- so the mirror is asked for only where the
-- field EXISTS.
function Gen4SummaryMenu:pictureArt()
  local mon, data = self.mon, self.game.data
  if not (mon and data) then return nil, false end
  if Party.isEgg(mon) then
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

-- SUMMARY_CONDITION_*: the status_icons sequence
function Gen4SummaryMenu:statusIndex()
  if Party.isEgg(self.mon) then return nil end
  if tonumber(self.mon.hp)==0 then return 6 end
  local status=tostring(self.mon.status or ''):upper()
  local indices={PAR=1,PARALYSIS=1,FRZ=2,FREEZE=2,SLP=3,SLEEP=3,
    PSN=4,TOX=4,POISON=4,TOXIC=4,BRN=5,BURN=5}
  return indices[status]
end

function Gen4SummaryMenu:pokerus()
  local virus=tonumber(self.mon.pokerus or self.mon.gen4Pokerus or self.mon.gen3Pokerus) or 0
  if virus==0 then return nil end
  return virus%16>0 and 'active' or 'cured'
end

function Gen4SummaryMenu:markingBits()
  local m=self.mon.markings
  if type(m)=='number' then return m end
  if type(m)=='table' then
    local bits=0
    for i,name in ipairs(require('src.import.Gen4SummaryArt').MARKINGS) do
      if m[name] or m[i] then bits=bits+2^(i-1) end
    end
    return bits
  end
  return 0
end

-- the OBJ priority-3 sprites, under the picture and the panels
function Gen4SummaryMenu:drawBackSprites(key)
  local egg=Party.isEgg(self.mon)
  local index=self:statusIndex()
  if index then
    if not self:sprite('status_'..index,POS.status[1],POS.status[2]) then
      local icon=self:img(('summary/status_%02d'):format(index))
      if icon then local w,h=icon:getDimensions();love.graphics.draw(icon,POS.status[1],POS.status[2],0,1,1,w/2,h/2) end
    end
  elseif self:pokerus()=='active' and not egg then
    self:sprite('pokerus_icon',POS.pokerus[1],POS.pokerus[2])
  end
  local bits=self:markingBits()
  for i,name in ipairs(require('src.import.Gen4SummaryArt').MARKINGS) do
    local on=math.floor(bits/2^(i-1))%2
    self:sprite(('marking_%s_%d'):format(name,on),POS.markings[1]+(i-1)*8,POS.markings[2])
  end
  if not egg then
    if require('src.pokemon.Pokemon').isShiny(self.mon) then self:sprite('shiny',POS.shiny[1],POS.shiny[2]) end
    if self:pokerus()=='cured' then self:sprite('pokerus_cured',POS.cured[1],POS.cured[2]) end
  end
  if not self.moveMode and not self.ribbonMode and #self:visiblePages()>1 then
    local base=self:tabBase()
    self:sprite('tab_arrow_0',base+POS.arrowLeft,POS.tabY)
    self:sprite('tab_arrow_1',POS.tabsCentre+(POS.tabsCentre-base)+POS.arrowRight,POS.tabY)
  end
  if key=='condition' then self:drawSheen() end
  if key=='ribbons' then self:drawRibbonSprites() end
end

function Gen4SummaryMenu:tabBase()
  local n=#self:visiblePages()
  return POS.tabsCentre-math.floor((POS.focusedTab+(n-1)*POS.tab)/2)
end

-- UpdatePageTabSprites: the tabs up to the current one at base + 16c, the
-- ones after it shifted by the focused tab's extra 8
function Gen4SummaryMenu:pageTabs()
  local ids=Gen4SummaryMenu.PAGE_ID or {info=0,memo=1,skills=2,moves=3,condition=4,contestMoves=5,ribbons=6,exit=7}
  local tabs={}
  local base=self:tabBase()
  local current=ids[self:pageKey()] or 0
  for c,i in ipairs(self:visiblePages()) do
    local page=self.pages[i]
    local id=ids[page.key] or 0
    local selected=i==self.page
    local x=current>=id and base+(c-1)*POS.tab or base+POS.focusedTab+(c-2)*POS.tab
    tabs[#tabs+1]={page=i,x=x,width=selected and POS.focusedTab or POS.tab,sequence=id+(selected and 8 or 0)}
  end
  return tabs
end

-- each tab is a sprite at its anchor; the cell's own origin places it
function Gen4SummaryMenu:drawPageTabs()
  for _,tab in ipairs(self:pageTabs()) do
    if not self:sprite(('tab_%02d'):format(tab.sequence),tab.x,POS.tabY) then
      local key=('summary/tab_%02d'):format(tab.sequence)
      local icon,old=self:img(key),self.art[key]
      if icon then
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(icon,tab.x+(type(old)=='table' and old.originX or 0),POS.tabY+(type(old)=='table' and old.originY or 0))
      end
    end
  end
end

-- the caught ball (priority 0)
function Gen4SummaryMenu:caughtBall()
  local ball=tonumber(self.mon.caughtBall or self.mon.ball or self.mon.pokeball)
  if not ball then
    local names={MASTER_BALL=1,ULTRA_BALL=2,GREAT_BALL=3,POKE_BALL=4,SAFARI_BALL=5,
      NET_BALL=6,DIVE_BALL=7,NEST_BALL=8,REPEAT_BALL=9,TIMER_BALL=10,LUXURY_BALL=11,
      PREMIER_BALL=12,DUSK_BALL=13,HEAL_BALL=14,QUICK_BALL=15,CHERISH_BALL=16}
    ball=names[self.mon.ball or self.mon.pokeball]
  end
  -- ITEM_NONE shows the Master Ball's tiles (SetCaughtBallGfx)
  if not ball or ball<1 or ball>16 then ball=1 end
  return ball
end

-- the button prompt (26,0) in white, with the A button 10 px before it
function Gen4SummaryMenu:prompt(key)
  local entry
  if self.moveMode then entry=not self.readOnlyMoves and B.switch or nil
  elseif self.ribbonMode then entry=B.ribbonCancel
  elseif key=='moves' then entry=B.battleInfo
  elseif key=='contestMoves' then entry=B.contestInfo
  elseif key=='ribbons' then entry=#self:ribbonList()>0 and B.ribbonInfo or nil
  elseif key=='exit' then entry=B.promptExit end
  local text=entry and self:b455(entry,nil)
  if not text then return end
  self:say('white',text,208,0,48)
  self:sprite('a_button',208-10,8)
end

function Gen4SummaryMenu:draw()
  local g = love.graphics
  g.setColor(0.08, 0.09, 0.14, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  self:drawSubscreen()

  local page = self.pages[self.page] or self.pages[1]
  local key = page and page.key or "info"
  -- BG3: the page (or its select-mode variant) and the bars main.c writes in
  local back = page and self:img(page.art)
  if back then g.draw(back, 0, 0) else Font.drawBox(0, 0, 32, 24) end

  if not self.mon then
    self:say('black',self:word("unknown", "???"), 100, 90)
    return
  end
  if key=='info' then self:drawExpBar() elseif key=='skills' then self:drawHpBar() end

  -- OBJ priority 3, then BG0: the condition graph and the picture
  self:drawBackSprites(key)
  if key=='condition' then self:drawConditionGraph() end
  self:drawPicture()
  if self.ribbonMode then self:drawRibbonCursor() end

  -- BG2: the panels
  local panel=self.moveMode and key or (self.ribbonMode and 'ribbons') or nil
  if panel then self:drawPanel(panel) end
  if self.moveMode and key=='contestMoves' then self:drawContestDetails() end

  -- BG1: the text windows
  if page and page.title then self:say('white',tostring(page.title),8,0,104) end
  local def = self:speciesDef()
  local egg = Party.isEgg(self.mon)
  local name = egg and Strings('Egg')
    or self.mon.nickname or (def and def.name) or tostring(self.mon.species)
  self:say('white',name,24,24,64)
  if not egg and not self.mon.hideGender then
    local gender=require('src.pokemon.DayCare').gender(self.game.data,self.mon)
    if gender=='male' or gender=='female' then
      local symbol=self:b455(gender=='male' and B.male or B.female,gender=='male' and '♂' or '♀')
      self:say(gender=='male' and 'blue' or 'red',symbol,24,24,72,'right')
    end
  end
  if not egg and not self.moveMode then
    -- PrintLevel: the "Lv" glyph at (0,5), the number at (16,0)
    if not self:sprite('lv',8,45) then self:say('black','Lv',8,40) end
    self:say('black',tostring(tonumber(self.mon.level) or 1),24,40)
  end
  if not egg and not self.moveMode and not self.ribbonMode then
    self:say('white',self:word('item',Strings('Item')),8,160,48)
    local held=self.mon.item or self.mon.heldItem
    local item=held and self.game.data.items and self.game.data.items[held]
    self:say('black',(item and item.name) or self:word('none',Strings('None')),8,176,96)
  end
  self:prompt(key)

  if key == "info" then self:drawInfo()
  elseif key == 'memo' then self:drawMemo()
  elseif key == 'condition' then
    self:say('white',self:b455(B.sheen,self:word('sheen','SHEEN')),112,160,40)
  elseif key == 'ribbons' then self:drawRibbonText()
  elseif key == "skills" then self:drawSkills()
  elseif key=='exit' then
    self:say('white',self:b455(B.closeWindow,Strings('Close window.')),144,88,72,'centre')
  elseif key=='moves' then self:drawMoves(false)
  elseif key=='contestMoves' then self:drawMoves(true) end
  if self.moveMode and key=='moves' then self:drawBattleDetails() end

  -- OBJ priority 0
  self:drawPageTabs()
  self:sprite(('ball_%02d'):format(self:caughtBall()),POS.ball[1],POS.ball[2])
  if key=='info' then
    local t1,t2=self:monTypes()
    if t1 and t2 then
      self:drawType(t1,POS.infoType1[1],POS.infoType1[2]);self:drawType(t2,POS.infoType2[1],POS.infoType2[2])
    elseif t1 then self:drawType(t1,POS.infoTypeSolo[1],POS.infoTypeSolo[2]) end
  end
  if self.moveMode and key=='moves' then self:drawBattleSprites()
  elseif self.moveMode and key=='contestMoves' then self:drawContestSprites() end
  if key=='condition' then self:drawConditionFlashes() end
  self:drawMoveCursor()
  g.setColor(1, 1, 1, 1)
end

-- THE BOTTOM SCREEN (subscreen.c): tiles_sub's rings and a button per page,
-- sSubscreenButtons_Normal's tile positions, lit for the page that is open
Gen4SummaryMenu.SUB_BUTTONS = {
  info = { 1, 4 }, memo = { 2, 10 }, skills = { 5, 15 }, moves = { 10, 18 },
  condition = { 17, 18 }, contestMoves = { 22, 15 }, ribbons = { 25, 10 }, exit = { 26, 4 },
}

function Gen4SummaryMenu:drawSubscreenBody()
  local g=love.graphics
  local back=self:sart('sub_backdrop') or self:img('summary/tiles_sub')
  g.setColor(1,1,1,1)
  if back then g.draw(back,0,0) end
  local layout=self:subLayout()
  if not layout then return end
  local ids=Gen4SummaryMenu.PAGE_ID or {}
  local press=self.subPress
  for i,b in ipairs(layout.buttons) do
    local id=ids[b.key]
    if id then
      -- UpdateSubscreenButtonGfx redraws every button in its resting face
      -- (anim 0); a touch shows the pressed face (2) and leaves the one it
      -- chose lit (1) until the pad changes the page
      local anim=(press and press.index==i) and 2 or (self.subLit==i and 1 or 0)
      local img=self:sart(('sub_button_%d_%d'):format(id,anim)) or self:sart(('sub_button_%d_0'):format(id))
      if img then g.draw(img,b.x*8-layout.scroll,b.y*8) end
    end
  end
  -- the tap circle, on the pressed button's centre (CalcSubscreenButtonTapAnimPos)
  local f=self:tapFrame()
  local b=f and press and layout.buttons[press.index]
  if b then self:sprite('tap_'..f,b.x*8+20-layout.scroll,b.y*8+20) end
end

function Gen4SummaryMenu:tapFrame()
  local t=self.tapT
  if not t then return nil end
  for f,d in ipairs(Gen4SummaryMenu.TAP_FRAMES) do
    if t<d then return f-1 end
    t=t-d
  end
  return nil
end

function Gen4SummaryMenu:drawSubscreen()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return end
  local mode = SS.mode(self.game)
  if not ((mode == "display" or mode == "inset") and not SS.stowed(self.game)) then return end
  SS.draw(self.game, function() self:drawSubscreenBody() end)
end

return Gen4SummaryMenu
