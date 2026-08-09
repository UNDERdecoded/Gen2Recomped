-- Trainer card (engine/menus/start_sub_menus.asm DrawTrainerInfo):
-- NAME / MONEY / TIME with the player's front pic upper-right, the
-- circle-dotted BADGES banner, and the numbered badge grid.  The boxes
-- are built from the real trainer_info.png frame tiles (the patterned
-- band + line style).

local Assets = require("src.render.Assets")
local Badges = require("src.inventory.Badges")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local TrainerCard = {}
TrainerCard.__index = TrainerCard
TrainerCard.isOpaque = true

-- SGB: PalPacket_TrainerCard leads with MEWMON.
--
-- Generation 2's card is a CGB screen, not an SGB one.  _CGB_TrainerCard
-- fills the whole attrmap with Falkner's trainer-class palette and cuts the
-- 5x7 player-pic box out in Chris's, so those two are all the port needs:
-- the eight badge boxes are already baked into the extracted slot art, and
-- drawGen2 marks that grid true-colour so this wash leaves it alone.
local GEN2_CARD_PAL = {
  { 255, 255, 255 }, { 222, 140, 115 }, { 58, 41, 255 }, { 0, 0, 0 },
}
local GEN2_PIC_PAL = {
  { 255, 255, 255 }, { 206, 148, 99 }, { 181, 74, 41 }, { 0, 0, 0 },
}

function TrainerCard:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  if self.gen2 then
    return {
      P.whole(GEN2_CARD_PAL),
      P.zone(GEN2_PIC_PAL, 14, 1, 18, 7),
      -- the top-right corner keeps the border's palette
      P.zone(GEN2_CARD_PAL, 18, 1, 18, 1),
    }
  end
  return P.wholeNamed(game.data, "MEWMON")
end

-- through Assets.resolve so an enabled mod's overrides/ shadows these the
-- same way it shadows every other generated asset
local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
  return ok and img or nil
end

local function quads16(img, count, stride, x0, y0)
  local q = {}
  local iw, ih = img:getDimensions()
  count = math.min(count, math.floor((ih - (y0 or 0)) / stride))
  for i = 0, count - 1 do
    q[i] = love.graphics.newQuad(x0 or 0, (y0 or 0) + i * stride, 16, 16, iw, ih)
  end
  return q
end

-- one grid page; Gen2 carries sixteen badges and its card pages Johto/Kanto
local PER_PAGE = 8

-- Generation 2 badge boxes: TrainerCard_Page2_3_InitObjectsAndStrings walks
-- the tilemap from coord (2,10) and again from (2,13), four columns apart.
local GEN2_SLOT_X = { 16, 48, 80, 112 }
local GEN2_SLOT_Y = { 80, 104 }
-- the shade the remap shader turns into palette color 2
local GEN2_SHADE2 = 0.33

function TrainerCard.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, onCancel = opts.onCancel, page = 0 },
                            TrainerCard)
  self.gen2 = require("src.core.GameVersion").isGen2()
  if self.gen2 then
    local slots = tryImage("assets/generated/trainer_card/gen2_slots.png")
    if slots then
      local iw, ih = slots:getDimensions()
      self.slots = { img = slots, plate = {}, face = {} }
      for i = 0, math.floor(ih / 24) - 1 do
        self.slots.plate[i] = love.graphics.newQuad(0, i * 24, 8, 8, iw, ih)
        self.slots.face[i] = love.graphics.newQuad(8, i * 24, 24, 24, iw, ih)
      end
    end
    local marks = tryImage("assets/generated/trainer_card/gen2_badges.png")
    if marks then
      self.marks = { img = marks, quads = quads16(marks, 16, 16, 0, 0) }
    end
  end
  local img = tryImage("assets/generated/trainer_card/badges.png")
  if img then
    -- badges.2bpp is stacked [face, badge] pairs (DrawBadges FaceBadgeTiles);
    -- the Gen2 rip leaves the face slot empty, which is what its card shows
    self.faces = { img = img, quads = quads16(img, 16, 32, 0, 0) }
    self.badges = { img = img, quads = quads16(img, 16, 32, 0, 16) }
  end
  local nums = tryImage("assets/generated/trainer_card/badge_numbers.png")
  if nums then
    self.nums = { img = nums, quads = {} }
    local iw, ih = nums:getDimensions()
    for i = 0, 7 do
      self.nums.quads[i] = love.graphics.newQuad((i % 2) * 8,
                                                 math.floor(i / 2) * 8,
                                                 8, 8, iw, ih)
    end
  end
  -- frame tiles (3x3 sheet): 0 bottom, 1 right, 2 tl, 3 top, 4 tr,
  -- 5 left, 6 bl, 7 br, 8 solid pattern
  local frame = tryImage("assets/generated/trainer_card/trainer_info.png")
  if frame then
    self.frame = { img = frame, quads = {} }
    for i = 0, 8 do
      self.frame.quads[i] = love.graphics.newQuad((i % 3) * 8,
                                                  math.floor(i / 3) * 8,
                                                  8, 8, frame:getDimensions())
    end
  end
  self.circle = tryImage("assets/generated/trainer_card/circle_tile.png")
  self.pic = tryImage(require("src.pokemon.Sprites").playerPath(
    game.data, "front", { kind = "trainer_card" }))
  return self
end

function TrainerCard:update(dt)
  local input = self.game.input
  -- Gen2 pages the whole card, not just the badge grid: page 1 is the dex
  -- and play-time half (TrainerCard_Page1_PrintDexCaught_GameTime), pages 2
  -- and 3 the Johto and Kanto badges
  local pages = self.gen2 and 3
    or math.ceil(#Badges.list(self.game.data) / PER_PAGE)
  -- TrainerCard_Page2_Joypad: d-left/d-right walk the badge pages
  if pages > 1 and input:wasPressed("right") then
    self.page = (self.page + 1) % pages
    return
  end
  if pages > 1 and input:wasPressed("left") then
    self.page = (self.page - 1) % pages
    return
  end
  -- either button dismisses the card back to the start menu
  -- (StartMenu_TrainerInfo: WaitForTextScrollButtonPress then
  -- RedisplayStartMenu)
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end
end

-- a frame box in tile coords from the trainer_info tiles
function TrainerCard:frameBox(tx, ty, tw, th)
  if not self.frame then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", tx * 8 + 0.5, ty * 8 + 0.5,
                            tw * 8 - 1, th * 8 - 1)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local img, q = self.frame.img, self.frame.quads
  love.graphics.setColor(1, 1, 1, 1)
  local x1, y1 = (tx + tw - 1) * 8, (ty + th - 1) * 8
  love.graphics.draw(img, q[2], tx * 8, ty * 8)
  love.graphics.draw(img, q[4], x1, ty * 8)
  love.graphics.draw(img, q[6], tx * 8, y1)
  love.graphics.draw(img, q[7], x1, y1)
  for i = 1, tw - 2 do
    love.graphics.draw(img, q[3], (tx + i) * 8, ty * 8)
    love.graphics.draw(img, q[0], (tx + i) * 8, y1)
  end
  for j = 1, th - 2 do
    love.graphics.draw(img, q[5], tx * 8, (ty + j) * 8)
    love.graphics.draw(img, q[1], x1, (ty + j) * 8)
  end
end

-- Generation 2's card (engine/menus/trainer_card.asm).
--
-- TrainerCard_PrintTopHalfOfCard places "NAME/" at tilemap (2,2) with the
-- player's name at (7,2), the ID plate at (2,4) with a five digit number at
-- (5,4), "MONEY" at (2,6) with six digits at (7,6), a rule across row 3 and
-- the player's 5x7 pic at (14,1) -- the string's two <NEXT> codes step two
-- rows apiece, which is what puts MONEY on row 6 where its PrintNum is.
-- Page 1 adds "POKeDEX" at (2,10) with the caught count at (15,10),
-- "PLAY TIME" two rows under it, and a "BADGES" prompt at (12,15).
function TrainerCard:drawGen2()
  local save = self.game.save
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  -- the card's own one-tile frame sits on shade 2, which the screen fill
  -- (_CGB_TrainerCard's falkner) turns blue
  love.graphics.setColor(GEN2_SHADE2, GEN2_SHADE2, GEN2_SHADE2, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 8)
  love.graphics.rectangle("fill", 0, 136, 160, 8)
  love.graphics.rectangle("fill", 0, 8, 8, 128)
  love.graphics.rectangle("fill", 152, 8, 8, 128)

  love.graphics.setColor(1, 1, 1, 1)
  if self.pic then love.graphics.draw(self.pic, 112, 8) end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("NAME/"), 16, 16)
  Font.draw(save.player.name or "GOLD", 56, 16)
  love.graphics.rectangle("fill", 8, 30, 104, 1)
  Font.draw(Strings("ID No."), 16, 32)
  Font.draw(("%05d"):format(save.player.id or 0), 72, 32)
  Font.draw(Strings("MONEY"), 16, 48)
  Font.draw(("¥%6d"):format(save.money or 0), 56, 48)

  if self.page == 0 then
    local dex = save.pokedex or {}
    local caught = 0
    for _ in pairs(dex.owned or {}) do caught = caught + 1 end
    Font.draw(Strings("POKéDEX"), 16, 80)
    Font.draw(("%3d"):format(caught), 120, 80)
    local t = math.floor(save.playTime or 0)
    Font.draw(Strings("PLAY TIME"), 16, 96)
    Font.draw(("%3d:%02d"):format(math.floor(t / 3600),
                                  math.floor(t / 60) % 60), 104, 96)
    Font.draw(Strings("BADGES"), 96, 120)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- badge pages: the leader's face always, the badge laid over it once won
  local badges = Badges.list(self.game.data)
  local first = (self.page - 1) * PER_PAGE
  Font.draw(Strings("BADGES"), 16, 64)
  for slot = 0, math.min(PER_PAGE, #badges - first) - 1 do
    local i = first + slot + 1
    local x = GEN2_SLOT_X[slot % 4 + 1]
    local y = GEN2_SLOT_Y[math.floor(slot / 4) + 1]
    love.graphics.setColor(1, 1, 1, 1)
    if self.slots and self.slots.face[i - 1] then
      love.graphics.draw(self.slots.img, self.slots.plate[i - 1], x, y)
      love.graphics.draw(self.slots.img, self.slots.face[i - 1], x + 8, y)
    end
    if Badges.has(save, badges[i]) and self.marks and self.marks.quads[i - 1] then
      love.graphics.draw(self.marks.img, self.marks.quads[i - 1], x, y + 8)
    end
    -- the slot art already carries that leader's own palette
    require("src.render.PaletteFX").markTrueColor(x, y, 32, 24)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function TrainerCard:draw()
  if self.gen2 then return self:drawGen2() end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local save = self.game.save

  -- top card (rows 0-7): NAME / MONEY / TIME, pic upper-right
  self:frameBox(0, 0, 20, 8)
  if self.pic then
    love.graphics.draw(self.pic, 104, 4)
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("NAME/%s", save.player.name or "RED"), 16, 16)
  Font.draw(("MONEY/¥%d"):format(save.money or 0), 16, 32)
  local t = math.floor(save.playTime or 0)
  Font.draw(("TIME/%3d:%02d"):format(math.floor(t / 3600),
                                     math.floor(t / 60) % 60), 16, 48)

  -- the circle-dotted BADGES banner (TrainerInfo_BadgesText)
  self:frameBox(0, 8, 20, 3)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("BADGES"), 56, 72)
  if self.circle then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.circle, 48, 72)
    love.graphics.draw(self.circle, 104, 72)
    love.graphics.setColor(0, 0, 0, 1)
  end

  -- numbered badge grid (rows 11-17): face by default, badge when owned
  self:frameBox(0, 11, 20, 7)
  local badges = Badges.list(self.game.data)
  local first = self.page * PER_PAGE
  for slot = 0, math.min(PER_PAGE, #badges - first) - 1 do
    local i = first + slot + 1
    local col, row = slot % 4, math.floor(slot / 4)
    local tx, ty = 16 + col * 32, 94 + row * 24
    -- the extracted sheets cover the eight Kanto slots; a longer badge
    -- list draws its extra entries unnumbered rather than crashing
    if self.nums and self.nums.quads[slot] then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self.nums.img, self.nums.quads[slot], tx, ty)
    end
    if self.faces and self.faces.quads[i - 1] then
      love.graphics.setColor(1, 1, 1, 1)
      local sheet = Badges.has(save, badges[i]) and self.badges or self.faces
      love.graphics.draw(sheet.img, sheet.quads[i - 1], tx + 4, ty + 6)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return TrainerCard
