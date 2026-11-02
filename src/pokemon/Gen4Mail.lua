-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S MAIL: the letter a Pokemon holds and the PC's
-- mailbox, as data (pokeheartgold src/mail.c, src/mail_message.c,
-- src/mail_misc.c; the screens are src/ui/HgssMailScreen.lua and
-- src/ui/HgssMailbox.lua).
--
-- A MAIL (struct Mail) is, in this port's save:
--
--   { type = 0..11 (MAIL_GRASS .. MAIL_BRICK; nil = MAIL_NONE, an empty slot),
--     author = name, gender = 0 / 1, otId = n,
--     icons = { species, ... }  -- up to three party icons (mon_icons[3])
--     forms = { form, ... },
--     msgs  = { msg, msg, msg } }
--
-- and a MESSAGE (MailMessage) is { bank = 0..4 | nil, no = 0..19, w = { w1, w2 } }:
-- `bank` indexes sMessageBanks (0 msg_0294, 1 msg_0296, 2 msg_0292,
-- 3 msg_0293, 4 msg_0295 -- twenty sentences each, every blank a
-- {STRVAR_1 28 n 0} filled with easy-chat word n), nil is MAILMSG_BANK_NONE.
-- A word is Gen4EasyChat's u16, 0xFFFF EC_WORD_NULL.
--
-- The mon keeps its letter in `mon.mail` (MON_DATA_MAIL) beside `mon.item`;
-- the mailbox is `save.gen4Mailbox`, twenty slots (MAILBOX_MSG_COUNT), a free
-- one `false`.

local M = {}

M.FIRST_MAIL_ITEM = 137          -- ITEM_GRASS_MAIL
M.NUM_MAIL = 12
M.MAILBOX_COUNT = 20
M.WORD_NULL = 0xFFFF
M.MSG_BANKS = { [0] = 294, 296, 292, 293, 295 }   -- sMessageBanks
M.MSGS_PER_BANK = 20
M.BANK_0293 = 3                   -- MAILMSG_BANK_0293_GMM, the writer's start
M.FRIEND_NAME_BANK = 445          -- msg_0445: 0 Ethan, 1 Lyra

local function num(id)
  return tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$"))
end

-- ItemIdIsMail
function M.isMailItem(id)
  local n = num(id)
  return n ~= nil and n >= M.FIRST_MAIL_ITEM and n < M.FIRST_MAIL_ITEM + M.NUM_MAIL
end
-- ItemToMailId / MailToItemId
function M.itemToType(id)
  local n = num(id)
  if not M.isMailItem(n) then return nil end
  return n - M.FIRST_MAIL_ITEM
end
function M.typeToItem(data, mailType)
  local n = M.FIRST_MAIL_ITEM + (tonumber(mailType) or 0)
  local named = ("ITEM_%03d"):format(n)
  if data and data.items and data.items[named] then return named end
  return n
end

function M.isHgss(data)
  local v = data and data.gen4_version
  return type(v) == "table" and v.family == "hgss"
end

-- MailMsg_Init
function M.emptyMsg() return { bank = nil, no = 0, w = { M.WORD_NULL, M.WORD_NULL } } end
-- MailMsg_Init_WithBank
function M.msgWithBank(bank) return { bank = bank, no = 0, w = { M.WORD_NULL, M.WORD_NULL } } end
function M.copyMsg(m)
  if type(m) ~= "table" then return M.emptyMsg() end
  return { bank = m.bank, no = m.no or 0, w = { (m.w or {})[1] or M.WORD_NULL, (m.w or {})[2] or M.WORD_NULL } }
end
-- MailMsg_IsInit
function M.msgIsInit(m) return type(m) == "table" and m.bank ~= nil end

-- Mail_Init
function M.blank()
  return { type = nil, author = "", gender = 0, otId = 0, icons = {}, forms = {},
           msgs = { M.emptyMsg(), M.emptyMsg(), M.emptyMsg() } }
end

function M.copy(mail)
  if type(mail) ~= "table" then return nil end
  local out = { type = mail.type, author = mail.author, gender = mail.gender, otId = mail.otId,
                icons = {}, forms = {}, msgs = {}, kenya = mail.kenya }
  for i, v in ipairs(mail.icons or {}) do out.icons[i] = v end
  for i, v in pairs(mail.forms or {}) do out.forms[i] = v end
  for i = 1, 3 do out.msgs[i] = M.copyMsg((mail.msgs or {})[i]) end
  return out
end

-- Mail_TypeIsValid
function M.valid(mail) return type(mail) == "table" and mail.type ~= nil and mail.type >= 0 and mail.type < M.NUM_MAIL end

local function msgEqual(a, b)
  a, b = a or M.emptyMsg(), b or M.emptyMsg()
  if a.bank ~= b.bank then return false end
  if a.bank == nil then return true end
  return (a.no or 0) == (b.no or 0) and (a.w or {})[1] == (b.w or {})[1] and (a.w or {})[2] == (b.w or {})[2]
end
-- Mail_Compare
function M.equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if (a.otId or 0) ~= (b.otId or 0) or (a.gender or 0) ~= (b.gender or 0) or a.type ~= b.type then return false end
  if tostring(a.author or "") ~= tostring(b.author or "") then return false end
  for i = 1, 3 do
    if (a.icons or {})[i] ~= (b.icons or {})[i] then return false end
    if not msgEqual((a.msgs or {})[i], (b.msgs or {})[i]) then return false end
  end
  return true
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

-- Mail_SetNewMessageDetails(mail, mailType, mon_no, save): the writer's name,
-- gender and id, and the icons of up to three party members from `slot` on
function M.newFrom(save, mailType, slot)
  local mail = M.blank()
  mail.type = mailType
  local p = (save and save.player) or {}
  mail.author = tostring(p.name or "")
  mail.gender = (p.gender == "girl" or p.gender == "female" or p.gender == 1) and 1 or 0
  mail.otId = tonumber(p.id or p.trainerId) or 0
  local party = (save and save.party) or {}
  local j = 0
  for i = (slot or 1), #party do
    local m = party[i]
    j = j + 1
    mail.icons[j] = (m and (m.isEgg or m.egg)) and 0 or speciesOf(m)
    mail.forms[j] = tonumber(m and m.form) or 0
    if j >= 3 then break end
  end
  return mail
end

-- CreateKenyaMail (and its two template users): `msgs` already built
local function kenyaShaped(data, mon, mailType, gender, author, otId)
  local mail = M.blank()
  mail.type = mailType
  mail.author = tostring(author or "")
  mail.gender = tonumber(gender) or 0
  mail.otId = tonumber(otId) or 0
  mail.icons[1] = speciesOf(mon)
  mail.forms[1] = tonumber(mon and mon.form) or 0
  return mail
end

local function ecWord(data, group, entry)
  local EC = require("src.pokemon.Gen4EasyChat")
  return EC.word(data, group, entry)
end
-- the easy-chat groups as Gen4EasyChat's 1-based bank indexes
local G_SPECIES, G_LIFESTYLE, G_FEELINGS, G_UNION = 1, 8, 9, 11

-- word index of a named word in its group's bank (the decomp's
-- EC_WORD_LIFESTYLE_LETTER etc. are bank entries; looked up by spelling so the
-- cache's own counts decide the number)
function M.wordByName(data, group, name)
  local T = require("src.import.Gen4Text")
  local EC = require("src.pokemon.Gen4EasyChat")
  local bank = EC.banks(data)[group]
  local text = data and data.text or {}
  local want = tostring(name):upper()
  local e = 0
  while true do
    local s = text[T.label(bank, e)]
    if s == nil then break end
    if type(s) == "string" and s:upper() == want then return ecWord(data, group, e) end
    e = e + 1
  end
  return M.WORD_NULL
end

-- the Route 35 man's letter on Kenya (CreateKenyaMail: "LETTER! Thank you!",
-- "ADVENTURE was fun, wasn't it?", "ZUBAT was the one thing I wanted to
-- avoid...")
function M.kenya(data, mon, mailType, gender, author, otId)
  local mail = kenyaShaped(data, mon, mailType, gender, author, otId)
  mail.msgs[1] = { bank = 1, no = 7, w = { M.wordByName(data, G_LIFESTYLE, "LETTER"), M.WORD_NULL } }
  mail.msgs[2] = { bank = 1, no = 15, w = { M.wordByName(data, G_LIFESTYLE, "ADVENTURE"), M.WORD_NULL } }
  mail.msgs[3] = { bank = 2, no = 1, w = { ecWord(data, G_SPECIES, 41), M.WORD_NULL } }   -- SPECIES_ZUBAT
  mail.kenya = true
  return mail
end

-- the new game's letter in the PC (overlay_36.c ov36 new game): Lyra writes to
-- a boy, Ethan to a girl, on Air Mail with a Marill icon -- "ADVENTURE!
-- EXCITED!" and "I love POKEMON!"
function M.friendMail(data, save)
  local T = require("src.import.Gen4Text")
  local p = (save and save.player) or {}
  local girl = (p.gender == "girl" or p.gender == "female" or p.gender == 1)
  local name = data and data.text and data.text[T.label(M.FRIEND_NAME_BANK, girl and 0 or 1)]
  local mail = kenyaShaped(data, { species = 183 }, 9, girl and 0 or 1,
                           type(name) == "string" and name or (girl and "Ethan" or "Lyra"), 0)
  mail.msgs[1] = { bank = 2, no = 4, w = { M.wordByName(data, G_LIFESTYLE, "ADVENTURE"),
                                           M.wordByName(data, G_FEELINGS, "EXCITED") } }
  mail.msgs[2] = { bank = 3, no = 1, w = { M.wordByName(data, G_UNION, "POKéMON"), M.WORD_NULL } }
  mail.msgs[3] = M.emptyMsg()
  return mail
end

-- the letter a mon holds (MON_DATA_MAIL). Kenya was lent before this port
-- kept letters (`mon.kenyaMail` alone): his is rebuilt from the trade record
-- (NPCTrade_MakeAndGiveLoanMon: trade 7's OT name, gender, id and item).
function M.ofMon(data, mon)
  if type(mon) ~= "table" then return nil end
  if M.valid(mon.mail) then return mon.mail end
  if mon.kenyaMail and M.isMailItem(mon.item) then
    local list = data and data.constants and data.constants.gen4Trades
    local row = type(list) == "table" and list[8] or {}
    mon.mail = M.kenya(data, mon, M.itemToType(mon.item), row.otGender, row.otName or mon.ot, row.otId or mon.otId)
    return mon.mail
  end
  if M.isMailItem(mon.item) then
    local mail = M.blank()
    mail.type = M.itemToType(mon.item)
    return mail
  end
  return nil
end

-- ------------------------------------------------------------- the mailbox

-- Save_Mailbox_Get. A save that predates this port's mailbox gets the new
-- game's letter once (the cartridge writes it at new game).
function M.mailbox(game)
  local save = game and game.save
  if not save then return {} end
  local box = save.gen4Mailbox
  if type(box) ~= "table" then
    box = {}
    for i = 1, M.MAILBOX_COUNT do box[i] = false end
    save.gen4Mailbox = box
  end
  if not save.gen4MailboxSeeded then
    save.gen4MailboxSeeded = true
    if game.data and M.isHgss(game.data) then
      local ok, mail = pcall(M.friendMail, game.data, save)
      if ok and mail and not M.valid(box[1]) then box[1] = mail end
    end
  end
  return box
end

-- Mailbox_CountMessages
function M.count(game)
  local n = 0
  for i = 1, M.MAILBOX_COUNT do if M.valid(M.mailbox(game)[i]) then n = n + 1 end end
  return n
end

-- Mailbox_GetFirstEmptySlotIdx (1-based here; nil when full)
function M.firstEmpty(game)
  local box = M.mailbox(game)
  for i = 1, M.MAILBOX_COUNT do if not M.valid(box[i]) then return i end end
  return nil
end

-- the mailbox's letters in slot order, as { slot, mail }
function M.list(game)
  local out, box = {}, M.mailbox(game)
  for i = 1, M.MAILBOX_COUNT do
    if M.valid(box[i]) then out[#out + 1] = { slot = i, mail = box[i] } end
  end
  return out
end

-- Mailbox_MoveMessageFromMon: the letter into the first free slot, the mon's
-- mail cleared and its held item gone. The slot, or nil when the box is full.
function M.moveFromMon(game, mon)
  local i = M.firstEmpty(game)
  if not i then return nil end
  local mail = M.ofMon(game.data, mon)
  if not M.valid(mail) then
    mail = M.blank(); mail.type = M.itemToType(mon.item) or 0
  end
  M.mailbox(game)[i] = M.copy(mail)
  mon.mail, mon.item, mon.kenyaMail = nil, nil, nil
  return i
end

-- sub_02091004: the slot's letter onto the mon (held item = its Mail), the
-- slot freed
function M.moveToMon(game, slot, mon)
  local box = M.mailbox(game)
  local mail = box[slot]
  if not M.valid(mail) then return false end
  mon.mail = M.copy(mail)
  mon.item = M.typeToItem(game.data, mail.type)
  mon.kenyaMail = mail.kenya or nil
  box[slot] = false
  return true
end

-- Mailbox_DeleteSlotI
function M.erase(game, slot)
  local box = M.mailbox(game)
  if box[slot] ~= nil then box[slot] = false end
end

-- ---------------------------------------------------------------- the text

local function text(data, bank, no)
  local T = require("src.import.Gen4Text")
  local s = data and data.text and data.text[T.label(bank, no)]
  return type(s) == "string" and s or ""
end

-- the sentence's raw text (MailMsg_GetRawString)
function M.rawString(data, msg)
  if not M.msgIsInit(msg) then return "" end
  return text(data, M.MSG_BANKS[msg.bank] or 293, msg.no or 0)
end

-- MailMsg_NumFields: how many blanks the sentence has
function M.numFields(data, msg)
  local n = 0
  for _ in M.rawString(data, msg):gmatch("{STRVAR_1 28 %d+ %d+}") do n = n + 1 end
  return n
end

-- MailMsg_GetExpandedString. `blank` (optional) is what an unfilled blank
-- reads as; the cartridge buffers words up to the first EC_WORD_NULL.
function M.expand(data, msg, blank)
  if not M.msgIsInit(msg) then return "" end
  local EC = require("src.pokemon.Gen4EasyChat")
  local words, stop = {}, false
  for i = 1, 2 do
    local w = (msg.w or {})[i] or M.WORD_NULL
    if w == M.WORD_NULL then stop = true end
    words[i] = (not stop) and EC.toString(data, w) or nil
  end
  local s = M.rawString(data, msg):gsub("{STRVAR_1 28 (%d+) %d+}", function(i)
    return words[tonumber(i) + 1] or blank or ""
  end)
  return s
end

-- the sentence after `msg` in the 5 x 20 cycle (ov102_021E7968), or before it
-- (ov102_021E79A0); fields past the new sentence's count cleared
-- (MailMsg_SetTrailingFieldsEmpty)
function M.stepSentence(data, msg, delta)
  local bank, no = msg.bank or M.BANK_0293, msg.no or 0
  local idx = (bank * M.MSGS_PER_BANK + no + delta) % (5 * M.MSGS_PER_BANK)
  local out = M.copyMsg(msg)
  out.bank, out.no = math.floor(idx / M.MSGS_PER_BANK), idx % M.MSGS_PER_BANK
  local n = M.numFields(data, out)
  for i = n + 1, 2 do out.w[i] = M.WORD_NULL end
  return out
end

-- MailMsg_AllFieldsAreInit
function M.allFieldsSet(data, msg)
  for i = 1, M.numFields(data, msg) do
    if (msg.w or {})[i] == nil or msg.w[i] == M.WORD_NULL then return false end
  end
  return true
end

return M
