-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's PARTY SCREEN -- the last of the four that were falling back to
-- Kanto's art.
--
-- WHAT IS ON THE TOP SCREEN, from src/applications/party_menu/{main,windows,
-- sprites,context_menu}.c, layer by layer:
--
--   BG3  `party/menu` (menu_tiles / menu.NSCR / menu.NCLR) -- the backdrop
--   BG2  THE PANELS: menu_panels.NSCR's three 16 x 6-tile templates (lead,
--        back, empty), every cell re-coloured to palette 3 + v -- v 0 normal,
--        +4 under the cursor, +2 fainted, 7 while switching.  Composed once per
--        state by src/import/Gen4PartyArt.lua (`gen4_party_art`).
--   text the name at (48, 8) white over 292929, the gender symbol at (112, 8),
--        "Lv" and the level from (5, 34) unless a status icon is there, the HP
--        right-aligned to x 84, "/" at 84, the max from 92 -- the numbers are
--        font_special_chars glyphs (`party/digits`), not text -- and the HP bar
--        from x 64, 48 pixels, rows 26..29.
--   OBJ  the Poke Ball (centre panel + (16, 14)), the species icon (panel +
--        (14, 0); the selected one at + (16, 2) and bouncing), the status icon
--        (panel + (20, 36)), the held item / mail and capsule seal (panel +
--        (30, 24) / (38, 24)), the cursor (panel + (0, 1), sequence 1 on the
--        lead, 0 elsewhere, grey while the submenu is open; + 2 marks the
--        switch source) and the CANCEL button centred on (232, 176).
--
-- The six slots, two columns of three, the right one eight pixels lower:
-- (0,0) (128,8) / (0,48) (128,56) / (0,96) (128,104).
--
-- WHAT THIS SCREEN DOES AND DOES NOT DO, said plainly because the alias in
-- `Screens.lua` is where it matters:
--
--   * THE FIELD PARTY MENU is this screen: the list, the cursor, SUMMARY,
--     the field moves, SWITCH and ITEM.
--   * IN A BATTLE the submenu's top row is SEND OUT (see `new`).
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

-- The six slots, in reading order.
local SLOT_W, SLOT_H = 128, 48
local SLOTS = {
  { x = 0,   y = 0 },   { x = 128, y = 8 },
  { x = 0,   y = 48 },  { x = 128, y = 56 },
  { x = 0,   y = 96 },  { x = 128, y = 104 },
}
Gen4PartyMenu.SLOTS = SLOTS
-- THE CANCEL BUTTON: a 56 x 32 sprite centred on (232, 176), its word
-- centred in (208, 168, 40, 16).
local CANCEL = { x = 200, y = 160, w = 56, h = 32, cx = 232, cy = 176,
                 label = { x = 208, y = 168, w = 40 } }
Gen4PartyMenu.CANCEL = CANCEL
-- The message boxes (DrawMessageBoxFrame around a text window): the short one
-- (window (16, 168) 160 x 16) and, while the submenu is open, the medium one
-- (window (16, 152) 104 x 32).  In the port's rectangle convention.
local SHORT_BOX = { tx = 1, ty = 20, tw = 22, th = 4, x = 16, y = 168 }
local MEDIUM_BOX = { tx = 1, ty = 18, tw = 15, th = 6, x = 16, y = 152 }
-- The submenu: a standard frame from x 144 to 255, its rows 16 apart ending
-- at y 184, the word at x 160 and the arrow at 152.
local MENU = { tx = 18, tw = 14, bottom = 192, textX = 160, arrowX = 152, row = 16 }
Gen4PartyMenu.MENU = MENU
-- the bottom screen's touch buttons, one per occupied slot
local TOUCH = { { 8, 24 }, { 208, 24 }, { 8, 80 }, { 208, 80 }, { 8, 136 }, { 208, 136 } }

-- NAVIGATION, the cartridge's Basic table (0-based slots, 7 = CANCEL):
-- up, down, left, right.
local NAV = {
  [0] = { 7, 2, 7, 1 }, [1] = { 7, 3, 0, 2 }, [2] = { 0, 4, 1, 3 },
  [3] = { 1, 5, 2, 4 }, [4] = { 2, 7, 3, 5 }, [5] = { 3, 7, 4, 7 },
  [7] = { 5, 1, 5, 0 },
}
Gen4PartyMenu.NAV = NAV
local DIRS = { up = 1, down = 2, left = 3, right = 4 }

-- The field moves this screen can run, in the order Gen4FieldMoves knows them.
-- The submenu lists them in the MON'S MOVE-SLOT ORDER, as the cartridge does.

local ICON_PERIOD = 0.32

function Gen4PartyMenu:uiSize() return W, H end
function Gen4PartyMenu:wantsFillScale() return true end
function Gen4PartyMenu:wantsEdgeBleed() return false end

function Gen4PartyMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

local function unit(c, fallback)
  c = c or fallback
  return { c[1] / 255, c[2] / 255, c[3] / 255 }
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
  -- The alias in Screens.lua left `battle` out on purpose, but a declined
  -- Gen 4 push does not fall through to Hoenn's screen on a Gen 4 cache:
  -- Screens.resolveId returns early unless isGen3(game), so it fell all the
  -- way to the Game Boy one.
  --
  -- The screen serves it now, and the one thing that had to change to make
  -- that honest is the submenu. Out of a battle the first row is SUMMARY and
  -- SWITCH reorders the party. IN a battle, pressing POKeMON and choosing a
  -- member has to SEND IT OUT -- reordering would be a dead end.
  self.battle = opts.battle
  -- THE MACHINE THAT IS OPEN.  `{ move, kind }`, put there by BagMenu.useOn
  -- for any item with a `machine` record.
  self.tmhm = opts.tmhm
  self.index = 1
  self.t = 0
  self.cache = {}
  self.icons = {}
  local data = game.data or {}
  self.art = (data.gen4_graphics or {}).screens or {}
  -- the panels, sprites and digits (src/import/Gen4PartyArt.lua)
  self.partyArt = data.gen4_party_art or {}
  -- menu.NCLR's colours (Gen4PartyArt.ink); a cache without the module gets
  -- the same numbers from the same function's defaults
  local okInk, PartyArt = pcall(require, "src.import.Gen4PartyArt")
  local ink = data.gen4_party_ink
  if type(ink) ~= "table" or not ink.text then ink = okInk and PartyArt.ink(nil) or {} end
  self.ink = {
    name = { text = unit(ink.text, { 255, 255, 255 }), shadow = unit(ink.shadow, { 41, 41, 41 }) },
    male = { text = unit(ink.blue, { 0, 115, 255 }), shadow = unit(ink.blueShadow, { 123, 189, 238 }) },
    female = { text = unit(ink.red, { 238, 32, 16 }), shadow = unit(ink.redShadow, { 255, 172, 189 }) },
    green = { unit((ink.hpGreen or {})[1], { 98, 255, 98 }), unit((ink.hpGreen or {})[2], { 24, 197, 32 }) },
    yellow = { unit((ink.hpYellow or {})[1], { 255, 222, 0 }), unit((ink.hpYellow or {})[2], { 238, 172, 0 }) },
    red = { unit((ink.hpRed or {})[1], { 255, 156, 156 }), unit((ink.hpRed or {})[2], { 255, 74, 57 }) },
  }
  -- the field moves' rows are drawn in the male symbol's blue (TEXT_COLOR of
  -- the context menu's FieldMove entries, `{COLOR 1}`)
  self.ink.field = self.ink.male
  -- The cartridge's own words.  Nothing here falls back to English except
  -- through Strings(), which is the engine's own translation seam.
  self.words = ((data.gen4_menus or {}).partyMenu or {}).text or {}
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
-- screen can never disagree with what pressing A does.
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

local function loadImage(cache, path)
  if type(path) ~= "string" then return nil end
  if cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    cache[path] = ok and img or false
    if cache[path] then cache[path]:setFilter("nearest", "nearest") end
  end
  return cache[path] or nil
end

function Gen4PartyMenu:img(key)
  local rec = self.art[key]
  return loadImage(self.cache, (type(rec) == "table" and rec.path) or rec)
end

-- a picture from `gen4_party_art`, and its record (for the origin)
function Gen4PartyMenu:partImg(key)
  local rec = self.partyArt[key]
  if type(rec) ~= "table" then return nil end
  return loadImage(self.cache, rec.path), rec
end

-- A sprite drawn from its centre, the way the cartridge positions one: the
-- record's origin is the cell's extent.
function Gen4PartyMenu:drawSprite(key, cx, cy)
  local img, rec = self:partImg(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, cx + (rec.originX or 0), cy + (rec.originY or 0))
  return true
end

function Gen4PartyMenu:drawAt(key, x, y)
  local img = self:partImg(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y)
  return true
end

function Gen4PartyMenu:party() return self.game.save.party or {} end

-- Slots 1..#party, then CANCEL.
function Gen4PartyMenu:count() return #self:party() + 1 end
function Gen4PartyMenu:onCancelRow() return self.index > #self:party() end

-- The submenu's frame, in pixels: rows 16 apart ending at y 184.
function Gen4PartyMenu:menuRect(n)
  local top = MENU.bottom - 8 - MENU.row * n
  return { x = MENU.tx * 8, y = top - 8, w = MENU.tw * 8, h = MENU.row * n + 16, firstRow = top }
end

function Gen4PartyMenu:touchpressed(_, px, py)
  local r=require('src.render.Renderer').uiPresentation
  if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
  local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
  if self.submenu then
    local actions=self:actions()
    local m=self:menuRect(#actions)
    if x>=m.x and x<m.x+m.w and y>=m.firstRow and y<m.firstRow+#actions*MENU.row then
      self:runAction(actions[math.floor((y-m.firstRow)/MENU.row)+1])
    else self.submenu=nil;self.itemMenu=nil end
    return true
  end
  if x>=CANCEL.x and x<CANCEL.x+CANCEL.w and y>=CANCEL.y and y<CANCEL.y+CANCEL.h then
    self.index=self:count();self:choose();return true
  end
  for i,at in ipairs(SLOTS) do
    if x>=at.x and x<at.x+SLOT_W and y>=at.y and y<at.y+SLOT_H and self:party()[i] then
      self.index=i;self:choose();return true
    end
  end
  return true
end

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
    if self.hpTransfer then self.hpTransfer = nil return end
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
  if self.hpTransfer then return self:finishHpTransfer() end
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
    -- rejects an egg, a fainted member and one already standing on the field.
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

-- THE SUBMENU, in the cartridge's order (context_menu.c): SUMMARY, the field
-- moves in the order the Pokemon KNOWS them, SWITCH, ITEM (or MAIL), CANCEL;
-- an egg gets SUMMARY, SWITCH and CANCEL.
function Gen4PartyMenu:actions()
  if self.itemMenu then return {'give','take','cancel'} end
  if self.battle then return Gen4PartyMenu.BATTLE_ACTIONS end
  local rows={'summary'}
  local F=require('src.world.Gen4FieldMoves');local mon=self:party()[self.index]
  local egg=require('src.pokemon.Party').isEgg(mon)
  -- EVERY FIELD MOVE THE POKEMON KNOWS, in move-slot order
  -- (GetContextMenuEntriesForPartyMon walks MON_DATA_MOVE1..4 through
  -- GetFieldMoveIndex): the list does not ask about badges or the weather --
  -- that is the CHECK's question, asked when the row is chosen, and a "This
  -- can't be used until a new Badge is obtained." is the cartridge's answer.
  if mon and not egg then
    local seen={}
    for _,slot in ipairs(mon.moves or {}) do
      local id=(type(slot)=='table' and (slot.id or slot.move)) or slot
      for _,name in ipairs(F.ORDER) do
        if not seen[name] and (F.ids[name]==id or name==id) then
          rows[#rows+1]='field:'..name;seen[name]=true;break
        end
      end
    end
  end
  rows[#rows+1]='switch'
  if not egg then rows[#rows+1]='item' end
  rows[#rows+1]='cancel';return rows
end

-- THE CHECK (field_move_tasks.c FieldMoves_Check*) and its answer. A refused
-- move prints the party menu's own line (PartyMenu_SelectFieldMove): 104
-- "You can't use that here.", 76 "This can't be used until a new Badge is
-- obtained.", 196 "You can't use that when you have someone with you.", 102
-- "You're already surfing."
Gen4PartyMenu.FIELD_ERROR = { location = 104, badge = 76, partner = 196, surfing = 102 }
local FIELD_ERROR_TEXT = {
  [104] = "You can't use that here.", [76] = "This can't be used until a new Badge is obtained.",
  [196] = "You can't use that when you have someone with you.", [102] = "You're already surfing.",
  [138] = "Not enough HP...", [131] = "This can't be used on that Pokémon.",
}
function Gen4PartyMenu:bankLine(n)
  local T = require('src.import.Gen4Text')
  local text = self.game.data and self.game.data.text and self.game.data.text[T.label(453, n)]
  return (type(text) == 'string' and text ~= '') and text or Strings(FIELD_ERROR_TEXT[n] or "")
end
function Gen4PartyMenu:fieldRefused(why)
  local n = Gen4PartyMenu.FIELD_ERROR[why] or 104
  self.game.stack:push(require('src.render.TextBox').new(self.game, self:bankLine(n)))
end

-- the object the player faces, and its graphics id (sub_0203C9D4 +
-- FieldMoves_SetUsableMoves): 84 a Strength boulder, 85 a Rock Smash rock,
-- 86 a Cut tree
Gen4PartyMenu.OBSTACLE = { STRENGTH = 84, ROCK_SMASH = 85, CUT = 86 }
function Gen4PartyMenu:facingObject()
  local ow = self.game.overworld
  if not (ow and ow.player and ow.npcAtCell) then return nil end
  local x, y = ow.player:facingCell()
  local npc = ow:npcAtCell(x, y)
  local gfx = npc and tonumber(npc.graphicsId or (npc.def and npc.def.graphicsId))
  return npc, gfx
end

function Gen4PartyMenu:facingBehaviour()
  local ow = self.game.overworld
  if not (ow and ow.map and ow.map.cellBehaviour and ow.player) then return nil end
  local x, y = ow.player:facingCell()
  local value = ow.map:cellBehaviour(x, y)
  return value and require('src.import.Gen4Behaviors').name(value)
end

-- the field move's script, run as the cartridge's task does: ScriptManager_
-- Change(FIELD_MOVES, n, facing object) and FieldSystem_SetScriptParameters
-- (party slot) -- VAR_0x8000 the slot, VAR_LAST_TALKED (0x800D) the object
function Gen4PartyMenu:runFieldScript(band, entry, npc)
  local ow = self.game.overworld
  local TS = require('src.world.Gen4TileScripts')
  local rows, why = TS.compile(self.game.data, band, entry)
  if not rows then
    require('src.core.Logger').warn('gen4 field move: %s %d -- %s', band, entry, tostring(why))
    return self:fieldRefused('location')
  end
  local C = require('src.script.Gen4Commands')
  if C.setVar then
    C.setVar(self.game.save, 0x8000, self.index - 1)
    local lid = npc and (npc.localId or (npc.def and npc.def.localId))
    if lid then C.setVar(self.game.save, 0x800D, lid) end
  end
  self:close()
  ow.runner:run(rows, { npc = npc, mapId = ow.map and ow.map.id })
end

-- MILK DRINK AND SOFTBOILED (PartyMenu_StartFieldMoveHPTransfer): a fifth of
-- the user's max HP, refused with "Not enough HP..." when it has no more than
-- that; then "Use on which Pokemon?", and the target must be another member,
-- not fainted, not full, not an egg.
function Gen4PartyMenu:startHpTransfer(mon)
  local give = math.floor((tonumber(mon.maxHp or mon.maxhp or (mon.stats and mon.stats.hp)) or 0) / 5)
  if (tonumber(mon.hp) or 0) <= give then
    self.game.stack:push(require('src.render.TextBox').new(self.game, self:bankLine(138)))
    return
  end
  self.hpTransfer = { from = self.index, amount = give }
end

function Gen4PartyMenu:finishHpTransfer()
  local t = self.hpTransfer
  local party = self:party()
  local giver, target = party[t.from], party[self.index]
  if not target or self.index == t.from then self.hpTransfer = nil return end
  local isEgg = require('src.pokemon.Party').isEgg(target)
  if isEgg then return end
  local max = tonumber(target.maxHp or target.maxhp or (target.stats and target.stats.hp)) or 0
  local hp = tonumber(target.hp) or 0
  if hp == 0 or hp >= max then
    self.game.stack:push(require('src.render.TextBox').new(self.game, self:bankLine(131)))
    return
  end
  local amount = math.min(t.amount, max - hp)
  giver.hp = (tonumber(giver.hp) or 0) - amount
  target.hp = hp + amount
  self.hpTransfer = nil
  -- 64 "{name}'s HP was restored by {n} point(s)."
  local T = require('src.import.Gen4Text')
  T.buffer(self.game, self:monName(target), tostring(amount))
  local line = T.resolve(self.game.data, 453, 64, self.game)
    or Strings("%s's HP was restored by %d point(s).", self:monName(target), amount)
  self.game.stack:push(require('src.render.TextBox').new(self.game, line))
end

-- the slot a SWITCH or an HP transfer is moving from: both mark it the same
-- way (inTargetSlotMode -- variant 7 and the source marker)
function Gen4PartyMenu:markedSlot()
  return self.switchFrom or (self.hpTransfer and self.hpTransfer.from) or nil
end

function Gen4PartyMenu:useFieldMove(mon,move)
  local ow=self.game.overworld;local F=require('src.world.Gen4FieldMoves')
  local save=self.game.save
  local function badge() return F.badgeHeld(self.game.data,save,move) end
  local partner=require('src.world.Gen4Follower').hasPartner(save)
  if move=='MILK_DRINK' or move=='SOFTBOILED' then return self:startHpTransfer(mon) end
  if not ow then return self:fieldRefused('location') end
  -- CUT, ROCK SMASH, STRENGTH: the badge, then the object faced
  local obstacle=Gen4PartyMenu.OBSTACLE[move]
  if obstacle then
    if F.badges[move] and not badge() then return self:fieldRefused('badge') end
    if move=='ROCK_SMASH' and ow.player.surfing then return self:fieldRefused('location') end
    local npc,gfx=self:facingObject()
    if gfx~=obstacle then return self:fieldRefused('location') end
    local entry=move=='CUT' and 8 or move=='ROCK_SMASH' and 9 or 10
    return self:runFieldScript('field_moves',entry,npc)
  end
  if move=='WATERFALL' then
    if not badge() then return self:fieldRefused('badge') end
    if self:facingBehaviour()~='WATERFALL' then return self:fieldRefused('location') end
    return self:runFieldScript('field_moves',13)
  end
  if move=='ROCK_CLIMB' then
    if not badge() then return self:fieldRefused('badge') end
    local b=self:facingBehaviour()
    local facing=ow.player.facing
    local ns=(facing=='up' or facing=='down') and b=='ROCK_CLIMB_N_S'
    local ew=(facing=='left' or facing=='right') and b=='ROCK_CLIMB_E_W'
    if not (ns or ew) then return self:fieldRefused('location') end
    if partner then return self:fieldRefused('partner') end
    return self:runFieldScript('field_moves',11)
  end
  -- CHATTER records the player's voice as Chatot's cry (SCRIPT_ID(RECORD_
  -- CHATOT_CRY, 0) and the microphone). With no microphone the recording
  -- commands are not lowered, so the port plays the cry as it stands.
  if move=='CHATTER' then
    local ok,Sound=pcall(require,'src.core.Sound')
    if ok and Sound.playCry then pcall(Sound.playCry,self.game.data,mon.species) end
    return
  end
  -- FLASH AND DEFOG: offered by the weather (FieldMoves_SetUsableMoves), run
  -- through `scripts_field_moves.s` entries 15 and 14
  local wm=F.WEATHER_MOVES[move]
  if wm then
    if move=='DEFOG' and not badge() then return self:fieldRefused('badge') end
    if not F.weatherOffers(save,move) then return self:fieldRefused('location') end
    return self:runFieldScript('field_moves',wm.entry)
  end
  -- FLY (src/world/Gen4Fly.lua): FieldMoves_CheckFly, then a destination
  if move=='FLY' then
    if not badge() then return self:fieldRefused('badge') end
    if partner then return self:fieldRefused('partner') end
    local Fly=require('src.world.Gen4Fly')
    local ok=Fly.check(self.game.data,save,ow.map and ow.map.def)
    local dests=ok and Fly.destinations(self.game.data,save) or {}
    if not ok or #dests==0 then return self:fieldRefused('location') end
    local game=self.game
    self:close()
    -- PLATINUM'S TOWN MAP IN FLY MODE (src/ui/Gen4TownMap.lua); the list is
    -- the fallback for a cache without the town map's data
    if game.data.gen4_town_map then
      game.stack:push(require('src.ui.Gen4TownMap').new(game,{mode='fly',
        onFly=function(firstArrival)
          local dest=Fly.destinationFor(game.data,firstArrival)
          if dest then ow:gen4FlyTo(dest,mon) end
        end}))
      return
    end
    local items={}
    for _,d in ipairs(dests) do items[#items+1]={value=d,label=d.label} end
    game.stack:push(require('src.ui.ListMenu').new(game,"FLY TO?",items,{
      onChoose=function(item,list) list:close();ow:gen4FlyTo(item.value,mon) end,
    }))
    return
  end
  if move=='SURF' then
    if not badge() then return self:fieldRefused('badge') end
    if ow.player.surfing then return self:fieldRefused('surfing') end
    if partner then return self:fieldRefused('partner') end
    if ow:useSurfFieldMove()~='ok' then return self:fieldRefused('location') end
    self:close()
    local x,y=ow.player:facingCell();ow:trySurf(x,y)
    return
  end
  local usable=true
  if move=='DIG' then usable=ow.map.def.allowEscapeRope and ow:escapePoint()
  elseif move=='TELEPORT' then usable=ow.map.def.allowFly and save.lastHeal
    -- PlayerInSafariZoneOrPalPark: no Teleport out of a Safari Game
    and not save.safari
  elseif move=='SWEET_SCENT' then
    local enc=require('src.world.Encounter').forMap(self.game.data,ow.map.def,ow.map.id)
    usable=enc and (ow.player.surfing and enc.water or enc.grass)
  end
  if (move=='DIG' or move=='TELEPORT') and partner then return self:fieldRefused('partner') end
  if not usable then return self:fieldRefused('location') end
  self:close()
  if move=='DIG' then ow:beginTeleportOut(nil,{escape=true})
  elseif move=='TELEPORT' then ow:beginTeleportOut()
  elseif move=='SWEET_SCENT' then ow:gen4SweetScent() end
end

-- A field move's row is the MOVE'S NAME (STRVAR 6), from the cache's move
-- records when it has them.
function Gen4PartyMenu:fieldMoveName(name)
  local F=require('src.world.Gen4FieldMoves')
  local moves=self.game.data and self.game.data.moves
  local rec=moves and moves[F.ids[name]]
  if type(rec)=='table' and type(rec.name)=='string' and rec.name~='' then return rec.name end
  return Strings((name:gsub('_',' ')))
end

function Gen4PartyMenu:actionLabel(action)
  local field=action:match('^field:(.+)$');if field then return self:fieldMoveName(field) end
  if action == "send" then return Strings("SEND OUT") end
  if action == "summary" then return self:word('summary','SUMMARY') end
  if action == "switch" then return self:word('switch','SWITCH') end
  if action == 'item' then return self:word('item','ITEM') end
  if action == 'give' then return self:word('give','GIVE') end
  if action == 'take' then return self:word('take','TAKE') end
  return self:word('cancel','CANCEL')
end

-- One step of the cursor, by the cartridge's table; an empty slot is passed
-- over in the same direction.
function Gen4PartyMenu:step(dir)
  local party = self:party()
  local at = self:onCancelRow() and 7 or (self.index - 1)
  for _ = 1, 8 do
    local row = NAV[at]
    if not row then return end
    at = row[DIRS[dir]]
    if at == 7 then self.index = self:count() return end
    if party[at + 1] then self.index = at + 1 return end
  end
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

  if input:wasPressed("up") then self:step("up")
  elseif input:wasPressed("down") then self:step("down")
  elseif input:wasPressed("left") then self:step("left")
  elseif input:wasPressed("right") then self:step("right")
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.switchFrom then self.switchFrom = nil
    elseif self.hpTransfer then self.hpTransfer = nil
    -- B IN A BATTLE IS "BACK TO THE MENU", NOT "I PICK NOTHING".
    --
    -- Out of a battle, handing the answer back as nil is how a caller learns
    -- the player cancelled, and that is right. IN a battle it crashed: the
    -- battle's own onSwitch is written for a Pokemon and went straight into
    -- `mon.hp`.  The battle already knows what to do when this screen simply
    -- closes, so closing is both the safe answer and the correct one.
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
  -- AN EGG SHOWS THE EGG (pl_poke_icon's SPECIES_EGG 494, Manaphy's 495),
  -- not the species inside it
  if require('src.pokemon.Party').isEgg(mon) and icons and icons.bySpecies then
    entry = icons.bySpecies[mon.species == 490 and 495 or 494] or entry
  end
  local path, frameH
  if type(entry) == "table" then
    path, frameH = entry.image, tonumber(entry.frameHeight)
  elseif type(entry) == "string" then
    path = entry
  end
  if not path then return nil end
  frameH = frameH or tonumber(icons and icons.frameHeight) or 32
  local img = loadImage(self.icons, path)
  if not img then return nil end
  return img, frameH
end

-- `still`: the icon holds its first frame (fainted, or being switched).
-- Returns the frame drawn, which is what decides the bounce.
function Gen4PartyMenu:iconFrame(mon, still)
  local img, frameH = self:iconFor(mon)
  if not img then return 0 end
  local _, ih = img:getDimensions()
  frameH = math.min(frameH or ih, ih)
  local frames = math.max(1, math.floor(ih / frameH))
  if still or frames < 2 then return 0 end
  return math.floor((self.t % (ICON_PERIOD * frames)) / ICON_PERIOD) % frames
end

function Gen4PartyMenu:drawIcon(mon, x, y, frame)
  local img, frameH = self:iconFor(mon)
  if not img then
    local ball = self:img("party/member_ball_00")
    if ball then love.graphics.draw(ball, x, y) end
    return
  end
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH or ih, ih)
  local quad = love.graphics.newQuad(0, (frame or 0) * frameH, iw, frameH, iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, x, y)
end

local function isEgg(mon) return require('src.pokemon.Party').isEgg(mon) end

local function hpOf(mon)
  local hp = tonumber(mon.hp) or 0
  local max = tonumber(mon.maxHp) or tonumber(mon.maxhp) or tonumber(mon.stats and mon.stats.hp) or 0
  return hp, max
end

-- The summary's condition numbering (SUMMARY_CONDITION_*): 0 Pokerus, 1 PAR,
-- 2 FRZ, 3 SLP, 4 PSN, 5 BRN, 6 fainted; nil for none.
function Gen4PartyMenu:statusIcon(mon)
  if isEgg(mon) then return nil end
  local hp, max = hpOf(mon)
  if max > 0 and hp == 0 then return 6 end
  local status = tostring(mon.status or ''):upper()
  local indices = { PAR=1, PARALYSIS=1, FRZ=2, FREEZE=2, SLP=3, SLEEP=3,
    PSN=4, TOX=4, POISON=4, TOXIC=4, BRN=5, BURN=5 }
  if indices[status] then return indices[status] end
  local virus = tonumber(mon.pokerus or mon.gen4Pokerus or mon.gen3Pokerus) or 0
  if virus % 16 > 0 then return 0 end
  return nil
end

-- the panel's state (Gen4PartyArt's v)
function Gen4PartyMenu:panelVariant(i, mon)
  local marked = self:markedSlot()
  if marked and (marked == i or self.index == i) then return 7 end
  local v = (self.index == i) and 4 or 0
  local hp, max = hpOf(mon)
  if not isEgg(mon) and max > 0 and hp == 0 then v = v + 2 end
  return v
end

-- font_special_chars, from `party/digits`: 0-9 at 8 each, "/" at 80, "Lv" at 88
function Gen4PartyMenu:glyph(column, width, x, y)
  local img = self:partImg("digits")
  if not img then return false end
  local iw, ih = img:getDimensions()
  self.quads = self.quads or {}
  local key = column .. ":" .. width
  self.quads[key] = self.quads[key] or love.graphics.newQuad(column * 8, 0, width, 8, iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, self.quads[key], x, y)
  return true
end

function Gen4PartyMenu:number(value, x, y)
  local text = tostring(math.floor(value))
  if not self:partImg("digits") then
    Font.pushStyle(self.ink.name); Font.draw(text, x, y - 2); Font.popStyle()
    return
  end
  for k = 1, #text do self:glyph(text:byte(k) - 48, 8, x + (k - 1) * 8, y) end
end

function Gen4PartyMenu:drawHpBar(at, hp, max)
  local g = love.graphics
  local px = math.floor(hp * 48 / max)
  if hp > 0 and px < 1 then px = 1 end
  if px <= 0 then return end
  local pair = (hp == max or px > 24) and self.ink.green
    or (px >= 10 and self.ink.yellow) or self.ink.red
  local light, dark = pair[1], pair[2]
  local x = at.x + 64
  g.setColor(dark[1], dark[2], dark[3], 1)
  g.rectangle("fill", x, at.y + 26, px, 1)
  g.rectangle("fill", x, at.y + 29, px, 1)
  g.setColor(light[1], light[2], light[3], 1)
  g.rectangle("fill", x, at.y + 27, px, 2)
  g.setColor(1, 1, 1, 1)
end

function Gen4PartyMenu:monName(mon)
  local name = tostring(mon.nickname or mon.name or "")
  if name == "" then
    local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
    name = (def and def.name) or tostring(mon.species)
  end
  return name
end

function Gen4PartyMenu:isMail(item)
  local items = self.game.data and self.game.data.items
  local rec = items and items[item]
  if type(rec) ~= "table" then return false end
  return rec.pocket == "MAIL" or rec.fieldPocket == 5
end

-- BG2 and the text windows: the panel, its words, numbers and HP bar
function Gen4PartyMenu:drawPanel(i, mon)
  local at = SLOTS[i]
  if not mon then
    self:drawAt("panel_none", at.x, at.y)
    return
  end
  local egg = isEgg(mon)
  local v = self:panelVariant(i, mon)
  local key = ("panel_%s%s_%d"):format(i == 1 and "lead" or "back", egg and "_egg" or "", v)
  self:drawAt(key, at.x, at.y)

  Font.pushStyle(self.ink.name)
  Font.draw(Font.fit(self:monName(mon), 64), at.x + 48, at.y + 8)
  Font.popStyle()
  if egg then return end

  local gender = require("src.pokemon.DayCare").gender(self.game.data, mon)
  if gender == "male" or gender == "female" then
    Font.pushStyle(self.ink[gender])
    Font.draw(self:word(gender, gender == "male" and "♂" or "♀"), at.x + 112, at.y + 8)
    Font.popStyle()
  end

  if not self:statusIcon(mon) then
    if not self:glyph(11, 16, at.x + 5, at.y + 34) then
      Font.pushStyle(self.ink.name); Font.draw("Lv", at.x + 5, at.y + 32); Font.popStyle()
    end
    self:number(tonumber(mon.level) or 1, at.x + 21, at.y + 34)
  end

  if self.tmhm then
    -- WITH A MACHINE OPEN THE PANEL ANSWERS THE QUESTION instead of showing
    -- the numbers and the bar.
    Font.pushStyle(self.ink.name)
    Font.draw(self:learnWord(mon), at.x + 48, at.y + 32)
    Font.popStyle()
    return
  end
  local hp, max = hpOf(mon)
  if max > 0 then
    local cur = tostring(math.floor(hp))
    self:number(hp, at.x + 84 - 8 * #cur, at.y + 34)
    if not self:glyph(10, 8, at.x + 84, at.y + 34) then
      Font.pushStyle(self.ink.name); Font.draw("/", at.x + 84, at.y + 32); Font.popStyle()
    end
    self:number(max, at.x + 92, at.y + 34)
    self:drawHpBar(at, hp, max)
  end
end

-- the sprites on a panel: ball, icon, status, held item / seal
function Gen4PartyMenu:drawPanelSprites(i, mon)
  local at = SLOTS[i]
  local selected = (self.index == i)
  if not self:drawSprite(selected and "ball_1" or "ball_0", at.x + 16, at.y + 14) then
    local ball = self:img(selected and "party/member_ball_01" or "party/member_ball_00")
    if ball then love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(ball, at.x, at.y - 2) end
  end

  local status = self:statusIcon(mon)
  local hp, max = hpOf(mon)
  local fainted = not isEgg(mon) and max > 0 and hp == 0
  local marked = self:markedSlot()
  local switching = marked and (marked == i or self.index == i)
  local still = fainted or switching
  local frame = self:iconFrame(mon, still)
  local x, y = at.x + 14, at.y
  if selected then
    x, y = at.x + 16, at.y + 2
    -- the bounce, for a member neither fainted nor statused
    if not still and not (status and status ~= 0) then
      y = y + ((frame == 0) and -3 or 1)
    end
  end
  self:drawIcon(mon, x, y, frame)

  if status then self:drawAt("status_" .. status, at.x + 20, at.y + 36) end
  if mon.item and mon.item ~= 0 then
    self:drawAt(self:isMail(mon.item) and "held_mail" or "held_item", at.x + 30, at.y + 24)
  end
  local seal = tonumber(mon.ballCapsule or mon.capsule or mon.cbSeal) or 0
  if seal > 0 then self:drawAt("held_seal", at.x + 38, at.y + 24) end
end

function Gen4PartyMenu:drawCursor()
  if self:onCancelRow() then return end
  local at = SLOTS[self.index]
  if not at then return end
  local row = self.submenu and 1 or 0
  local seq = (self.index == 1) and 1 or 0
  if not self:drawAt(("cursor_%d_%d"):format(seq, row), at.x, at.y + 1) then
    local cursor = self:img(seq == 1 and "party/cursor_01" or "party/cursor_00")
    if cursor then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(cursor, at.x, at.y + 1)
    else
      Font.drawCode(Theme.cursor, at.x + 2, at.y + 14)
    end
  end
  -- the switch source's marker: the same shape, sequence + 2
  local marked = self:markedSlot()
  if marked and SLOTS[marked] then
    local from = SLOTS[marked]
    local s = (marked == 1) and 3 or 2
    self:drawAt(("cursor_%d_0"):format(s), from.x, from.y + 1)
  end
end

function Gen4PartyMenu:drawCancel()
  local selected = self:onCancelRow()
  if not self:drawSprite(selected and "button_1" or "button_0", CANCEL.cx, CANCEL.cy) then
    Font.drawBox(25, 20, 7, 4)
    if selected then Font.drawCode(Theme.cursor, CANCEL.x + 2, CANCEL.label.y) end
  end
  local word = self:word("cancelButton", "CANCEL")
  Font.pushStyle(self.ink.name)
  Font.draw(word, CANCEL.label.x + math.floor((CANCEL.label.w - Font.width(word)) / 2), CANCEL.label.y)
  Font.popStyle()
end

local function messageBox(box)
  if Font.hasDialogueFrame and Font.hasDialogueFrame() then
    Font.drawDialogueBox(box.tx, box.ty, box.tw, box.th)
  else
    Font.drawBox(box.tx, box.ty, box.tw, box.th)
  end
end

-- the question at the bottom: why the screen was opened, or what to do with
-- the member the submenu is open on
function Gen4PartyMenu:prompt()
  if self.switchFrom then return self:word("moveWhere", "Move to where?") end
  if self.hpTransfer then return self:word("useOn", "Use on which Pokémon?") end
  if self.tmhm then return self:word("teachWhich", "Teach which POKéMON?") end
  if self.pickOnly then return self:word("useOn", "Use on which Pokémon?") end
  return self:word("choose", "Choose a Pokémon.")
end

function Gen4PartyMenu:drawMessage()
  if self.submenu then
    messageBox(MEDIUM_BOX)
    local mon = self:party()[self.index]
    local text
    if self.itemMenu then
      text = self:word("promptItem", "Do what with\nan item?")
    else
      local said = self.words.promptPokemon
      local name = mon and self:monName(mon) or ""
      if type(said) == "string" and said ~= "" then
        -- buffered and expanded the way every Gen 4 line is, not a gsub
        require("src.import.Gen4Text").buffer(self.game, name)
        local okC, Commands = pcall(require, "src.script.Commands")
        local okM, plain = false, nil
        if okC and Commands.gen4Markup then okM, plain = pcall(Commands.gen4Markup, said, self.game) end
        text = (okM and type(plain) == "string") and plain or Strings("Do what with\n%s?", name)
      else
        text = Strings("Do what with\n%s?", name)
      end
    end
    local y = MEDIUM_BOX.y
    for line in (tostring(text):gsub("{[^}]*}", "") .. "\n"):gmatch("([^\n]*)\n") do
      if y < MEDIUM_BOX.y + 32 then Font.draw(Font.fit(line, 104), MEDIUM_BOX.x, y) end
      y = y + 16
    end
    return
  end
  messageBox(SHORT_BOX)
  Font.draw(Font.fit(self:prompt(), 160), SHORT_BOX.x, SHORT_BOX.y)
end

function Gen4PartyMenu:drawSubmenu()
  local actions = self:actions()
  local n = #actions
  local m = self:menuRect(n)
  Font.drawBox(MENU.tx, m.y / 8, MENU.tw, n * 2 + 2)
  for i, action in ipairs(actions) do
    local ry = m.firstRow + (i - 1) * MENU.row
    if i == self.submenu then Font.drawCode(Theme.cursor, MENU.arrowX, ry) end
    local field = action:match('^field:')
    if field then Font.pushStyle(self.ink.field) end
    Font.draw(self:actionLabel(action), MENU.textX, ry)
    if field then Font.popStyle() end
  end
end

-- the bottom screen: the backdrop and a touch button per member
function Gen4PartyMenu:drawSubscreen()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return end
  local mode = SS.mode(self.game)
  if not ((mode == "display" or mode == "inset") and not SS.stowed(self.game)) then return end
  local back = self:img("party/subscreen")
  if not back then return end
  local party = self:party()
  SS.draw(self.game, function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(back, 0, 0)
    for i, p in ipairs(TOUCH) do
      -- touch_ball_2 is the PRESSED face, which only a touch shows
      if party[i] then self:drawAt("touch_ball_0", p[1], p[2]) end
    end
  end)
end

function Gen4PartyMenu:draw()
  local g = love.graphics
  g.setColor(0.08, 0.09, 0.14, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local back = self:img("party/menu")
  if back then g.draw(back, 0, 0) else Font.drawBox(0, 0, 32, 20) end

  local party = self:party()
  for i = 1, #SLOTS do self:drawPanel(i, party[i]) end
  self:drawCursor()
  for i = 1, math.min(#party, #SLOTS) do self:drawPanelSprites(i, party[i]) end

  self:drawCancel()
  self:drawMessage()
  if self.submenu then self:drawSubmenu() end
  self:drawSubscreen()
  g.setColor(1, 1, 1, 1)
end

return Gen4PartyMenu
