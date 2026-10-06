-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MINING GAME'S SCREEN.
--
-- Everything under it is already built and measured: `Gen4Mining` is what can be
-- buried, `Gen4MiningWall` puts it in a wall, `Gen4MiningSpots` says which walls
-- may be dug and `Gen4MiningDig` is the rules.  This draws it and takes the taps.
--
-- IT IS PLAYED WITH A FINGER AND NOTHING ELSE, which is why `Game:touchpressed`
-- had to learn to offer a pointer to the top state first.  Platinum has no button
-- binding for this to copy: the whole game is the bottom screen.  The d-pad
-- selects nothing here, and B is the port's own way out rather than the
-- cartridge's -- see `close` below.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")
local Bag = require("src.inventory.Bag")
local Mining = require("src.import.Gen4Mining")
local MiningWall = require("src.world.Gen4MiningWall")
local Dig = require("src.world.Gen4MiningDig")

local Gen4MiningScreen = {}
Gen4MiningScreen.__index = Gen4MiningScreen
Gen4MiningScreen.name = "Gen4MiningScreen"

local W, H = 256, 192

-- A mining cell is 2x2 tiles and the grid starts four tile rows down, which is
-- the cartridge's own arithmetic read backwards:
--
--     x = touchX / (TILE_WIDTH_PIXELS * 2);
--     y = touchY / (TILE_HEIGHT_PIXELS * 2) - 2;
--
-- so a cell is 16px and the grid's top edge is at 2 cells = 32px.  The grid is
-- 13x10, which puts its right edge at 208 -- and 208 is exactly the sidebar
-- test, `touchX >= MINING_GAME_WIDTH * 2 * TILE_WIDTH_PIXELS`.
local CELL = 16
local GRID_X, GRID_Y = 0, 32
local SIDEBAR_X = 208

-- sHammerButtonRectangle and sPickaxeButtonRectangle, in TILES, converted once.
-- Both are `for y = startY; y < endY`, so the ends are exclusive.
local HAMMER  = { x = 26 * 8, y = 6 * 8,  w = (32 - 26) * 8, h = (14 - 6) * 8 }
local PICKAXE = { x = 26 * 8, y = 15 * 8, w = (32 - 26) * 8, h = (23 - 15) * 8 }

-- WHICH 2x2 QUAD OF `dirt_tiles` EACH LAYER USES.  The sheet is 32 tiles in a
-- 16x2 grid (the NCGR says so), and Mining_DrawDirt names the four tile indices
-- per layer:
--
--   layer 0 { 14, 15, 30, 31 }   layer 4 { 4, 5, 20, 21 }
--   layer 1 { 10, 11, 26, 27 }   layer 5 { 2, 3, 18, 19 }
--   layer 2 {  8,  9, 24, 25 }   layer 6 { 0, 1, 16, 17 }
--   layer 3 {  6,  7, 22, 23 }
--
-- Index 14 and 15 are row 0 columns 14 and 15; 30 and 31 are row 1 of the same
-- columns.  So each layer is a column PAIR, and the pairs are 14, 10, 8, 6, 4, 2,
-- 0 -- which skips 12.  COLUMNS 12 AND 13 ARE NEVER DRAWN: the sheet holds eight
-- quads and the game uses seven, and the unused one is in the middle rather than
-- at the end.  Worth writing down because a reader deriving the column as
-- `14 - 2 * layer` gets the right answer for layer 0 and is wrong from layer 1 on.
local DIRT_COLUMN = { [0] = 14, [1] = 10, [2] = 8, [3] = 6, [4] = 4, [5] = 2, [6] = 0 }

-- The crack across the top.  Four tile rows at screen tile column 25, growing
-- LEFTWARD as the wall weakens (`tilemapBuffer[CRACK_START... - i]`), with the
-- art taken from the interface sheet at column 11 - (i % 3) of rows 0..3 --
-- the sheet is 54 tiles wide, which is what the base tiles 11, 65, 119 and 173
-- are: column 11 of each of the first four rows.
local CRACK_END_TILE = 25
local CRACK_ROWS = 4
local CRACK_SHEET_COLUMN = 11
local CRACK_SHEET_WIDTH = 54

-- PUBLISHED so a check can exercise the decisions this screen actually makes
-- rather than a second copy of them. Pass 134 was a lesson in that: assertions
-- written against a constant table and a model rebuilt inside the test passed
-- happily while the shipped function did something else.
Gen4MiningScreen.LAYOUT = {
  CELL = CELL, GRID_X = GRID_X, GRID_Y = GRID_Y, SIDEBAR_X = SIDEBAR_X,
  HAMMER = HAMMER, PICKAXE = PICKAXE, DIRT_COLUMN = DIRT_COLUMN,
  CRACK_END_TILE = CRACK_END_TILE, CRACK_ROWS = CRACK_ROWS,
  CRACK_SHEET_COLUMN = CRACK_SHEET_COLUMN, CRACK_SHEET_WIDTH = CRACK_SHEET_WIDTH,
}

-- Which cell a bottom-screen point is, or nil and why not. The inverse of the
-- cartridge's `touchX / 16` and `touchY / 16 - 2`.
function Gen4MiningScreen.cellAt(x, y)
  if x >= SIDEBAR_X then return nil, "sidebar" end
  if y < GRID_Y then return nil, "crack" end
  local cx = math.floor((x - GRID_X) / CELL)
  local cy = math.floor((y - GRID_Y) / CELL)
  if cx < 0 or cy < 0 or cx >= Mining.GRID_WIDTH or cy >= Mining.GRID_HEIGHT then
    return nil, "off the grid"
  end
  return cx, cy
end

-- Which tool a sidebar point picks, or nil between the two buttons.
--
-- Mining_ButtonTouchCheck's own test, which is NOT the drawn rectangles: both
-- comparisons are strict and the numbers are tile edges nudged inward --
--
--   26 * 8 + 6 < x < 31 * 8 + 4                       (214 < x < 252)
--   hammer   5 * 8 + 3 < y < 13 * 8 + 6               ( 43 < y < 110)
--   pickaxe 14 * 8 + 2 < y < 21 * 8 + 6               (114 < y < 174)
--
-- so the hammer's live area starts five pixels ABOVE its picture and both
-- stop short of the bottom. `x` may be omitted to ask about the rows alone.
Gen4MiningScreen.TOOL_HIT = {
  x0 = 26 * 8 + 6, x1 = 31 * 8 + 4,
  hammer = { 5 * 8 + 3, 13 * 8 + 6 },
  pickaxe = { 14 * 8 + 2, 21 * 8 + 6 },
}
function Gen4MiningScreen.toolAt(y, x)
  local T = Gen4MiningScreen.TOOL_HIT
  if x ~= nil and not (T.x0 < x and x < T.x1) then return nil end
  if T.hammer[1] < y and y < T.hammer[2] then return "hammer" end
  if T.pickaxe[1] < y and y < T.pickaxe[2] then return "pickaxe" end
  return nil
end

-- THE SPRITES' SEQUENCES (animations_anim.NANR in /data/ug_anim.narc), as
-- { cell, ticks } at 60 Hz, each played once and ending on cell 0 -- the
-- empty one. Read from the file; a cell n is `gen4_mining_art`'s anim_<n>.
Gen4MiningScreen.SEQUENCES = {
  [0] = { { 5, 2 }, { 6, 4 }, { 7, 4 }, { 8, 4 }, { 7, 4 }, { 8, 4 }, { 0, 22 } },  -- pickaxe swing
  [1] = { { 1, 2 }, { 2, 4 }, { 3, 4 }, { 4, 4 }, { 3, 4 }, { 4, 4 }, { 0, 22 } },  -- hammer swing
  [2] = { { 9, 2 }, { 0, 2 }, { 9, 2 }, { 0, 2 }, { 9, 2 }, { 0, 22 } },            -- hit a rock
  [3] = { { 10, 2 }, { 0, 2 }, { 10, 2 }, { 0, 2 }, { 10, 2 }, { 0, 22 } },         -- pickaxe impact
  [4] = { { 11, 2 }, { 0, 2 }, { 11, 2 }, { 0, 2 }, { 11, 2 }, { 0, 22 } },         -- hammer impact
  [5] = { { 12, 2 }, { 13, 2 }, { 14, 2 }, { 0, 22 } },                             -- item hit sparkle
  [6] = { { 15, 4 }, { 16, 2 }, { 17, 2 }, { 0, 44 } },                             -- hammer button
  [7] = { { 18, 4 }, { 19, 2 }, { 20, 2 }, { 0, 44 } },                             -- pickaxe button
  [8] = { { 0, 4 }, { 12, 2 }, { 13, 2 }, { 14, 2 }, { 0, 22 } },                   -- dug-up sparkles
  [9] = { { 0, 13 }, { 12, 2 }, { 13, 2 }, { 14, 2 }, { 0, 22 } },
  [10] = { { 0, 22 }, { 12, 2 }, { 13, 2 }, { 14, 2 }, { 0, 22 } },
}

-- The cell a sequence shows `tick` frames after it was set, or 0 once done.
function Gen4MiningScreen.cellOf(seq, tick)
  local frames = Gen4MiningScreen.SEQUENCES[seq]
  if not frames then return 0 end
  local t = 0
  for _, f in ipairs(frames) do
    t = t + f[2]
    if tick < t then return f[1] end
  end
  return 0
end

-- Mining_DrawWallCrack's crack-end sprite: the animation (1..6, each one
-- still cell) and Mining_CalcWallCrackEndPos's spot, before the shake.
function Gen4MiningScreen.crackEnd(integrity)
  local rounded = math.floor(integrity / 4) * 4
  local anim = 6 - math.floor((rounded % 24) / 4)
  return anim - 1, rounded + 16, 16
end

-- The message bank (underground_common) and its entries this screen prints,
-- and the bank of Underground item names with their articles.
Gen4MiningScreen.BANK = 634
Gen4MiningScreen.TEXT = {
  itemObtained = 17, pinged = 62, collapsed = 63, everything = 64, tutorial = 85,
}
Gen4MiningScreen.ITEM_ARTICLE_BANK = 629
Gen4MiningScreen.INITIAL_WALL_INTEGRITY = 196

-- Mining_CalcWallCrackEndPos and the length beside it.
local function crackLengthFor(integrity)
  local rounded = math.floor(integrity / 4) * 4 + 8
  local px = Mining.GRID_WIDTH * 2 * 8 - rounded
  return math.max(0, math.floor(px / 8))
end
Gen4MiningScreen.crackLengthFor = crackLengthFor

-- ---------------------------------------------------------------------- new --

-- `MATH_Rand32(rand, n)` is a uniform integer in 0 .. n-1.  love.math.random is
-- the engine's generator everywhere else, so it is the one used here rather than
-- a second source seeded some other way.
local function engineRand(n)
  if n <= 0 then return 0 end
  return love.math.random(0, n - 1)
end

function Gen4MiningScreen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4MiningScreen)
  self.game = game
  self.onDone = opts.onDone
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  self.rand = opts.rand or engineRand

  local save = game.save or {}
  local ug = save.underground or {}
  save.underground = ug

  -- The two questions the weights turn on.  `trainerId` is the player's public
  -- id and the cartridge takes its LOW BIT, so this is `% 2` and not a compare.
  local tid = tonumber(save.player and save.player.id) or 0
  local wall, why = MiningWall.generate({
    rand = self.rand,
    oddTID = (tid % 2) == 1,
    nationalDex = ug.nationalDex or save.nationalDex or false,
    neverMined = not ug.hasMined,
    plateMined = function(id) return (ug.minedPlates or {})[id] == true end,
  })
  if not wall then
    Logger.warn("gen4 mining: could not lay out a wall -- %s", tostring(why))
    return nil
  end
  self.wall = wall
  self.state = Dig.new(wall, self.rand)
  self.pickaxe = true            -- Mining_InitGameState starts on the pickaxe
  self.timer = 0
  self.found = {}
  self.foundIds = {}
  self.flash = 0
  -- the two buttons' BG1 blocks: Mining_InitButtons draws the pickaxe PRESSED
  self.buttons = { hammer = "up", pickaxe = "down" }
  self.pendingPress = nil
  -- the sprites (MINING_SPRITE_*), each { seq, tick, x, y } once set
  self.sprites = {}
  self.crackShown = false        -- the crack end starts off-screen (y 240)
  self.shakeTimer, self.shakeX, self.shakeY = 0, 0, 0
  self.out = {}                  -- treasures already uncovered
  -- "Something pinged in the wall! N confirmed!" -- printed at once, held
  -- ~80 frames (MINING_STATE_WAIT_2), then the tutorial the first time.
  self.phase = "intro"
  self.timer = 80
  self.neverMined = not ug.hasMined
  Gen4MiningScreen.buffer(game, tostring(wall.itemCount or 0))
  self.message = self:text("pinged")
  return self
end

-- ------------------------------------------------------------------ text --

-- slot by slot from 0, like every Gen 4 `buffer`
function Gen4MiningScreen.buffer(game, ...)
  local T = require("src.import.Gen4Text")
  T.buffer(game, ...)
end

-- A bank-634 line by name, markup run, or nil when the cache has no text.
function Gen4MiningScreen:text(name)
  local T = require("src.import.Gen4Text")
  local line = T.resolve((self.game or {}).data, Gen4MiningScreen.BANK,
                         Gen4MiningScreen.TEXT[name], self.game)
  if type(line) ~= "string" or line == "" then return nil end
  return line
end

-- "An Everstone\nwas obtained." -- the name with its article out of bank 629
-- (StringTemplate_SetUndergroundItemNameWithArticle, slot 2), capitalised
-- (UndergroundTextPrinter_CapitalizeArgAtIndex), into entry 17.
function Gen4MiningScreen:obtainedLine(objId, constant)
  local T = require("src.import.Gen4Text")
  local data = (self.game or {}).data
  local name = T.resolve(data, Gen4MiningScreen.ITEM_ARTICLE_BANK, objId, self.game)
  if type(name) ~= "string" or name == "" then
    name = constant and constant:gsub("^ITEM_", ""):gsub("_", " ") or "?"
  end
  name = name:gsub("^%l", string.upper)
  Gen4MiningScreen.buffer(self.game, "", "", name)
  return self:text("itemObtained") or (name .. "\n" .. Strings("was obtained."))
end

-- The pages of a message: the cartridge's scroll/clear marks (\v, \f) split it.
local function pages(text)
  local out = {}
  for page in (tostring(text) .. "\v"):gmatch("([^\v\f]*)[\v\f]") do
    if page ~= "" then out[#out + 1] = page end
  end
  return out
end
Gen4MiningScreen.pages = pages

-- Queue messages, each held `hold` frames (the cartridge's textTimer 60)
-- unless A or a tap moves it on; nil holds until A or a tap.
function Gen4MiningScreen:say(list, after)
  self.queue = {}
  for _, m in ipairs(list) do
    for _, p in ipairs(pages(m.text)) do
      self.queue[#self.queue + 1] = { text = p, hold = m.hold }
    end
  end
  self.after = after
  self.advance = false
  self:nextMessage()
end

function Gen4MiningScreen:nextMessage()
  local m = self.queue and table.remove(self.queue, 1)
  if not m then
    self.message = nil
    local after = self.after
    self.after = nil
    if after then after() end
    return
  end
  self.message = m.text
  self.messageHold = m.hold
end

function Gen4MiningScreen:uiSize() return W, H end
function Gen4MiningScreen:wantsFillScale() return true end

-- ------------------------------------------------------------------ art --

function Gen4MiningScreen:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local got, image = pcall(Assets.image, path)
    self.cache[path] = got and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- The art lands under `underground/` once the two UG archives have been
-- extracted.  A cache imported before that has none of it, and the screen still
-- has to be playable -- so every picture is optional and the fallbacks below are
-- flat colour.  Saying so once beats a screen that is silently blank.
function Gen4MiningScreen:warnOnce()
  if self.warned then return end
  self.warned = true
  Logger.info("gen4 mining: no underground art in this cache -- re-import to "
              .. "get ug_parts and ug_fossil; drawing placeholders")
end

-- ---------------------------------------------------------------- input --

function Gen4MiningScreen:close(result)
  if self.closed then return end
  self.closed = true
  self.game.stack:pop()
  if self.onDone then self.onDone(result) end
end

-- What the player walks away with.  `Gen4Mining.bagItem` gives the cartridge's
-- own ITEM_* constant; this dataset keys items by number, so the two are joined
-- on the display name -- checked to resolve for all forty-nine.
function Gen4MiningScreen:itemIdFor(constant)
  if not constant then return nil end
  if not self.itemsByName then
    local out = {}
    for id, def in pairs((self.game.data or {}).items or {}) do
      if type(def) == "table" and type(def.name) == "string" then
        out[def.name:upper()] = id
      end
    end
    self.itemsByName = out
  end
  return self.itemsByName[(constant:gsub("^ITEM_", ""):gsub("_", " "))]
end

-- What the player walks away with: every treasure that is fully uncovered.
-- On a win that is all of them; on a collapse the cartridge still prints and
-- adds the ones already dug out (MINING_STATE_PRINT_COLLAPSE_MESSAGE runs on
-- into MINING_STATE_PRINT_DUG_UP_ITEM), so `onlyOut` asks for those alone.
function Gen4MiningScreen:award(onlyOut)
  local save = self.game.save
  if not save then return end
  local ug = save.underground or {}
  save.underground = ug
  ug.hasMined = true                       -- Underground_SetHasMined
  local out = onlyOut and Dig.treasuresOut(self.state) or nil
  for i, placed in ipairs(MiningWall.treasures(self.wall)) do
    if not out or out[i] then
      local constant = Mining.bagItem(placed.obj)
      local id = constant and self:itemIdFor(constant)
      if id then
        Bag.add(save, id, 1, self.game.data)
        self.found[#self.found + 1] = constant
        self.foundIds[#self.foundIds + 1] = placed.obj.id
      end
      -- A plate is once per save (Underground_HasPlateNeverBeenMined), so the bit
      -- is set here rather than when it is buried -- burying one you then fail to
      -- dig out must not lock it away.
      if Mining.isPlate(placed.obj.id) then
        ug.minedPlates = ug.minedPlates or {}
        ug.minedPlates[placed.obj.id] = true
      end
    end
  end
end

-- one "<item> was obtained." per treasure taken, in the cartridge's order
function Gen4MiningScreen:obtainedMessages(list)
  for i, constant in ipairs(self.found) do
    list[#list + 1] = { text = self:obtainedLine(self.foundIds[i], constant), hold = 60 }
  end
  return list
end

-- ------------------------------------------------------------- sprites --

function Gen4MiningScreen:setSprite(slot, seq, x, y)
  self.sprites[slot] = { seq = seq, tick = 0, x = x, y = y }
end

-- Mining_ButtonTouchCheck on the frame of the tap: the chosen block goes to
-- TRANSITION and the other to UNPRESSED, the flash sprite starts, and the next
-- frame finishes the press. Re-choosing the selected tool replays all of it.
function Gen4MiningScreen:chooseTool(tool)
  self.pickaxe = (tool == "pickaxe")
  local other = self.pickaxe and "hammer" or "pickaxe"
  self.buttons[tool], self.buttons[other] = "mid", "up"
  self.pendingPress = tool
  if self.pickaxe then self:setSprite("button", 7, 232, 152)
  else self:setSprite("button", 6, 232, 80) end
end

-- Mining_PlayHitAnimationsAndSoundEffects, at the cell's centre.
function Gen4MiningScreen:playHit(cx, cy, hit)
  local x, y = GRID_X + cx * CELL + 8, GRID_Y + cy * CELL + 8
  self:setSprite("tool", self.pickaxe and 0 or 1, x, y)
  local impact = hit.hitRock and 2 or (self.pickaxe and 3 or 4)
  self:setSprite("impact", impact, x, y)
  if hit.foundItem then self:setSprite("sparkle", 5, x, y) end
end

-- Mining_DrawUncoveredItemShines' first half: three sparkles at random spots
-- over each treasure the moment it is fully out (`width * 8`, the cartridge's
-- own range, which covers half the object).
function Gen4MiningScreen:sparkleNewlyOut()
  local out = Dig.treasuresOut(self.state)
  for i, placed in ipairs(MiningWall.treasures(self.wall)) do
    if out[i] and not self.out[i] then
      self.out[i] = true
      for j = 0, 2 do
        local x = self.rand(placed.obj.w * 8) + placed.x * CELL
        local y = self.rand(placed.obj.h * 8) + placed.y * CELL + GRID_Y
        self:setSprite("kira" .. (j + 1), 8 + j, x, y)
      end
    end
  end
end

-- Mining_QueueScreenShake (in the main loop) and Mining_ShakeScreen (VBlank).
function Gen4MiningScreen:queueShake()
  if self.shakeTimer == 0 then return end
  local lost = Gen4MiningScreen.INITIAL_WALL_INTEGRITY - self.state.integrity
  local duration, magnitude = math.floor(lost / 15), math.floor(lost / 50)
  self.shakeTimer = self.shakeTimer + 1
  if self.shakeTimer > duration then
    self.shakeX, self.shakeY = 0, 0
  else
    local n = 3 + magnitude
    self.shakeX = self.rand(n) - math.floor(n / 2)
    self.shakeY = self.rand(n) - math.floor(n / 2)
  end
end

function Gen4MiningScreen:shakeScreen()
  if self.shakeTimer == 0 then return end
  local lost = Gen4MiningScreen.INITIAL_WALL_INTEGRITY - self.state.integrity
  if self.shakeTimer > math.floor(lost / 10) then self.shakeTimer = 0 end
end

function Gen4MiningScreen:tickSprites()
  for _, s in pairs(self.sprites) do s.tick = s.tick + 1 end
end

-- ---------------------------------------------------------------- input --

-- Returns true when the press was ours, which is what stops it reaching the
-- d-pad underneath.
function Gen4MiningScreen:touchpressed(_, px, py)
  if self.phase ~= "digging" then
    -- a tap moves a waiting message on, as A does
    if self.message and self.phase ~= "intro" then self.advance = true end
    return true
  end
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x then return false end

  if x >= SIDEBAR_X then
    -- Mining_ButtonTouchCheck: the sidebar picks the tool and never digs.
    local tool = Gen4MiningScreen.toolAt(y, x)
    if tool then self:chooseTool(tool) end
    return true
  end

  -- `touchY >= 4 * TILE_HEIGHT_PIXELS` -- the crack strip is not diggable, and a
  -- press there is still ours: it must not fall through to the d-pad.
  local cx, cy = Gen4MiningScreen.cellAt(x, y)
  if not cx then return true end
  local hit = Dig.dig(self.state, cx, cy, self.pickaxe)
  if hit then
    self.lastHit = { x = cx, y = cy, rock = hit.hitRock, time = 12 }
    self:playHit(cx, cy, hit)
    self.crackShown = true               -- Mining_DrawWallCrack places it
    self.shakeTimer = 1
  end
  self:sparkleNewlyOut()

  local done = Dig.finished(self.state)
  if done == "won" then
    self:award()
    self.phase = "won"
    self.timer = 25                        -- ctx->timer = 25
  elseif done == "collapsed" then
    local ug = self.game.save and self.game.save.underground
    if ug then ug.hasMined = true end
    self.phase = "collapsed"
    self.timer = 45                        -- ctx->timer = 45
  end
  return true
end

-- the message phases: hold, then A / a tap / the timer moves on
function Gen4MiningScreen:updateMessage(input)
  if not self.message then return end
  local pressed = self.advance or (input and input:wasPressed("a"))
  self.advance = false
  if self.messageHold then
    self.messageHold = self.messageHold - 1
    if pressed or self.messageHold <= 0 then self:nextMessage() end
  elseif pressed then
    self:nextMessage()
  end
end

function Gen4MiningScreen:update()
  self.flash = (self.flash + 1) % 60
  if self.lastHit and self.lastHit.time > 0 then
    self.lastHit.time = self.lastHit.time - 1
  end
  local input = self.game.input
  self:tickSprites()
  self:shakeScreen()

  if self.phase == "intro" then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.message = nil
      if self.neverMined and self:text("tutorial") then
        self.phase = "tutorial"
        self:say({ { text = self:text("tutorial") } }, function() self.phase = "digging" end)
      else
        self.phase = "digging"
      end
    end
    return
  elseif self.phase == "tutorial" then
    return self:updateMessage(input)
  elseif self.phase == "won" then
    -- MINING_STATE_EVERYTHING_DUG: 25 frames of shine, then the lines
    if self.timer > 0 then
      self.timer = self.timer - 1
      if self.timer == 0 then
        local list = { { text = self:text("everything") or Strings("Everything was dug up!"), hold = 60 } }
        self:say(self:obtainedMessages(list), function() self:close("won") end)
      end
      return
    end
    return self:updateMessage(input)
  elseif self.phase == "collapsed" then
    -- MINING_STATE_COLLAPSE_SHAKE: the shake is re-armed every frame
    if self.timer > 0 then
      self.shakeTimer = 1
      self:queueShake()
      self.timer = self.timer - 1
      if self.timer == 0 then
        self.shakeTimer = 100
        self.shakeX, self.shakeY = 0, 0
        self.fade = 0                       -- 15 frames down to black
      end
      return
    end
    if self.fade then
      self.fade = self.fade + 1
      if self.fade >= 15 then
        self.fade = nil
        self.dark = true
        self:award(true)
        local list = { { text = self:text("collapsed") or Strings("The wall collapsed!"), hold = 60 } }
        self:say(self:obtainedMessages(list), function() self:close("collapsed") end)
      end
      return
    end
    return self:updateMessage(input)
  end

  -- digging
  if self.pendingPress then
    self.buttons[self.pendingPress] = "down"
    self.pendingPress = nil
  end
  self:queueShake()
  -- THE PORT'S OWN WAY OUT.  The cartridge has none: once the game starts you
  -- play it to a win or a collapse.  A player here may have no touch device at
  -- all, or a stuck screen, and leaving them in a state with no exit is worse
  -- than allowing one the cartridge does not -- so B gives up the wall, which is
  -- the same outcome as a collapse without the animation.
  if input and input:wasPressed("b") then
    local ug = self.game.save and self.game.save.underground
    if ug then ug.hasMined = true end
    return self:close("quit")
  end
end

-- ----------------------------------------------------------------- draw --

-- a picture from `gen4_mining_art` (src/import/Gen4MiningArt.lua), with its record
function Gen4MiningScreen:miningArt(key)
  local index = ((self.game or {}).data or {}).gen4_mining_art
  local rec = index and index[key]
  if type(rec) ~= "table" or type(rec.path) ~= "string" then return nil end
  if self.cache[rec.path] == nil then
    local got, image = pcall(Assets.image, rec.path)
    self.cache[rec.path] = got and image or false
    if self.cache[rec.path] then self.cache[rec.path]:setFilter("nearest", "nearest") end
  end
  return self.cache[rec.path] or nil, rec
end

function Gen4MiningScreen:quad(key, x, y, w, h, sw, sh)
  self.quads = self.quads or {}
  local k = key .. ":" .. x .. ":" .. y .. ":" .. w .. ":" .. h
  if not self.quads[k] then self.quads[k] = love.graphics.newQuad(x, y, w, h, sw, sh) end
  return self.quads[k]
end

-- The crack: the interface sheet in palette ROW 2, which is what the map's
-- crack cells carry (Mining_DrawWallCrack keeps their palette bits).
function Gen4MiningScreen:drawCrack()
  local sheet = self:miningArt("interface_tiles_row2") or self:img("underground/interface_tiles")
  local length = crackLengthFor(self.state.integrity)
  if not sheet then
    love.graphics.setColor(0.45, 0.32, 0.22, 1)
    love.graphics.rectangle("fill", (CRACK_END_TILE + 1 - length) * 8, 0,
                            length * 8, CRACK_ROWS * 8)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local sw, sh = sheet:getDimensions()
  for i = 0, length - 1 do
    local column = CRACK_SHEET_COLUMN - (i % 3)
    for row = 0, CRACK_ROWS - 1 do
      love.graphics.draw(sheet, self:quad("crack", column * 8, row * 8, 8, 8, sw, sh),
                         (CRACK_END_TILE - i) * 8, row * 8)
    end
  end
end

function Gen4MiningScreen:drawObjects()
  for _, placed in ipairs(self.wall.objects) do
    local base = placed.obj.sprite:gsub("_NCGR$", "")
    local image = self:img("underground/" .. base)
    local px, py = GRID_X + placed.x * CELL, GRID_Y + placed.y * CELL
    if image then
      love.graphics.draw(image, px, py)
    else
      self:warnOnce()
      love.graphics.setColor(0.55, 0.5, 0.42, 1)
      love.graphics.rectangle("fill", px, py, placed.obj.w * CELL, placed.obj.h * CELL)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

-- The dirt: dirt_tiles in interface_tiles.NCLR ROW 2 (Mining_DrawDirt writes
-- TILEMAP_PALETTE_SHIFT(2); dirt_tiles.NCLR is never loaded).
function Gen4MiningScreen:drawDirt()
  local sheet = self:miningArt("dirt_tiles_row2") or self:img("underground/dirt_tiles")
  local sw, sh = nil, nil
  if sheet then sw, sh = sheet:getDimensions() end
  for y = 0, Mining.GRID_HEIGHT - 1 do
    for x = 0, Mining.GRID_WIDTH - 1 do
      local level = self.state.dirt[y + 1][x + 1]
      if level > 0 then
        local px, py = GRID_X + x * CELL, GRID_Y + y * CELL
        if sheet then
          local column = DIRT_COLUMN[level] or 0
          love.graphics.draw(sheet, self:quad("dirt", column * 8, 0, CELL, CELL, sw, sh), px, py)
        else
          self:warnOnce()
          local shade = 0.22 + level * 0.06
          love.graphics.setColor(shade, shade * 0.78, shade * 0.55, 1)
          love.graphics.rectangle("fill", px, py, CELL, CELL)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
    end
  end
end

-- The two buttons: the BG1 blocks Mining_DrawButton copies -- up (the
-- backdrop's own), mid (the frame of the tap) and down (selected).
function Gen4MiningScreen:drawSidebar()
  local hammer = self:miningArt("hammer_btn_" .. self.buttons.hammer)
  local pickaxe = self:miningArt("pickaxe_btn_" .. self.buttons.pickaxe)
  if hammer and pickaxe then
    love.graphics.draw(hammer, HAMMER.x, HAMMER.y)
    love.graphics.draw(pickaxe, PICKAXE.x, PICKAXE.y)
    return
  end
  -- a cache without gen4_mining_art: the old hand-drawn stand-ins
  local function button(rect, selected, label)
    if selected then
      love.graphics.setColor(1, 1, 1, 0.32)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    end
    love.graphics.setColor(1, 1, 1, selected and 1 or 0.55)
    love.graphics.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1)
    love.graphics.setColor(1, 1, 1, 1)
    Font.print(label, rect.x + 6, rect.y + rect.h / 2 - 4)
  end
  button(HAMMER, not self.pickaxe, Strings("HAM"))
  button(PICKAXE, self.pickaxe, Strings("PIC"))
end

function Gen4MiningScreen:drawCell(key, x, y)
  local image, rec = self:miningArt(key)
  if image then love.graphics.draw(image, x + (rec.originX or 0), y + (rec.originY or 0)) end
end

-- OBJ: every sprite on its own position (they are not on the shaken BGs);
-- the tool, MINING_SPRITE 0, last so it is on top.
function Gen4MiningScreen:drawSprites()
  if self.crackShown then
    local cell, x, y = Gen4MiningScreen.crackEnd(self.state.integrity)
    self:drawCell("crack_end_" .. cell, x - self.shakeX, y - self.shakeY)
  end
  for _, slot in ipairs({ "kira3", "kira2", "kira1", "sparkle", "impact", "button", "tool" }) do
    local s = self.sprites[slot]
    if s then
      local cell = Gen4MiningScreen.cellOf(s.seq, s.tick)
      if cell ~= 0 then self:drawCell("anim_" .. cell, s.x, s.y) end
    end
  end
end

-- the field message box on BG3 (window (2, 19) 27x4), as the other Gen 4 screens
function Gen4MiningScreen:drawMessage(text)
  if not text then return end
  local g = love.graphics
  if Font.hasDialogueFrame and Font.hasDialogueFrame() then
    Font.drawDialogueBox(1, 18, 29, 6)
  else
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 8, 144, 240, 44)
  end
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
  local y = 152
  for l in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
  Font.popStyle()
end

function Gen4MiningScreen:drawBody()
  local g = love.graphics
  -- BG0..BG2 shake together (Mining_ShakeScreen sets each one's offset)
  g.push()
  g.translate(-self.shakeX, -self.shakeY)
  local bg = self:img("underground/interface")
  if bg then
    g.draw(bg, 0, 0)
  else
    self:warnOnce()
    g.setColor(0.12, 0.10, 0.09, 1)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end
  self:drawCrack()
  self:drawObjects()
  self:drawSidebar()
  self:drawDirt()
  g.pop()

  if self.dark then
    -- the brightness at -16 on BG0..2, sprites hidden: only the box is left
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  else
    self:drawSprites()
    if self.fade then
      -- FADE_TYPE_DOWNWARD_OUT: black comes down from the top
      g.setColor(0, 0, 0, 1)
      g.rectangle("fill", 0, 0, W, H * (self.fade + 1) / 15)
      g.setColor(1, 1, 1, 1)
    end
  end
  self:drawMessage(self.message)
end

function Gen4MiningScreen:draw()
  SecondScreen.drawFrame(self.game)
  SecondScreen.draw(self.game, function() self:drawBody() end)
end

return Gen4MiningScreen
