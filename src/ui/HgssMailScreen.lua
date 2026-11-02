-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S MAIL SCREEN: reading a letter and writing one
-- (pokeheartgold src/overlay_55.c drives it; the screen is overlay 56 and the
-- sentence editor overlay 102, both undecompiled -- asm/overlay_56.s,
-- asm/overlay_102.s). The data is src/pokemon/Gen4Mail.lua.
--
-- READ FROM CODE
--   * ov55_UnkApp_Main: the mail screen runs; a message chosen opens the easy
--     chat app in mode 2 on that message (a fresh one starts as bank
--     MAILMSG_BANK_0293 sentence 0), and its answer is copied back only when
--     the editor was not cancelled; CONFIRM (unk0 3) writes the three
--     messages and the type into the Mail (ov55_021E5BC4) and counts
--     SCORE_EVENT_WROTE_MAIL / GAME_STAT_MAIL_WRITTEN; anything else leaves
--     the Mail as it was.
--   * the stationery: NARC 0x4F (/a/0/7/9) members type / type+0xC /
--     type+0x18 (ov56_021E6650; Gen4MailGra).
--   * the windows (ov56_021E696C, tiles of 8): the three messages at
--     (3, 3) (3, 8) (3, 13), 26 x 4 each; two 8 x 2 windows at (3, 20) and
--     (21, 20); the message window at (2, 19) 27 x 4. The touch boxes
--     (ov56 rodata): the messages y 24..56 / 64..96 / 104..136 x 24..232,
--     then y 148..172 x 160..224 and x 24..88.
--   * its words: msg_0233 (0 CONFIRM, 1 CANCEL, 2 "Please enter a phrase or
--     word.", 3 "Stop giving the Pokemon Mail?").
--   * the sentence editor's UP / DOWN: the next / previous of the 5 banks x
--     20 sentences, wrapping (ov102_021E7968 / ov102_021E79A0); its CONFIRM
--     asks MailMsg_AllFieldsAreInit. Its words: msg_0283 (0 "Choose a word
--     or phrase.", 7 "Please enter a phrase or word.", 8 "Quit without
--     doing anything?"), msg_0284 (CONFIRM, CANCEL, QUIT); the word lists
--     are Gen4EasyChat's groups.
--
-- INFERRED (the overlays are asm and this follows their words, not their
-- every pixel): which 8 x 2 window is CONFIRM (right) and which CANCEL
-- (left); the read screen's author line in the right one; the icons in the
-- stationery's three stamp boxes; the editor drawn as a panel over the mail
-- rather than overlay 102's own two screens; a CONFIRM with nothing written
-- answered with msg_0233 2.

local S = require("src.ui.HgssSafariScreen")
local Mail = require("src.pokemon.Gen4Mail")

local V = {}
V.__index = V
V.isOpaque = true

local W, H = 256, 192
function V:uiSize() return W, H end
function V:wantsFillScale() return true end

V.MSG_Y = { 24, 64, 104 }
V.MSG_X, V.MSG_W = 24, 208
V.BTN = { cancel = { x = 24, y = 148, w = 64, h = 24 }, confirm = { x = 160, y = 148, w = 64, h = 24 } }
V.ICONS = { { 48, 162 }, { 88, 162 }, { 128, 162 } }
V.INK = { 66, 66, 74 }
V.SHADOW = { 198, 198, 206 }

local function txt(game, bank, n, fallback)
  local T = require("src.import.Gen4Text")
  local s = game.data and game.data.text and game.data.text[T.label(bank, n)]
  if type(s) ~= "string" or s == "" then return fallback or "" end
  return (s:gsub("\011", "\n"):gsub("{[^}]*}", ""))
end
V.txt = txt

-- opts: mode "read" | "write"; mail (a Gen4Mail table; write edits a copy);
-- onDone(mail or nil) -- write: the written mail on CONFIRM, nil when
-- cancelled; read: nil
function V.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, mode = opts.mode or "read", onDone = opts.onDone,
                              t = 0, cursor = 1, fade = S.FADE, closing = false }, V)
  self.mail = (self.mode == "write") and Mail.copy(opts.mail or Mail.blank()) or (opts.mail or Mail.blank())
  -- "sentence": the easy chat editor alone, on one message (ScrCmd_681's
  -- battle greeting); onDone(msg or nil)
  if self.mode == "sentence" then
    self.mail = Mail.blank()
    self.mail.msgs[1] = Mail.copyMsg(opts.msg)
    self:openEditor(1)
    if opts.startBank and not Mail.msgIsInit(opts.msg) then self.editor.msg = Mail.msgWithBank(opts.startBank) end
  end
  return self
end

function V.available(game, mailType)
  local rec = game and game.data and game.data.gen4_mail_gra
  local d = rec and rec.designs and rec.designs[(tonumber(mailType) or 0) + 1]
  return d and d.top ~= nil or false
end

function V:design()
  local rec = self.game.data and self.game.data.gen4_mail_gra
  return rec and rec.designs and rec.designs[(tonumber(self.mail.type) or 0) + 1]
end

local function se(self, name)
  local data = self.game.data
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end

-- ------------------------------------------------------------------ flow

function V:finish(result)
  if self.finished then return end
  self.finished = true
  local stack = self.game.stack
  if stack and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone(result) end
end

function V:anyWritten()
  for i = 1, 3 do if Mail.msgIsInit(self.mail.msgs[i]) then return true end end
  return false
end

function V:ask(text, yes)
  self.prompt = { text = text, yes = yes, cursor = 1 }
end

function V:say(text, after)
  self.notice = { text = text, after = after }
end

-- the sentence editor (overlay 102, mode 2) on message i
function V:openEditor(i)
  local msg = self.mail.msgs[i]
  local m = Mail.msgIsInit(msg) and Mail.copyMsg(msg) or Mail.msgWithBank(Mail.BANK_0293)
  self.editor = { slot = i, msg = m, cursor = 1 }
end

function V:editorTargets()
  local n = Mail.numFields(self.game.data, self.editor.msg)
  local out = {}
  for k = 1, n do out[#out + 1] = k end
  out[#out + 1] = "confirm"
  out[#out + 1] = "cancel"
  return out
end

function V:editorAct(target)
  local e = self.editor
  local data = self.game.data
  if target == "confirm" then
    if not Mail.allFieldsSet(data, e.msg) then
      se(self, "SEQ_SE_DP_CUSTOM06")
      self:say(txt(self.game, 283, 7, "Please enter a phrase or word."))
      return
    end
    se(self, "SEQ_SE_DP_DECIDE")
    self.mail.msgs[e.slot] = Mail.copyMsg(e.msg)
    self.editor = nil
    if self.mode == "sentence" then
      self.result = Mail.copyMsg(e.msg)
      self.closing, self.fade = true, 0
    end
  elseif target == "cancel" then
    self:ask(txt(self.game, 283, 8, "Quit without doing anything?"), function()
      self.editor = nil
      if self.mode == "sentence" then self.result = nil; self.closing, self.fade = true, 0 end
    end)
  else
    se(self, "SEQ_SE_DP_SELECT")
    local slot = target
    require("src.pokemon.Gen4EasyChat").pick(self.game, function(word)
      if word and self.editor then self.editor.msg.w[slot] = word end
    end)
  end
end

function V:writeAct(target)
  if type(target) == "number" then
    se(self, "SEQ_SE_DP_SELECT")
    return self:openEditor(target)
  end
  if target == "confirm" then
    if not self:anyWritten() then
      self:say(txt(self.game, 233, 2, "Please enter a phrase or word."))
      return
    end
    se(self, "SEQ_SE_DP_DECIDE")
    self.result = self.mail
    self.closing, self.fade = true, 0
  else
    self:ask(txt(self.game, 233, 3, "Stop giving the Pokémon\nMail?"), function()
      self.result = nil
      self.closing, self.fade = true, 0
    end)
  end
end

-- the touch boxes (ov56 rodata), bottom-screen pixels
function V.hit(x, y)
  for i, my in ipairs(V.MSG_Y) do
    if y >= my and y < my + 32 and x >= 24 and x < 232 then return i end
  end
  if y >= 148 and y < 172 then
    if x >= 160 and x < 224 then return "confirm" end
    if x >= 24 and x < 88 then return "cancel" end
  end
  return nil
end

function V:touchpressed(_, px, py)
  local x, y = S.point(self.game, px, py)
  if not x then return false end
  self.tap = { x = x, y = y }
  return true
end
function V:mousepressed(x, y, b) if b == 1 then return self:touchpressed("mouse", x, y) end end

local function pressed(self, k) return S.pressed(self.game, k) end

function V:update()
  self.t = self.t + 1
  local tap = self.tap
  self.tap = nil
  if self.closing then
    self.fade = self.fade + 1
    if self.fade >= S.FADE then self:finish(self.result) end
    return
  end
  if self.fade > 0 then self.fade = self.fade - 1 return end
  -- a notice waits for A / B (or a touch)
  if self.notice then
    if pressed(self, "a") or pressed(self, "b") or tap then
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
    elseif pressed(self, "b") then
      self.prompt = nil
    end
    return
  end
  if self.mode ~= "write" and not self.editor then
    if pressed(self, "a") or pressed(self, "b") or tap then
      se(self, "SEQ_SE_DP_PIRORIRO2")
      self.closing, self.fade = true, 0
    end
    return
  end
  if self.editor then
    local e = self.editor
    local targets = self:editorTargets()
    if e.cursor > #targets then e.cursor = #targets end
    if pressed(self, "up") or pressed(self, "down") then
      e.msg = Mail.stepSentence(self.game.data, e.msg, pressed(self, "down") and 1 or -1)
      local n = #self:editorTargets()
      if e.cursor > n then e.cursor = n end
      se(self, "SEQ_SE_DP_SELECT")
    elseif pressed(self, "left") then
      e.cursor = (e.cursor - 2) % #targets + 1; se(self, "SEQ_SE_DP_SELECT")
    elseif pressed(self, "right") then
      e.cursor = e.cursor % #targets + 1; se(self, "SEQ_SE_DP_SELECT")
    elseif pressed(self, "a") then
      self:editorAct(targets[e.cursor])
    elseif pressed(self, "b") then
      self:editorAct("cancel")
    end
    return
  end
  -- the mail itself: three messages, then CANCEL | CONFIRM
  local hit = tap and V.hit(tap.x, tap.y)
  if hit then
    self.cursor = (type(hit) == "number") and hit or (hit == "cancel" and 4 or 5)
    return self:writeAct(hit)
  end
  if pressed(self, "up") then
    if self.cursor >= 4 then self.cursor = 3 elseif self.cursor > 1 then self.cursor = self.cursor - 1 end
    se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "down") then
    if self.cursor < 3 then self.cursor = self.cursor + 1 elseif self.cursor == 3 then self.cursor = 5 end
    se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "left") and self.cursor == 5 then self.cursor = 4; se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "right") and self.cursor == 4 then self.cursor = 5; se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "a") then
    local target = (self.cursor <= 3) and self.cursor or (self.cursor == 4 and "cancel" or "confirm")
    self:writeAct(target)
  elseif pressed(self, "b") then
    self:writeAct("cancel")
  end
end

-- --------------------------------------------------------------- drawing

local function ink(s, x, y) S.text(s, x, y, V.INK, V.SHADOW) end

function V:drawIcon(species, cx, cy)
  local data = self.game.data
  local def = data and data.pokemon and data.pokemon[species]
  local icons = data and data.icons
  local entry = (icons and icons.bySpecies and icons.bySpecies[species]) or (def and def.icon)
  local path = type(entry) == "table" and entry.image or entry
  if type(path) ~= "string" then return end
  local img = S.image({ path = path })
  if not img then return end
  local iw, ih = img:getDimensions()
  local fh = math.min(ih, (type(entry) == "table" and tonumber(entry.frameHeight)) or 32)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, love.graphics.newQuad(0, 0, iw, fh, iw, ih), cx - math.floor(iw / 2), cy - math.floor(fh / 2))
end

function V:drawMessage(i, y)
  local msg = self.mail.msgs[i]
  local s = Mail.expand(self.game.data, msg, (self.mode == "write") and "____" or "")
  local ly = y
  for line in (s .. "\n"):gmatch("(.-)\n") do
    ink(line:gsub("{[^}]*}", ""), V.MSG_X + 4, ly)
    ly = ly + 16
  end
end

function V:drawButton(b, label, on)
  S.box(b.x, b.y, b.w, b.h, on and { 255, 232, 160 } or { 240, 240, 240 },
        on and { 216, 120, 40 } or { 120, 120, 128 })
  S.centred(label, b.x, b.w, b.y + 5)
end

function V:drawMail()
  local g = love.graphics
  g.clear(0.08, 0.1, 0.14, 1)
  local d = self:design()
  if not (d and d.top and S.draw(d.top, 0, 0)) then
    S.box(8, 8, W - 16, H - 16, { 244, 244, 236 }, { 120, 140, 120 })
  end
  for i, y in ipairs(V.MSG_Y) do
    if self.mode == "write" and not self.editor and self.cursor == i then
      S.color({ 255, 232, 160 }, 0.7); g.rectangle("fill", V.MSG_X, y, V.MSG_W, 32)
    end
    self:drawMessage(i, y)
  end
  if self.mode == "write" then
    self:drawButton(V.BTN.cancel, txt(self.game, 233, 1, "CANCEL"), not self.editor and self.cursor == 4)
    self:drawButton(V.BTN.confirm, txt(self.game, 233, 0, "CONFIRM"), not self.editor and self.cursor == 5)
  else
    for k, sp in ipairs(self.mail.icons or {}) do
      local at = V.ICONS[k]
      if at and sp and sp > 0 then self:drawIcon(sp, at[1], at[2]) end
    end
    local author = tostring(self.mail.author or "")
    if author ~= "" then ink(author, 168 + 64 - S.width(author), 160) end
  end
  g.setColor(1, 1, 1, 1)
end

function V:drawEditor()
  local e = self.editor
  local g = love.graphics
  local data = self.game.data
  S.box(8, 24, W - 16, 132, { 248, 248, 248 }, { 88, 104, 136 })
  ink(txt(self.game, 283, 0, "Choose a word or phrase."), 16, 30)
  -- the sentence, its blanks boxed
  local raw = Mail.rawString(data, e.msg)
  local targets = self:editorTargets()
  local on = targets[e.cursor]
  local EC = require("src.pokemon.Gen4EasyChat")
  local y = 60
  for line in (raw .. "\n"):gmatch("(.-)\n") do
    local x = 20
    local pos = 1
    while true do
      local a, b, slot = line:find("{STRVAR_1 28 (%d+) %d+}", pos)
      local plain = line:sub(pos, (a or 0) - 1):gsub("{[^}]*}", "")
      if not a then plain = line:sub(pos):gsub("{[^}]*}", "") end
      ink(plain, x, y); x = x + S.width(plain)
      if not a then break end
      local k = tonumber(slot) + 1
      local w = e.msg.w[k]
      local word = (w and w ~= Mail.WORD_NULL) and EC.toString(data, w) or "      "
      local ww = math.max(40, S.width(word) + 6)
      S.box(x, y - 2, ww, 18, on == k and { 255, 232, 160 } or { 232, 236, 248 }, on == k and { 216, 120, 40 } or { 120, 128, 160 })
      ink(word, x + 3, y)
      x = x + ww + 2
      pos = b + 1
    end
    y = y + 22
  end
  S.text("UP / DOWN: sentence   A: word", 16, 112, { 120, 120, 136 }, false)
  local bc = { x = 40, y = 128, w = 72, h = 22 }
  local bk = { x = 144, y = 128, w = 72, h = 22 }
  self:drawButton(bc, txt(self.game, 284, 0, "CONFIRM"), on == "confirm")
  self:drawButton(bk, txt(self.game, 284, 1, "CANCEL"), on == "cancel")
  g.setColor(1, 1, 1, 1)
end

function V:drawBottom()
  if self.mode == "sentence" then
    love.graphics.clear(0.55, 0.72, 0.86, 1)
  else
    self:drawMail()
  end
  if self.editor then self:drawEditor() end
  if self.notice then S.message(self.notice.text) end
  if self.prompt then
    S.message(self.prompt.text)
    S.yesNo(self.prompt.cursor, 88)
  end
end

function V:drawTop()
  local g = love.graphics
  g.clear(0.08, 0.1, 0.14, 1)
  local d = self:design()
  if d and d.sub then S.draw(d.sub, 0, 0) end
  g.setColor(1, 1, 1, 1)
end

function V:veil()
  if self.closing then return math.min(1, self.fade / S.FADE) end
  return math.max(0, self.fade / S.FADE)
end

function V:draw()
  S.present(self.game, function() self:drawTop() end, function() self:drawBottom() end, self:veil())
end

return V
