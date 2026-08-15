-- The ancient writing on the Ruins of Alph chamber walls.
--
-- DisplayUnownWords (22:$6E68) is what the wall scripts run after their
-- "Patterns appear on the wall!" line: it opens a window, copies one of the
-- four words out of UnownWalls as 2x2 tile blocks taken from the CHAMBER'S OWN
-- tileset, recolours them, and waits for A or B.  Without it the line printed
-- and nothing else happened, which is the whole point of the wall.
--
-- The glyphs are ordinary tileset tiles, so this screen blits them straight
-- out of the tileset atlas the map is already using -- the same 8x8 grid
-- TileRenderer draws the room from.

local Assets = require("src.render.Assets")
local Sound = require("src.core.Sound")

local UnownWall = {}
UnownWall.__index = UnownWall

local TILE = 8

-- _CopyWord.ConvertChar (22:$6F1C).  A run byte is normally the top-left tile
-- of a 2x2 block laid out `a, a+1` over `a+$10, a+$10+1`; three ids are not
-- glyph bases and are spelled out tile by tile instead.
local LITERAL = {
  [0x60] = { 0x5B, 0x5C, 0x4D, 0x5D },   -- Y
  [0x62] = { 0x4E, 0x4F, 0x5E, 0x5F },   -- Z
  [0x64] = { 0x02, 0x03, 0x03, 0x02 },   -- the dash
}

-- The run bytes are VRAM BANK 1 tile numbers -- that is what
-- _DisplayUnownWords_FillAttr's `cp $60 / ld a, $0D` is doing, since bit 3 of
-- a BG attribute byte is the bank bit and $0D has it set.  The port's tileset
-- atlas is the flat 192-tile sheet with bank 0 first, so bank 1 tile N is
-- atlas tile 96 + N, and the whole Unown alphabet sits in that upper half.
--
-- Reading the ids as bank 0 -- straight atlas indices -- drew the chamber's
-- own bricks and doors instead of the writing.
--
-- The three ids FillAttr hands attribute $05 (bank bit clear) are the ones
-- ConvertChar spells out literally, and those really are bank 0, so they stay
-- unshifted.
local GLYPH_BANK1 = 96

local function glyphTiles(id)
  local literal = LITERAL[id]
  if literal then return literal end
  local base = id + GLYPH_BANK1
  return { base, base + 1, base + 0x10, base + 0x10 + 1 }
end

function UnownWall.new(game, opts)
  local self = setmetatable({}, UnownWall)
  opts = opts or {}
  self.game = game
  self.onDone = opts.onDone
  local walls = ((game.data.field or {}).gen2UnownWalls) or {}
  local index = (tonumber(opts.word) or 0) + 1
  self.word = (walls.words or {})[index] or {}
  self.box = (walls.boxes or {})[index] or { x1 = 3, y1 = 4, x2 = 16, y2 = 9 }
  -- the tileset the chamber is drawn with; its atlas holds the glyphs, and
  -- they are drawn in the room's own colours -- FillAttr stamps BG palette 5
  -- over the word, it does not strip it to black and white
  local ow = game.overworld
  local name = ow and ow.map and ow.map.def and ow.map.def.tileset
  local def = name and (game.data.tilesets or {})[name]
  if def and def.image then
    local ok, img = pcall(Assets.image, def.image)
    if ok then self.atlas = img end
  end
  return self
end

function UnownWall:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function UnownWall:drawTile(id, x, y)
  local img = self.atlas
  if not img then return end
  local perRow = math.max(1, math.floor(img:getWidth() / TILE))
  local sx = (id % perRow) * TILE
  local sy = math.floor(id / perRow) * TILE
  if sy + TILE > img:getHeight() then return end
  local quad = love.graphics.newQuad(sx, sy, TILE, TILE, img:getDimensions())
  love.graphics.draw(img, quad, x, y)
end

function UnownWall:draw()
  local box = self.box
  local px, py = box.x1 * TILE, box.y1 * TILE
  local pw = (box.x2 - box.x1 + 1) * TILE
  local ph = (box.y2 - box.y1 + 1) * TILE
  -- MenuBox: the plain white frame the ROM opens over the room
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", px + 1.5, py + 1.5, pw - 3, ph - 3)
  love.graphics.setColor(1, 1, 1, 1)
  -- MenuBoxCoord2Tile, then `inc hl` and two rows down, puts the first glyph
  -- one column in and two rows below the box's corner.  _CopyWord's loop then
  -- ends each glyph with `inc hl / inc hl` -- TWO COLUMNS, so the word runs
  -- LEFT TO RIGHT.  Stacking it downwards instead is what turned "ESCAPE"
  -- into a totem pole.
  local ox = (box.x1 + 1) * TILE
  local oy = (box.y1 + 2) * TILE
  for i, id in ipairs(self.word) do
    local tiles = glyphTiles(id)
    local gx = ox + (i - 1) * TILE * 2
    self:drawTile(tiles[1], gx, oy)
    self:drawTile(tiles[2], gx + TILE, oy)
    self:drawTile(tiles[3], gx, oy + TILE)
    self:drawTile(tiles[4], gx + TILE, oy + TILE)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return UnownWall
