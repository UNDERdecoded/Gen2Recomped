-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's PARTY SCREEN -- the last of the four that were falling back to
-- Kanto's art.
--
-- WHERE THE SIX PANELS ARE, measured off `party/menu` rather than guessed.
-- The panels are drawn in one teal, striped every other row, so the stripes
-- give the bands away: on the left half they run 5..47, 53..95 and 101..143,
-- and on the right half 13..57, 61..107 and 109..151.  Two columns of three,
-- a pitch of 48 both sides, the right one starting eight pixels lower -- which
-- is the stagger Platinum's screen has.  The cursor art is 128 wide, which is
-- the third independent way of saying a column is half the screen.
--
-- WHAT THIS SCREEN DOES AND DOES NOT DO, said plainly because the alias in
-- `Screens.lua` is where it matters:
--
--   * THE FIELD PARTY MENU is this screen: the list, the cursor, SUMMARY and
--     SWITCH.
--   * EVERYTHING IN A BATTLE still goes to the Gen 3 screen, which already
--     answers SHIFT, forced switches and an item's target.  The alias does not
--     list `battle`, so those pushes are declined here and served there.
--   * TM TEACHING IS THIS SCREEN NOW.  The old note here said it needed words
--     the cache does not carry; it carries them -- bank 453 -- and what the
--     gap actually cost was a CRASH, not a wrong-looking list.  See the
--     `tmhm` note in Screens.lua.
--   * THE FRONTIER'S TEAM ORDER is still not served, and for a reason that
--     has nothing to do with words: the only caller in the port that pushes
--     `chooseOrder` is a GEN 3 script special, so no Platinum cache ever
--     sends one.
--   * GIVE/TAKE AN ITEM uses the native item submenu and checks bag capacity
--     before transferring either the chosen item or the previous held item.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4PartyMenu = {}
Gen4PartyMenu.__index = Gen4PartyMenu
Gen4PartyMenu.isOpaque = true

local W, H = 256, 192

-- The six slots, in reading order, from the bands above.
local SLOT_W, SLOT_H = 128, 48
local SLOTS = {
  { x = 0,   y = 0 },   { x = 128, y = 8 },
  { x = 0,   y = 48 },  { x = 128, y = 56 },
  { x = 0,   y = 96 },  { x = 128, y = 104 },
}
-- The panels stop at 151, so CANCEL gets the strip under them.
local CANCEL = { x = 8, y = 160, w = 240, h = 24 }

local ICON_PERIOD = 0.32

function Gen4PartyMenu:uiSize() return W, H end
function Gen4PartyMenu:wantsFillScale() return true end
function Gen4PartyMenu:wantsEdgeBleed() return false end

function Gen4PartyMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4PartyMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4PartyMenu)
  self.game = game
  self.onCancel = opts.onCancel
  self.onSwitch = opts.onSwitch
  self.pickOnly = opts.pickOnly
  self.forceSwitch = opts.forceSwitch
  self.keepOpen = opts.keepOpen
  -- THE BATTLE THAT OPENED THIS SCREEN, and what it changes.
  --
  -- Reported from play: the party screen in a Platinum battle was KANTO'S.
  -- The alias in Screens.lua left `battle` out on purpose -- the reasoning is
  -- in the header above -- but a declined Gen 4 push does not fall through to
  -- Hoenn's screen on a Gen 4 cache: Screens.resolveId returns early unless
  -- isGen3(game), so it fell all the way to the Game Boy one.
  --
  -- The screen serves it now, and the one thing that had to change to make
  -- that honest is the submenu. Out of a battle the first row is SUMMARY and
  -- SWITCH reorders the party. IN a battle, pressing POKeMON and choosing a
  -- member has to SEND IT OUT -- reordering would be a dead end, which is
  -- exactly what the header warns against serving.
  self.battle = opts.battle
  -- THE MACHINE THAT IS OPEN.  `{ move, kind }`, put there by BagMenu.useOn
  -- for any item with a `machine` record -- so this arrives on every cache,
  -- and used to be the one key that made the whole push fall to Kanto's list.
  self.tmhm = opts.tmhm
  self.index = 1
  self.t = 0
  self.cache = {}
  self.icons = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  -- The cartridge's own words.  Nothing here falls back to English except
  -- through Strings(), which is the engine's own translation seam.
  self.words = (((game.data or {}).gen4_menus or {}).partyMenu or {}).text or {}
  if self.tmhm and not self.words.able then
    Logger.warn("gen4 party: this cache carries no party-screen words -- "
                .. "the machine prompt falls back to the engine's own")
  end
  if not self.art["party/menu"] then
    Logger.warn("gen4 party: this cache carries no party screen art -- "
                .. "the panels will be drawn in the engine's own frame")
  end
  return self
end

function Gen4PartyMenu:word(key, fallback)
  local said = self.words[key]
  if type(said) ~= "string" or said == "" then return Strings(fallback) end
  return said
end

-- CAN THIS POKEMON LEARN THE MACHINE THAT IS OPEN?
--
-- The same scan ItemEffects.use makes when it actually teaches, so the word on
-- screen can never disagree with what pressing A does -- which is the rule the
-- Gen 3 screen states and the only thing that keeps an ABLE! from being
-- followed by a refusal.
function Gen4PartyMenu:canLearn(mon)
  local data = self.game.data
  local def = require('src.pokemon.Gen4Forms').definition(data,mon)
  for _, move in ipairs((def and def.tmhm) or {}) do
    if move == self.tmhm.move then return true end
  end
  return false
end

-- ...and which of the three words that is.  A Pokemon that already knows the
-- move is told so rather than offered it, which is the order ItemEffects tests
-- them in as well.
function Gen4PartyMenu:learnWord(mon)
  for _, slot in ipairs(mon.moves or {}) do
    local id = (type(slot) == "table" and (slot.id or slot.move)) or slot
    if id == self.tmhm.move then return self:word("learned", "LEARNED") end
  end
  if self:canLearn(mon) then return self:word("able", "ABLE!") end
  return self:word("unable", "UNABLE!")
end

function Gen4PartyMenu:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4PartyMenu:party() return self.game.save.party or {} end

function Gen4PartyMenu:touchpressed(_, px, py)
  local r=require('src.render.Renderer').uiPresentation
  if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
  local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
  if self.submenu then
    local actions=self:actions()
    local left,top=W-120,H-#actions*16-20
    if x>=left and x<left+112 and y>=top+6 and y<top+6+#actions*16 then
      self:runAction(actions[math.floor((y-top-6)/16)+1])
    else self.submenu=nil;self.itemMenu=nil end
    return true
  end
  if y>=CANCEL.y and y<CANCEL.y+CANCEL.h then
    self.index=self:count();self:choose();return true
  end
  for i,at in ipairs(SLOTS) do
    if x>=at.x and x<at.x+SLOT_W and y>=at.y and y<at.y+SLOT_H and self:party()[i] then
      self.index=i;self:choose();return true
    end
  end
  return true
end

-- Slots 1..#party, then CANCEL.
function Gen4PartyMenu:count() return #self:party() + 1 end

function Gen4PartyMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- Hand the pick back, popping first, which is the order every other picker in
-- this port uses: a caller that opens a message box would otherwise draw it
-- underneath this screen.
function Gen4PartyMenu:handOff(mon)
  if not self.keepOpen then self.game.stack:pop() end
  if self.onSwitch then self.onSwitch(mon, self) end
end

function Gen4PartyMenu:swapWith(slot)
  local party = self:party()
  local from = self.switchFrom
  self.switchFrom = nil
  if not from or from == slot then return end
  party[from], party[slot] = party[slot], party[from]
end

function Gen4PartyMenu:choose()
  if self.index > #self:party() then
    if self.switchFrom then self.switchFrom = nil return end
    -- CANCEL is the same refusal as B and takes the same route; see update().
    if self.onSwitch and not (self.pickOnly or self.forceSwitch)
       and not self.battle then
      return self:handOff(nil)
    end
    return self:close()
  end
  local mon = self:party()[self.index]
  if not mon then return end

  -- A screen opened to PICK a member hands it back at once, the way the
  -- cartridge does when the previous Pokemon has fainted or an item is
  -- waiting on a target: there is nothing to choose between.
  if self.onSwitch and (self.pickOnly or self.forceSwitch) then
    return self:handOff(mon)
  end
  -- A second press while a slot is marked completes the swap.
  if self.switchFrom then return self:swapWith(self.index) end
  self.submenu = 1
end

function Gen4PartyMenu:runAction(action)
  local mon = self:party()[self.index]
  self.submenu = nil
  if action == 'cancel' and self.itemMenu then
    self.itemMenu=nil;self.submenu=1;return
  end
  if action == 'item' then
    self.itemMenu = true;self.submenu = 1;return
  end
  self.itemMenu = nil
  local field=action:match('^field:(.+)$')
  if field and mon then return self:useFieldMove(mon,field) end
  if action == "send" and mon then
    -- Straight back to the caller. Whether this member MAY be sent out is the
    -- caller's question and it already asks it: BattleState's own onSwitch
    -- rejects an egg, a fainted member and one already standing on the field,
    -- says so, and reopens this screen. Duplicating those three tests here
    -- would be a second place for them to drift.
    return self:handOff(mon)
  elseif action == "summary" and mon then
    require("src.ui.Screens").push(self.game, "SummaryMenu", {
      mon=mon,readOnlyMoves=self.battle and true or false,
    })
  elseif action == "switch" then
    self.switchFrom = self.index
  elseif action == 'give' and mon then
    require('src.ui.Screens').push(self.game,'BagMenu',{
      pick=true,onPick=function(id)
        require('src.ui.BagMenu').handOver(self.game,mon,id,nil,{
          giveHeld=function(target,item) return self:giveHeld(target,item) end,
        })
      end,
    })
  elseif action == 'take' and mon then
    local held=mon.item
    local got,why=require('src.inventory.Bag').takeHeld(self.game.save,mon,self.game.data)
    local item=held and self.game.data.items and self.game.data.items[held]
    local text=got and Strings('Received the %s.',(item and item.name) or held)
      or why=='full' and Strings("There's no room to store items.")
      or Strings("This Pokémon isn't holding anything.")
    self.game.stack:push(require('src.render.TextBox').new(self.game,text))
  end
end

function Gen4PartyMenu:giveHeld(mon,id)
  local save=self.game.save
  if (save.inventory[id] or 0)<1 then return false end
  local trial={inventory={},bagOrder={}}
  for key,value in pairs(save.inventory) do trial.inventory[key]=value end
  for i,value in ipairs(save.bagOrder or {}) do trial.bagOrder[i]=value end
  local Bag=require('src.inventory.Bag')
  Bag.remove(trial,id,1)
  if mon.item and not Bag.add(trial,mon.item,1,self.game.data) then return false end
  save.inventory,save.bagOrder=trial.inventory,trial.bagOrder
  mon.item=id
  return true
end

Gen4PartyMenu.ACTIONS = { "summary", "switch", "cancel" }
-- In a battle the top row sends the member out; the party order is not
-- something the cartridge lets you rearrange mid-fight either.
Gen4PartyMenu.BATTLE_ACTIONS = { "send", "summary", "cancel" }

function Gen4PartyMenu:actions()
  if self.itemMenu then return {'give','take','cancel'} end
  if self.battle then return Gen4PartyMenu.BATTLE_ACTIONS end
  local rows={'summary'}
  local F=require('src.world.Gen4FieldMoves');local mon=self:party()[self.index]
  for _,name in ipairs({'CUT','SURF','DIG','TELEPORT','SWEET_SCENT'}) do
    if F.knows(mon,name) then rows[#rows+1]='field:'..name end
  end
  rows[#rows+1]='switch'
  if not require('src.pokemon.Party').isEgg(mon) then rows[#rows+1]='item' end
  rows[#rows+1]='cancel';return rows
end

function Gen4PartyMenu:useFieldMove(mon,move)
  local ow=self.game.overworld;local F=require('src.world.Gen4FieldMoves')
  local usable=ow and F.badgeHeld(self.game.data,self.game.save,move)
  if move=='SURF' then usable=usable and ow:useSurfFieldMove()=='ok'
  elseif move=='CUT' then usable=usable and ow:useCutFieldMove()=='ok'
  elseif move=='DIG' then usable=usable and ow.map.def.allowEscapeRope and ow:escapePoint()
  elseif move=='TELEPORT' then usable=usable and ow.map.def.allowFly and self.game.save.lastHeal
  elseif move=='SWEET_SCENT' then
    local enc=ow and require('src.world.Encounter').forMap(self.game.data,ow.map.def,ow.map.id)
    usable=usable and enc and (ow.player.surfing and enc.water or enc.grass)
  end
  if not usable then
    self.game.stack:push(require('src.render.TextBox').new(self.game,"Can't use that here."));return
  end
  self:close()
  if move=='DIG' then ow:beginTeleportOut(nil,{escape=true})
  elseif move=='TELEPORT' then ow:beginTeleportOut()
  elseif move=='SWEET_SCENT' then ow:gen4SweetScent()
  elseif move=='SURF' then local x,y=ow.player:facingCell();ow:trySurf(x,y)
  elseif move=='CUT' then local x,y=ow.player:facingCell();ow:tryCut(x,y) end
end

function Gen4PartyMenu:actionLabel(action)
  local field=action:match('^field:(.+)$');if field then return Strings(field:gsub('_',' ')) end
  if action == "send" then return Strings("SEND OUT") end
  if action == "summary" then return Strings("SUMMARY") end
  if action == "switch" then return Strings("SWITCH") end
  if action == 'item' then return self:word('item','ITEM') end
  if action == 'give' then return self:word('give','GIVE') end
  if action == 'take' then return self:word('take','TAKE') end
  return Strings("CANCEL")
end

function Gen4PartyMenu:update(dt)
  self.t = (self.t or 0) + (dt or 1 / 60)
  local input = self.game.input
  if not input then return end

  if self.submenu then
    local actions = self:actions()
    local n = #actions
    if input:wasPressed("up") then
      self.submenu = (self.submenu - 2) % n + 1
    elseif input:wasPressed("down") then
      self.submenu = self.submenu % n + 1
    elseif input:wasPressed("a") then
      self:runAction(actions[self.submenu])
    elseif input:wasPressed("b") then
      if self.itemMenu then self.itemMenu=nil;self.submenu=1
      else self.submenu = nil end
    end
    return
  end

  local n = self:count()
  -- Two columns, so left and right step by one and up/down step by two --
  -- which is what the staggered panels read as.
  if input:wasPressed("up") then
    self.index = ((self.index - 3) % n) + 1
  elseif input:wasPressed("down") then
    self.index = ((self.index + 1) % n) + 1
  elseif input:wasPressed("left") or input:wasPressed("right") then
    self.index = (self.index % n) + 1
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.switchFrom then self.switchFrom = nil
    -- B IN A BATTLE IS "BACK TO THE MENU", NOT "I PICK NOTHING".
    --
    -- Out of a battle, handing the answer back as nil is how a caller learns
    -- the player cancelled, and that is right. IN a battle it crashed: the
    -- battle's own onSwitch is written for a Pokemon and went straight into
    -- `mon.hp`. Reported from play as a crash on backing out of the party
    -- screen.
    --
    -- The battle already knows what to do when this screen simply closes --
    -- `afterQueue` put it back in the menu phase before it opened -- so
    -- closing is both the safe answer and the correct one.
    elseif self.onSwitch and not (self.pickOnly or self.forceSwitch)
           and not self.battle then
      self:handOff(nil)
    else
      self:close()
    end
  end
end

-- ------------------------------------------------------------------- draw --

function Gen4PartyMenu:iconFor(mon)
  local data = self.game and self.game.data
  if not (data and mon and mon.species) then return nil end
  local icons = data.icons
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[mon.species])
                or (def and def.icon)
  local path, frameH
  if type(entry) == "table" then
    path, frameH = entry.image, tonumber(entry.frameHeight)
  elseif type(entry) == "string" then
    path = entry
  end
  if not path then return nil end
  frameH = frameH or tonumber(icons and icons.frameHeight) or 32
  if self.icons[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.icons[path] = ok and img or false
    if self.icons[path] then self.icons[path]:setFilter("nearest", "nearest") end
  end
  local img = self.icons[path] or nil
  if not img then return nil end
  return img, frameH
end

function Gen4PartyMenu:drawIcon(mon, x, y)
  local img, frameH = self:iconFor(mon)
  if not img then
    local ball = self:img("party/member_ball_00")
    if ball then love.graphics.draw(ball, x, y) end
    return
  end
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH or ih, ih)
  local frames = math.max(1, math.floor(ih / frameH))
  local frame = frames > 1
    and (math.floor((self.t % (ICON_PERIOD * frames)) / ICON_PERIOD) % frames)
    or 0
  local quad = love.graphics.newQuad(0, frame * frameH, iw, frameH, iw, ih)
  love.graphics.draw(img, quad, x, y)
end

function Gen4PartyMenu:drawSlot(i, mon)
  local g = love.graphics
  local at = SLOTS[i]
  if not at then return end

  if i == self.index then
    local cursor = self:img("party/cursor_00")
    if cursor then
      g.setColor(1, 1, 1, 1)
      g.draw(cursor, at.x, at.y - 2)
    else
      Font.drawCode(Theme.cursor, at.x + 2, at.y + 14)
    end
  end
  if self.switchFrom == i then
    g.setColor(1, 0.9, 0.3, 0.35)
    g.rectangle("fill", at.x + 2, at.y, SLOT_W - 4, SLOT_H)
    g.setColor(1, 1, 1, 1)
  end

  self:drawIcon(mon, at.x + 14, at.y)

  local name = tostring(mon.nickname or mon.name or "")
  if name == "" then
    local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
    name = (def and def.name) or tostring(mon.species)
  end
  Font.draw(Font.fit(name, 72), at.x + 48, at.y + 8)
  if mon.isEgg then return end
  Font.draw(("Lv%d"):format(tonumber(mon.level) or 1), at.x + 4, at.y + 32)

  local hp = tonumber(mon.hp) or 0
  local max = tonumber(mon.maxHp) or tonumber(mon.maxhp) or tonumber(mon.stats and mon.stats.hp) or 0
  -- WITH A MACHINE OPEN THE PANEL ANSWERS THE QUESTION instead of showing the
  -- numbers: what is being chosen is whether this Pokemon can learn the move,
  -- and its current HP has nothing to do with that.  THE BAR STAYS -- it is
  -- the only thing left saying which of them is hurt, and a player picking a
  -- target still wants to know.
  if self.tmhm then
    local word = self:learnWord(mon)
    Font.draw(word, at.x + SLOT_W - Font.width(word) - 6, at.y + 32)
  end
  if max > 0 then
    if not self.tmhm then
      local text = ("%d/%d"):format(hp, max)
      Font.draw(text, at.x + SLOT_W - Font.width(text) - 8, at.y + 32)
    end
    local full = 48
    local share = math.max(0, math.min(1, hp / max))
    g.setColor(0.10, 0.12, 0.16, 1)
    g.rectangle("fill", at.x + 64, at.y + 24, full, 6)
    if share > 0.5 then g.setColor(0.36, 0.85, 0.36, 1)
    elseif share > 0.2 then g.setColor(0.95, 0.82, 0.28, 1)
    else g.setColor(0.92, 0.32, 0.30, 1) end
    g.rectangle("fill", at.x + 64, at.y + 24, math.floor(full * share), 6)
    g.setColor(1, 1, 1, 1)
  end
end

function Gen4PartyMenu:draw()
  local g = love.graphics
  g.setColor(0.08, 0.09, 0.14, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local back = self:img("party/menu")
  if back then g.draw(back, 0, 0) else Font.drawBox(0, 0, 32, 20) end

  local party = self:party()
  for i = 1, math.min(#party, #SLOTS) do
    self:drawSlot(i, party[i])
  end

  -- CANCEL, under the panels.
  Font.drawBox(math.floor(CANCEL.x / 8), math.floor(CANCEL.y / 8),
               math.floor(CANCEL.w / 8), math.floor(CANCEL.h / 8))
  local word = Strings("CANCEL")
  Font.draw(word, CANCEL.x + 12, CANCEL.y + 6)
  if self.index > #party then
    Font.drawCode(Theme.cursor, CANCEL.x + 2, CANCEL.y + 6)
  end

  -- "Teach which Pokemon?" where CANCEL's word is, because with a machine open
  -- the strip along the bottom is the question rather than a row to land on.
  -- The CANCEL box is still drawn and still selectable -- backing out of a
  -- teach is the same press it always was.
  if self.tmhm then
    -- RIGHT-ALIGNED AGAINST THE STRIP'S FAR EDGE and cut to whatever CANCEL
    -- leaves, because the face is proportional and the question is a whole
    -- sentence: placed at a fixed column it runs through CANCEL on exactly the
    -- wordings that are long enough to matter. The same budget rule the Gen 3
    -- panels were rewritten around.
    local prompt = self:word("teachWhich", "Teach which POKéMON?")
    local taken = 12 + Font.width(Strings("CANCEL")) + 12
    local room = CANCEL.w - taken - 12
    if room > 0 then
      local fitted = Font.fit(prompt, room)
      Font.draw(fitted, CANCEL.x + CANCEL.w - Font.width(fitted) - 12,
                CANCEL.y + 6)
    end
  end

  if self.submenu then
    local actions = self:actions()
    local n = #actions
    local boxW, rowH = 112, 16
    local x, y = W - boxW - 8, H - (n * rowH) - 20
    Font.drawBox(math.floor(x / 8), math.floor(y / 8),
                 math.floor(boxW / 8), math.floor((n * rowH + 12) / 8))
    for i, action in ipairs(actions) do
      local ry = y + 6 + (i - 1) * rowH
      if i == self.submenu then Font.drawCode(Theme.cursor, x + 4, ry) end
      Font.draw(self:actionLabel(action), x + 16, ry)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4PartyMenu
