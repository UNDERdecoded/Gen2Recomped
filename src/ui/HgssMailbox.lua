-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S PC MAILBOX: ScrCmd_376 (scrcmd_c.c, "todo: mail
-- screen") -> sub_0203F074 -> overlay 103 (asm, undecompiled), reached from
-- the PC script (scr_seq_0003 _0CEC) only after ScrCmd_377 counted a letter.
-- The data is src/pokemon/Gen4Mail.lua (save.gen4Mailbox).
--
-- READ FROM CODE: the words, msg_0232 -- 0 MAILBOX, 1 {author}, 4 CLOSE,
-- 5 READ / 6 ERASE / 7 GIVE / 8 CANCEL, 9 "What would you like to do with
-- {author}'s Mail?", 10 "The message will be lost. Is that OK?", 12 "Let a
-- Pokemon hold this Mail?", 13 "The Mail's message was erased, and it was
-- put in the Bag.", 14 "Your Bag is full... The Mail was discarded."; GIVE
-- goes through the party menu in PARTY_MENU_CONTEXT_GIVE_MAIL_FROM_MAILBOX
-- (PartyMenu_HandleAttachMailFromMailbox: a mon holding nothing takes the
-- letter, "Mail was transferred from the Mailbox." msg_0300 116; one holding
-- an item refuses, 117) and the letter moves with sub_02091004; READ is the
-- mail screen on the slot (sub_02090EC0).
--
-- INFERRED (overlay 103 is asm): the list's look (one row per letter, its
-- writer's name, CLOSE last), the action list as a column at the right,
-- ERASE emptying the slot even when the bag refuses the Mail (14 says it
-- was discarded).

local S = require("src.ui.HgssSafariScreen")
local Mail = require("src.pokemon.Gen4Mail")

local B = {}
B.__index = B
B.isOpaque = true
B.BANK = 232

local W, H = 256, 192
function B:uiSize() return W, H end
function B:wantsFillScale() return true end

local function txt(game, n, fallback, author)
  local T = require("src.import.Gen4Text")
  local s = game.data and game.data.text and game.data.text[T.label(B.BANK, n)]
  if type(s) ~= "string" or s == "" then s = fallback or "" end
  s = s:gsub("{STRVAR_1 %d+ 0 0}", function() return author or "" end)
  return (s:gsub("\011", "\n"):gsub("{[^}]*}", ""))
end

local function se(self, name)
  local data = self.game.data
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end

function B.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, cursor = 1, top = 1, fade = S.FADE, t = 0 }, B)
  self:refresh()
  return self
end

function B:refresh()
  self.letters = Mail.list(self.game)
  if self.cursor > #self.letters + 1 then self.cursor = #self.letters + 1 end
end

function B:finish()
  if self.finished then return end
  self.finished = true
  local stack = self.game.stack
  if stack and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone() end
end

local function pressed(self, k) return S.pressed(self.game, k) end

function B:openActions(entry)
  self.actions = { entry = entry, cursor = 1,
                   rows = { { "read", txt(self.game, 5, "READ") }, { "erase", txt(self.game, 6, "ERASE") },
                            { "give", txt(self.game, 7, "GIVE") }, { "cancel", txt(self.game, 8, "CANCEL") } } }
end

function B:say(text, after) self.notice = { text = text, after = after } end
function B:ask(text, yes) self.prompt = { text = text, yes = yes, cursor = 1 } end

function B:act(kind, entry)
  local game = self.game
  self.actions = nil
  if kind == "read" then
    local Screen = require("src.ui.HgssMailScreen")
    game.stack:push(Screen.new(game, { mode = "read", mail = entry.mail }))
  elseif kind == "erase" then
    self:ask(txt(game, 10, "The message will be lost.\nIs that OK?"), function()
      local Bag = require("src.inventory.Bag")
      local ok = Bag.add(game.save, Mail.typeToItem(game.data, entry.mail.type), 1, game.data)
      Mail.erase(game, entry.slot)
      self:refresh()
      self:say(ok and txt(game, 13, "The Mail's message was erased,\nand it was put in the Bag.")
                   or txt(game, 14, "Your Bag is full...\nThe Mail was discarded."))
    end)
  elseif kind == "give" then
    local Party = require("src.ui.HgssMailParty")
    require("src.ui.Screens").push(game, "PartyMenu", {
      pickOnly = true,
      onSwitch = function(mon)
        if not mon then return end
        local msg
        if mon.item then
          msg = Party.partyText(game, 117, "This Pokémon is holding an item.\nIt cannot hold Mail.")
        else
          Mail.moveToMon(game, entry.slot, mon)
          msg = Party.partyText(game, 116, "Mail was transferred from\nthe Mailbox.")
        end
        self:refresh()
        game.stack:push(require("src.render.TextBox").new(game, msg))
      end,
    })
  end
end

function B:update()
  self.t = self.t + 1
  if self.closing then
    self.fade = self.fade + 1
    if self.fade >= S.FADE then self:finish() end
    return
  end
  if self.fade > 0 then self.fade = self.fade - 1 return end
  if self.notice then
    if pressed(self, "a") or pressed(self, "b") then
      local after = self.notice.after
      self.notice = nil
      if after then after() end
    end
    return
  end
  if self.prompt then
    local p = self.prompt
    if pressed(self, "up") or pressed(self, "down") then p.cursor = 3 - p.cursor; se(self, "SEQ_SE_DP_SELECT") end
    if pressed(self, "a") then
      self.prompt = nil
      se(self, "SEQ_SE_DP_SELECT")
      if p.cursor == 1 and p.yes then p.yes() end
    elseif pressed(self, "b") then self.prompt = nil end
    return
  end
  if self.actions then
    local a = self.actions
    local n = #a.rows
    if pressed(self, "up") then a.cursor = (a.cursor - 2) % n + 1; se(self, "SEQ_SE_DP_SELECT")
    elseif pressed(self, "down") then a.cursor = a.cursor % n + 1; se(self, "SEQ_SE_DP_SELECT")
    elseif pressed(self, "a") then se(self, "SEQ_SE_DP_SELECT"); self:act(a.rows[a.cursor][1], a.entry)
    elseif pressed(self, "b") then self.actions = nil end
    return
  end
  local n = #self.letters + 1
  if pressed(self, "up") then self.cursor = (self.cursor - 2) % n + 1; se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "down") then self.cursor = self.cursor % n + 1; se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "a") then
    se(self, "SEQ_SE_DP_SELECT")
    local entry = self.letters[self.cursor]
    if entry then self:openActions(entry) else self.closing, self.fade = true, 0 end
  elseif pressed(self, "b") then
    self.closing, self.fade = true, 0
  end
end

local ROWS = 6
function B:drawList()
  local g = love.graphics
  S.box(8, 8, 240, 24, { 120, 168, 216 }, { 56, 96, 152 })
  S.text(txt(self.game, 0, "MAILBOX"), 18, 12, S.WHITE, { 56, 80, 120 })
  local n = #self.letters + 1
  if self.cursor < self.top then self.top = self.cursor end
  if self.cursor >= self.top + ROWS then self.top = self.cursor - ROWS + 1 end
  for r = 0, ROWS - 1 do
    local i = self.top + r
    if i > n then break end
    local y = 40 + r * 24
    local on = (i == self.cursor)
    S.box(16, y, 160, 22, on and { 255, 232, 160 } or { 248, 248, 248 }, on and { 216, 120, 40 } or { 120, 120, 128 })
    local entry = self.letters[i]
    if entry then
      local name = (self.game.data.items[Mail.FIRST_MAIL_ITEM + (entry.mail.type or 0)] or {}).name or ""
      S.text(txt(self.game, 1, "", tostring(entry.mail.author or "")), 24, y + 4)
      S.text(name, 176 - 6 - S.width(name), y + 4, { 120, 120, 136 }, false)
    else
      S.text(txt(self.game, 4, "CLOSE"), 24, y + 4)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function B:drawBottom()
  local g = love.graphics
  g.clear(0.86, 0.9, 0.96, 1)
  self:drawList()
  if self.actions then
    local a = self.actions
    S.message(txt(self.game, 9, "What would you like to do with\n{author}'s Mail?", tostring(a.entry.mail.author or "")))
    S.box(184, 40, 64, #a.rows * 22 + 8, { 248, 248, 248 }, { 88, 104, 136 })
    for i, row in ipairs(a.rows) do
      local y = 44 + (i - 1) * 22
      if i == a.cursor then S.color({ 255, 228, 150 }); g.rectangle("fill", 188, y, 56, 20) end
      S.text(row[2], 194, y + 3)
    end
  end
  if self.notice then S.message(self.notice.text) end
  if self.prompt then S.message(self.prompt.text); S.yesNo(self.prompt.cursor, 88) end
  g.setColor(1, 1, 1, 1)
end

function B:drawTop()
  love.graphics.clear(0.86, 0.9, 0.96, 1)
  local entry = self.letters[self.cursor]
  if entry then
    local rec = self.game.data.gen4_mail_gra
    local d = rec and rec.designs and rec.designs[(entry.mail.type or 0) + 1]
    if d and d.top then S.draw(d.top, 0, 0) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function B:veil()
  if self.closing then return math.min(1, self.fade / S.FADE) end
  return math.max(0, self.fade / S.FADE)
end

function B:draw()
  S.present(self.game, function() self:drawTop() end, function() self:drawBottom() end, self:veil())
end

return B
