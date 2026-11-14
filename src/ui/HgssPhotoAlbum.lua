-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S PHOTO ALBUM: OpenPhotoAlbum from the PC
-- (scr_seq_0003 _0D86, "PHOTO ALBUM" once CountSavedPhotos is nonzero), the
-- photos Cameron takes (CameronPhoto -> g4_take_photo, save.hgssPhotoAlbum,
-- 36 at most -- photo_album.h PHOTO_ALBUM_MAX).
--
-- READ FROM CODE: the album's words, msg_0000 -- 0 EXIT, 1 VIEW, 2 DELETE,
-- 3 MOVE, 4 CANCEL, 5 "Please select a photo.", 6 "What will you do with
-- the selected photo?", 7 "Switch with which photo?", 8 "The selected photos
-- were switched.", 9 "Is it OK to delete this photo?", and the photo's card
-- 10 / 11 ("{player}'s Photo / Taken: {place} / Photo of: {lead} [and
-- friends] / M/D/YY") -- ViewPhoto reads 10 + i (view_photo.c); a Photo
-- keeps the player's name, the lead's nickname, numMons, mapId, the date and
-- hour (field_take_photo.c 527-547, filled here by g4_hgss_photo_details).
--
-- INFERRED: the album app itself (PhotoAlbum_LaunchApp) is undecompiled; the
-- list, the action column and the card are drawn plainly. The picture is
-- not re-rendered (the cartridge rebuilds the 3D scene from the saved map,
-- camera and party, field_take_photo.c) -- the card stands in for it.

local S = require("src.ui.HgssSafariScreen")

local A = {}
A.__index = A
A.isOpaque = true
A.BANK = 0

local W, H = 256, 192
function A:uiSize() return W, H end
function A:wantsFillScale() return true end

local function txt(game, n, fallback, buffers)
  local T = require("src.import.Gen4Text")
  local s = game.data and game.data.text and game.data.text[T.label(A.BANK, n)]
  if type(s) ~= "string" or s == "" then s = fallback or "" end
  s = require("src.script.Commands").gen4Markup(s, { stringBuffers = buffers or {} })
  return (s:gsub("\011", "\n"):gsub("{[^}]*}", ""))
end
A.txt = txt

local function se(self, name)
  local data = self.game.data
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end

function A.new(game, onDone)
  local save = game.save or {}
  save.hgssPhotoAlbum = save.hgssPhotoAlbum or {}
  return setmetatable({ game = game, onDone = onDone, album = save.hgssPhotoAlbum, cursor = 1, top = 1,
                        fade = S.FADE, t = 0 }, A)
end

-- the card's buffers: 0 player, 1 place, 2 lead, 3 year, 4 month, 5 day
function A.card(game, photo)
  local place = ""
  local def = photo.map and game.data.maps and game.data.maps[photo.map]
  if def then place = def.label or def.name or def.displayName or "" end
  if (place == "" or place == photo.map) and photo.mapsecName then place = photo.mapsecName end
  local d = photo.date or {}
  local bufs = { photo.player or "", place or "", photo.lead or "",
                 ("%02d"):format((tonumber(d.year) or 0) % 100), tostring(d.month or ""), tostring(d.day or "") }
  local n = ((tonumber(photo.numMons) or 1) > 1) and 11 or 10
  return txt(game, n, "{player}'s Photo", bufs)
end

local function pressed(self, k) return S.pressed(self.game, k) end

function A:finish()
  if self.finished then return end
  self.finished = true
  local stack = self.game.stack
  if stack and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone() end
end

function A:update()
  self.t = self.t + 1
  if self.closing then
    self.fade = self.fade + 1
    if self.fade >= S.FADE then self:finish() end
    return
  end
  if self.fade > 0 then self.fade = self.fade - 1 return end
  local n = #self.album
  if self.viewing then
    if pressed(self, "a") or pressed(self, "b") then self.viewing = nil end
    if pressed(self, "left") and self.viewing and self.viewing > 1 then self.viewing = self.viewing - 1; se(self, "SEQ_SE_DP_SELECT") end
    if pressed(self, "right") and self.viewing and self.viewing < n then self.viewing = self.viewing + 1; se(self, "SEQ_SE_DP_SELECT") end
    return
  end
  if self.notice then
    if pressed(self, "a") or pressed(self, "b") then self.notice = nil end
    return
  end
  if self.prompt then
    local p = self.prompt
    if pressed(self, "up") or pressed(self, "down") then p.cursor = 3 - p.cursor end
    if pressed(self, "a") then self.prompt = nil; if p.cursor == 1 then p.yes() end
    elseif pressed(self, "b") then self.prompt = nil end
    return
  end
  if self.actions then
    local a = self.actions
    if pressed(self, "up") then a.cursor = (a.cursor - 2) % 4 + 1
    elseif pressed(self, "down") then a.cursor = a.cursor % 4 + 1
    elseif pressed(self, "b") then self.actions = nil
    elseif pressed(self, "a") then
      se(self, "SEQ_SE_DP_SELECT")
      local i = a.index
      self.actions = nil
      if a.cursor == 1 then self.viewing = i
      elseif a.cursor == 2 then
        self.prompt = { text = txt(self.game, 9, "Is it OK to delete this\nphoto?"), cursor = 2, yes = function()
          table.remove(self.album, i)
          if self.cursor > #self.album + 1 then self.cursor = #self.album + 1 end
        end }
      elseif a.cursor == 3 then
        self.moving = i
      end
    end
    return
  end
  if pressed(self, "up") then self.cursor = (self.cursor - 2) % (n + 1) + 1; se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "down") then self.cursor = self.cursor % (n + 1) + 1; se(self, "SEQ_SE_DP_SELECT")
  elseif pressed(self, "b") then
    if self.moving then self.moving = nil else self.closing, self.fade = true, 0 end
  elseif pressed(self, "a") then
    se(self, "SEQ_SE_DP_SELECT")
    if self.cursor > n then
      if self.moving then self.moving = nil else self.closing, self.fade = true, 0 end
    elseif self.moving then
      local from = self.moving
      self.moving = nil
      if from ~= self.cursor then
        self.album[from], self.album[self.cursor] = self.album[self.cursor], self.album[from]
        self.notice = { text = txt(self.game, 8, "The selected photos were\nswitched.") }
      end
    else
      self.actions = { index = self.cursor, cursor = 1 }
    end
  end
end

local ROWS = 6
function A:drawBottom()
  local g = love.graphics
  g.clear(0.93, 0.9, 0.84, 1)
  local n = #self.album
  if self.cursor < self.top then self.top = self.cursor end
  if self.cursor >= self.top + ROWS then self.top = self.cursor - ROWS + 1 end
  for r = 0, ROWS - 1 do
    local i = self.top + r
    if i > n + 1 then break end
    local y = 8 + r * 24
    local on = (i == self.cursor)
    S.box(8, y, 168, 22, on and { 255, 232, 160 } or { 248, 248, 248 },
          (self.moving == i) and { 40, 120, 216 } or (on and { 216, 120, 40 } or { 120, 120, 128 }))
    local p = self.album[i]
    if p then
      local label = ("%02d  %s"):format(i, tostring(p.lead or ("Photo " .. tostring(p.photo))))
      S.text(label, 16, y + 4)
    else
      S.text(txt(self.game, 0, "EXIT"), 16, y + 4)
    end
  end
  if self.actions then
    local labels = { txt(self.game, 1, "VIEW"), txt(self.game, 2, "DELETE"), txt(self.game, 3, "MOVE"), txt(self.game, 4, "CANCEL") }
    S.box(184, 8, 64, 4 * 22 + 8, { 248, 248, 248 }, { 88, 104, 136 })
    for k, l in ipairs(labels) do
      local y = 12 + (k - 1) * 22
      if k == self.actions.cursor then S.color({ 255, 228, 150 }); g.rectangle("fill", 188, y, 56, 20) end
      S.text(l, 194, y + 3)
    end
    S.message(txt(self.game, 6, "What will you do with the\nselected photo?"))
  elseif self.moving then
    S.message(txt(self.game, 7, "Switch with which photo?"))
  elseif self.prompt then
    S.message(self.prompt.text); S.yesNo(self.prompt.cursor, 88)
  elseif self.notice then
    S.message(self.notice.text)
  else
    S.message(txt(self.game, 5, "Please select a photo."))
  end
  if self.viewing then self:drawCard(self.viewing) end
  g.setColor(1, 1, 1, 1)
end

function A:drawCard(i)
  local p = self.album[i]
  if not p then return end
  S.box(16, 24, 224, 120, { 252, 250, 240 }, { 120, 96, 72 })
  S.lines(A.card(self.game, p), 28, 36)
  S.text(("%d/%d"):format(i, #self.album), 200, 124, { 120, 120, 136 }, false)
end

function A:drawTop()
  love.graphics.clear(0.93, 0.9, 0.84, 1)
  local p = self.album[self.viewing or self.cursor]
  if p then
    S.box(16, 24, 224, 120, { 252, 250, 240 }, { 120, 96, 72 })
    S.lines(A.card(self.game, p), 28, 36)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function A:veil()
  if self.closing then return math.min(1, self.fade / S.FADE) end
  return math.max(0, self.fade / S.FADE)
end

function A:draw()
  S.present(self.game, function() self:drawTop() end, function() self:drawBottom() end, self:veil())
end

return A
