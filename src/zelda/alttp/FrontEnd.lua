-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE FRONT END (round 13): the GBA's screens between its title and the
-- game, as the cartridge shows them (tasks 8 and 6 of the top-level task
-- table 0x0842731C): CHOOSE A FILE -> (a new file) ENTER A NAME -> CHOOSE A
-- GAME (A Link to the Past / Four Swords). The pictures are the cartridge's
-- (FrontExtract.lua: its BG tiles and maps, OBJ tiles and palettes); the
-- OBJ layouts are where the cartridge puts its sprites on each screen
-- (round 36: its OAM, built at import by the cartridge's own code in
-- FrontRun.lua).
--
-- OURS (not the cartridge's): one file (the launcher's save slot; the
-- cartridge's files 2 and 3, COPY, ERASE and OPTIONS are shown but do
-- nothing); the names and the letter grid are written with the HUD's menu
-- letters (the cartridge renders them with its front-end font, not decoded),
-- so the grid has A-Z, the digits and '-' (no accented letters, no "abc"
-- page); the file panel shows the name and the hearts as text; the
-- cartridge's blending is LOVE alpha (BG2 over the water at 12/16, the
-- unselected game card at 4/16); no screen transitions or music.

local Hud = require("src.zelda.alttp.Hud")

local FE = {}
FE.__index = FE

-- round 36: the OBJ layouts (x, y, shape, size, tile, palette, h flip,
-- v flip, priority) and the BG setup are no longer written here: the
-- import runs the cartridge's front end (FrontRun.lua) and keeps its OAM
-- and display registers (data.front.info.layouts); FE.bind fills these
-- tables in place when a front end is made.
local L = {}
FE.L = L
local SCREENS = {}
FE.SCREENS = SCREENS

-- ours: which layers the port draws (BG1 holds the cartridge's own-font
-- letters, not imported) and, for the name screen, which imported map
-- (FrontExtract: 1 = BG0 header, 2 = BG2 panel) stands for each layer
local USE = {
  file = { vram = "file", pal = "file", shot = "fileEmpty", bgs = { 0, 2, 3 } },
  name = { vram = "file", pal = "file", shot = "name", bgs = { 0, 2, 3 }, maps = { [0] = 1, [2] = 2 } },
  game = { vram = "game", pal = "game", shot = "game", bgs = { 0, 1, 2, 3 } },
}

local function bitSet(v, b) return math.floor(v / 2 ^ b) % 2 == 1 end

-- the cartridge's registers -> the port's screen setup: BGxCNT and scroll
-- as left; BLDCNT alpha mode (0x40) blends its first-target BGs at EVA / 16
-- (BLDALPHA bits 0-4) -- on the game screen that is the unselected card
-- (FE:draw), elsewhere a fixed alpha
function FE.bind(info)
  local lay = info and info.layouts
  if not lay or not lay.oam or not lay.io then return false end
  for k in pairs(L) do L[k] = nil end
  for name, rows in pairs(lay.oam) do L[name] = rows end
  for sname, u in pairs(USE) do
    local io = lay.io[u.shot]
    if not io then return false end
    local eva = math.min(io.alpha % 32, 16) / 16
    local blend = math.floor(io.bld / 64) % 4 == 1
    local bgs = {}
    for _, i in ipairs(u.bgs) do
      local b = io.bgs[i]
      bgs[i] = { cnt = b.cnt, x = b.x, y = b.y, map = u.maps and u.maps[i] }
      if blend and sname ~= "game" and bitSet(io.bld, i) then bgs[i].alpha = eva end
    end
    SCREENS[sname] = { vram = u.vram, pal = u.pal, bgs = bgs, dim = eva }
  end
  return true
end

-- our letter grid (cell x = 16 + 16 * column, y = 45 + 16 * row, the
-- cartridge's cursor steps): rows 2-3 hold the cartridge's accented
-- letters, which the menu letters do not have
FE.GRID = { "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "", "", "0123456789-" }
FE.BUTTONS = { { x = 20, label = "ABC" }, { x = 73, label = "abc" }, { x = 126, label = "DEL" }, { x = 179, label = "END" } }
FE.NAME_MAX = 6

local SIZES = {
  [0] = { [0] = { 8, 8 }, { 16, 16 }, { 32, 32 }, { 64, 64 } },
  [1] = { [0] = { 16, 8 }, { 32, 8 }, { 32, 16 }, { 64, 32 } },
  [2] = { [0] = { 8, 16 }, { 8, 32 }, { 16, 32 }, { 32, 64 } },
}

function FE.new(game)
  local self = setmetatable({ game = game, data = game.data, screen = "file", t = 0,
                              row = 0, col = 0, name = "", choice = 1, cache = {} }, FE)
  FE.bind(game.data and game.data.front and game.data.front.info)
  local sv = type(game.opts.save) == "table" and game.opts.save
  self.used = not game.newGame
  self.savedName = sv and (sv.name or (sv.alttp and sv.alttp.name)) or nil
  return self
end

function FE.available(data)
  return data and data.front ~= nil and data.front.info ~= nil and data.front.info.layouts ~= nil
end

local function rgb(c)
  return (c % 32) / 31, (math.floor(c / 32) % 32) / 31, (math.floor(c / 1024) % 32) / 31
end

function FE:vram(which)
  return which == "game" and self.data.front.game or self.data.front.file
end

function FE:palette(which, obj)
  local info = self.data.front.info
  if which == "game" then return obj and info.gameObj or info.gameBg end
  return obj and info.fileObj or info.fileBg
end

-- one BG layer as an image (256 or 512 wide, 4bpp text mode)
function FE:bgImage(sname, i)
  local key = sname .. ":bg" .. i
  if self.cache[key] then return self.cache[key] end
  local sc = SCREENS[sname]
  local bg = sc.bgs[i]
  local v = self:vram(sc.vram)
  local pal = self:palette(sc.pal, false)
  local cnt = bg.cnt
  local cb = math.floor(cnt / 4) % 4 * 0x4000
  local sb = math.floor(cnt / 256) % 32 * 0x800
  local size = math.floor(cnt / 16384) % 4
  local w = (size == 1 or size == 3) and 512 or 256
  local h = (size == 2 or size == 3) and 512 or 256
  local mapData
  if bg.map then
    local base = 0x18000 + (bg.map - 1) * 0x800
    mapData = function(o) return v:byte(base + o + 1) + v:byte(base + o + 2) * 256 end
  else
    mapData = function(o) return v:byte(sb + o + 1) + v:byte(sb + o + 2) * 256 end
  end
  local im = love.image.newImageData(w, h)
  for ty = 0, h / 8 - 1 do
    for tx = 0, w / 8 - 1 do
      local blk = 0
      if size == 1 then blk = math.floor(tx / 32)
      elseif size == 2 then blk = math.floor(ty / 32)
      elseif size == 3 then blk = math.floor(tx / 32) + 2 * math.floor(ty / 32) end
      local word = mapData(blk * 0x800 + ((ty % 32) * 32 + (tx % 32)) * 2)
      local tile = word % 1024
      local hf = math.floor(word / 1024) % 2 == 1
      local vf = math.floor(word / 2048) % 2 == 1
      local p = math.floor(word / 4096) * 16
      for py = 0, 7 do
        for px = 0, 7 do
          local sx, sy = hf and 7 - px or px, vf and 7 - py or py
          local b = v:byte(cb + tile * 32 + sy * 4 + math.floor(sx / 2) + 1) or 0
          local ci = (sx % 2 == 1) and math.floor(b / 16) or b % 16
          if ci ~= 0 then
            local r, g, bl = rgb(pal[p + ci + 1] or 0)
            im:setPixel(tx * 8 + px, ty * 8 + py, r, g, bl, 1)
          end
        end
      end
    end
  end
  local out = { image = love.graphics.newImage(im), w = w, h = h, prio = cnt % 4 }
  out.image:setFilter("nearest", "nearest")
  self.cache[key] = out
  return out
end

-- one OBJ (1D tile mapping) as an image
function FE:objImage(sname, o)
  local key = table.concat({ sname, o[3], o[4], o[5], o[6] }, ":")
  if self.cache[key] then return self.cache[key] end
  local sc = SCREENS[sname]
  local v = self:vram(sc.vram)
  local pal = self:palette(sc.pal, true)
  local wh = SIZES[o[3]] and SIZES[o[3]][o[4]] or { 8, 8 }
  local w, h = wh[1], wh[2]
  local im = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local t = o[5] + math.floor(y / 8) * (w / 8) + math.floor(x / 8)
      local b = v:byte(0x10000 + (t % 1024) * 32 + (y % 8) * 4 + math.floor((x % 8) / 2) + 1) or 0
      local ci = (x % 2 == 1) and math.floor(b / 16) or b % 16
      if ci ~= 0 then
        local r, g, bl = rgb(pal[o[6] * 16 + ci + 1] or 0)
        im:setPixel(x, y, r, g, bl, 1)
      end
    end
  end
  local img = love.graphics.newImage(im)
  img:setFilter("nearest", "nearest")
  self.cache[key] = img
  return img
end

local function drawWrapped(img, w, h, sx, sy)
  sx, sy = sx % w, sy % h
  for ox = -sx, 240, w do
    for oy = -sy, 160, h do
      love.graphics.draw(img, ox, oy)
    end
  end
end

-- the GBA's order: priority 3 to 0, each BG (3 to 0) under the OBJs of
-- the same priority; within OBJs the lower OAM slot is on top
function FE:compose(sname, layout, dim)
  local sc = SCREENS[sname]
  local bp = self:palette(sc.pal, false)
  local r, g, b = rgb(bp[1] or 0)
  love.graphics.clear(r, g, b, 1)
  for prio = 3, 0, -1 do
    for i = 3, 0, -1 do
      local bg = sc.bgs[i]
      if bg and bg.cnt % 4 == prio then
        local im = self:bgImage(sname, i)
        local a = bg.alpha or 1
        if dim and dim[i] then a = dim[i] end
        love.graphics.setColor(1, 1, 1, a)
        drawWrapped(im.image, im.w, im.h, bg.x, bg.y)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
    for k = #layout, 1, -1 do
      local o = layout[k]
      if o[9] == prio and not (self.hide and self.hide[k]) then
        love.graphics.draw(self:objImage(sname, o), o[1], o[2])
      end
    end
  end
end

-- the HUD's menu letters (cartridge art) for a line of text
function FE:text(str, x, y)
  local view = self.game.view
  if not view or str == "" then return end
  self.hudPal = self.hudPal or Hud.palette(self.data, 0)
  local words = Hud.textWords(str)
  local im = view:hudImage(words, #words, 1, self.hudPal)
  love.graphics.draw(im, x, y)
end

local function pressed(input, b) return input and input.wasPressed(b) end

-- returns nil, or "alttp" / "fs" once a game is chosen
function FE:update(input)
  self.t = self.t + 1
  if self.screen == "file" then
    if pressed(input, "a") or pressed(input, "start") then
      if self.used then self.screen = "game" else self.screen = "name"; self.row, self.col = 0, 0 end
    end
  elseif self.screen == "name" then
    local rows = 6
    if pressed(input, "up") then repeat self.row = (self.row - 1) % rows until self:rowUsable(self.row) end
    if pressed(input, "down") then repeat self.row = (self.row + 1) % rows until self:rowUsable(self.row) end
    local width = (self.row == 5) and #FE.BUTTONS or 13
    if pressed(input, "left") then self.col = (self.col - 1) % width end
    if pressed(input, "right") then self.col = (self.col + 1) % width end
    if self.row == 5 then self.col = math.min(self.col, #FE.BUTTONS - 1) end
    if pressed(input, "b") then self.name = self.name:sub(1, -2) end
    if pressed(input, "start") then self.row, self.col = 5, 3 end
    if pressed(input, "a") then
      if self.row == 5 then
        local btn = FE.BUTTONS[self.col + 1].label
        if btn == "DEL" then self.name = self.name:sub(1, -2)
        elseif btn == "END" and #self.name > 0 then
          self.chosenName = self.name
          self.used = true
          self.screen = "file"
          self.saving = 60
        end
      else
        local ch = FE.GRID[self.row + 1]:sub(self.col + 1, self.col + 1)
        if ch ~= "" and #self.name < FE.NAME_MAX then self.name = self.name .. ch end
        if #self.name >= FE.NAME_MAX then self.row, self.col = 5, 3 end
      end
    end
  elseif self.screen == "game" then
    if pressed(input, "up") or pressed(input, "down") or pressed(input, "left") or pressed(input, "right") then
      self.choice = 3 - self.choice
    end
    if pressed(input, "b") then self.screen = "file" end
    if pressed(input, "a") or pressed(input, "start") then
      return self.choice == 1 and "alttp" or "fs"
    end
  end
  if self.saving then self.saving = self.saving - 1; if self.saving <= 0 then self.saving = nil end end
  return nil
end

function FE:rowUsable(r)
  return r == 5 or (FE.GRID[r + 1] or "") ~= ""
end

function FE:playerName()
  return self.chosenName or self.savedName
end

function FE:draw()
  if self.screen == "file" then
    local used = self.used
    self:compose("file", used and L.fileUsed or L.fileEmpty)
    if used then
      self:text(self:playerName() or "LINK", 32, 23)
      local st = self.game.stats or {}
      local hearts = math.floor((st.healthMax or 24) / 8)
      self:text(string.format("%d HEARTS", hearts), 52, 56)
    end
  elseif self.screen == "name" then
    self:compose("name", L.name)
    -- the cursor: the cartridge's 16x16 cursor OBJ (layout's last slot),
    -- under our letters (the cartridge's letters are on BG1)
    local cur = L.name[#L.name]
    if self.row == 5 then
      love.graphics.draw(self:objImage("name", cur), FE.BUTTONS[self.col + 1].x - 2, 126, 0, 2.25, 1.25)
    else
      love.graphics.draw(self:objImage("name", cur), 16 + self.col * 16, 45 + self.row * 16)
    end
    -- the grid (our letters at the cartridge's cells)
    for r, line in ipairs(FE.GRID) do
      for c = 1, #line do
        self:text(line:sub(c, c), 16 + (c - 1) * 16 + 4, 45 + (r - 1) * 16 + 4)
      end
    end
    self:text(self.name, 32, 22)
  elseif self.screen == "game" then
    -- the unselected card fades (BLDCNT 0x3F42: BG1 at EVA 4 / 16 while
    -- A Link to the Past is chosen; OURS: BG0 the same way for Four Swords)
    local d = SCREENS.game.dim
    local dim = self.choice == 1 and { [1] = d } or { [0] = d }
    self:compose("game", L.game, dim)
  end
end

return FE
