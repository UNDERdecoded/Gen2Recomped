-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER: MAIL ON THE PARTY SCREEN (pokeheartgold
-- src/party_menu.c, src/party_menu_list_items.c, src/start_menu.c) -- the
-- party menu (src/ui/Gen4PartyMenu.lua) and the bag's GIVE
-- (src/ui/BagMenu.lua handOver) hand their mail cases here.
--
-- READ FROM CODE
--   * the mon's menu shows MAIL (msg_0300 131) in place of ITEM when it holds
--     a Mail (party_menu.c 1627); MAIL opens READ (132) / TAKE (133) / QUIT
--     under "Do what with the Mail?" (40) (PartyMonContextMenuAction_Mail).
--   * READ: the mail screen in read mode on MON_DATA_MAIL, back to the party
--     (PARTY_MENU_ACTION_RETURN_READ_MAIL -> sub_0203F050).
--   * TAKE: "Send the removed Mail to your PC?" (44): YES ->
--     Mailbox_MoveMessageFromMon -> "The Mail was sent to your PC." (47), or
--     "Your PC's Mailbox is full." (51); NO -> "If the Mail is removed, its
--     written message will be lost. Is that OK?" (48): YES -> the Mail into
--     the bag, "Mail was taken from the Pokemon." (52) or "The Bag is full."
--     (84); NO -> nothing.
--   * GIVE a Mail (PartyMenu_Subtask_GiveItemToMon): to a mon holding nothing
--     -> the mail screen in write mode (sub_02090E68: the writer's name and
--     the icons of the party from this mon on); written -> the Mail leaves
--     the bag and is held with its letter (PartyMenu_GiveOrSwapHeldItems,
--     "X was given the Y to hold." 107); cancelled -> nothing changes. To a
--     mon holding a Mail -> "Must remove Mail before the Pokemon is allowed
--     to hold an item." (78). To a mon holding an item -> the switch question
--     (79); YES -> write; written -> the old item into the bag and "The X was
--     taken and replaced with the Y." (85).
--   * giving a NON-mail item to a mon holding a Mail -> 78 too (sub_0207C3D0
--     case 2).

local Mail = require("src.pokemon.Gen4Mail")

local M = {}

M.BANK = 300

function M.enabled(game) return game and Mail.isHgss(game.data) or false end

local function partyText(game, n, fallback, ...)
  local s = require("src.ui.Gen4PartyText").say(game, n, fallback, ...)
  return s or fallback
end
M.partyText = partyText

local function itemName(game, id)
  local n = tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$"))
  local def = game.data.items and (game.data.items[id] or (n and game.data.items[n]))
  return (def and def.name) or tostring(id)
end
local function monName(game, mon)
  return mon.nickname or ((game.data.pokemon or {})[mon.species] or {}).name or "?"
end

local function show(game, text, onDone)
  game.stack:push(require("src.render.TextBox").new(game, text, onDone))
end
local function ask(game, text, onYes, onNo)
  show(game, text, function()
    game.stack:push(require("src.ui.ChoiceBox").new(game, function(yes)
      if yes then if onYes then onYes() end elseif onNo then onNo() end
    end))
  end)
end

local function slotOf(game, mon)
  for i, m in ipairs(game.save.party or {}) do if m == mon then return i end end
  return 1
end

-- the mail screen in write mode for `mon` with Mail item `id`; done(mail|nil)
function M.write(game, mon, id, done)
  local mail = Mail.newFrom(game.save, Mail.itemToType(id) or 0, slotOf(game, mon))
  local Screen = require("src.ui.HgssMailScreen")
  game.stack:push(Screen.new(game, { mode = "write", mail = mail, onDone = function(written)
    if written then
      -- SCORE_EVENT_WROTE_MAIL / GAME_STAT_MAIL_WRITTEN
      local save = game.save
      save.gen4Stats = save.gen4Stats or {}
      save.gen4Stats.mailWritten = (tonumber(save.gen4Stats.mailWritten) or 0) + 1
    end
    if done then done(written) end
  end }))
end

-- BagMenu.handOver's mail cases. Returns true when it took the give.
function M.handOver(game, mon, id, onChanged)
  if not M.enabled(game) then return false end
  local Bag = require("src.inventory.Bag")
  local giving = Mail.isMailItem(id)
  local holdsMail = Mail.isMailItem(mon.item)
  if not giving and not holdsMail then return false end
  if holdsMail then
    show(game, partyText(game, 78, "Must remove Mail before the\nPokémon is allowed to hold an item."))
    return true
  end
  local name, mn = itemName(game, id), monName(game, mon)
  local function attach(mail)
    if not mail then return end
    if (game.save.inventory[id] or 0) < 1 then return end
    local old = mon.item
    if old and not Bag.add(game.save, old, 1, game.data) then
      show(game, partyText(game, 84, "The Bag is full."))
      return
    end
    Bag.remove(game.save, id, 1)
    mon.item, mon.mail = id, mail
    if onChanged then onChanged() end
    if old then
      show(game, partyText(game, 85, ("The %s was taken and\nreplaced with the %s."):format(itemName(game, old), name),
        mn, itemName(game, old), name))
    else
      show(game, partyText(game, 107, ("%s was given the\n%s to hold."):format(mn, name), mn, name))
    end
  end
  if mon.item then
    ask(game, partyText(game, 79, ("%s is already holding\n%s.\nWould you like to switch the\ntwo items?"):format(mn, itemName(game, mon.item)),
      mn, itemName(game, mon.item)), function() M.write(game, mon, id, attach) end)
  else
    M.write(game, mon, id, attach)
  end
  return true
end

-- the party menu's MAIL > READ
function M.read(game, mon)
  local Screen = require("src.ui.HgssMailScreen")
  local mail = Mail.ofMon(game.data, mon)
  if not mail then
    mail = Mail.blank(); mail.type = Mail.itemToType(mon.item) or 0
  end
  game.stack:push(Screen.new(game, { mode = "read", mail = mail }))
end

-- the party menu's MAIL > TAKE
function M.take(game, mon, onChanged)
  local Bag = require("src.inventory.Bag")
  ask(game, partyText(game, 44, "Send the removed Mail to\nyour PC?"), function()
    if Mail.moveFromMon(game, mon) then
      if onChanged then onChanged() end
      show(game, partyText(game, 47, "The Mail was sent to your PC."))
    else
      show(game, partyText(game, 51, "Your PC's Mailbox is full."))
    end
  end, function()
    ask(game, partyText(game, 48, "If the Mail is removed, its written\nmessage will be lost. Is that OK?"), function()
      if Bag.add(game.save, mon.item, 1, game.data) then
        mon.item, mon.mail, mon.kenyaMail = nil, nil, nil
        if onChanged then onChanged() end
        show(game, partyText(game, 52, "Mail was taken from the\nPokémon."))
      else
        show(game, partyText(game, 84, "The Bag is full."))
      end
    end)
  end)
end

return M
