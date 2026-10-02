-- Overworld character sprites.  A 12-tile sheet (16x96 PNG) holds 6 16x16
-- frames: stand down/up/left, walk down/up/left (data/sprites/facings.asm).
-- Right-facing frames are horizontal flips of the left frames.
-- Sprites draw 4px above their cell, like the GB engine.

local Assets = require("src.render.Assets")
local PaletteFX = require("src.render.PaletteFX")

local SpriteRenderer = {}
SpriteRenderer.__index = SpriteRenderer

local imageCache = {}

local function getImage(path)
  -- BELT AND BRACES.  `Assets.image(nil)` indexes its cache with nil and
  -- raises "table index is nil" from inside the asset layer, where the
  -- traceback says nothing about which sprite was missing.  A def with no
  -- image is a content bug worth surviving: degrade to the placeholder the
  -- asset layer already has for a missing path.
  if type(path) ~= "string" then return Assets.image("MISSING") end
  if not imageCache[path] then
    imageCache[path] = Assets.image(path)
  end
  return imageCache[path]
end

-- Overworld sprite OBJ-palette recolor, baked into an ImageData like
-- BattleState's mon-pic palette bake (src/battle/BattleState.lua getImage):
-- CPU-remap the 4 DMG shades to the resolved OBP colors, cached per
-- (image path, group).  Every colour mode goes through it now (#301): RED++
-- resolves real per-sprite colours (color/sprites.asm ColorOverworldSprite),
-- OG RED the one boot-ROM object palette, and everything else the plain
-- rOBP0 = $D0 shade lift (PaletteFX.dmgObj) that leaves the sprite in DMG
-- shades for the zone shader to colour.
--
-- Sprite sheets carry no real alpha (every pixel, including the
-- background, is opaque -- confirmed by sampling the extracted PNGs): the
-- "transparent" look in every other draw path is a coincidence of the
-- whole-canvas shade-remap shader, where shade 0 (white) happens to map to
-- a similarly light color in whatever terrain zone the sprite stands over.
-- That coincidence breaks once terrain is colored per-tile instead of one
-- flat color per map (different tiles can have very different color-0s),
-- so shade 0 is keyed to alpha 0 here explicitly -- matching real GBC OBJ
-- hardware, where sprite palette index 0 is unconditionally transparent
-- (same rule TileRenderer's getColor0KeyShader documents for tall grass).
local obpCache = {}

local function getObpImage(path, colors, group)
  local key = path .. "#obp" .. group
  if not obpCache[key] then
    local img
    if love.image and love.image.newImageData then
      local id = Assets.imageData(path)
      id:mapPixel(function(_, _, r, g, b, a)
        if a == 0 then return r, g, b, a end
        if r > 0.83 then return r, g, b, 0 end -- OBJ color 0: always transparent
        local col = r > 0.5 and colors[2] or r > 0.17 and colors[3] or colors[4]
        return col[1] / 255, col[2] / 255, col[3] / 255, a
      end)
      img = love.graphics.newImage(id)
    else
      img = getImage(path) -- headless stub: no pixel access
    end
    obpCache[key] = img
  end
  return obpCache[key]
end

-- The OBP bake, for overlays that are not sprites but still wear a Gen2 OBJ
-- palette -- the Pokemon Center heal machine is one (its OAM rows carry CGB
-- palette 6).  Same cache, so the bake happens once.
function SpriteRenderer.obpImage(path, colors, group)
  if not (path and colors) then return nil end
  local ok, img = pcall(getObpImage, path, colors, group or "fx")
  return ok and img or nil
end

-- hot reload drops the sheets; live instances hold their own image, so
-- the world rebuilds them (MapLoader.invalidateAll) rather than this
function SpriteRenderer.invalidate()
  imageCache = {}
  obpCache = {}
end

Assets.register(SpriteRenderer.invalidate)

-- exported: a render pipeline's own sprite geometry picks frames by the
-- same tables, so a 3D pose can never drift from the 2D one
local STAND = { down = 0, up = 1, left = 2, right = 2 }
local WALK = { down = 3, up = 4, left = 5, right = 5 }
-- THE OTHER LEG, on a sheet that actually has one.
--
-- A Game Boy walker carries one step frame per axis and the engine X-flips it
-- to fake the other leg.  Emerald's walkers carry TWO real ones -- its
-- animation table reads `3 0 4 0`, step / stand / step / stand -- and the
-- extractor now keeps both, appended after the classic six so 0-5 still mean
-- what they always did.  These are the appended three.
local WALK2 = { down = 6, up = 7, left = 8, right = 8 }
-- the frame count that says a sheet has them
local FULL_WALK_FRAMES = 9
SpriteRenderer.STAND = STAND
SpriteRenderer.WALK = WALK
SpriteRenderer.WALK2 = WALK2

-- SetPartyMonIconAnimSpeed's overworld rate: the icon bobs twice a second
local MON_ICON_FPS = 4

-- seed: any stable per-instance value (e.g. an NPC's `id`) used to resolve
-- RED++'s per-instance "random" OBP sentinel (PaletteFX.spriteObp)
function SpriteRenderer.new(spriteDef, seed)
  local self = setmetatable({}, SpriteRenderer)
  self.def = spriteDef
  self.seed = seed
  local source = type(spriteDef.source) == "string" and spriteDef.source or ""
  local gen3ObjectEvent = spriteDef.gen3ObjectEvent == true
    or source:find("gObjectEventGraphicsInfoPointers", 1, true) ~= nil
  self.cellYBias = gen3ObjectEvent and 0 or -4
  self.image = getImage(spriteDef.image)
  local iw, ih = self.image:getDimensions()
  -- Big dolls (Snorlax / Lapras): FacingBigDollSymmetric uses a 16x32 left
  -- half mirrored to 32x32 over a 2x2 footprint.  Detect by id even when the
  -- extracted sheet is still a 16-wide strip (common before reimport).
  local bigById = spriteDef.id == "SPRITE_BIG_SNORLAX"
    or spriteDef.id == "SPRITE_BIG_LAPRAS"
  self.tileW = 16
  self.tileH = 16
  self.mirrorHalf = false
  if spriteDef.big or bigById or (iw >= 32 and (spriteDef.width or 0) >= 32) then
    self.big = true
    spriteDef.frames = 1
    if iw >= 32 and ih >= 32 then
      self.tileW, self.tileH = 32, 32
      self.frames = { [0] = love.graphics.newQuad(0, 0, 32, 32, iw, ih) }
      self.mirrorHalf = false
    else
      -- 16xN strip: take the first 32px of height as the left body half
      self.tileW, self.tileH = 16, math.min(32, ih)
      self.frames = { [0] = love.graphics.newQuad(0, 0, 16, self.tileH, iw, ih) }
      self.mirrorHalf = true
    end
  else
    -- A CELL IS NOT ALWAYS 16x16.  Gen 1 and Gen 2 people are one tile square;
    -- Emerald's are 16 wide and 32 TALL, and its bikes and vehicles wider
    -- still.  A sheet that says so gets quads its own size, and `draw` hangs
    -- the extra height above the cell so the feet stay where the engine put
    -- them.  Nothing that does not say so changes at all.
    self.tileW = math.floor(tonumber(spriteDef.frameWidth) or 16)
    self.tileH = math.floor(tonumber(spriteDef.frameHeight) or 16)
    if self.tileW < 8 or self.tileH < 8 then self.tileW, self.tileH = 16, 16 end
    -- Only a sheet that DECLARES its cell gets an offset: the big-doll branch
    -- above has always drawn from the cell's own corner and a Gen 1 or Gen 2
    -- sheet must keep landing exactly where it did.
    self.offsetX = math.floor((self.tileW - 16) / 2)
    self.offsetY = self.tileH - 16
    self.frames = {}
    -- ...INCLUDING THE ONES ONLY A POSE PLAYS.  A sheet whose frames are a
    -- SEQUENCE rather than a set of facings keeps `frames = 1`, so that every
    -- ordinary drawing path treats it as the still it is -- but the picture
    -- carries the whole animation and drawPose below reaches into it, so the
    -- quads have to exist.  See the import's note on poseFrames.
    local quadCount = math.max(tonumber(spriteDef.frames) or 1,
                               tonumber(spriteDef.poseFrames) or 0)
    for f = 0, math.max(0, quadCount - 1) do
      self.frames[f] = love.graphics.newQuad(0, f * self.tileH, self.tileW,
                                             self.tileH, iw, ih)
    end
  end
  return self
end

-- A PALETTE THIS INSTANCE WEARS INSTEAD OF ITS SHEET'S.
--
-- Every other sprite in the game is its sheet: one OBJ palette per id, baked
-- once and shared by every actor wearing it. The player in Prism is not --
-- the character customiser lets the player mix their own skin tone and outfit
-- colour, which is two entries of that four-colour palette chosen at runtime.
--
-- It cannot be done by editing `def.gen2ObjPal`, which is the tempting fix:
-- the def is the shared table out of data.sprites, so writing the player's
-- colours into it repaints every NPC that happens to use the same sheet, and
-- the bake cache (keyed on the def's id) would hand the stale image back
-- anyway. So the override lives on the INSTANCE and carries its own cache
-- key, which is what lets the mixed palette be baked and re-baked as the
-- player drags a slider without disturbing the shared sheet at all.
--
-- `key` must change whenever `colors` does, or the cache returns the previous
-- mix and the sliders appear to do nothing.
function SpriteRenderer:setPalette(colors, key)
  if colors and key then
    self.palColors, self.palKey = colors, key
  else
    self.palColors, self.palKey = nil, nil
  end
end

-- The palette actually in force: the instance's, else the sheet's own.
function SpriteRenderer:objPalette()
  if self.palColors then return self.palColors, "cust:" .. self.palKey end
  if self.def.gen2ObjPal then return self.def.gen2ObjPal, "gen2:" .. self.def.id end
  return nil
end

-- The image this sprite would draw from right now: the plain sheet, or the
-- OBP-recolored bake of it.  Exposed so a render pipeline can texture its
-- own geometry from the very same image -- the geometry carries sheet pixel
-- coordinates rather than baked colors, so sharing this one resolver is
-- what makes palette modes and sprite-replacing mods apply to 2D and 3D
-- alike.
--
-- Deliberately free of draw's bookkeeping: markTrueColor and
-- markSpriteRedraw exist to patch up the screen-space zone shader, and a
-- pipeline that renders into its own canvas never runs through it.  For the
-- same reason the OG-RED bake is returned unconditionally here rather than
-- only during a redraw pass -- there is no later pass to restore it.
function SpriteRenderer:resolveImage()
  if self.def.trueColor then return self.image end
  -- Gen2 carries the hardware's own OBJ palette per sheet (MapObjectPals,
  -- picked by the OverworldSprites palette field).  Applying it in the two
  -- hardware-colour modes is what makes a Gen2 overworld look like a GBC
  -- game; applying it in EVERY mode is what made COLORS do nothing out in the
  -- world while battle still responded to it.
  local objColors, objGroup = self:objPalette()
  if objColors and PaletteFX.usesGen2ObjPal() then
    return getObpImage(self.def.image, objColors, objGroup)
  end
  if PaletteFX.usesGbcPack() then
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then return getObpImage(self.def.image, colors, group) end
    return getObpImage(self.def.image, PaletteFX.dmgObj())
  elseif PaletteFX.usesSpriteObp() then
    return getObpImage(self.def.image, PaletteFX.ogObj())
  end
  return getObpImage(self.def.image, PaletteFX.dmgObj())
end

-- facing: down/up/left/right; walkPhase: 0 stand, 1 walk; flip: alternate
-- steps mirror the walk frame for up/down (GB uses OAM flip for this).
local function blitFrame(image, quad, x, y, flip, redraw, width)
  width = width or 16
  if flip then
    love.graphics.draw(image, quad, x + width, y, 0, -1, 1)
    if redraw then PaletteFX.markSpriteRedraw(image, quad, x + width, y, -1) end
  else
    love.graphics.draw(image, quad, x, y)
    if redraw then PaletteFX.markSpriteRedraw(image, quad, x, y, 1) end
  end
end

-- topHalf blits only the upper 8 rows of the frame: FishingAnim overwrites the
-- bottom tile row of the standing frames with the fishing pose art, which the
-- caller then draws itself through :drawTile (Player:draw, #384)
-- The palette-mode plumbing shared by :draw and :drawFixedFrame: which image
-- to blit from in the current color mode, plus whether the OG-RED redraw
-- queue needs the sprite.  Split out so a fixed-frame object (polished's cut
-- trees on the ball/cut/fruit sheet) recolors exactly like everything else.
function SpriteRenderer:resolveModeImage(x, y)
  local image = self.image
  local redraw = false
  -- full-color art claims its 16x16 cell out of the shade-remap pass
  if self.def.trueColor then
    -- the CELL, not a tile: a fixed-frame sheet may be 16x32 (Emerald's berry
    -- trees), and claiming only the top square left the trunk to the shade
    -- remap while the crown above it stayed in colour
    PaletteFX.markTrueColor(x, y, self.tileW or 16, self.tileH or 16)
  elseif self:objPalette() and PaletteFX.usesGen2ObjPal() then
    local objColors, objGroup = self:objPalette()
    image = getObpImage(self.def.image, objColors, objGroup)
    PaletteFX.markTrueColor(x, y, self.tileW or 16, self.tileH or 16)
  elseif PaletteFX.usesGbcPack() then
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then
      image = getObpImage(self.def.image, colors, group)
    else
      image = getObpImage(self.def.image, PaletteFX.dmgObj())
    end
  elseif PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    image = getObpImage(self.def.image, PaletteFX.ogObj())
    redraw = true
  else
    image = getObpImage(self.def.image, PaletteFX.dmgObj())
  end
  return image, redraw
end

-- Draw one specific 16x16 sheet row, no facing, no walk cycle.  The polished
-- ball/cut/fruit sheet keeps three different OBJECTS in one image -- ball
-- frame 0, cut tree frame 1, fruit tree frame 2 -- and the object's movement
-- data (not its facing) says which one it is, so the ordinary facing math
-- must never touch it.
-- A FIXED FRAME STILL SITS IN ITS CELL.
--
-- `draw` hangs a cell taller or wider than 16x16 so the feet stay on the tile
-- the engine put them on; this drew from the cell's own corner instead, which
-- is the same picture for the 16x16 sheets that used to be the only fixed-
-- frame objects (polished's cut trees) and one whole tile too low for
-- Emerald's berry trees, whose cell is 16x32.  Both offsets are zero on a
-- 16x16 sheet, so nothing that worked moves.
function SpriteRenderer:drawFixedFrame(px, py, camX, camY, frame)
  local x = math.floor(px - camX) - (self.offsetX or 0)
  local y = math.floor(py - camY) + (self.cellYBias or -4) - (self.offsetY or 0)
  local image, redraw = self:resolveModeImage(x, y)
  local quad = self.frames[frame] or self.frames[0]
  if quad then blitFrame(image, quad, x, y, false, redraw) end
end

function SpriteRenderer:draw(px, py, camX, camY, facing, walkPhase, stepFlip, topHalf)
  local x = math.floor(px - camX) - (self.offsetX or 0)
  local y = math.floor(py - camY) + (self.cellYBias or -4) - (self.offsetY or 0)
  local image = self.image
  local redraw = false
  -- full-color art claims its 16x16 cell out of the shade-remap pass
  if self.def.trueColor then
    PaletteFX.markTrueColor(x, y, self.tileW or 16, self.tileH or 16)
  elseif self:objPalette() and PaletteFX.usesGen2ObjPal() then
    -- Gen2 GBC mode: the ROM's own OBJ palette for this sheet, baked in --
    -- or, for a customised player, the mix they chose. It is full colour, so
    -- it claims its cell out of the shade-remap pass exactly like a trueColor
    -- sprite does.
    local objColors, objGroup = self:objPalette()
    image = getObpImage(self.def.image, objColors, objGroup)
    PaletteFX.markTrueColor(x, y, self.tileW or 16, self.tileH or 16)
  elseif PaletteFX.usesGbcPack() then
    -- RED++: the world canvas is already true-color (TileRenderer bakes
    -- terrain, this bakes the sprite) and the world pass runs unshaded
    -- (OverworldState.sgbWorldZones), so this draws like any normal sprite
    -- -- opaque character pixels over a real-alpha-transparent background,
    -- no trueColor rect needed (there is no shader left to exempt it from).
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then
      image = getObpImage(self.def.image, colors, group)
    else
      image = getObpImage(self.def.image, PaletteFX.dmgObj())
    end
  elseif PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    -- OG RED (GBC boot-ROM look): every OBJ wears the one global object
    -- palette -- green over Red's red background, pink over Blue's blue
    -- background (PaletteFX.ogObj, #155).  The BG zone shader still runs over
    -- the world canvas, so the baked sprite is queued for a post-zone redraw
    -- (PaletteFX.markSpriteRedraw) that restores its object-colored pixels on
    -- top.
    image = getObpImage(self.def.image, PaletteFX.ogObj())
    redraw = true
  else
    image = getObpImage(self.def.image, PaletteFX.dmgObj())
  end
  -- single-frame sprites (item balls, fossils...) have one fixed pose;
  -- still 3-frame sprites turn to face (the nurse at her machine,
  -- facePlayer on STAY NPCs) but never show walk frames
  if self.def.frames <= 1 then
    if self.mirrorHalf and self.frames[0] then
      -- FacingBigDollSymmetric: left 16x32 + X-flipped copy = 32x32 body
      blitFrame(image, self.frames[0], x, y, false, redraw)
      blitFrame(image, self.frames[0], x + 16, y, true, redraw, self.tileW)
    else
      blitFrame(image, self.frames[0], x, y, false, redraw)
    end
    return
  end
  -- SPRITE_POKEMON objects wear the party menu icon (GetMonSprite.Mon ->
  -- LoadOverworldMonIcon): two frames that cycle on their own clock, and no
  -- facing at all -- the Lake of Rage Gyarados never turns to look at you.
  if self.def.monIcon then
    local t = love.timer and love.timer.getTime() or 0
    local quad = self.frames[math.floor(t * MON_ICON_FPS) % 2] or self.frames[0]
    blitFrame(image, quad, x, y, false, redraw)
    return
  end
  local frame, flip = self:poseFrame(facing, walkPhase, stepFlip)
  local quad = self.frames[frame] or self.frames[0]
  if topHalf then
    self.halfFrames = self.halfFrames or {}
    if not self.halfFrames[frame] then
      local iw, ih = self.image:getDimensions()
      self.halfFrames[frame] = love.graphics.newQuad(
        0, frame * (self.tileH or 16), self.tileW or 16,
        math.floor((self.tileH or 16) / 2), iw, ih)
    end
    quad = self.halfFrames[frame]
  end
  blitFrame(image, quad, x, y, flip, redraw, self.tileW)
end

-- ONE FRAME OF A SEQUENCE, by its number.
--
-- For a sheet whose frames are an animation and not a set of facings -- the
-- field-move pose, where the character reaches for a Poke Ball and raises it.
-- `index` is clamped, so a caller may simply count upward and the pose settles
-- on its last frame and stays there, which is what holding a ball up is.
function SpriteRenderer:poseCount()
  return math.max(1, tonumber(self.def.poseFrames) or 1)
end

function SpriteRenderer:drawPose(index, px, py, camX, camY)
  local n = self:poseCount()
  index = math.max(0, math.min(n - 1, math.floor(tonumber(index) or 0)))
  local x = math.floor(px - camX) - (self.offsetX or 0)
  local y = math.floor(py - camY) + (self.cellYBias or -4) - (self.offsetY or 0)
  if self.def.trueColor then
    PaletteFX.markTrueColor(x, y, self.tileW or 16, self.tileH or 16)
  end
  local quad = self.frames[index] or self.frames[0]
  if not quad then return end
  blitFrame(self.image, quad, x, y, false, false, self.tileW)
end

-- ---------------------------------------------------------------------------
-- THE SAME CHARACTER, UPSIDE DOWN, IN THE WATER
--
-- Reported from play: "puddles and the bright blue water arent showing their
-- reflections like they do in the emerald rom".
--
-- A Gen 3 reflection is not an effect over the tiles -- it is a SECOND SPRITE
-- of the same object, vertically flipped, drawn below it on the water line,
-- and the cartridge decides three things about it:
--
--   * WHETHER, from the metatile behaviour under the object's feet.  That set
--     is derived at import (see extractReflections) and is the caller's
--     business, not this file's.
--   * WHICH PICTURE.  The same frame the character is showing this instant --
--     which is why this copies the quad the last :draw chose rather than
--     working one out again.  A reflection that picked its own frame would be
--     a different person in the water.
--   * WHICH COLOURS.  The graphics row's reflectionPaletteTag when it names
--     one -- 25 of Emerald's 246 rows do, all of them the player's own
--     avatars -- and the sprite's OWN palette when it does not, which is what
--     LoadObjectRegularReflectionPalette does for everybody else.  The import
--     composes the recoloured sheet for the 25 and names it on the def; this
--     just uses it when it is there.
--
-- DRAWN FROM THE FEET DOWN.  The water line is the bottom of the cell the
-- character stands in, so the reflection occupies the cell below it, and the
-- two touch. `sy = -1` with the origin at the far edge is what mirrors it.
-- WHICH FRAME THE CHARACTER IS SHOWING, AND WHICH WAY ROUND.
--
-- Pulled out of :draw so the REFLECTION can ask the same question without
-- having to be drawn after the sprite.  It used to copy the quad the last
-- :draw chose, which forced the reflection to come second -- and that put it
-- on the wrong side of the map's top layer for anyone standing on a bridge,
-- where the whole point is that the deck covers the reflection and not the
-- character.  Both callers get the same answer from the same code, so they
-- cannot show different frames.
-- A SHEET THAT SAYS WHICH OF ITS OWN PICTURES FACES WHICH WAY.
--
-- STAND/WALK/WALK2 above are the Game Boy's layout, and Gen 1, Gen 2 and Gen
-- 3 all lay their sheets out that way -- six or nine frames in a fixed order,
-- with east drawn by mirroring west because the cartridge has no east art.
-- A Platinum sheet is neither: its frames are in the archive's own order, and
-- it carries a REAL east side.  Read with the fixed slots it shows a back
-- view where the southward stand belongs, so the character appears to spin as
-- it walks.
--
-- So a def may carry its own answer.  `facings` is { stand, step, step } per
-- side in the sheet's own frame numbers, written by the import from the
-- cartridge's own frame-sequence tables (see src/import/Gen4Facings.lua).
-- Nothing is mirrored on this path: all four sides are drawn, and mirroring a
-- real east frame would put the bag on the wrong shoulder.
--
-- Exported so a second pipeline can ask the same question rather than
-- re-deriving it, for the same reason STAND/WALK/WALK2 are.
function SpriteRenderer.facingFrames(def, facing, walkPhase, stepFlip)
  local own = def and def.facings
  local cycle = own and (own[facing] or own.down)
  if type(cycle) ~= "table" or cycle[1] == nil then return nil end
  if def.fullCycle then return cycle[(tonumber(walkPhase) or 0)%#cycle+1] end
  if def.walker and walkPhase == 1 then
    if stepFlip then return cycle[3] or cycle[2] or cycle[1] end
    return cycle[2] or cycle[1]
  end
  return cycle[1]
end

function SpriteRenderer:poseFrame(facing, walkPhase, stepFlip)
  -- A sheet with the full nine alternates its two REAL step frames; the
  -- six-frame ones keep the Game Boy's mirror, which is all they can do.
  -- ...unless the sheet said so itself.  Never flipped: see facingFrames.
  local own = SpriteRenderer.facingFrames(self.def, facing, walkPhase, stepFlip)
  if own then return own, false end
  local full = (tonumber(self.def.frames) or 0) >= FULL_WALK_FRAMES
  local stepping = self.def.walker and walkPhase == 1
  local frame
  if stepping then
    frame = (full and stepFlip) and WALK2[facing] or WALK[facing]
  else
    frame = STAND[facing]
  end
  local flip = false
  if facing == "right" then
    -- east is west mirrored on both kinds of sheet: the cartridge has no
    -- east art either, which is why its POSE list skips that slot
    flip = true
  elseif not full and (facing == "down" or facing == "up")
         and walkPhase == 1 and stepFlip then
    -- the Game Boy fake, and ONLY for the sheets that need it.  Left out for
    -- a full sheet, or the second step would be drawn back to front -- and it
    -- was never applied to SIDE at all, because a mirrored side frame faces
    -- the wrong way.  That asymmetry is what made side-to-side read as two
    -- frames while up and down read as three.
    flip = true
  end
  return frame, flip
end

function SpriteRenderer:reflectionImage()
  local key = self.def.reflect
  if not key then return self.image end
  if self._reflectImage ~= nil then return self._reflectImage or self.image end
  local defs = _G.Game and _G.Game.data and _G.Game.data.sprites
  local def = defs and defs[key]
  local ok, img = pcall(getImage, def and def.image or nil)
  -- A SHEET THAT IS NOT THIS SPRITE'S SIZE IS NOT THIS SPRITE'S SHEET.
  --
  -- The frame quads were built against self.image's dimensions, so handing
  -- them a differently-sized texture samples outside it and draws NOTHING --
  -- which on screen is indistinguishable from "this character has no
  -- reflection".  And that is exactly the shape a failed load takes here: the
  -- asset layer degrades a missing path to a placeholder rather than raising
  -- (src/render/Assets.lua loadImage), so the sprite gets an Image back and
  -- every check short of measuring it passes.
  local rw, rh, iw, ih
  if ok and img and self.image then
    iw, ih = self.image:getDimensions()
    rw, rh = img:getDimensions()
    if rw ~= iw or rh ~= ih then img = nil end
  end
  self._reflectImage = (ok and img) or false
  -- ...and say what was actually loaded, once per sheet.  A count of the
  -- opaque pixels in the first frame settles "is the art there at all"
  -- without another round of guessing at it.
  local opaque = nil
  local okData, data = pcall(require("src.render.Assets").imageData,
                             def and def.image or nil)
  if okData and data then
    local dw, dh = data:getDimensions()
    opaque = 0
    for y = 0, math.min(dh, self.tileH or 16) - 1 do
      for x = 0, dw - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a and a > 0 then opaque = opaque + 1 end
      end
    end
  end
  -- The record is right and the file is on disk, so if this still comes back
  -- as the 16x16 placeholder the failure is in resolving the PATH -- report
  -- what the asset layer actually looked for, with the sprite's OWN sheet
  -- beside it as a control, since that one demonstrably loads.
  local want = def and def.image or nil
  local resolved = want and Assets.resolve(want) or nil
  local fs = love and love.filesystem
  local function seen(path)
    if not (fs and fs.getInfo and type(path) == "string") then return "?" end
    local info = fs.getInfo(path)
    return info and ("yes," .. tostring(info.size)) or "NO"
  end
  require("src.core.Probe").say(
    "reflectsheet", "%s -> %s: image %sx%s, sprite %sx%s, frame0 opaque=%s%s"
    .. " | want=%s resolved=%s exists=%s | own=%s exists=%s",
    tostring(self.def.id), tostring(key), tostring(rw), tostring(rh),
    tostring(iw), tostring(ih), tostring(opaque),
    self._reflectImage and "" or "  <-- REJECTED, using its own art",
    tostring(want), tostring(resolved), seen(resolved),
    tostring(self.def.image), seen(Assets.resolve(self.def.image)))
  return self._reflectImage or self.image
end

function SpriteRenderer:reflect(px, py, camX, camY, facing, walkPhase,
                                stepFlip, still)
  local frame, flip = self:poseFrame(facing, walkPhase, stepFlip)
  local quad = self.frames[frame] or self.frames[0]
  local image = quad and self:reflectionImage()
  if not (quad and image) then
    require("src.core.Probe").say(
      "reflectdraw", "%s: quad=%s(frame %s) image=%s",
      tostring(self.def and self.def.image), tostring(quad ~= nil),
      tostring(frame), tostring(image ~= nil))
    return
  end
  local w, h = self.tileW or 16, self.tileH or 16
  local x = math.floor(px - camX) - (self.offsetX or 0)
  local y = math.floor(py - camY) + (self.cellYBias or -4) - (self.offsetY or 0)
  -- WHERE THE MIRRORED IMAGE SITS, to the pixel.
  --
  -- GetReflectionVerticalOffset (ROM:0153F98) is the whole of it: it loads
  -- the graphics record's height and returns `height - 2`, and
  -- UpdateObjectReflectionSprite (ROM:01540A8) writes
  -- `reflection.y = main.y + that + data[2]`.  So the reflection's top edge
  -- is two pixels ABOVE the sprite's own bottom edge -- the character and
  -- their image meet a fraction inside the feet rather than exactly at them,
  -- which is what stops a two-pixel seam of water showing between the two.
  local top = y + h - 2
  -- A REFLECTION IS FULL-COLOUR ART LIKE THE SPRITE IT MIRRORS, and has to
  -- claim its cell out of the shade-remap pass for the same reason :draw
  -- does -- otherwise a dark map runs the DMG remap over pixels that were
  -- never DMG shades.
  if self.def.trueColor then PaletteFX.markTrueColor(x, top, w, h) end
  local sx = flip and -1 or 1
  local ox = flip and (x + w) or x
  love.graphics.draw(image, quad, ox, top + h, 0, sx, -1, 0, 0,
                     still and 0 or SpriteRenderer.reflectionSway(), 0)
end

-- ---- THE SWAY, AND WHAT IS AND IS NOT DERIVED ABOUT IT -------------------
--
-- Reported from play: "in the real game when reflections appear in the water
-- they sway and move, they arent perfect reflections like we have right now".
-- That is right, and this is the one thing in the reflection that this port
-- does NOT read off the cartridge.  What was established, so the next person
-- does not repeat it:
--
--   * A water reflection is an affine sprite.  SetUpReflection (ROM:0153ED4)
--     sets oam.affineMode = ST_OAM_AFFINE_NORMAL for the non-still case, and
--     water IS the non-still case -- the ground-effect flag table at
--     0850E5DC maps ice to bit 5 (still) and reflective to bit 4 (affine).
--   * UpdateObjectReflectionSprite (ROM:01540A8) forces oam.matrixNum to 0,
--     or 1 when the sprite is horizontally flipped.  So the sway can only be
--     OAM matrix 0 and 1 -- there is nowhere else for it to live.
--   * ResetOamMatrices (ROM:00071F8) fills all 32 matrices with a pure
--     identity, and the reflection's affine anim table is
--     gDummySpriteAffineAnimTable (082EC6A8, referenced 857 times), whose
--     only command is END -- so the sprite engine never writes one either.
--   * Every place the cartridge can write a matrix was checked: both
--     SetOamMatrix entry points (the 5-argument one at 0007224 with its 27
--     callers, and the pointer form at 0007DD4) and all 18 sites that
--     materialise the matrix array.  NONE targets matrix 0 or 1 from field
--     code; the constant-index callers are task-driven battle and contest
--     sprites.
--
-- Which leaves a contradiction I could not resolve -- an identity matrix
-- would not even flip the reflection, and it plainly is flipped -- so one
-- link is still missing and this is NOT that link.  It is a stand-in.
--
-- What it copies is the SHAPE the hardware can make, which is the honest part
-- of the guess: one affine matrix per sprite cannot ripple a reflection row
-- by row, it can only shear it -- x' = a*x + b*y -- so an animated `b` skews
-- the image, leaving the end nearest the feet still and the far end swinging
-- widest.  That is what this draws, and it rides the tileset animation clock
-- so it keeps time with the water it is lying on rather than free-running
-- against it.
local SWAY_SKEW = 0.055      -- radians-ish of shear at the extreme
local SWAY_PERIOD = 128      -- ticks for one full swing: the water's own cycle

function SpriteRenderer.reflectionSway()
  local ok, TileRenderer = pcall(require, "src.render.TileRenderer")
  local t = (ok and TileRenderer and TileRenderer.animFrame
             and TileRenderer.animFrame()) or 0
  return SWAY_SKEW * math.sin(t * 2 * math.pi / SWAY_PERIOD)
end

-- Blit a loose 16-wide fx tile at screen (x, y) wearing THIS sprite's OBJ
-- palette, mirroring the mode branches in :draw above.  The fishing pose row
-- overwrites the sheet's own tiles in VRAM in the original, so it has to be
-- recolored and OG-RED-redrawn exactly like the sheet rather than blitted as
-- raw DMG shades (#384).
function SpriteRenderer:drawTile(path, x, y, flip)
  local image, redraw = getImage(path), false
  if self.def.trueColor then
    PaletteFX.markTrueColor(x, y, 16, 8)
  elseif PaletteFX.usesGbcPack() then
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then image = getObpImage(path, colors, group) end
  elseif PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    image, redraw = getObpImage(path, PaletteFX.ogObj()), true
  else
    image = getObpImage(path, PaletteFX.dmgObj())
  end
  local iw, ih = image:getDimensions()
  self.tileQuads = self.tileQuads or {}
  self.tileQuads[path] = self.tileQuads[path]
                         or love.graphics.newQuad(0, 0, iw, ih, iw, ih)
  blitFrame(image, self.tileQuads[path], x, y, flip, redraw)
end

return SpriteRenderer
