-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's party screen.
--
-- Not the Gen 2 list.  That screen is six rows down a Game Boy letterbox;
-- this one is six PANELS on a 240x160 GBA screen, with the lead one large on
-- the left and the other five stacked to its right, and a CANCEL button in
-- the corner.  The shape is the point: on the cartridge you can see at a
-- glance which one is out front.
--
-- WHAT THE CARTRIDGE SUPPLIES is the vocabulary, found the same way the
-- START menu's was -- a run of labels sitting end to end in the text region:
--
--   SHIFT  SEND OUT  SWITCH  SUMMARY  MOVES  ENTER  NO ENTRY  TAKE  READ
--   TRADE
--
-- That run is battle entries and field entries together, so which of them a
-- given press offers is a decision this file makes; the WORDS are not
-- invented, which is the half that would otherwise be wrong in a way nobody
-- would notice.
--
-- IN BATTLE the same screen answers, and it has to: a Hoenn player who
-- pressed POKeMON mid-fight was getting Kanto's six-row Game Boy list, in
-- the middle of an Emerald battle, because this screen only knew how to be
-- opened from the START menu.  The three shapes the battle asks for are the
-- cartridge's own, and the run above names two of them:
--
--   * a VOLUNTARY switch (POKeMON from the battle menu) offers SHIFT --
--     one mon is already out, and the pick takes its place
--   * a FORCED one (the mon fainted) offers SEND OUT, and the pick is
--     immediate: Emerald does not stop to ask
--   * an ITEM's target (`pickOnly`) is picked with no submenu at all
--
-- SHIFT and SEND OUT being two different words for what looks like the same
-- action is exactly the sort of thing that would have been written as one,
-- and the cartridge lists them separately.
--
-- What is NOT derived is the geometry.
--
-- THE ICONS ARE, NOW.  The little bouncing sprites were the one sheet the
-- import never opened -- gMonIconTable, six shared palettes, two frames each
-- -- so a Hoenn party was six panels of text with a blank where the Pokemon
-- should be.  extractMonIcons writes them and icons.bySpecies names them; the
-- bounce below is this port's, since the cartridge's is a sprite-callback
-- rather than data.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3PartyMenu = {}
Gen3PartyMenu.__index = Gen3PartyMenu

local GBA_W, GBA_H = 240, 160

-- THE PANELS ARE THE CARTRIDGE'S NOW.
--
-- They used to be four numbers chosen here -- a wide box in the top-left, a
-- column of five down the right -- drawn with this port's own frame on a
-- flat fill.  Emerald keeps two tables and they agree with each other, which
-- is what says both are read right:
--
--   sPartyMenuWindowTemplates (0615810) gives each slot's window in TILES:
--     the lead at (1,3) 10x7 = (8,24) 80x56, and five at (12,1+3n) 18x3 =
--     (96, 8+24n) 144x24.
--   sPartyMenuSpriteCoords (0615704) gives the four sprites inside it in
--     PIXELS: the icon, the held item, the status pill and the ball behind
--     the icon.
--
-- Three tiles is twenty-four pixels; both tables step by that.
--
-- The fallbacks below are what this drew before any of it was read, so a
-- cache imported before the stage existed keeps exactly what it had.
local LEAD = { tx = 0, ty = 0, tw = 13, th = 9, tall = true }
local REST = { tx = 13, ty = 0, tw = 17, th = 4 }   -- th is ONE panel
local CANCEL = { tx = 0, ty = 16, tw = 13, th = 4 }
local HP_BAR_W = 48

-- ...and where the pieces sit INSIDE a panel, when the cartridge has not
-- said.  Same shape as sPartyBoxInfoRects, so one drawing routine serves
-- both: { x, y, w, h }, relative to the panel's own corner.
local FALLBACK_RECTS = {
  wide = { name = { x = 8, y = 8, width = 64, height = 13 },
           level = { x = 8, y = 24, width = 32, height = 8 },
           gender = { x = 64, y = 24, width = 8, height = 8 },
           hp = { x = 24, y = 44, width = 24, height = 8 },
           maxHp = { x = 48, y = 44, width = 24, height = 8 },
           bar = { x = 8, y = 36, width = 48, height = 3 } },
  narrow = { name = { x = 24, y = 4, width = 56, height = 13 },
             level = { x = 24, y = 16, width = 32, height = 8 },
             gender = { x = 60, y = 16, width = 8, height = 8 },
             hp = { x = 100, y = 14, width = 24, height = 8 },
             maxHp = { x = 116, y = 14, width = 24, height = 8 },
             bar = { x = 88, y = 10, width = 48, height = 3 } },
}

function Gen3PartyMenu:uiSize() return GBA_W, GBA_H end
function Gen3PartyMenu:wantsFillScale() return true end

function Gen3PartyMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

local function screenText(game, key)
  local record = ((game.data.constants or {}).gen3Screens or {})[key]
  return record and record.items or nil
end

function Gen3PartyMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3PartyMenu)
  self.game = game
  self.onCancel = opts.onCancel
  -- the battle's three shapes (see the note at the top of this file)
  self.onSwitch = opts.onSwitch
  self.battle = opts.battle
  self.forceSwitch = opts.forceSwitch
  self.pickOnly = opts.pickOnly
  -- TM/HM TEACHING.  The bag pushes the party menu with the machine's move on
  -- it; each panel then answers ABLE or NOT ABLE out of that Pokemon's own
  -- learnset, and the box at the bottom asks Emerald's question.  Without
  -- this the push was declined and Kanto's Game Boy party list served every
  -- teach in Hoenn.
  self.tmhm = opts.tmhm
  -- HP medicine wants the picker still drawn while its bar fills, and closes
  -- it itself -- the same contract the Gen 1/2 picker offers (#252)
  self.keepOpen = opts.keepOpen
  -- CHOOSING A TEAM, which is the Frontier's door and the link colosseum's.
  -- `chooseOrder` carries the cartridge's own two bounds -- the most this
  -- screen will take and the fewest it will accept -- and its own four
  -- sentences; `onOrder` is handed the slots in the order they were picked,
  -- or nil if the player walked away.  See the note above :confirmOrder.
  self.chooseOrder = opts.chooseOrder
  self.onOrder = opts.onOrder
  self.order = {}
  self.index = 1
  self.words = screenText(game, "partyActions")
  if not self.words then
    Logger.warn("gen3 party: this dataset carries no action words -- falling "
                .. "back to the engine's own")
  end
  return self
end

function Gen3PartyMenu:party() return self.game.save.party or {} end

-- slots 1..6, then the CANCEL button as slot #party+1
function Gen3PartyMenu:slots() return #self:party() + 1 end

function Gen3PartyMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3PartyMenu:word(n, fallback)
  local words = self.words
  return (words and words[n]) or Strings(fallback)
end

-- DOES THIS POKEMON KNOW A FIELD MOVE THAT WOULD DO SOMETHING HERE?
--
-- Emerald puts the field move in the party menu itself, on the Pokemon that
-- knows it, and only when using it would do something.  Two are served end
-- to end here: FLASH, because seven maps in Hoenn are dark, the map header
-- says which, and lighting one is a save flag and a repaint; and DIVE,
-- because the route header names the seafloor map under it.
--
-- The badge gate is the one the extractor placed by reading the cartridge's
-- own field-move scripts; the move number is the cartridge's too.
-- A REGI CHAMBER'S FIELD MOVE.
--
-- Two of the three chambers are opened by a field move used on the right
-- tile, and the cartridge offers that move by asking the chamber FIRST:
-- SetUpFieldMove_Flash (01370FC) runs ShouldDoBrailleRegisteelEffect before
-- its ordinary is-this-cave-dark test, and SetUpFieldMove_RockSmash
-- (0135654) runs ShouldDoBrailleRegirockEffect before looking for a rock.
-- That order is why FLASH is offered in a lit room in Ancient Tomb and
-- nowhere else, and it is the order here.
function Gen3PartyMenu:regiUsableBy(mon)
  local Gen3Regi = require("src.world.Gen3Regi")
  local chamber = Gen3Regi.spotHere(self.game, self.game.overworld)
  if not chamber then return nil end
  if not self:knowsFieldMove(mon, chamber.move) then return nil end
  return chamber
end

function Gen3PartyMenu:useRegi(chamber)
  local Gen3Regi = require("src.world.Gen3Regi")
  local ow = self.game.overworld
  self:close()
  Gen3Regi.open(self.game, ow, chamber)
end

function Gen3PartyMenu:flashUsableBy(mon)
  local ow = self.game.overworld
  if not (ow and ow.map and ow.map.def and ow.map.def.requiresFlash) then
    return false
  end
  if require("src.world.Gen3Flash").lit(self.game) then return false end
  local gate = (self.game.data.constants or {}).gen3FieldMoves
  local flash = gate and gate.FLASH
  if not flash then return false end
  if flash.badgeFlag then
    local key = ("FLAG_G3_%04X"):format(flash.badgeFlag)
    if not (self.game.save.flags and self.game.save.flags[key]) then
      return false
    end
  end
  return self:knowsFieldMove(mon, "FLASH")
end

-- The move NUMBER is the cartridge's, and a party slot names its moves by
-- KEY, so the two only meet through the extractor's own ordering.
function Gen3PartyMenu:knowsFieldMove(mon, moveId)
  local constants = self.game.data.constants or {}
  local gate = constants.gen3FieldMoves
  local entry = gate and gate[moveId]
  local want = entry and constants.moveOrder and constants.moveOrder[entry.move]
  if not want then return false end
  for _, slot in ipairs(mon.moves or {}) do
    local id = (type(slot) == "table") and slot.id or slot
    if id == want then return true end
  end
  return false
end

function Gen3PartyMenu:useFlash()
  local TextBox = require("src.render.TextBox")
  local ow = self.game.overworld
  require("src.world.Gen3Flash").setLit(self.game, true)
  -- ...and the cave gets its lit RADIUS, not merely "not dark": the hole the
  -- field draws goes from 24 pixels to 72, which is the whole point of the
  -- move.  The level is the cartridge's own (Gen3Flash.record().lit).
  require("src.world.Gen3Flash").defaultFor(self.game, true, true)
  self.game.stack:push(TextBox.new(self.game,
    self.game.data.text and self.game.data.text._FlashLightsAreaText
      or Strings("A blinding FLASH\nlights the area!"),
    function()
      self:close()
      if ow and ow.setDark then ow:setDark(false) end
    end))
end

-- DIVE, on the mon that knows it, where using it would do something.  The
-- overworld owns the question of whether this cell dives or surfaces (see
-- OverworldState:gen3DiveHere) -- the menu only asks whether THIS Pokemon is
-- the one that would do it.
function Gen3PartyMenu:diveUsableBy(mon)
  local ow = self.game.overworld
  if not (ow and ow.gen3DiveHere and ow:gen3DiveHere()) then return false end
  if not (ow.gen3HasBadge and ow:gen3HasBadge("DIVE")) then return false end
  return self:knowsFieldMove(mon, "DIVE")
end

function Gen3PartyMenu:useDive()
  local ow = self.game.overworld
  ow:gen3UseDive(function() self:close() end)
end

-- FLY, on the mon that knows it, and only where the bird could take off:
-- outdoors, with the badge, to a town the player has actually stood in.
--
-- The destination list is data.field.flyOrder, which is exactly what Kanto's
-- FLY already reads -- Hoenn's copy of it is written by the heal-location
-- stage from sHealLocations, so no screen or controller had to learn a Gen 3
-- shape.  What it does NOT use is the TOWN MAP screen the older games open:
-- that screen draws Kanto's region picture, and Hoenn's does not exist here
-- yet.  A named list of the towns is the honest stand-in, and it is the same
-- list the picture would put a cursor on.
function Gen3PartyMenu:flyUsableBy(mon)
  local ow = self.game.overworld
  if not (ow and ow.map and ow.map.def) then return false end
  if not require("src.world.Map").isOutdoor(ow.map.def) then return false end
  if not (ow.gen3HasBadge and ow:gen3HasBadge("FLY")) then return false end
  local order = ((self.game.data.field or {}).flyOrder) or {}
  if #order == 0 then return false end
  return self:knowsFieldMove(mon, "FLY")
end

-- FLY OPENS THE MAP, not a list of words.
--
-- Kanto picks its destination from a list because Kanto's TOWN MAP is a
-- separate screen you look at; Hoenn's IS the picker -- LoadTownMap_Fly puts
-- the region map up with the cursor cycling the visited destinations.  This
-- opened FlyMenu, which is Kanto's list wearing Hoenn's names, so the one
-- screen the field move exists to show never appeared.
--
-- The list stays as the fallback for a cache imported before the section
-- rectangles were kept -- openRegionMap says so by returning false -- because
-- refusing to fly at all would be worse than flying from a list.
function Gen3PartyMenu:useFly()
  local ow = self.game.overworld
  local game = self.game
  self:close()
  local function depart(mapId) if ow then ow:flyTo(mapId) end end
  if ow and ow.openRegionMap
     and ow:openRegionMap({ fly = true, onFly = depart }) then
    return
  end
  game.stack:push(require("src.ui.FlyMenu").new(game, { onFly = depart }))
end

-- The submenu the cartridge puts up after a pick, as { label, action } rows.
-- The words are the cartridge's, by their index in the run; only WHICH of
-- them appear is this file's decision.
function Gen3PartyMenu:actionsFor()
  if not (self.battle and self.onSwitch) then return nil end
  return {
    -- SHIFT when a mon is still out, SEND OUT when the slot is empty
    { label = self:word(self.forceSwitch and 2 or 1,
                        self.forceSwitch and "SEND OUT" or "SHIFT"),
      action = "switch" },
    { label = self:word(4, "SUMMARY"), action = "summary" },
    { label = Strings("CANCEL"), action = "cancel" },
  }
end

-- ---------------------------------------------------------------------------
-- THE FIELD PICK, which is a LIST and was a jump.
--
-- Reported from play: "in the party menu when i click a pokemon theres no
-- summary, switch, item, hm use etc option it goes straight to an hm or the
-- summary when clicked".  It did: choose() asked four questions in a row --
-- is this a Regi chamber, is this cave dark, does this cell dive, can this
-- bird take off -- and ran the first that said yes, and otherwise opened the
-- summary.  So the one thing the cartridge always shows, the list, was the
-- one thing that never appeared.
--
-- SetPartyMonFieldSelectionActions builds it in this order and no other:
--
--   SUMMARY, then every FIELD MOVE the Pokemon knows in its own move-slot
--   order, then SWITCH when there is a second Pokemon to switch with, then
--   MAIL if it is holding mail and ITEM if it is not, then CANCEL.
--
-- ...and it lists a field move whether or not it would WORK here.  The
-- cartridge decides that when the move is picked (CursorCb_FieldMove runs
-- the move's own setup and says "can't be used here" when it returns false),
-- which is why the four gates below moved out of the listing and into the
-- action.  A FLY that is simply absent from the list is indistinguishable
-- from a FLY the game has forgotten how to offer.
--
-- The vocabulary is sPartyMenuActions, ripped whole: ITEM, GIVE, TAKE, MAIL
-- and CANCEL are not in the ten-word run this screen used to read, so before
-- the rip there were no words to build this list out of.
-- ---------------------------------------------------------------------------

function Gen3PartyMenu:actionWords()
  local record = (self.game.data.constants or {}).gen3PartyActions
  return (type(record) == "table" and type(record.labels) == "table")
         and record.labels or nil
end

function Gen3PartyMenu:actionWord(key, index, fallback)
  local words = self:actionWords()
  return (words and words[key]) or self:word(index, fallback)
end

-- The cartridge's field-move rows, in the order this Pokemon's move slots
-- name them.  A dataset imported before the rip has no rows, and the screen
-- falls back to the four moves it already knew how to serve.
function Gen3PartyMenu:fieldMovesOf(mon)
  local constants = self.game.data.constants or {}
  local record = constants.gen3PartyActions
  local table_ = (type(record) == "table") and record.fieldMoves or nil
  local out = {}
  if type(table_) ~= "table" or #table_ == 0 then
    for _, key in ipairs({ "FLASH", "DIVE", "FLY", "ROCK_SMASH" }) do
      if self:knowsFieldMove(mon, key) then
        out[#out + 1] = { label = Strings(key:gsub("_", " ")), move = key }
      end
    end
    return out
  end
  local byId = {}
  for _, row in ipairs(table_) do byId[row.move] = row end
  local seen = {}
  for _, slot in ipairs(mon.moves or {}) do
    local id = (type(slot) == "table") and slot.id or slot
    local row = id and byId[id]
    if row and not seen[id] then
      seen[id] = true
      out[#out + 1] = { label = row.label, move = row.move }
    end
  end
  return out
end

function Gen3PartyMenu:fieldActionsFor(mon)
  local rows = {
    { label = self:actionWord("summary", 4, "SUMMARY"), action = "summary" },
  }
  for _, move in ipairs(self:fieldMovesOf(mon)) do
    rows[#rows + 1] = { label = move.label, action = "field", move = move.move }
  end
  -- SWITCH only when there is something to switch WITH: the cartridge tests
  -- gPlayerParty[1], the second slot, not the party count
  if self:party()[2] then
    rows[#rows + 1] = { label = self:actionWord("switch", 3, "SWITCH"),
                        action = "switchOrder" }
  end
  local held = mon.item
  local def = held and (self.game.data.items or {})[held]
  if def and def.mail then
    rows[#rows + 1] = { label = self:actionWord("mail", nil, "MAIL"),
                        action = "mail" }
  else
    rows[#rows + 1] = { label = self:actionWord("item", nil, "ITEM"),
                        action = "item" }
  end
  rows[#rows + 1] = { label = self:actionWord("cancel", nil, "CANCEL"),
                      action = "cancel" }
  return rows
end

-- ITEM's own three, which the cartridge puts up in place of the first list.
function Gen3PartyMenu:itemActions()
  return {
    { label = self:actionWord("give", nil, "GIVE"), action = "give" },
    { label = self:actionWord("takeItem", 8, "TAKE"), action = "take" },
    { label = self:actionWord("cancel", nil, "CANCEL"), action = "cancel" },
  }
end

local function monName(game, mon)
  return mon.nickname or (game.data.pokemon[mon.species] or {}).name or "?"
end

function Gen3PartyMenu:say(text, after)
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, text, after))
end

-- USING one, which is the half the cartridge decides at the press rather
-- than at the listing.
function Gen3PartyMenu:useFieldMove(mon, move)
  local chamber = self:regiUsableBy(mon)
  if chamber and chamber.move == move then return self:useRegi(chamber) end
  if move == "FLASH" and self:flashUsableBy(mon) then return self:useFlash() end
  if move == "DIVE" and self:diveUsableBy(mon) then return self:useDive() end
  if move == "FLY" and self:flyUsableBy(mon) then return self:useFly() end
  -- CursorCb_FieldMove's own answer when the move's setup returns false,
  -- in the cartridge's own words: sActionStringTable[PARTY_MSG_CANT_USE_HERE]
  local record = (self.game.data.constants or {}).gen3PartyActions
  local said = type(record) == "table" and record.messages or nil
  local text = said and (move == "CUT" and said.nothingToCut
                         or move == "SURF" and said.cantSurfHere
                         or said.cantUseHere)
  self:say(text or Strings("Can't use that here."))
end

function Gen3PartyMenu:giveItem(mon)
  local game = self.game
  local Screens_ = require("src.ui.Screens")
  local ok = pcall(function()
    Screens_.push(game, "BagMenu", {
      pick = true,
      onPick = function(id)
        require("src.ui.BagMenu").handOver(game, mon, id)
      end,
    })
  end)
  if not ok then
    Logger.info("gen3 party: no bag screen to give from")
  end
end

function Gen3PartyMenu:takeItem(mon)
  local game = self.game
  local name = monName(game, mon)
  local held = mon.item
  if not held then
    return self:say(Strings("%s isn't holding\nanything.", name))
  end
  local itemName = ((game.data.items or {})[held] or {}).name or held
  local got, why = require("src.inventory.Bag").takeHeld(game.save, mon,
                                                        game.data)
  if not got then
    if why == "full" then
      return self:say(Strings("There's no room to\nstore items."))
    end
    return
  end
  self:say(Strings("Received the %s\nfrom %s.", itemName, name))
end

-- SWITCH: the cartridge marks the first slot and swaps it with the second.
function Gen3PartyMenu:swapWith(index)
  local party = self:party()
  local from = self.switchFrom
  self.switchFrom = nil
  if not (from and party[from] and party[index]) or from == index then return end
  party[from], party[index] = party[index], party[from]
  self.index = index
end

-- ---------------------------------------------------------------------------
-- CHOOSING A TEAM.
--
-- The Frontier's seven facilities, both Battle Tents and the link colosseum
-- all open with the same screen: pick some of your party, in order, and the
-- order is what goes into battle.  Thirty-four call sites, and none of them
-- could be served until the import found HOW MANY -- a number that is in
-- neither special's own argument (both hand one to a function that throws it
-- away) but in two little functions further in, one saying the most the
-- screen will take and the other the fewest it will accept.
--
-- THE TWO RULES ARE THE CARTRIDGE'S and so are the words for breaking them:
-- no two of the chosen may be the same species, and no two may hold the same
-- item.  Both come out of the same loop in the cartridge's own validator, and
-- the sentences come out of the party menu's own message table.
-- ---------------------------------------------------------------------------

-- Which pick is this slot, or nil.
function Gen3PartyMenu:orderOf(slot)
  for i, n in ipairs(self.order or {}) do
    if n == slot then return i end
  end
  return nil
end

function Gen3PartyMenu:orderWord(key, fallback)
  local said = (self.chooseOrder or {}).messages or {}
  return said[key] or Strings(fallback)
end

function Gen3PartyMenu:orderActionsFor(slot)
  local rows = {}
  local picked = self:orderOf(slot)
  if picked then
    rows[#rows + 1] = { label = self:word(7, "NO ENTRY"), action = "noEntry" }
  elseif #self.order < (self.chooseOrder.most or 1) then
    rows[#rows + 1] = { label = self:word(6, "ENTER"), action = "enter" }
  end
  rows[#rows + 1] = { label = self:word(4, "SUMMARY"), action = "summary" }
  rows[#rows + 1] = { label = Strings("CANCEL"), action = "cancel" }
  return rows
end

-- The two rules, checked against everything already chosen.  A held item of
-- nothing is not an item two Pokemon are both holding, which is why the
-- cartridge tests it for zero before comparing.
function Gen3PartyMenu:orderRefusal(slot)
  local party = self:party()
  local mon = party[slot]
  if not mon then return nil end
  for _, n in ipairs(self.order or {}) do
    local other = party[n]
    if other then
      if other.species == mon.species then
        return self:orderWord("same", "POKéMON can't be the same.")
      end
      if mon.item and mon.item ~= 0 and other.item == mon.item then
        return self:orderWord("holdItems", "No identical hold items.")
      end
    end
  end
  return nil
end

-- WHAT THE CANCEL BUTTON DOES HERE, which is not cancelling.
--
-- On the cartridge the button runs the VALIDATOR: with enough chosen it
-- confirms, and with too few it says so and leaves you on the screen.  Only
-- backing out with B leaves with nothing -- which is exactly what the return
-- callback tests, `gSelectedOrderFromParty[0] == 0`, and what the scripts
-- compare VAR_RESULT against straight afterwards.
function Gen3PartyMenu:confirmOrder()
  local least = (self.chooseOrder or {}).least or 1
  if #self.order >= least then return self:handOrder(self.order) end
  if least <= 1 or #self.order == 0 then
    return self:say(self:orderWord("none", "No POKéMON for battle!"))
  end
  local line = tostring(self:orderWord("needed", "{VAR1} POKéMON are needed."))
  return self:say((line:gsub("{VAR1}", tostring(least))))
end

function Gen3PartyMenu:handOrder(slots)
  self.game.stack:pop()
  if self.onOrder then
    local out = nil
    if slots and #slots > 0 then
      out = {}
      for i, n in ipairs(slots) do out[i] = n end
    end
    self.onOrder(out)
  end
end

-- Hand the pick back to whoever opened the screen.  Popping first is the
-- order every other picker in the port uses: a caller that opens a message
-- box would otherwise draw it under this screen.
function Gen3PartyMenu:handOff(mon)
  if not self.keepOpen then self.game.stack:pop() end
  self.onSwitch(mon, self)
end

function Gen3PartyMenu:runAction(action, mon, row)
  self.submenu = nil
  if action == "cancel" then return end
  if action == "enter" then
    local refused = self:orderRefusal(self.index)
    if refused then return self:say(refused) end
    self.order[#self.order + 1] = self.index
    -- filling the last slot confirms outright: the cartridge does not ask
    -- again once there is no room to change your mind
    if #self.order >= (self.chooseOrder.most or 1) then
      return self:handOrder(self.order)
    end
    return
  end
  if action == "noEntry" then
    local at = self:orderOf(self.index)
    if at then table.remove(self.order, at) end
    return
  end
  if action == "switch" then return self:handOff(mon) end
  if action == "summary" then return self:openSummary(mon) end
  if action == "field" then return self:useFieldMove(mon, row and row.move) end
  if action == "switchOrder" then
    self.switchFrom = self.index
    return
  end
  if action == "item" then
    self.submenu = self:itemActions()
    self.subIndex = 1
    return
  end
  if action == "give" then return self:giveItem(mon) end
  if action == "take" then return self:takeItem(mon) end
  if action == "mail" then
    -- READ / TAKE / CANCEL is the mail list, and there is no mail screen in
    -- this port yet: say so with the cartridge's own word rather than
    -- silently doing nothing
    Logger.info("gen3 party: no %s screen yet", self:actionWord("mail", nil, "MAIL"))
    return
  end
end

function Gen3PartyMenu:openSummary(mon)
  -- Emerald's summary is not Gen 2's with different words: it is four pages
  -- rather than three, and two of them exist to show things Johto has no
  -- concept of -- the nature, and a Special that is split in two.  So Gen 3
  -- gets its own screen, and the shared one stays exactly as it was for the
  -- generations it was written for.
  local screen = require("src.core.GameVersion").isGen3()
                 and "Gen3SummaryMenu" or "SummaryMenu"
  local ok = pcall(function()
    Screens.push(self.game, screen,
                 { mon = mon, onCancel = function() end })
  end)
  if not ok then
    Logger.info("gen3 party: %s is not implemented yet",
                self:word(4, "SUMMARY"))
  end
end

function Gen3PartyMenu:choose()
  local mon = self:party()[self.index]
  if not mon then return self:close() end

  -- CHOOSING A TEAM offers its own two rows and nothing else.  ENTER and
  -- NO ENTRY are the cartridge's own words, sixth and seventh in the run of
  -- party actions this screen already reads -- they have been sitting in the
  -- extracted vocabulary with nothing to spend them on.
  if self.chooseOrder then
    self.submenu = self:orderActionsFor(self.index)
    self.subIndex = 1
    return
  end

  -- AN ITEM'S TARGET, or a mon the battle has already decided it needs:
  -- both are picked outright.  ChooseNextMon does not offer a submenu on the
  -- cartridge either -- the previous mon has fainted and there is nothing to
  -- choose between.
  if self.onSwitch and (self.pickOnly or self.forceSwitch) then
    return self:handOff(mon)
  end

  -- A VOLUNTARY in-battle switch: SHIFT / SUMMARY / CANCEL
  local actions = self:actionsFor()
  if actions then
    self.submenu = actions
    self.subIndex = 1
    return
  end

  -- ...and in the field, the LIST.  A second press while a slot is marked
  -- for SWITCH completes the swap instead of opening it again.
  if self.switchFrom then return self:swapWith(self.index) end
  self.submenu = self:fieldActionsFor(mon)
  self.subIndex = 1
end

function Gen3PartyMenu:update(dt)
  -- RECONSTRUCTED: every icon bounces, all the time, on the same beat.  On
  -- the cartridge each one is an OBJ with its own callback; here it is one
  -- clock, which is indistinguishable on screen and cannot drift.
  self.t = (self.t or 0) + (dt or 0)
  local input = self.game.input

  -- the pick's own submenu takes the stick while it is up
  local sub = self.submenu
  if sub then
    local n = #sub
    if input:wasPressed("down") then self.subIndex = self.subIndex % n + 1
    elseif input:wasPressed("up") then
      self.subIndex = (self.subIndex - 2) % n + 1
    elseif input:wasPressed("a") then
      local row = sub[self.subIndex]
      self:runAction(row.action, self:party()[self.index], row)
    elseif input:wasPressed("b") then self.submenu = nil
    end
    return
  end

  local n = self:slots()
  if input:wasPressed("down") then self.index = self.index % n + 1
  elseif input:wasPressed("up") then self.index = (self.index - 2) % n + 1
  elseif input:wasPressed("a") then
    if self.index > #self:party() then
      -- the CANCEL button VALIDATES when a team is being chosen; everywhere
      -- else it is the way out
      if self.chooseOrder then return self:confirmOrder() end
      return self:close()
    end
    self:choose()
  elseif input:wasPressed("b") then
    -- B drops a SWITCH that was half-made before it closes the screen
    if self.switchFrom then self.switchFrom = nil return end
    if self.chooseOrder then return self:handOrder(nil) end
    self:close()
  end
end

-- The extracted record, or nil on a cache that predates the stage.
function Gen3PartyMenu:record()
  local r = (self.game.data.constants or {}).gen3PartyMenu
  if type(r) ~= "table" or type(r.slots) ~= "table" then return nil end
  return r
end

local function loadImage(path)
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  return ok and img or nil
end

-- Where slot n's panel sits, in PIXELS.  The cartridge's window when the
-- import read it, and the old tile rectangle turned into pixels when it did
-- not -- so everything downstream works in one unit either way.
function Gen3PartyMenu:panelFor(n)
  local rec = self:record()
  local slot = rec and rec.slots[n]
  if slot and slot.window then
    local w = slot.window
    return { x = w.x, y = w.y, width = w.width, height = w.height,
             wide = slot.wide == true, tall = slot.wide == true,
             icon = slot.icon, ball = slot.ball, status = slot.status,
             item = slot.item, index = n }
  end
  local t = (n == 1) and LEAD
            or { tx = REST.tx, ty = REST.ty + (n - 2) * REST.th,
                 tw = REST.tw, th = REST.th }
  return { x = t.tx * 8, y = t.ty * 8, width = t.tw * 8, height = t.th * 8,
           wide = t.tall == true, tall = t.tall == true, index = n,
           tiles = t }
end

-- ...and what is where inside it.
function Gen3PartyMenu:rectsFor(panel)
  local rec = self:record()
  local which = panel.wide and "wide" or "narrow"
  local got = rec and rec.rects and rec.rects[which]
  return got or FALLBACK_RECTS[which]
end

-- THE PARTY ICON, resolved the way every other picture in this port is: the
-- registry first, then the species row's own field.  Cached per species,
-- because a party screen redraws six of them sixty times a second.
local iconCache = {}
local iconQuads = {}

function Gen3PartyMenu:iconFor(mon)
  local data = self.game and self.game.data
  if not (data and mon and mon.species) then return nil end
  local icons = data.icons
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[mon.species])
                or (def and def.icon)
  local path, frameH
  if type(entry) == "table" then
    path = entry.image
    frameH = tonumber(entry.frameHeight)
  elseif type(entry) == "string" then
    path = entry
  end
  -- the mod seam every other icon load goes through
  local okHook, hooked = pcall(function()
    return require("src.pokemon.Sprites").iconPath(data, mon, path, {})
  end)
  if okHook and type(hooked) == "string" then path = hooked end
  if not path then return nil end
  frameH = frameH or tonumber(icons and icons.frameHeight) or 32

  local cached = iconCache[path]
  if cached == nil then
    local Assets = require("src.render.Assets")
    local ok, img = pcall(function()
      return love.graphics.newImage(Assets.resolve(path))
    end)
    cached = ok and img or false
    iconCache[path] = cached
  end
  if not cached then return nil end
  return cached, frameH
end

-- RECONSTRUCTED: the two frames alternate about three times a second, which
-- is the cadence the cartridge's icons read at.
local ICON_PERIOD = 0.32

function Gen3PartyMenu:drawIcon(mon, panel)
  local img, frameH = self:iconFor(mon)
  if not img then return 0 end
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH or ih, ih)
  local frames = math.max(1, math.floor(ih / frameH))
  local frame = frames > 1
    and (math.floor(((self.t or 0) % (ICON_PERIOD * frames)) / ICON_PERIOD)
         % frames)
    or 0
  -- CACHED, because this runs six times a frame.  A fresh Quad per member per
  -- frame is three hundred and sixty allocations a second for a picture that
  -- only ever has two of them.
  local key = ("%d:%d:%d:%d"):format(iw, ih, frameH, frame)
  local quad = iconQuads[key]
  if not quad then
    quad = love.graphics.newQuad(0, frame * frameH, iw, frameH, iw, ih)
    iconQuads[key] = quad
  end
  -- CreateMonIcon's coordinates are the sprite's CENTRE, so the corner is
  -- half the frame back.  Without the record, the old left-of-panel place.
  local x, y
  if panel.icon then
    x = panel.icon.x - math.floor(iw / 2)
    y = panel.icon.y - math.floor(frameH / 2)
  else
    x = panel.x + 4
    y = panel.y + math.floor((panel.height - frameH) / 2)
  end
  -- ...AND THE BOUNCE IS DATA, not a callback.  sMonIconAnims (0857C5B4)
  -- holds five programs and the one a mon uses is chosen by its HP bar
  -- level -- a hurt Pokemon animates SLOWER.  The selected slot is the one
  -- that bobs: AnimateSelectedPartyIcon (1B5B6C) gives it y2 = -3 on odd
  -- frames and leaves the rest sitting still, nudged four pixels aside.
  if panel.selected then
    if frame % 2 == 1 then y = y - 3 end
  elseif panel.wide then
    y = y - 4
  else
    x = x - 4
  end
  love.graphics.setColor(1, 1, 1, 1)
  -- the ball sits BEHIND the icon (subpriority 8 against the icon's 4)
  if panel.ballImage and panel.ball then
    local bw, bh = panel.ballImage:getDimensions()
    local fw = math.floor(bw / 2)          -- closed, then open
    local q = panel.ballQuad
    if q then
      love.graphics.draw(panel.ballImage, q,
                         panel.ball.x - math.floor(fw / 2),
                         panel.ball.y - math.floor(bh / 2))
    end
  end
  love.graphics.draw(img, quad, x, y)
  return iw
end

local function hpColor(fraction)
  if fraction > 0.5 then return 0.25, 0.80, 0.35 end
  if fraction > 0.2 then return 0.95, 0.80, 0.20 end
  return 0.90, 0.25, 0.25
end

-- THE PANEL IS A BUDGET, not three independent draws.
--
-- The Gen 3 font is proportional, so a name placed at a fixed column and a
-- level placed at another fixed column collide on exactly the names that are
-- long enough to matter -- POOCHYENA ran straight through its own Lv9, and
-- TORCHIC through Lv12.  So the level is measured and right-aligned against
-- the panel's inner edge FIRST, and the name is then cut to whatever is
-- left; the HP numbers are right-aligned against the same edge on the row
-- below.  Nothing here can leave the panel.
-- CAN THIS POKEMON LEARN THE MACHINE THAT IS OPEN?  The same scan
-- ItemEffects.use makes when it actually teaches, so the label on screen can
-- never disagree with what pressing A does.
function Gen3PartyMenu:canLearn(mon)
  local data = self.game.data
  local def = data.pokemon and data.pokemon[mon.species]
  for _, move in ipairs((def and def.tmhm) or {}) do
    if move == self.tmhm.move then return true end
  end
  return false
end

-- ...and the word for it, the cartridge's own where the import found them.
function Gen3PartyMenu:learnWord(mon)
  local words = (self.game.data.constants or {}).gen3TeachText or {}
  -- a Pokemon that already knows the move is told so rather than offered it
  for _, slot in ipairs(mon.moves or {}) do
    if slot.id == self.tmhm.move then
      return words.learned or Strings("LEARNED")
    end
  end
  if self:canLearn(mon) then return words.able or Strings("ABLE") end
  return words.notAble or Strings("NOT ABLE")
end

-- EVERY PIECE OF A PANEL HAS ITS OWN RECTANGLE.
--
-- sPartyBoxInfoRects (06156C4 wide, 06156E4 narrow) is six { x, y, w, h }
-- relative to the panel's own corner, and they are not a grid: the nickname
-- is thirteen pixels tall while everything else is eight, the level and the
-- gender symbol share a row, and the current HP and the "/max" are two
-- separate rects fifteen pixels apart rather than one string.  Drawing them
-- as one line -- which is what this did -- is what ran POOCHYENA through its
-- own Lv9.
--
-- The bar is a rect too, 48 wide and THREE tall, and its colour comes from
-- the cartridge's own ramp rather than three values picked here.
-- THE HELD-ITEM ICON, which the panel had a place for and no picture.
--
-- Reported from play: "in the pokemon party menu the hold item icon shows,
-- currently when theyre holding items it doesnt show anything like in the
-- rom".  sPartyMenuSpriteCoords has been read since the panels were -- every
-- slot's `item` x/y is already in the record and already on `panel` -- and
-- the sprite it points at simply had no art on this side.
--
-- It is not in the compressed party-graphics block with the ball and the
-- status pills.  It is sixty-four RAW bytes in the middle of the sprite
-- tables at 615E30, which is why a sweep of the block never found it: two
-- 8x8 frames, a yellow-and-red parcel and a white envelope.
--
-- WHICH ONE is ItemIsMail (0D47BC), four instructions over two constants --
-- item numbers 121 to 132, Hoenn's twelve mails -- and the extractor keeps
-- the answer as a set of item IDS so this never sees a raw number.  An empty
-- hand draws nothing at all, exactly as the cartridge sets the sprite's
-- invisible bit rather than picking a third frame (081B5CB0).
local heldQuads = {}

function Gen3PartyMenu:drawHeldItem(mon, panel)
  local held = mon and mon.item
  if not held then return end
  local rec = self:record()
  local images = rec and rec.images or {}
  local img = loadImage(images.heldItem)
  if not (img and panel.item) then return end
  local iw, ih = img:getDimensions()
  local frames = images.heldItemFrames or { item = 1, mail = 2 }
  local mail = rec and rec.mail
  local frame = (mail and mail[held]) and (frames.mail or 2)
                or (frames.item or 1)
  local fw = math.floor(iw / 2)
  local key = ("%d:%d:%d"):format(iw, ih, frame)
  local quad = heldQuads[key]
  if not quad then
    quad = love.graphics.newQuad((frame - 1) * fw, 0, fw, ih, iw, ih)
    heldQuads[key] = quad
  end
  -- CreateSprite's coordinates are the sprite's CENTRE, the same convention
  -- the icon and the ball on this panel already use
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, panel.item.x - math.floor(fw / 2),
                     panel.item.y - math.floor(ih / 2))
end

function Gen3PartyMenu:drawMember(mon, panel, selected, inset)
  local data = self.game.data
  local def = data.pokemon and data.pokemon[mon.species]
  local name = mon.nickname or (def and def.name) or tostring(mon.species)
  local rects = self:rectsFor(panel)
  local rec = self:record()
  self:drawIcon(mon, panel)
  self:drawHeldItem(mon, panel)

  local maxHp = math.max(1, (mon.stats and mon.stats.hp) or mon.maxHp or 1)
  local hp = math.max(0, math.min(maxHp, mon.hp or 0))
  local fraction = hp / maxHp

  local function at(key) return panel.x + rects[key].x, panel.y + rects[key].y end

  local faced = not panel.wide and Font.pushFace("small") or nil
  love.graphics.setColor(0, 0, 0, 1)

  local nx, ny = at("name")
  Font.draw(Font.fit(name, rects.name.width + 16), nx, ny)

  local lx, ly = at("level")
  Font.draw(Strings("Lv%d", mon.level or 1), lx, ly)

  -- the gender symbol is an ordinary font glyph on the cartridge too
  if mon.gender == "male" or mon.gender == "female" then
    local gx, gy = at("gender")
    Font.draw(mon.gender == "male" and "♂" or "♀", gx, gy)
  end

  -- WITH A MACHINE OPEN the panel answers the question instead of showing
  -- the numbers: what is being chosen is whether this Pokemon can learn the
  -- move, and its current HP has nothing to do with that.  The bar stays --
  -- it is the only thing that says which of them is hurt.
  if self.tmhm then
    local wx, wy = at("hp")
    Font.draw(self:learnWord(mon), wx, wy)
  elseif self.chooseOrder then
    -- CHOOSING A TEAM: the panel says WHICH pick it is, and the order is the
    -- whole point -- the cartridge sends them out in the order they were
    -- entered, so a screen that only marked them as chosen would be hiding
    -- the half of the answer that matters.
    local wx, wy = at("hp")
    local picked = self:orderOf(panel.index)
    Font.draw(picked and Strings("- %d -", picked) or "", wx, wy)
  else
    -- THE TWO RECTS MEET; THEY DO NOT SIT SIDE BY SIDE.
    --
    -- `hp` and `maxHp` are each 24 wide but only FIFTEEN apart -- (102,12)
    -- and (117,12) on the narrow panel, (38,37) and (53,37) on the wide one.
    -- Fifteen is exactly three digits in the face these panels are drawn in,
    -- which is what the pair is: the current HP right-aligned so it ENDS
    -- where the slash begins, and "/max" left-aligned from there.  Reading
    -- the rects as two independent left-aligned fields puts "188" straight
    -- through "/999".
    local hx, hy = at("hp")
    local mx, my = at("maxHp")
    local right = panel.x + panel.width - 4
    local text = tostring(hp)
    local slash = "/" .. tostring(maxHp)
    -- ...and NOTHING LEAVES THE PANEL.  The rects are the cartridge's budget
    -- for its own five faces; a dataset whose font measures wider -- or none
    -- at all, which is what a fixture has -- must still not write past the
    -- panel's edge, so the pair is clamped against it rather than trusted.
    local sx = math.min(mx, right - Font.width(slash))
    Font.draw(slash, sx, my)
    Font.draw(text, math.min(sx - Font.width(text), hx + rects.hp.width), hy)
  end
  if faced then Font.popFace() end

  -- ---- the bar -----------------------------------------------------------
  local bx, by = at("bar")
  local bw, bh = rects.bar.width, math.max(3, rects.bar.height)
  love.graphics.setColor(0.15, 0.15, 0.18, 1)
  love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
  -- GetHPBarLevel's three steps, and the cartridge's own colours for them:
  -- the bar recolours by PALETTE rather than by drawing different art, which
  -- is why the ramp is two colours per step and not one.
  local ramp = rec and rec.hp
  local step = (fraction > 0.5 and "green")
               or (fraction > 0.2 and "yellow") or "red"
  local c = ramp and ramp[step] and ramp[step][1]
  if c then
    love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
  else
    love.graphics.setColor(hpColor(fraction))
  end
  love.graphics.rectangle("fill", bx, by,
                          math.floor(bw * fraction + 0.5), bh)
  love.graphics.setColor(0, 0, 0, 1)

  if selected and not panel.icon then
    -- with no cartridge geometry the cursor still needs somewhere to go
    Font.drawCode(Theme.cursor, panel.x + 8, panel.y + 8)
  end
end

function Gen3PartyMenu:draw()
  local inset = math.max(0, math.floor((16 - Font.glyphHeight()) / 2))
  local rec = self:record()
  local images = rec and rec.images or {}

  -- ---- the field ---------------------------------------------------------
  --
  -- One 32x20 tilemap over a 62-tile sheet, and the CANCEL button is part of
  -- it rather than a sprite -- baked in at (184,136), 56x16.  A dataset with
  -- no field keeps the flat fill this drew before.
  local bg = loadImage(images.bg)
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.16, 0.30, 0.46, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  love.graphics.setColor(1, 1, 1, 1)

  local wide = loadImage(images.wide)
  local narrow = loadImage(images.narrow)
  local wideEgg = loadImage(images.wideEgg)
  local narrowEgg = loadImage(images.narrowEgg)
  local empty = loadImage(images.empty)
  local ball = loadImage(images.ball)

  local party = self:party()
  for n = 1, 6 do
    local mon = party[n]
    local panel = self:panelFor(n)
    panel.selected = (n == self.index)
    if ball then
      panel.ballImage = ball
      local bw, bh = ball:getDimensions()
      local fw = math.floor(bw / 2)
      -- the ball OPENS on the cursor slot: frame 1 rather than 0
      panel.ballQuad = love.graphics.newQuad(panel.selected and fw or 0, 0,
                                             fw, bh, bw, bh)
    end
    if mon then
      local isEgg = mon.isEgg == true
      local art = panel.wide and (isEgg and wideEgg or wide)
                             or (isEgg and narrowEgg or narrow)
      if art then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(art, panel.x, panel.y)
      else
        Font.drawBox(math.floor(panel.x / 8), math.floor(panel.y / 8),
                     math.floor(panel.width / 8), math.floor(panel.height / 8))
      end
      love.graphics.setColor(0, 0, 0, 1)
      self:drawMember(mon, panel, panel.selected, inset)
      love.graphics.setColor(1, 1, 1, 1)
    elseif empty and not panel.wide then
      -- ...and an empty slot is its own map.  There is no wide "empty" in
      -- this ROM: an empty LEAD slot is simply not drawn.
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(empty, panel.x, panel.y)
    end
  end

  -- ---- CANCEL ------------------------------------------------------------
  --
  -- Part of the field's own tilemap when there is one, so only the word and
  -- the cursor are drawn over it.
  local cancel = rec and rec.cancel
  if bg and cancel then
    love.graphics.setColor(0, 0, 0, 1)
    local label = Strings("CANCEL")
    local lx = cancel.x + math.floor((cancel.width - Font.width(label)) / 2)
    local ly = cancel.y + math.floor((cancel.height - Font.glyphHeight()) / 2)
    Font.draw(label, lx, ly)
    if self.index > #party then
      Font.drawCode(Theme.cursor, cancel.x - 8, ly)
    end
  else
    Font.drawBox(CANCEL.tx, CANCEL.ty, CANCEL.tw, CANCEL.th)
    love.graphics.setColor(0, 0, 0, 1)
    local label = Strings("CANCEL")
    local y = (CANCEL.ty + 1) * 8 + inset
    Font.draw(label, (CANCEL.tx + 2) * 8, y)
    if self.index > #party then
      Font.drawCode(Theme.cursor, (CANCEL.tx + 1) * 8, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)

  self:drawTeachPrompt(inset)
  self:drawSubmenu(inset)
end

-- "Teach which POKeMON?" along the bottom, in the same box the rest of this
-- screen's message text uses.  Only with a machine open: nothing else this
-- screen does has a question to ask.
function Gen3PartyMenu:drawTeachPrompt(inset)
  if not (self.tmhm or self.chooseOrder) then return end
  local words = (self.game.data.constants or {}).gen3TeachText or {}
  local prompt = self.chooseOrder
    and self:orderWord("choose", "Choose POKéMON and confirm.")
    or (words.prompt or Strings("Teach which POKéMON?"))
  local tx, ty, tw, th = 0, 16, 20, 4
  Font.drawBox(tx, ty, tw, th)
  love.graphics.setColor(0, 0, 0, 1)
  local ly = (ty + 1) * 8 + inset
  for line in (prompt .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(line, (tx + 1) * 8, ly)
    ly = ly + 16
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- RECONSTRUCTED geometry, cartridge words: the action list sits in the
-- bottom-right corner, sized to its longest label, and never covers the
-- panel of the mon it is asking about.
function Gen3PartyMenu:drawSubmenu(inset)
  local sub = self.submenu
  if not sub then return end
  local widest = 0
  for _, row in ipairs(sub) do
    widest = math.max(widest, Font.width(row.label))
  end
  local tw = math.max(7, math.ceil((widest + 24) / 8))
  local th = #sub * 2 + 2
  local tx = math.floor(GBA_W / 8) - tw
  local ty = math.floor(GBA_H / 8) - th
  Font.drawBox(tx, ty, tw, th)
  love.graphics.setColor(0, 0, 0, 1)
  for i, row in ipairs(sub) do
    local ry = (ty + 1) * 8 + (i - 1) * 16 + inset
    Font.draw(row.label, (tx + 2) * 8, ry)
    if i == self.subIndex then
      Font.drawCode(Theme.cursor, (tx + 1) * 8, ry)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3PartyMenu
