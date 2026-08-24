-- Map object (NPC/item) built from a generated object_event entry.
-- STAY objects keep their facing; WALK objects wander randomly within the
-- roam constraint (ANY_DIR / UP_DOWN / LEFT_RIGHT), like the original.

local Assets = require("src.render.Assets")
local Collision = require("src.world.Collision")
local SpriteRenderer = require("src.render.SpriteRenderer")

local NPC = {}
NPC.__index = NPC

local STEP_FRAMES = 16

local FACING_FROM_RANGE = {
  DOWN = "down", UP = "up", LEFT = "left", RIGHT = "right",
}

local ROAM_DIRS = {
  ANY_DIR = { "up", "down", "left", "right" },
  UP_DOWN = { "up", "down" },
  LEFT_RIGHT = { "left", "right" },
}

-- Gen2 spinners.  `_MovementSpinNextFacing` walks a fixed four-entry table
-- (engine/overworld/map_objects.asm .facings_clockwise /
-- .facings_counterclockwise), indexed by the CURRENT facing, and holds each
-- one for $10 frames.  The two random spinners just roll a facing and hold it
-- for `Random and $7f` (slow) or `and $1f` (fast) frames; the fast one
-- additionally refuses to roll the facing it is already showing, flipping
-- both direction bits instead -- which is the XOR below.
local SPIN_NEXT = {
  SPIN_CW  = { down = "left", left = "right", right = "up", up = "down" },
  SPIN_CCW = { down = "right", right = "left", left = "up", up = "down" },
}
local SPIN_FLIP = { down = "right", up = "left", left = "up", right = "down" }
local SPIN_DIRS = { "down", "up", "left", "right" }

local FALLBACK_SPRITE = {
  id = "SPRITE_FALLBACK",
  source = "runtime fallback",
  image = "assets/generated/sprites/placeholder.png",
  frames = 6,
  walker = true,
}

-- An object_event sprite byte of $F0 or more indexes wVariableSprites instead
-- of OverworldSprites (GetMonSprite.Variable, 05:$4303), and the map's own
-- `variablesprite` callback fills the slot in -- that is how Route 36's
-- Sudowoodo gets its sheet.  An unset slot resolves to sprite id 1, the same
-- fallback the routine takes when the slot reads zero.
local byIndexCache = { sprites = nil, map = nil }

local function spriteByIndex(sprites, index)
  if byIndexCache.sprites ~= sprites then
    local map = {}
    for _, def in pairs(sprites) do
      if type(def) == "table" and def.index then map[def.index] = def end
    end
    byIndexCache.sprites, byIndexCache.map = sprites, map
  end
  return byIndexCache.map[index]
end

-- Named variable-sprite slots (SPRITE_VARS $F0+).  Copycat is $FB = slot 11.
local VAR_SPRITE_SLOTS = {
  SPRITE_COPYCAT = 11,   -- $FB - $F0
  SPRITE_CONSOLE = 0,
  SPRITE_DOLL_1 = 1,
  SPRITE_DOLL_2 = 2,
  SPRITE_BIG_DOLL = 3,
  SPRITE_WEIRD_TREE = 4, -- Sudowoodo
  SPRITE_OLIVINE_RIVAL = 5,
  SPRITE_AZALEA_ROCKET = 6,
  SPRITE_FUCHSIA_GYM_1 = 7,
  SPRITE_FUCHSIA_GYM_2 = 8,
  SPRITE_FUCHSIA_GYM_3 = 9,
  SPRITE_FUCHSIA_GYM_4 = 10,
  SPRITE_JANINE_IMPERSONATOR = 12,
}

-- Default sheet when the slot has never been assigned (Copycat = LASS)
local VAR_SPRITE_DEFAULTS = {
  [11] = 0x28, -- SPRITE_LASS
  [4] = 0x5D,  -- SPRITE_FRUIT_TREE (Sudowoodo until script)
}

-- Find a standing overworld sheet by several keying conventions the
-- extractor has used across imports (SPRITE_LASS, lass, index 0x28, …).
local function findSheet(sprites, names, index)
  if type(sprites) ~= "table" then return nil end
  for _, n in ipairs(names or {}) do
    local def = sprites[n]
    if type(def) == "table" and def.image then return def end
    -- lowercase path-style keys some imports still carry
    local low = type(n) == "string" and n:lower():gsub("^sprite_", "") or n
    def = sprites[low] or sprites[tostring(low)]
    if type(def) == "table" and def.image then return def end
  end
  if index then
    local def = spriteByIndex(sprites, index)
    if def and def.image then return def end
    def = sprites[string.format("SPRITE_%02X", index)]
      or sprites[string.format("SPRITE_%d", index)]
      or sprites[index]
    if type(def) == "table" and def.image then return def end
  end
  return nil
end

-- Does this id name a wVariableSprites SLOT rather than an OverworldSprites
-- row?  It has to be asked BEFORE data.sprites is consulted by name: the
-- extractor emits an entry for every id a map object mentions, and one with no
-- sheet of its own is handed placeholder_sprite.png -- which then won the
-- direct lookup in resolveSpriteDef and left Route 36's Sudowoodo and Route
-- 37's Twins Ann & Anne (both SPRITE_WEIRD_TREE = slot 4) as blue placeholder
-- people whatever the slot actually held.
local function isVariableSpriteId(spriteId)
  if type(spriteId) ~= "string" then return false end
  if VAR_SPRITE_SLOTS[spriteId] then return true end
  return spriteId:match("^SPRITE_VAR_%d+$") ~= nil
end

-- Which wVariableSprites slot does this object_event sprite id name, if any?
-- One answer to that question, so OverworldState:refreshVariableSprite cannot
-- disagree with resolveVariableSprite below about which objects a
-- `variablesprite` assignment repaints.  Only five of the thirteen slots ever
-- reach the runtime spelled SPRITE_VAR_nn -- the extractor names the rest
-- after what they hold (SPRITE_WEIRD_TREE, SPRITE_OLIVINE_RIVAL,
-- SPRITE_AZALEA_ROCKET, SPRITE_COPYCAT, SPRITE_JANINE_IMPERSONATOR) -- and
-- those five ARE the ones scripts reassign mid-scene.  nil = not a slot.
function NPC.variableSpriteSlot(spriteId)
  if type(spriteId) ~= "string" then return nil end
  local slot = tonumber(spriteId:match("^SPRITE_VAR_(%d+)$"))
  if slot then return slot end
  slot = VAR_SPRITE_SLOTS[spriteId]
  if slot then return slot end
  -- raw $F0-$FF spellings, the same last resort resolveVariableSprite takes
  local tail = spriteId:match("^SPRITE_(%x+)$")
  local hex = tail and tonumber(tail, 16) or nil
  if hex and hex >= 0xF0 then return hex - 0xF0 end
  return nil
end

local function resolveVariableSprite(data, sprites, spriteId)
  local slot = tonumber(spriteId:match("^SPRITE_VAR_(%d+)$"))
  if not slot then
    slot = VAR_SPRITE_SLOTS[spriteId]
  end
  -- Also accept raw $F0-$FF as SPRITE_%02X style.
  -- tonumber(nil, 16) THROWS ("string expected, got nil") where tonumber(nil)
  -- merely returns nil, so the match has to be tested before it is converted.
  -- Any ordinary name whose tail is not all hex digits (SPRITE_ROCKET,
  -- SPRITE_GRAMPS, ...) reaches here whenever its sheet is missing from
  -- data.sprites, and used to take the whole map load down with it -- that is
  -- the Goldenrod-during-the-takeover crash.
  if not slot then
    local tail = spriteId:match("^SPRITE_(%x+)$")
    local hex = tail and tonumber(tail, 16) or nil
    if hex and hex >= 0xF0 then slot = hex - 0xF0 end
  end
  if not slot then return nil end

  local save = nil
  pcall(function()
    local Game = require("src.core.Game")
    save = Game.save or (Game.getSave and Game.getSave())
  end)
  local assigned = save and save.gen2VarSprites and save.gen2VarSprites[slot]
  if not assigned then
    local defaults = data and data.map_scripts and data.map_scripts.varSprites
    assigned = defaults and defaults[slot]
  end
  if not assigned then
    assigned = VAR_SPRITE_DEFAULTS[slot]
  end

  -- assigned may be a numeric OverworldSprites index OR a SPRITE_* name
  if type(assigned) == "string" then
    local byName = findSheet(sprites, { assigned, assigned:upper(), assigned:lower() })
    if byName then return byName end
  end
  if type(assigned) == "number" then
    local byIdx = findSheet(sprites, nil, assigned)
    if byIdx then return byIdx end
  end

  -- Copycat ($FB / slot 11) always defaults to the LASS sheet — there is no
  -- separate copycat.png in the ROM (Copycat uses SPRITE_LASS via variablesprite).
  if slot == 11 or spriteId == "SPRITE_COPYCAT" then
    local lass = findSheet(sprites, {
      "SPRITE_LASS", "SPRITE_TWIN", "lass", "twin",
    }, 0x28)
    if lass then return lass end
    -- Fabricate a sheet pointing at the extracted file so she is never a
    -- grey placeholder when lass.png exists on disk.
    return {
      id = "SPRITE_LASS",
      image = "assets/generated/sprites/lass.png",
      frames = 6,
      walker = true,
      index = 0x28,
    }
  end

  return spriteByIndex(sprites, (type(assigned) == "number" and assigned) or 1)
end

-- Sprite bytes $E0/$E1 read the day-care mons' species live
-- (GetMonSprite.BreedMon1/2), so the Day-Care's yard object wears whatever is
-- boarded there.  With the pen empty the routine returns sprite id 1.
local function resolveBreedSprite(sprites, spriteId)
  local slot = spriteId:match("^SPRITE_MON_BREED_(%d)$")
  if not slot then return nil end
  local save = require("src.core.Game").save
  local mon = require("src.pokemon.DayCare").mon(save, tonumber(slot))
    or (save and save.daycare and save.daycare.mon)
  local species = mon and tonumber(tostring(mon.species):match("(%d+)$"))
  return (species and sprites[string.format("SPRITE_MON_%03d", species)])
    or spriteByIndex(sprites, 1)
end

-- pret renamed Silver→Rival; some extracts still emit one name or the other.
-- Prefer a real sheet over falling through to whatever pairs() returns first
-- (that was how Misty could paint as the green fruit-tree sheet).
local SPRITE_ALIASES = {
  SPRITE_SILVER = { "SPRITE_RIVAL" },
  SPRITE_RIVAL = { "SPRITE_SILVER" },
  SPRITE_RED = { "SPRITE_CHRIS" },
  SPRITE_RED_BIKE = { "SPRITE_CHRIS_BIKE" },
  SPRITE_CHRIS = { "SPRITE_RED" },
  SPRITE_CHRIS_BIKE = { "SPRITE_RED_BIKE" },
  SPRITE_COPYCAT = { "SPRITE_LASS", "SPRITE_TWIN" },
}

-- OverworldSprites row index (= object_event sprite byte) for story NPCs
-- when the named sheet is missing after a partial extract.
-- Indices match pret/pokegold constants/sprite_constants.asm.
local SPRITE_INDEX_FALLBACK = {
  SPRITE_SILVER = 4,
  SPRITE_RIVAL = 4,
  SPRITE_MISTY = 0x1D,
  SPRITE_BLUE = 7,
  SPRITE_RED_KANTO = 6,
  SPRITE_ROCKET = 0x35,
  SPRITE_COPYCAT = 0x28, -- default LASS; variablesprite may swap to CHRIS
  SPRITE_SUPER_NERD = 0x2B,
  SPRITE_COOLTRAINER_M = 0x23,
  SPRITE_COOLTRAINER_F = 0x24,
  SPRITE_BUG_CATCHER = 0x25,
  SPRITE_TWIN = 0x26,           -- Route 37 twins, etc.
  SPRITE_YOUNGSTER = 0x27,
  SPRITE_LASS = 0x28,
  SPRITE_TEACHER = 0x29,
  SPRITE_BEAUTY = 0x2A,         -- Route 37 / common trainers
  SPRITE_GRAMPS = 0x2F,
  SPRITE_GRANNY = 0x30,
  SPRITE_FRUIT_TREE = 0x5D,
  SPRITE_SURF = 0x53,
  SPRITE_SURFING_PIKACHU = 0x34,
  SPRITE_ROCKER = 0x2C,
  SPRITE_POKEFAN_M = 0x2D,
  SPRITE_POKEFAN_F = 0x2E,
  -- Kanto post-game / special overworld actors
  SPRITE_BIG_SNORLAX = 0x33,  -- pret SPRITE_BIG_SNORLAX; not mon-icon $6C
  SPRITE_SLOWPOKE = 0x45,     -- Azalea Town, after the well
  SPRITE_SUDOWOODO = 0x52,
  SPRITE_WEIRD_TREE = 0x5D,   -- pre-reveal default = fruit tree sheet
  SPRITE_GYM_GUIDE = 0x48,
  SPRITE_OFFICER = 0x43,
  SPRITE_JANINE = 0x0A,
  SPRITE_SURGE = 0x1F,
  SPRITE_ERIKA = 0x20,
  SPRITE_SABRINA = 0x22,
  SPRITE_BROCK = 0x1A,
  -- Mon-icon sheets ($80+, SpriteMons order), not OverworldSprites rows
  SPRITE_SNORLAX = 0x9F,
  SPRITE_MACHOP = 0x9A,
}

-- Fabricate a sheet pointing at an extracted file so common NPCs are never
-- grey placeholders when the png exists on disk but the registry key missed.
--
-- The file name is the extractor's own convention: RomExtractorGen2 writes
-- each OverworldSprites row to "sprites/" .. <GfxLabel>:lower() .. ".png".
-- `frames` follows what the extractor actually writes: frames = height / 16,
-- where height comes from the gap to the next sheet capped by the sprite
-- kind.  Sudowoodo is a STANDING_SPRITE that spans 128 bytes -> 32px -> 2
-- frames, and Slowpoke / fruit trees are STILL_SPRITEs at 1.  Claiming the
-- walking default of 6 would build quads off the bottom of the sheet.
local DISK_SHEET_FALLBACK = {
  SPRITE_LASS = { file = "lass.png", index = 0x28 },
  SPRITE_TWIN = { file = "twin.png", index = 0x26 },
  SPRITE_BEAUTY = { file = "beauty.png", index = 0x2A },
  SPRITE_TEACHER = { file = "teacher.png", index = 0x29 },
  SPRITE_YOUNGSTER = { file = "youngster.png", index = 0x27 },
  SPRITE_COOLTRAINER_F = { file = "cooltrainerf.png", index = 0x24 },
  SPRITE_COOLTRAINER_M = { file = "cooltrainerm.png", index = 0x23 },
  SPRITE_SLOWPOKE = { file = "slowpoke.png", index = 0x45, frames = 1 },
  SPRITE_SUDOWOODO = { file = "sudowoodo.png", index = 0x52, frames = 2 },
  SPRITE_FRUIT_TREE = { file = "fruittree.png", index = 0x5D, frames = 1 },
}

-- Only ever hand back a fabricated sheet whose png is actually there.  This
-- fallback is reached precisely when the sheet was NOT extracted, which is
-- also when the file is most likely absent -- and SpriteRenderer.new ->
-- Assets.image -> love.graphics.newImage raises on a missing path, so an
-- unchecked guess turns a cosmetic miss into a hard crash on map load.
local function diskSheet(spriteId)
  local tip = DISK_SHEET_FALLBACK[spriteId]
  if not tip then return nil end
  local path = "assets/generated/sprites/" .. tip.file
  if not Assets.exists(path) then return nil end
  local frames = tip.frames or 6
  return {
    id = spriteId,
    image = path,
    frames = frames,
    walker = frames >= 6,
    index = tip.index,
  }
end

local function resolveSpriteDef(data, spriteId)
  local sprites = (data and data.sprites) or {}
  -- Copycat is never a real sheet in the ROM: object events use $FB and the
  -- map callback (or our default) remaps the slot to SPRITE_LASS (lass.png).
  if spriteId == "SPRITE_COPYCAT" or spriteId == 0xFB then
    local lass = findSheet(sprites, {
      "SPRITE_LASS", "SPRITE_TWIN", "lass", "twin",
    }, 0x28)
    if lass and lass.image then return lass end
    return {
      id = "SPRITE_LASS",
      image = "assets/generated/sprites/lass.png",
      frames = 6, walker = true, index = 0x28,
    }
  end
  -- Sudowoodo post-reveal sheet by direct id.  The OverworldSprites row is
  -- $52 (pret SPRITE_SUDOWOODO) -- $6D is not a sprite constant at all, and
  -- looking it up is why the revealed tree came back as a placeholder.
  if spriteId == "SPRITE_SUDOWOODO" or spriteId == 0x52 then
    local s = findSheet(sprites, {
      "SPRITE_SUDOWOODO", "sudowoodo", "Sudowoodo",
    }, 0x52)
    if s and s.image then return s end
    local fabricated = diskSheet("SPRITE_SUDOWOODO")
    if fabricated then return fabricated end
  end
  -- Variable-sprite ids resolve through their SLOT first; see isVariableSpriteId.
  if isVariableSpriteId(spriteId) then
    local fromSlot = resolveVariableSprite(data, sprites, spriteId)
    if fromSlot and fromSlot.image then return fromSlot end
  end
  local spriteDef = type(spriteId) == "string" and sprites[spriteId] or nil
  if spriteDef and spriteDef.image then return spriteDef end
  if type(spriteId) == "string" then
    spriteDef = resolveVariableSprite(data, sprites, spriteId)
      or resolveBreedSprite(sprites, spriteId)
    if spriteDef and spriteDef.image then return spriteDef end
    local aliases = SPRITE_ALIASES[spriteId]
    if aliases then
      for _, alt in ipairs(aliases) do
        if sprites[alt] and sprites[alt].image then return sprites[alt] end
      end
    end
    local index = SPRITE_INDEX_FALLBACK[spriteId]
    if index then
      spriteDef = spriteByIndex(sprites, index)
      if spriteDef and spriteDef.image then return spriteDef end
      -- Some extracts only key sheets as SPRITE_%02X / SPRITE_%d
      local hex = sprites[string.format("SPRITE_%02X", index)]
        or sprites[string.format("SPRITE_%d", index)]
        or sprites[index]
      if hex and type(hex) == "table" and hex.image then return hex end
    end
    -- Disk path last-resort for common overworld sheets (Route 37 girls, etc.)
    local fabricated = diskSheet(spriteId)
    if fabricated then return fabricated end
    -- Never accept the fruit-tree sheet for a named story NPC: that is how
    -- Misty / Rocket became the green "boundary bush" on Route 25.
    if spriteId == "SPRITE_FRUIT_TREE" or spriteId == "SPRITE_BUSH" then
      if sprites.SPRITE_RED then return sprites.SPRITE_RED end
    end
  end
  -- Never pick a random sheet (pairs iteration used to hand Misty the tree).
  if sprites.SPRITE_RED and sprites.SPRITE_RED.image then return sprites.SPRITE_RED end
  if sprites.SPRITE_CHRIS and sprites.SPRITE_CHRIS.image then return sprites.SPRITE_CHRIS end
  sprites.SPRITE_FALLBACK = sprites.SPRITE_FALLBACK or FALLBACK_SPRITE
  return sprites.SPRITE_FALLBACK
end


-- Force big-doll ids through to SpriteRenderer even if the sheet was looked
-- up by index (id string may otherwise be SPRITE_33 / a mon icon).
local function withBigFlag(spriteDef, spriteId, objDef)
  if not spriteDef then return spriteDef end
  local big = (objDef and objDef.big)
    or spriteId == "SPRITE_BIG_SNORLAX"
    or spriteId == "SPRITE_BIG_LAPRAS"
    or (spriteDef.id == "SPRITE_BIG_SNORLAX")
    or (spriteDef.id == "SPRITE_BIG_LAPRAS")
  if not big then return spriteDef end
  return setmetatable({
    big = true,
    id = (spriteId == "SPRITE_BIG_LAPRAS" or spriteDef.id == "SPRITE_BIG_LAPRAS")
      and "SPRITE_BIG_LAPRAS" or "SPRITE_BIG_SNORLAX",
    frames = 1,
    walker = false,
  }, { __index = spriteDef })
end

-- Published so the MAP EDITOR draws the same sheet the world does.
--
-- The resolution above is not a lookup, it is a pile of hard-won special
-- cases: Copycat is never a real sheet, Sudowoodo's row is $52 and not $6D,
-- variable-sprite ids resolve through their SLOT, several imports key sheets
-- only as SPRITE_%02X, and the fruit-tree sheet must never be accepted for a
-- named story NPC. An editor that looked sprites up by name would get the
-- placeholder for every one of those and show a map full of blue boxes that
-- the game draws people on -- so it asks this instead.
NPC.resolveSpriteDef = resolveSpriteDef

function NPC.new(data, mapId, objDef)
  local self = setmetatable({}, NPC)
  self.def = objDef
  self.id = string.format("%s_obj_%d", mapId, objDef.index)
  self.sprite = SpriteRenderer.new(withBigFlag(resolveSpriteDef(data, objDef.sprite), objDef.sprite, objDef), self.id)
  -- 2x2 footprint for Snorlax / Lapras dolls (Collision.occupied reads this)
  self.big = (self.sprite and self.sprite.big) or objDef.big
    or objDef.sprite == "SPRITE_BIG_SNORLAX"
    or objDef.sprite == "SPRITE_BIG_LAPRAS"
    or false
  -- object_event coordinates are already walk-grid cells
  self.cellX, self.cellY = objDef.x, objDef.y
  self.px, self.py = self.cellX * 16, self.cellY * 16
  self.facing = FACING_FROM_RANGE[objDef.range] or "down"
  -- A fixed sheet frame from the extractor (polished's ball/cut/fruit
  -- sheet: cut trees are frame 1, fruit trees frame 2).  The renderer
  -- draws exactly this 16x16 row and skips facing entirely -- a tree has
  -- no directions to turn to.
  self.fixedFrame = objDef.frame
  self.moving = false
  self.progress = 0
  self.stepFlip = false
  self.frozen = false -- scripts freeze NPCs while talking
  self.wanders = objDef.movement == "WALK"
  -- SPRITEMOVEDATA_SPINRANDOM_* / _SPIN_CLOCKWISE / _SPIN_COUNTERCLOCKWISE
  self.spins = objDef.movement == "SPIN" and (objDef.range or "SPIN_SLOW") or nil
  self.roamDirs = ROAM_DIRS[objDef.range] or ROAM_DIRS.ANY_DIR
  self.timer = love.math.random(30, 120)
  return self
end

-- Re-resolve the sheet after a `variablesprite` assignment: a map's callback
-- can fill the slot in after its objects have already been built.
function NPC:refreshSprite(data)
  self.sprite = SpriteRenderer.new(withBigFlag(resolveSpriteDef(data, self.def.sprite), self.def.sprite, self.def), self.id)
end

function NPC:facePlayer(player)  local dx = player.cellX - self.cellX
  local dy = player.cellY - self.cellY
  if math.abs(dx) > math.abs(dy) then
    self.facing = dx > 0 and "right" or "left"
  else
    self.facing = dy > 0 and "down" or "up"
  end
end

-- movement_tree_shake (ShakeHeadbuttTree, 23:$4A8E): the object jitters in
-- place without leaving its cell.  Sudowoodo does this when talked to without
-- the SQUIRTBOTTLE, and a headbutt tree does it when struck.
function NPC:shake(frames, onDone)
  self.shakeFrames = frames or 32
  self.shakeDone = onDone
end

function NPC:update(map, entities)
  if self.shakeFrames then
    self.shakeFrames = self.shakeFrames - 1
    self.px = self.cellX * 16 + (math.floor(self.shakeFrames / 2) % 2 == 0 and 1 or -1)
    if self.shakeFrames <= 0 then
      self.shakeFrames = nil
      self.px = self.cellX * 16
      local done = self.shakeDone
      self.shakeDone = nil
      if done then done() end
    end
    return
  end
  -- self.stepFrames overrides the shared 16-frame walk for an object whose
  -- step has to stay in phase with something else: Yellow's follower
  -- Pikachu takes the player's own step length, halved while it is more
  -- than a cell behind (FastPikachuFollow, engine/pikachu/
  -- pikachu_follow.asm).  self.hopStep is the same file's $5-$8 hop
  -- command: two cells of travel inside one step's frames
  -- (DoubleAddPikachuStepVectorToScreenPixelCoords), which is why the
  -- pixel span doubles while the frame count does not.  Nothing else sets
  -- either field, so every other object keeps the constant (#410, #409).
  local stepLen = self.stepFrames or STEP_FRAMES
  local span = self.hopStep and 2 or 1
  if self.moving then
    self.progress = self.progress + 1
    -- NPC_CHANGE_FACING: animate the walk cycle in place, no translation
    -- (movement.asm ChangeFacingDirection zeroes the delta); px/py stay
    -- pinned to the current cell while walkPhase() cycles.
    if self.marching then
      if self.progress >= stepLen then
        self.progress = 0
        self.moving = false
        self.marching = false
        self.stepFlip = not self.stepFlip
      end
      return
    end
    local d = Collision.DELTA[self.facing]
    -- 1px per frame at the default length; a shortened step scales instead,
    -- so the cell still lands on a 16px boundary (Player:update does the
    -- same for the bicycle)
    local moved = math.floor(self.progress * 16 * span / stepLen)
    self.px = self.cellX * 16 + d[1] * moved
    self.py = self.cellY * 16 + d[2] * moved
    if self.progress >= stepLen then
      self.cellX, self.cellY = self.targetX, self.targetY
      self.targetX, self.targetY = nil, nil
      self.px, self.py = self.cellX * 16, self.cellY * 16
      self.moving = false
      self.hopStep = nil
      self.stepFlip = not self.stepFlip
    end
    return
  end
  if self.frozen then return end
  if self.spins then
    -- Spinners never leave their cell, so this is the whole behaviour: turn
    -- on a timer.  A script that freezes the object (talking to it, a
    -- cutscene) stops the spin, exactly as SPRITEMOVEFN is suspended while
    -- STEP_TYPE_SCRIPT owns the object.
    self.timer = self.timer - 1
    if self.timer > 0 then return end
    local kind = self.spins
    if kind == "SPIN_CW" or kind == "SPIN_CCW" then
      self.facing = SPIN_NEXT[kind][self.facing] or "down"
      self.timer = 16
    elseif kind == "SPIN_FAST" then
      local pick = SPIN_DIRS[love.math.random(4)]
      if pick == self.facing then pick = SPIN_FLIP[pick] or pick end
      self.facing = pick
      self.timer = love.math.random(1, 32)
    else
      self.facing = SPIN_DIRS[love.math.random(4)]
      self.timer = love.math.random(1, 128)
    end
    return
  end
  if not self.wanders then return end
  self.timer = self.timer - 1
  if self.timer > 0 then return end
  self.timer = love.math.random(30, 180)
  local dir = self.roamDirs[love.math.random(#self.roamDirs)]
  self.facing = dir
  if love.math.random() < 0.5 then return end -- sometimes just turn
  -- never wander onto warps, so NPCs don't walk out of the map
  local tx, ty = Collision.target(self.cellX, self.cellY, dir)
  if map:warpAtCell(tx, ty) then return end
  if Collision.canMove(map, entities, self, dir) then
    self.targetX, self.targetY = tx, ty
    self.moving = true
    self.progress = 0
  end
end

function NPC:walkPhase()
  if not self.moving then return 0 end
  local p = self.progress % 16
  return (p >= 4 and p < 12) and 1 or 0
end

-- Same contract as Player:pose -- the sheet, position, facing and step
-- phase this frame renders to -- so a render pipeline can pose an NPC
-- without caring which kind of entity it is.  An NPC never hops, so the
-- trailing hop flag is always false.
function NPC:pose()
  -- movement_set_sliding: the object keeps its standing frame while it moves,
  -- so it glides rather than walks (Ice Path boulders, the Kimono Girls).
  return self.sprite, self.px, self.py, self.facing,
         self.sliding and 0 or self:walkPhase(), self.stepFlip, false
end

function NPC:draw(camX, camY)
  local sprite, px, py, facing, phase, flip = self:pose()
  if self.fixedFrame then
    sprite:drawFixedFrame(px, py, camX, camY, self.fixedFrame)
    return
  end
  sprite:draw(px, py, camX, camY, facing, phase, flip)
end

return NPC
