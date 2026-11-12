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
-- OBJ layouts below are where the cartridge put its sprites on each screen
-- (OAM read from the scratch interpreter's run: x, y, shape, size, tile,
-- palette, h flip, v flip, priority).
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

local L = {}
L.fileEmpty = { -- 50
  {6,22,0,1,100,10,0,0,2}, {210,131,0,0,60,6,0,0,2}, {168,134,1,0,55,6,0,0,2}, {184,134,1,1,55,6,0,0,2}, {210,99,0,0,60,6,0,0,2}, {168,102,1,0,55,6,0,0,2},
  {184,102,1,1,55,6,0,0,2}, {84,134,0,0,59,6,0,0,2}, {88,134,1,1,55,6,0,0,2}, {136,134,1,1,55,6,0,0,2}, {120,134,1,0,55,6,0,0,2}, {84,102,0,0,59,6,0,0,2},
  {88,102,1,1,55,6,0,0,2}, {136,102,1,1,55,6,0,0,2}, {120,102,1,0,55,6,0,0,2}, {40,144,0,1,141,6,0,0,2}, {56,144,1,2,266,6,0,0,2}, {88,144,2,0,274,6,0,0,2},
  {96,144,2,0,145,6,0,0,2}, {136,144,0,1,141,6,0,0,2}, {152,144,1,2,298,6,0,0,2}, {184,144,2,0,306,6,0,0,2}, {192,144,2,0,145,6,0,0,2}, {32,118,2,0,24,6,0,0,1},
  {40,118,2,0,26,6,0,0,1}, {48,118,2,0,28,6,0,0,1}, {56,118,2,0,30,6,0,0,1}, {64,118,2,0,32,6,0,0,1}, {72,118,2,0,34,6,0,0,1}, {12,122,0,0,63,6,0,0,1},
  {16,114,1,3,64,6,0,0,1}, {80,114,2,1,96,6,0,0,1}, {32,86,2,0,12,6,0,0,1}, {40,86,2,0,14,6,0,0,1}, {48,86,2,0,16,6,0,0,1}, {56,86,2,0,18,6,0,0,1},
  {64,86,2,0,20,6,0,0,1}, {72,86,2,0,22,6,0,0,1}, {12,90,0,0,62,6,0,0,1}, {16,82,1,3,64,6,0,0,1}, {80,82,2,1,96,6,0,0,1}, {30,22,2,0,0,4,0,0,1},
  {38,22,2,0,2,4,0,0,1}, {46,22,2,0,4,4,0,0,1}, {54,22,2,0,6,4,0,0,1}, {62,22,2,0,8,4,0,0,1}, {70,22,2,0,10,4,0,0,1}, {10,26,0,0,61,4,0,0,1},
  {14,18,1,3,64,4,0,0,1}, {78,18,2,1,96,4,0,0,1},
}
L.fileUsed = { -- 57
  {6,22,0,1,108,10,0,0,2}, {210,131,0,0,60,6,0,0,2}, {168,134,1,0,55,6,0,0,2}, {184,134,1,1,55,6,0,0,2}, {210,99,0,0,60,6,0,0,2}, {168,102,1,0,55,6,0,0,2},
  {184,102,1,1,55,6,0,0,2}, {84,134,0,0,59,6,0,0,2}, {88,134,1,1,55,6,0,0,2}, {136,134,1,1,55,6,0,0,2}, {120,134,1,0,55,6,0,0,2}, {84,102,0,0,59,6,0,0,2},
  {88,102,1,1,55,6,0,0,2}, {136,102,1,1,55,6,0,0,2}, {120,102,1,0,55,6,0,0,2}, {129,47,1,1,896,7,0,0,2}, {137,55,0,1,900,7,0,0,2}, {30,57,0,1,774,12,0,0,2},
  {30,50,1,0,768,12,0,0,2}, {40,144,0,1,141,6,0,0,2}, {56,144,1,2,266,6,0,0,2}, {88,144,2,0,274,6,0,0,2}, {96,144,2,0,145,6,0,0,2}, {136,144,0,1,141,6,0,0,2},
  {152,144,1,2,298,6,0,0,2}, {184,144,2,0,306,6,0,0,2}, {192,144,2,0,145,6,0,0,2}, {32,118,2,0,24,6,0,0,1}, {40,118,2,0,26,6,0,0,1}, {48,118,2,0,28,6,0,0,1},
  {56,118,2,0,30,6,0,0,1}, {64,118,2,0,32,6,0,0,1}, {72,118,2,0,34,6,0,0,1}, {12,122,0,0,63,6,0,0,1}, {16,114,1,3,64,6,0,0,1}, {80,114,2,1,96,6,0,0,1},
  {213,72,0,1,192,8,0,0,1}, {165,72,1,2,360,8,0,0,1}, {197,72,0,1,368,8,0,0,1}, {32,86,2,0,12,6,0,0,1}, {40,86,2,0,14,6,0,0,1}, {48,86,2,0,16,6,0,0,1},
  {56,86,2,0,18,6,0,0,1}, {64,86,2,0,20,6,0,0,1}, {72,86,2,0,22,6,0,0,1}, {12,90,0,0,62,6,0,0,1}, {16,82,1,3,64,6,0,0,1}, {80,82,2,1,96,6,0,0,1},
  {30,22,2,0,0,4,0,0,1}, {38,22,2,0,2,4,0,0,1}, {46,22,2,0,4,4,0,0,1}, {54,22,2,0,6,4,0,0,1}, {62,22,2,0,8,4,0,0,1}, {70,22,2,0,10,4,0,0,1},
  {10,26,0,0,61,4,0,0,1}, {14,18,1,3,64,4,0,0,1}, {78,18,2,1,96,4,0,0,1},
}
L.name = { -- 20
  {32,10,0,0,54,0,0,0,0}, {30,18,2,0,0,4,0,0,0}, {38,18,2,0,2,4,0,0,0}, {46,18,2,0,4,4,0,0,0}, {54,18,2,0,6,4,0,0,0}, {62,18,2,0,8,4,0,0,0},
  {70,18,2,0,10,4,0,0,0}, {10,22,0,0,61,4,0,0,0}, {14,14,1,3,64,4,0,0,0}, {78,14,2,1,96,4,0,0,0}, {179,128,1,2,350,6,0,0,2}, {211,128,2,0,358,6,0,0,2},
  {20,128,1,2,320,6,0,0,2}, {52,128,2,0,328,6,0,0,2}, {73,128,1,2,330,6,0,0,2}, {105,128,2,0,338,6,0,0,2}, {126,128,1,2,340,6,0,0,2}, {158,128,2,0,348,6,0,0,2},
  {6,18,0,1,104,10,0,0,2}, {16,45,0,1,48,5,0,0,2},
}
L.game = { -- 77
  {40,23,0,2,624,13,0,0,0}, {56,55,2,1,640,13,0,0,0}, {56,87,2,1,644,13,0,0,0}, {40,55,0,3,480,12,0,0,0}, {104,55,0,3,544,12,0,0,0}, {80,39,1,2,608,12,0,0,0},
  {112,47,1,1,616,12,0,0,0}, {144,47,1,1,620,12,0,0,0}, {168,95,0,1,648,12,0,0,0}, {72,1,1,2,424,4,0,0,0}, {104,1,1,2,432,4,0,0,0}, {136,1,1,2,440,4,0,0,0},
  {168,1,1,2,448,4,0,0,0}, {40,17,1,1,456,4,0,0,0}, {72,17,1,1,460,4,0,0,0}, {104,17,1,1,464,4,0,0,0}, {136,17,1,1,468,4,0,0,0}, {168,17,1,1,472,4,0,0,0},
  {40,1,1,2,416,4,0,0,0}, {112,115,1,2,256,8,0,0,1}, {144,115,1,2,264,8,0,0,1}, {176,115,1,2,272,8,0,0,1}, {112,131,1,1,284,8,0,0,1}, {160,131,1,1,280,8,0,0,1},
  {120,139,0,0,412,10,0,0,1}, {141,139,0,0,413,10,0,0,1}, {165,139,0,0,414,11,0,0,1}, {184,139,0,0,415,11,0,0,1}, {144,99,0,0,189,8,0,0,1}, {144,83,0,1,185,8,0,0,1},
  {128,83,2,0,183,8,0,0,1}, {128,59,0,1,179,8,0,0,1}, {64,59,0,3,192,8,0,0,1}, {64,59,0,3,0,9,0,0,1}, {128,67,0,3,64,9,0,0,1}, {72,123,1,1,128,9,0,0,1},
  {104,123,1,1,132,9,0,0,1}, {104,131,1,2,136,9,0,0,1}, {136,131,1,2,144,9,0,0,1}, {168,131,1,2,152,9,0,0,1}, {192,67,2,2,160,9,0,0,1}, {192,99,0,1,168,9,0,0,1},
  {128,59,0,0,172,9,0,0,1}, {120,147,0,0,173,9,0,0,1}, {136,147,0,0,174,9,0,0,1}, {144,147,0,0,175,9,0,0,1}, {160,147,0,0,176,9,0,0,1}, {168,147,0,0,177,9,0,0,1},
  {184,147,0,0,178,9,0,0,1}, {192,116,2,0,190,9,0,0,1}, {226,128,0,0,404,5,0,0,2}, {236,117,0,0,404,5,0,0,2}, {215,116,0,0,402,5,0,0,2}, {-27,145,1,0,656,5,0,0,2},
  {-19,149,1,0,656,5,0,0,2}, {203,156,0,0,402,5,0,0,2}, {156,133,0,2,652,5,0,0,2}, {80,128,0,2,652,5,0,0,2}, {118,139,1,0,656,5,0,0,2}, {126,144,1,0,656,5,0,0,2},
  {208,149,1,0,656,5,0,0,2}, {131,88,0,1,395,5,0,0,2}, {147,96,1,1,408,5,0,0,2}, {91,96,1,1,408,5,0,0,2}, {184,48,1,2,384,6,0,0,3}, {103,36,1,2,372,6,0,0,3},
  {135,36,0,1,380,6,0,0,3}, {152,41,0,0,394,6,0,0,3}, {46,24,1,2,352,6,0,0,3}, {78,24,0,1,360,6,0,0,3}, {62,16,1,0,364,6,0,0,3}, {94,24,2,0,366,6,0,0,3},
  {62,40,1,1,368,6,0,0,3}, {-59,0,0,2,288,6,0,0,3}, {-27,0,0,2,304,6,0,0,3}, {5,0,0,2,320,6,0,0,3}, {37,0,0,2,336,6,0,0,3},
}
FE.L = L

-- the BG setup each screen leaves in the display registers (BGxCNT, scroll)
local SCREENS = {
  file = { vram = "file", pal = "file", bgs = {
    [0] = { cnt = 0x1C00, x = 0, y = 0 }, [2] = { cnt = 0x1B02, x = 492, y = 480, alpha = 12 / 16 },
    [3] = { cnt = 0x1E0B, x = 0, y = 96 } } },
  name = { vram = "file", pal = "file", bgs = {
    [0] = { cnt = 0x1C00, x = 0, y = 0, map = 1 }, [2] = { cnt = 0x1B02, x = 4, y = 4, map = 2, alpha = 12 / 16 },
    [3] = { cnt = 0x1E0B, x = 0, y = 96 } } },
  game = { vram = "game", pal = "game", bgs = {
    [0] = { cnt = 0x1A40, x = 496, y = 496 }, [1] = { cnt = 0x1B41, x = 464, y = 464 },
    [2] = { cnt = 0x5C46, x = 510, y = 0 }, [3] = { cnt = 0x5E47, x = 511, y = 0 } } },
}
FE.SCREENS = SCREENS

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
  local sv = type(game.opts.save) == "table" and game.opts.save
  self.used = not game.newGame
  self.savedName = sv and (sv.name or (sv.alttp and sv.alttp.name)) or nil
  return self
end

function FE.available(data)
  return data and data.front ~= nil
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
    local dim = self.choice == 1 and { [1] = 4 / 16 } or { [0] = 4 / 16 }
    self:compose("game", L.game, dim)
  end
end

return FE
