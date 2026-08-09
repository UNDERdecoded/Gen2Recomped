-- The Ruins of Alph wall puzzle (`special 41` -> UnownPuzzle, 3:$44BA).
--
-- A 6x6 board holds 16 picture pieces.  They start scattered around the
-- border (InitUnownPuzzlePiecePositions.PuzzlePieceInitialPositions,
-- 56:$5A7A) and the puzzle is solved when they sit in the middle 4x4 in
-- reading order (CheckSolvedUnownPuzzle.SolvedPuzzleConfiguration,
-- 56:$5CC2).  Both layouts are extracted from the ROM rather than retyped.
--
-- Controls follow the original: the D-pad walks a cursor over the board, A
-- picks up the piece under it and A again drops the carried piece on an
-- empty cell (UnownPuzzle_CheckCurrentTileOccupancy gates the drop), B puts
-- a carried piece back, START gives up.
--
-- Art: LoadUnownPuzzlePiecesGFX decompresses a 48x48 picture and
-- EnlargePuzzlePieceTiles pixel-doubles it to 96x96, cutting sixteen 24x24
-- pieces (3x3 tiles) out of the result -- so one source piece is a 12x12
-- window of the extracted PNG drawn at 2x.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Assets = require("src.render.Assets")
local PaletteFX = require("src.render.PaletteFX")

local UnownPuzzle = {}
UnownPuzzle.__index = UnownPuzzle
UnownPuzzle.isOpaque = true

local CELL = 24            -- an enlarged piece is 3 tiles square
local SRC = 12             -- ...cut from a 12x12 window of the source art

-- board origin: the 6x6 grid centred on the 160x144 screen
local ORIGIN_X = (160 - 6 * CELL) / 2
local ORIGIN_Y = 0

local function defaultLayout()
  -- a cache imported before the puzzle stage existed still has to play
  local start, solved = {}, {}
  for i = 1, 16 do start[i] = i - 1 end
  for i = 1, 36 do solved[i] = 0 end
  local n = 0
  for row = 1, 4 do
    for col = 1, 4 do
      n = n + 1
      solved[row * 6 + col + 1] = n
    end
  end
  return { width = 6, height = 6, pieces = 16, start = start, solved = solved,
           puzzles = {} }
end

-- pictureIndex is the script's `setval` argument: 0 Kabuto, 1 Omanyte,
-- 2 Aerodactyl, 3 Ho-Oh.  onDone(solved) resumes the script.
function UnownPuzzle.new(game, pictureIndex, onDone)
  local def = (game.data and game.data.unown_puzzle) or defaultLayout()
  local self = setmetatable({
    game = game,
    def = def,
    onDone = onDone,
    picture = def.puzzles and def.puzzles[(pictureIndex or 0) + 1] or nil,
    cursor = 0,          -- board index 0..35
    held = nil,          -- piece number being carried
    board = {},          -- board index (1-based) -> piece number or 0
  }, UnownPuzzle)
  for i = 1, def.width * def.height do self.board[i] = 0 end
  for piece = 1, def.pieces do
    local cell = (def.start[piece] or (piece - 1)) + 1
    self.board[cell] = piece
  end
  return self
end

function UnownPuzzle:solved()
  for i = 1, self.def.width * self.def.height do
    if self.board[i] ~= (self.def.solved[i] or 0) then return false end
  end
  return true
end

function UnownPuzzle:finish(won)
  self.game.stack:pop()
  if self.onDone then self.onDone(won) end
end

function UnownPuzzle:update()
  local input = self.game.input
  local w, h = self.def.width, self.def.height
  local col, row = self.cursor % w, math.floor(self.cursor / w)
  if input:wasPressed("left") then col = (col - 1) % w end
  if input:wasPressed("right") then col = (col + 1) % w end
  if input:wasPressed("up") then row = (row - 1) % h end
  if input:wasPressed("down") then row = (row + 1) % h end
  self.cursor = row * w + col

  if input:wasPressed("start") then
    -- give up: the wall stays shut, exactly like walking away
    self:finish(false)
    return
  end

  if input:wasPressed("b") and self.held then
    self.board[self.heldFrom] = self.held
    self.held, self.heldFrom = nil, nil
    Sound.play(self.game.data, "Wrong")
    return
  end

  if input:wasPressed("a") then
    local cell = self.cursor + 1
    if self.held then
      if self.board[cell] == 0 then
        self.board[cell] = self.held
        self.held, self.heldFrom = nil, nil
        Sound.play(self.game.data, "Press_AB")
        if self:solved() then self:finish(true) end
      else
        Sound.play(self.game.data, "Wrong")
      end
    elseif self.board[cell] ~= 0 then
      self.held, self.heldFrom = self.board[cell], cell
      self.board[cell] = 0
      Sound.play(self.game.data, "Press_AB")
    end
  end
end

-- The four DMG shades of the extracted picture, mapped to the palette the
-- hardware loads for this screen; nil in DMG modes, where the shade-remap
-- shader owns the colour instead.
function UnownPuzzle:palette()
  if not PaletteFX.usesGbcPack() then return nil end
  local pal = self.def.palette
  if type(pal) ~= "table" or #pal < 4 then return nil end
  return pal
end

function UnownPuzzle:image()
  if self._image ~= nil then return self._image or nil end
  local path = self.picture and self.picture.image
  local img = false
  if path and Assets.exists(path) then
    local pal = self:palette()
    local ok, loaded
    if pal and love.image and love.image.newImageData then
      ok, loaded = pcall(function()
        local id = Assets.imageData(path)
        id:mapPixel(function(_, _, r, _, _, a)
          local col = r > 0.83 and pal[1] or r > 0.5 and pal[2]
            or r > 0.17 and pal[3] or pal[4]
          return col[1] / 255, col[2] / 255, col[3] / 255, a
        end)
        return love.graphics.newImage(id)
      end)
    else
      ok, loaded = pcall(love.graphics.newImage, Assets.resolve(path))
    end
    if ok then img = loaded end
  end
  self._image = img
  return img or nil
end

function UnownPuzzle:drawPiece(piece, x, y)
  local img = self:image()
  if not img then
    -- no art in the cache: the piece number still makes the puzzle playable
    love.graphics.rectangle("line", x, y, CELL, CELL)
    Font.draw(tostring(piece), x + 8, y + 8)
    return
  end
  local index = piece - 1
  local quad = love.graphics.newQuad(
    (index % 4) * SRC, math.floor(index / 4) * SRC, SRC, SRC,
    img:getDimensions())
  love.graphics.draw(img, quad, x, y, 0, CELL / SRC, CELL / SRC)
end

function UnownPuzzle:draw()
  local pal = self:palette()
  if pal then
    love.graphics.setColor(pal[1][1] / 255, pal[1][2] / 255, pal[1][3] / 255, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  love.graphics.setColor(1, 1, 1, 1)
  local w, h = self.def.width, self.def.height
  for row = 0, h - 1 do
    for col = 0, w - 1 do
      local piece = self.board[row * w + col + 1]
      if piece and piece ~= 0 then
        self:drawPiece(piece, ORIGIN_X + col * CELL, ORIGIN_Y + row * CELL)
      end
    end
  end
  -- cursor
  local cx = ORIGIN_X + (self.cursor % w) * CELL
  local cy = ORIGIN_Y + math.floor(self.cursor / w) * CELL
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", cx + 0.5, cy + 0.5, CELL - 1, CELL - 1)
  if self.held then
    self:drawPiece(self.held, cx + 4, cy + 4)
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("START:QUIT", 8, 144 - 16)
  love.graphics.setColor(1, 1, 1, 1)
  if pal then PaletteFX.markTrueColor(0, 0, 160, 144) end
end

return UnownPuzzle
