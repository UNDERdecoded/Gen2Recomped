-- The field HUD drawn from the cartridge's own BG0 tiles (src/ui.c).
--
-- InitUI loads gfx group 16 ($0600C000, BG0 char base 3) and palette group
-- 12 (global palette 12 -> slot 15).  BG0 map entries:
--   hearts  row 1 from column 0: tile $10 (the cap), then gUnk_080C8F2C
--           entries ($15 full, $11 empty); a partly full heart is tile
--           (health & 3) + $11; a second row (row 2) past ten hearts
--   rupees  rows 18-19: the wallet icon tiles (gWalletSizes iconStartTile,
--           2x2) at column 24, then three 8x16 digits (RenderDigits copies
--           RupeeKeyDigits glyphs into tiles $70-$75), yellow when full.
-- gHUD.health / gHUD.rupees count towards the save one step a frame, as
-- DrawHearts / DrawRupees do.

local bit = require("bit")
local band = bit.band

local Hud = {}
Hud.__index = Hud

local WALLET = { [0] = { 100, 0x60 }, { 300, 0x64 }, { 500, 0x68 }, { 999, 0x6C } }

local function decodeTiles(bytes, pal, count)
  local n = count or math.floor(#bytes / 32)
  local cols = 16
  local rows = math.ceil(n / cols)
  local img = love.image.newImageData(cols * 8, math.max(8, rows * 8))
  for t = 0, n - 1 do
    local ox, oy = (t % cols) * 8, math.floor(t / cols) * 8
    for py = 0, 7 do
      for px = 0, 7 do
        local byte = bytes:byte(t * 32 + py * 4 + math.floor(px / 2) + 1) or 0
        local ci = px % 2 == 0 and byte % 16 or math.floor(byte / 16)
        if ci ~= 0 then
          local c = pal[ci] or { 255, 0, 255 }
          img:setPixel(ox + px, oy + py, c[1] / 255, c[2] / 255, c[3] / 255, 1)
        end
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  return image, cols
end

function Hud.new(assets)
  local self = setmetatable({ assets = assets, health = nil, rupees = nil, tick = 0 }, Hud)
  local m = assets.manifest
  local st = assets.store
  local tiles = st:read("hud.bin")
  local digits = st:read("digits.bin")
  if not (m.ui and tiles and #tiles > 0 and digits) then return self end
  local pal = assets:paletteColors(m.ui.hudPalette or 12)
  self.tiles, self.cols = decodeTiles(tiles, pal)
  self.hearts = m.ui.hearts
  -- digits: 10 white then 10 yellow glyphs, each two stacked tiles
  self.digits = decodeTiles(digits, pal, 40)
  self.quads = {}
  self.ok = true
  return self
end

function Hud:quad(img, t, cols)
  local key = tostring(img) .. t
  local q = self.quads[key]
  if not q then
    local w, h = img:getDimensions()
    q = love.graphics.newQuad((t % cols) * 8, math.floor(t / cols) * 8, 8, 8, w, h)
    self.quads[key] = q
  end
  return q
end

function Hud:tile(t, x, y)
  love.graphics.draw(self.tiles, self:quad(self.tiles, band(t, 0x3FF), self.cols), x, y)
end

-- one step towards the save values per frame (DrawHearts / DrawRupees)
function Hud:update(stats, sound)
  local target = (stats.health or 0) ~= 1 and math.floor((stats.health or 0) / 2) or 1
  local maxH = math.floor((stats.maxHealth or 24) / 2)
  if target > maxH then target = maxH end
  self.health = self.health or target
  self.tick = self.tick + 1
  if target > self.health then
    if self.tick % 2 == 0 then
      if self.tick % 8 == 0 and sound then sound(0x6B) end -- SFX_HEART_GET
      self.health = self.health + 1
    end
  elseif target < self.health then
    self.health = self.health - 1
  end
  local r = stats.rupees or 0
  self.rupees = self.rupees or r
  if self.rupees ~= r then
    self.rupees = self.rupees + (self.rupees < r and 1 or -1)
    if self.tick % 4 == 0 and sound then sound(0x6C) end -- SFX_RUPEE_GET
  end
end

function Hud:draw(stats, keys)
  if not self.ok then return false end
  -- DrawKeys: in an area with keys, the key icon (tiles $1C-$1F) at
  -- gBG0Buffer[$219] (column 25, row 16) and two white digits after it
  -- (RenderDigits($76, keys, 0, 2))
  if keys then
    self:tile(0x1C, 200, 128); self:tile(0x1D, 208, 128)
    self:tile(0x1E, 200, 136); self:tile(0x1F, 208, 136)
    local k = math.max(0, math.min(99, keys))
    for i, d in ipairs({ math.floor(k / 10), k % 10 }) do
      love.graphics.draw(self.digits, self:quad(self.digits, d * 2, 16), 216 + (i - 1) * 8, 128)
      love.graphics.draw(self.digits, self:quad(self.digits, d * 2 + 1, 16), 216 + (i - 1) * 8, 136)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  local maxH = math.floor((stats.maxHealth or 24) / 2)
  local health = self.health or 0
  local full = math.floor(health / 4)
  local hearts = math.floor(maxH / 4)
  for row = 0, (hearts > 10) and 1 or 0 do
    local y = 8 + row * 8
    self:tile(0x10, 0, y)
    local n = row == 0 and math.min(hearts, 10) or hearts - 10
    local f = row == 0 and math.min(full, 10) or math.max(0, full - 10)
    for i = 0, n - 1 do
      local entry = self.hearts[(10 - f) + i] or 0xF011
      self:tile(entry, 8 + i * 8, y)
    end
  end
  if health % 4 ~= 0 then
    local slot = full
    local y = 8
    if slot > 9 then slot = slot - 10; y = 16 end
    self:tile((health % 4) + 0x11, 8 + slot * 8, y)
  end
  -- rupees
  local wallet = WALLET[stats.walletType or 0] or WALLET[0]
  local icon = wallet[2]
  self:tile(icon, 192, 144); self:tile(icon + 1, 200, 144)
  self:tile(icon + 2, 192, 152); self:tile(icon + 3, 200, 152)
  local yellow = (self.rupees or 0) >= wallet[1]
  local v = math.max(0, math.min(999, self.rupees or 0))
  local ds = { math.floor(v / 100), math.floor(v / 10) % 10, v % 10 }
  for i, d in ipairs(ds) do
    local t = (yellow and 20 or 0) + d * 2
    love.graphics.draw(self.digits, self:quad(self.digits, t, 16), 208 + (i - 1) * 8, 144)
    love.graphics.draw(self.digits, self:quad(self.digits, t + 1, 16), 208 + (i - 1) * 8, 152)
  end
  return true
end

return Hud
