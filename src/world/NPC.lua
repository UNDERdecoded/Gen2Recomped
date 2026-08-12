-- Map object (NPC/item) built from a generated object_event entry.
-- STAY objects keep their facing; WALK objects wander randomly within the
-- roam constraint (ANY_DIR / UP_DOWN / LEFT_RIGHT), like the original.

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

local function resolveVariableSprite(data, sprites, spriteId)
  local slot = tonumber(spriteId:match("^SPRITE_VAR_(%d+)$"))
  if not slot then return nil end
  local save = require("src.core.Game").save
  local assigned = save and save.gen2VarSprites and save.gen2VarSprites[slot]
  if not assigned then
    local defaults = data and data.map_scripts and data.map_scripts.varSprites
    assigned = defaults and defaults[slot]
  end
  return spriteByIndex(sprites, assigned or 1)
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
}

-- OverworldSprites row index (= object_event sprite byte) for story NPCs
-- when the named sheet is missing after a partial extract.
local SPRITE_INDEX_FALLBACK = {
  SPRITE_SILVER = 4,
  SPRITE_RIVAL = 4,
  SPRITE_MISTY = 0x1D,
  SPRITE_BLUE = 7,
  SPRITE_RED_KANTO = 6,
  SPRITE_ROCKET = 0x35,
  SPRITE_COPYCAT = 0xFB,
  SPRITE_SUPER_NERD = 0x2B,
  SPRITE_COOLTRAINER_M = 0x23,
  SPRITE_GRAMPS = 0x2F,
  SPRITE_FRUIT_TREE = 0x5D,
  SPRITE_SURF = 0x53,
  SPRITE_SURFING_PIKACHU = 0x34,
  -- Kanto post-game overworld actors
  SPRITE_BIG_SNORLAX = 0x6C,
  SPRITE_SNORLAX = 0x6C,
  SPRITE_MACHOP = 0x6E,
  SPRITE_GYM_GUIDE = 0x29,
  SPRITE_OFFICER = 0x3A,
  SPRITE_JANINE = 0x1E,
  SPRITE_SURGE = 0x1B,
  SPRITE_ERIKA = 0x1C,
  SPRITE_SABRINA = 0x1F,
  SPRITE_BROCK = 0x1A,
}

local function resolveSpriteDef(data, spriteId)
  local sprites = (data and data.sprites) or {}
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

function NPC.new(data, mapId, objDef)
  local self = setmetatable({}, NPC)
  self.def = objDef
  self.id = string.format("%s_obj_%d", mapId, objDef.index)
  self.sprite = SpriteRenderer.new(resolveSpriteDef(data, objDef.sprite), self.id)
  -- object_event coordinates are already walk-grid cells
  self.cellX, self.cellY = objDef.x, objDef.y
  self.px, self.py = self.cellX * 16, self.cellY * 16
  self.facing = FACING_FROM_RANGE[objDef.range] or "down"
  self.moving = false
  self.progress = 0
  self.stepFlip = false
  self.frozen = false -- scripts freeze NPCs while talking
  self.wanders = objDef.movement == "WALK"
  self.roamDirs = ROAM_DIRS[objDef.range] or ROAM_DIRS.ANY_DIR
  self.timer = love.math.random(30, 120)
  return self
end

-- Re-resolve the sheet after a `variablesprite` assignment: a map's callback
-- can fill the slot in after its objects have already been built.
function NPC:refreshSprite(data)
  self.sprite = SpriteRenderer.new(resolveSpriteDef(data, self.def.sprite), self.id)
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
  if self.frozen or not self.wanders then return end
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
  sprite:draw(px, py, camX, camY, facing, phase, flip)
end

return NPC
