-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S SEASON CHANGE: the splash and Deerling / Sawsbuck.
--
-- (The season itself, the textures and the seasonal music, encounters and
-- battle backgrounds were already ported: src/world/Gen5FieldRules.lua's
-- R.season, src/render/Gen5Seasons.lua, Gen5Audio, Gen5WildTables.)
--
-- READ FROM CODE (Black):
--   * the field's start-up (ov20 0x02183B90) compares the save's season
--     (gamedata +0x1C4, 0x02012984) with the month's ((month - 1) & 3,
--     0x0202E888; 0x0202E848); when they differ it stores the new one
--     (0x0202E8CC) and runs the splash task (0x02187808): starting from the
--     old season it steps (s + 1) & 3 (0x0202E8A4) and shows each season's
--     picture until it has shown the new one (0x02187C4A / 0x02187CA4)
--   * the picture of season s is archive 0x97 (/a/1/5/1) members 3s
--     (palette), 3s + 1 (chars), 3s + 2 (screen) on BG3 (0x0218794C)
--   * every party Deerling (585) / Sawsbuck (586) takes the season as its
--     form (field 0x6F; ov10 0x0216AAE4, run with the field's season)
-- READ FROM CODE: the transition (0x02187A10 / 0x02187A38) is fades only --
-- BG3's brightness / alpha blend at 16 * t / T (G2_SetBlendBrightness /
-- G2_SetBlendAlpha, 0x0207D658 / 0x0207D63C) and the sub screen's master
-- brightness -- no affine scale, so the picture is drawn as it is: the two
-- halves of each word sit at the art's own heights.
-- INFERRED: the timings (fade 16, hold 40, fade 16 field frames a season);
-- the word sits across the 256-wide map's wrap, so it is drawn scrolled 128.
-- The check runs on every map load, as the field's start-up does.

local M = {}

M.DEERLING, M.SAWSBUCK = 585, 586
M.FADE, M.HOLD = 16, 40

local function art(data)
  local c = data and data.constants
  return c and c.gen5SeasonArt
end

function M.season(save)
  return require("src.world.Gen5FieldRules").season(save)
end

-- Deerling / Sawsbuck wear the season
function M.applyForms(data, save, s)
  local F = require("src.pokemon.Gen4Forms")
  for _, mon in ipairs(save and save.party or {}) do
    if (mon.species == M.DEERLING or mon.species == M.SAWSBUCK) and not mon.isEgg
       and (mon.form or 0) ~= s then
      F.setForm(data, mon, s)
    end
  end
end

-- the splash, as a state over the field
local Splash = { isOpaque = false }
Splash.__index = Splash

local images = {}
local function image(entry)
  local path = type(entry) == "table" and entry.path or entry
  if not path then return nil end
  if images[path] == nil then
    local ok, img = pcall(function() return require("src.render.Assets").image(path) end)
    images[path] = ok and img or false
  end
  return images[path] or nil
end

function Splash.new(game, from, to)
  local steps, s = {}, from
  repeat
    s = (s + 1) % 4
    steps[#steps + 1] = s
  until s == to or #steps >= 4
  return setmetatable({ game = game, steps = steps, i = 1, t = 0, acc = 0 }, Splash)
end

function Splash:uiSize() return 256, 192 end

function Splash:update(dt)
  self.acc = self.acc + (tonumber(dt) or 1 / 60)
  while self.acc >= 1 / 30 do
    self.acc = self.acc - 1 / 30
    self.t = self.t + 1
    if self.t >= M.FADE * 2 + M.HOLD then
      self.t, self.i = 0, self.i + 1
      if self.i > #self.steps then self.game.stack:pop() return end
    end
  end
end

function Splash:draw()
  local w, h = 256, 192
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local a = art(self.game.data)
  local s = self.steps[self.i]
  local img = a and s and image(a[s] or a[tostring(s)])
  if img then
    local alpha = 1
    if self.t < M.FADE then alpha = self.t / M.FADE
    elseif self.t > M.FADE + M.HOLD then alpha = 1 - (self.t - M.FADE - M.HOLD) / M.FADE end
    love.graphics.setColor(1, 1, 1, math.max(0, math.min(1, alpha)))
    local iw = img:getWidth()
    love.graphics.draw(img, -iw / 2, 0)
    love.graphics.draw(img, iw / 2, 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
end
M.Splash = Splash

-- per map load
function M.check(ow)
  local game = require("src.core.Game")
  local save = game and game.save
  if not save then return end
  local s = M.season(save)
  M.applyForms(game.data, save, s)
  local shown = tonumber(save.gen5SeasonShown)
  save.gen5SeasonShown = s
  if shown == nil or shown == s or not art(game.data) then return end
  game.stack:push(Splash.new(game, shown, s))
end

function M.update(ow)
  local id = ow and ow.map and ow.map.id
  if id and ow.gen5SeasonMap ~= id then
    ow.gen5SeasonMap = id
    pcall(M.check, ow)
  end
end

return M
