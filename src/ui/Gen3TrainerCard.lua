-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's TRAINER CARD.
--
-- Not the Gen 2 card.  That one is a Game Boy page with a badge row and a
-- Johto map; this is a 240x160 GBA card whose front carries the player's
-- name, their ID number, their money, their POKéDEX count and their play
-- time, with the eight badges along the bottom -- and a back with the link
-- record on it, which B flips to.
--
-- THE LABELS ARE THE CARTRIDGE'S, found the way the START menu's were: they
-- sit consecutively in the text region in the order the card prints them.
--
--   NAME:   IDNo.   MONEY   POKéDEX   TIME
--
-- and the title line, "{PLAYER}'s TRAINER CARD", is in the same block a few
-- strings later.  Reading them rather than writing them down is what keeps
-- the trailing space and the full stop in "IDNo." -- two details that are
-- wrong in every reconstruction and right here.
--
-- THE BADGES ARE THE CARTRIDGE'S NOW.  They were eight rectangles, filled
-- for the ones earned, because every search for the art had looked for a
-- SPRITE and the cartridge draws them as BACKGROUND TILES -- four tilemap
-- cells per badge, sixteen tiles across, eight side by side in one 1024-byte
-- sheet on one shared palette (RomExtractorGen3:trainerCardBadges).  Their
-- places on this card are the cartridge's too: the first sits four tiles in,
-- they step three tiles apart, and they sit on rows fifteen and sixteen.
--
-- AN UNEARNED BADGE IS NOT DRAWN AT ALL, which is what the cartridge does --
-- there is no empty socket waiting to be filled.
--
-- What is still NOT derived is the rest of the card's ARTWORK: the gradient
-- front and the trainer's picture are graphics the import does not reach yet.
-- This draws the card in the cartridge's own window frame instead, with the
-- fields in their places, and it is the part to replace when that art is
-- extracted.

local Badges = require("src.inventory.Badges")
local Gen3BadgeArt = require("src.render.Gen3BadgeArt")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen3TrainerCard = {}
Gen3TrainerCard.__index = Gen3TrainerCard
Gen3TrainerCard.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED, not derived: the card fills the screen with a tile of margin.
local CARD = { tx = 1, ty = 1, tw = 28, th = 18 }
local LABEL_X = 24
local VALUE_X = 128
local ROW_PITCH = 18
local FIRST_ROW = 5          -- pixels below the card's inner edge
-- the badge row, in the cartridge's own tile coordinates
local BADGE_FIRST_TX = 4
local BADGE_STEP_TX = 3
local BADGE_TY = 15

function Gen3TrainerCard:uiSize() return GBA_W, GBA_H end
function Gen3TrainerCard:wantsFillScale() return true end

function Gen3TrainerCard:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

local function screenText(game, key)
  local record = ((game.data.constants or {}).gen3Screens or {})[key]
  return record and record.items or nil
end

function Gen3TrainerCard.new(game, opts)
  local self = setmetatable({}, Gen3TrainerCard)
  self.game = game
  self.onCancel = opts and opts.onCancel
  self.back = false
  local labels = screenText(game, "trainerCard")
  if not labels then
    Logger.warn("gen3 trainer card: this dataset carries no field labels -- "
                .. "falling back to the engine's own")
    labels = { Strings("NAME: "), "IDNo.", Strings("MONEY"),
               Strings("POKéDEX"), Strings("TIME") }
  end
  self.labels = labels
  return self
end

function Gen3TrainerCard:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3TrainerCard:update(dt)
  local input = self.game.input
  if input:wasPressed("a") then
    self.back = not self.back
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.back then self.back = false else self:close() end
  end
end

-- The five rows, as {label, value} in the cartridge's order.
function Gen3TrainerCard:rows()
  local game = self.game
  local save = game.save or {}
  local player = save.player or {}
  local dex = 0
  for _ in pairs((save.pokedex or {}).owned or {}) do dex = dex + 1 end
  local t = math.floor(tonumber(save.playTime) or 0)
  local id = tonumber(player.id) or 0
  local labels = self.labels
  return {
    { labels[1] or "NAME: ", player.name or Strings("PLAYER") },
    { labels[2] or "IDNo.", ("%05d"):format(id % 100000) },
    { labels[3] or "MONEY", Strings("₽%d", math.floor(save.money or 0)) },
    { labels[4] or "POKéDEX", tostring(dex) },
    { labels[5] or "TIME",
      ("%d:%02d"):format(math.floor(t / 3600), math.floor(t / 60) % 60) },
  }
end

function Gen3TrainerCard:draw()
  local inset = math.max(0, math.floor((ROW_PITCH - Font.glyphHeight()) / 2))
  love.graphics.setColor(0.13, 0.34, 0.29, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
  love.graphics.setColor(0, 0, 0, 1)

  local title = Strings("%s's TRAINER CARD",
                        (self.game.save.player or {}).name
                        or Strings("PLAYER"))
  Font.draw(title, math.floor((GBA_W - Font.width(title)) / 2),
            (CARD.ty + 1) * 8 + inset)

  if self.back then
    -- the back: the link record, which this save does not keep yet, so the
    -- card says so rather than printing zeros that look like facts
    Font.draw(Strings("No link records yet."), LABEL_X,
              (CARD.ty + 4) * 8 + inset)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- THE PORTRAIT.
  --
  -- The card carried no picture at all, and the comment at the top of this
  -- file said the art was out of reach.  It is not: the player's own face is
  -- also the RIVAL'S -- whichever of the pair you did not choose is who you
  -- fight -- so both are in gTrainerFrontPicTable, and extractTrainerSprites
  -- writes field.playerForms with each one's file, read off the PKMN TRAINER
  -- rows the cartridge names BRENDAN and MAY.  Sprites.playerForm picks the
  -- one matching the save's gender, which is the same mechanism Crystal's
  -- KRIS uses.
  --
  -- Drawn before the rows so the fields sit over it if the two ever overlap,
  -- and skipped silently when there is no picture -- a cache imported before
  -- the portraits were derived must still show a usable card.
  do
    local Sprites = require("src.pokemon.Sprites")
    local path = Sprites.playerPath(self.game.data, "front",
                                    { kind = "trainer_card",
                                      save = self.game.save })
    if type(path) == "string" then
      local Assets = require("src.render.Assets")
      local okImg, img = pcall(Assets.image, path)
      if okImg and img then
        love.graphics.setColor(1, 1, 1, 1)
        local px = (CARD.tx + CARD.tw) * 8 - img:getWidth() - 8
        local py = (CARD.ty + 3) * 8
        love.graphics.draw(img, px, py)
        love.graphics.setColor(0, 0, 0, 1)
      end
    end
  end

  local y = (CARD.ty + 3) * 8 + FIRST_ROW
  for _, row in ipairs(self:rows()) do
    Font.draw(row[1], LABEL_X, y + inset)
    Font.draw(row[2], VALUE_X, y + inset)
    y = y + ROW_PITCH
  end

  -- THE BADGE ROW, at the cartridge's own coordinates: the first badge four
  -- tiles in, three tiles between them, on rows fifteen and sixteen.
  local game = self.game
  local list = Badges.list(game.data)
  for i, entry in ipairs(list) do
    if Badges.has(game.save, entry) then
      local x, y = (BADGE_FIRST_TX + (i - 1) * BADGE_STEP_TX) * 8, BADGE_TY * 8
      local image = Gen3BadgeArt.image(game.data, i)
      if image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, x, y)
      else
        -- no sheet in this cache: the block of colour this card used to draw
        love.graphics.setColor(0.95, 0.82, 0.30, 1)
        love.graphics.rectangle("fill", x + 2, y + 2, 12, 12)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3TrainerCard
