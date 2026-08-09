-- Gen 2 battle-animation player.
--
-- GSC's animations are a bytecode VM, not Gen 1's subanimation/frame-block
-- tables, so this is a separate player from src/battle/AnimPlayer.lua rather
-- than another code path inside it.  The extractor
-- (RomExtractorGen2:gen2BattleAnims) hands over:
--
--   scripts[animId]  = { entry = <index>, code = { <instruction>, ... } }
--   objects[id]      = { oamFlags, fixY, frameset, fn, palette, gfx }
--   framesets[id]    = { frames = { { oam, duration, xflip, yflip } },
--                        loop = "hold" | "restart" }
--   oam[id]          = { tile = <sheet offset>,
--                        sprites = { { y, x, tile, attr } } }
--   gfx[id]          = { tiles, cols, image }
--   palettes[i]      = { {r,g,b}, {r,g,b}, {r,g,b}, {r,g,b} }
--   moveAnims[MOVE]  = animId
--
-- The engine's own object `function`s (~200 hand-written asm routines that
-- push objects along arcs, spin them, track the target and eventually
-- delete them) are not portable as data.  Objects here therefore hold the
-- position their script spawned them at and simply run their real frameset,
-- which reproduces the correct sprites, palettes, placement and timing for
-- every move while motion paths read as static bursts.
--
-- Coordinates follow the hardware: an object's x/y are OAM coordinates, so
-- screen space is (x - 8, y - 16).  InitBattleAnimBuffer (33:$49F9) mirrors
-- an object for the enemy's side when its oamFlags bit 0 is set:
--   x' = 180 - x
--   y' = fixY == $FF and 40 + y or fixY - y
--   xOffset' = -xOffset

local Gen2AnimPlayer = {}
Gen2AnimPlayer.__index = Gen2AnimPlayer

local MAX_OBJECTS = 10          -- wActiveAnimObjects holds ten slots
local MAX_STEPS_PER_FRAME = 256 -- guard against a script looping forever
local TAIL_FRAMES = 16          -- let the last objects finish after `ret`
local MAX_OBJECT_AGE = 48       -- see tickObjects
local TRAVEL_FRAMES = 20        -- how long a *ToTarget function takes

-- DoBattleAnimFrame's ~80 object functions are hand-written asm, so the port
-- reads their names out of the manifest and approximates the handful of
-- motions that actually move an object across the screen.  Everything else
-- stays where its script spawned it, which is where the real engine puts it
-- on frame one anyway.  Anchors are OAM coordinates: an animation is written
-- from the player's side, with the user around (64, 96) and the target pic
-- around (136, 48); InitBattleAnimBuffer's mirror maps those to the enemy's
-- side as x' = 180 - x and y' = 40 + y.
local TARGET_ANCHOR = { x = 136, y = 48 }
local TARGET_ANCHOR_MIRRORED = { x = 44, y = 88 }

local function shade(value)
  return { value, value, value }
end

local DEFAULT_PALETTE = {
  shade(1), shade(0.66), shade(0.33), shade(0),
}

-- Lua 5.1 has no bitwise operators
local function band(a, b)
  local result, bit = 0, 1
  for _ = 1, 8 do
    if a % 2 == 1 and b % 2 == 1 then result = result + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return result
end

local function bxor(a, b)
  local result, bit = 0, 1
  for _ = 1, 8 do
    if a % 2 ~= b % 2 then result = result + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return result
end

function Gen2AnimPlayer.new(data)
  local anims = data and data.battle_anims or {}
  return setmetatable({
    data = data,
    anims = anims,
    images = {},
    quads = {},
    warned = {},
    objects = {},
    -- WideBattle reads these two off the Gen 1 player; keep them defined
    steps = {},
    stepIndex = 1,
    done = true,
  }, Gen2AnimPlayer)
end

function Gen2AnimPlayer:release()
  for _, img in pairs(self.images) do
    if img and img.release then pcall(img.release, img) end
  end
  self.images, self.quads = {}, {}
end

function Gen2AnimPlayer:warnOnce(key, fmt, ...)
  if self.warned[key] then return end
  self.warned[key] = true
  print(string.format(fmt, ...))
end

-- Resolve a move id (or one of the misc animation names) to a script.
function Gen2AnimPlayer:scriptFor(moveId)
  local anims = self.anims
  local id = anims.moveAnims and anims.moveAnims[moveId]
  if not id and anims.misc then id = anims.misc[moveId] end
  if not id and type(moveId) == "number" then id = moveId end
  return id and anims.scripts and anims.scripts[id] or nil
end

function Gen2AnimPlayer:start(moveId, attackerIsPlayer, opts)
  self.objects = {}
  self.callStack = {}
  self.vars = { var = 0, param = 0, loop = nil }
  self.wait = 0
  self.tail = 0
  self.ranFrames = 0
  self.enemySide = not attackerIsPlayer
  self.opts = opts
  self.moveId = moveId
  self.loops = {}
  self.script = self:scriptFor(moveId)
  if not self.script then
    self:warnOnce("anim:" .. tostring(moveId),
                  "Gen2AnimPlayer: no animation data for move %s",
                  tostring(moveId))
    self.done = true
    return false
  end
  self.pc = self.script.entry
  self.done = false
  return true
end

function Gen2AnimPlayer:isDone()
  -- BattleAnimRunScript also waits on wNumActiveBattleAnims, but objects
  -- only clear themselves from inside their asm functions, so the port ends
  -- on the top-level `ret` plus a short drain instead of hanging forever.
  return self.done and self.tail <= 0
end

-- No SE_* routing: Gen 2 drives screen effects from BattleBGEffects, which
-- the port approximates locally rather than through BattleState's Gen 1
-- animation-effect table.
function Gen2AnimPlayer:pollEffects()
  return {}
end

function Gen2AnimPlayer:spawn(id, x, y, param)
  if #self.objects >= MAX_OBJECTS then return end
  local def = self.anims.objects and self.anims.objects[id]
  if not def then
    self:warnOnce("obj:" .. tostring(id),
                  "Gen2AnimPlayer: unknown animation object %d", id)
    return
  end
  local ox, oy, xOffset = x, y, 0
  if self.enemySide and (def.oamFlags or 0) % 2 == 1 then
    ox = 180 - x
    if (def.fixY or 0) == 0xFF then oy = 40 + y else oy = (def.fixY or 0) - y end
    xOffset = -xOffset
  end
  local set = self.anims.framesets and self.anims.framesets[def.frameset]
  local first = set and set.frames[1]
  if not first then return end
  self.objects[#self.objects + 1] = {
    def = def, x = ox, y = oy, xOffset = xOffset, yOffset = 0,
    fn = self.anims.functions and self.anims.functions[def.fn or 0],
    param = param, frame = 1, left = first.duration + 1, cycles = 0, age = 0,
  }
end

local function frameset(self, obj)
  return self.anims.framesets and self.anims.framesets[obj.def.frameset]
end

function Gen2AnimPlayer:moveObject(obj)
  local name = obj.fn
  if not name then return end
  local t = math.min(1, obj.age / TRAVEL_FRAMES)
  if name:find("Circle") then
    local angle = obj.age / 8
    obj.xOffset = math.floor(math.cos(angle) * 12 + 0.5)
    obj.yOffset = math.floor(math.sin(angle) * 8 + 0.5)
    return
  end
  if not name:find("ToTarget") then return end
  local anchor = self.enemySide and TARGET_ANCHOR_MIRRORED or TARGET_ANCHOR
  obj.xOffset = math.floor((anchor.x - obj.x) * t + 0.5)
  obj.yOffset = math.floor((anchor.y - obj.y) * t + 0.5)
  if name:find("Throw") then
    obj.yOffset = obj.yOffset - math.floor(math.sin(t * math.pi) * 16 + 0.5)
  elseif name:find("Wave") then
    obj.yOffset = obj.yOffset + math.floor(math.sin(t * math.pi * 4) * 6 + 0.5)
  end
  if t >= 1 and name:find("Disappear") then obj.dead = true end
end

function Gen2AnimPlayer:tickObjects()
  local live = {}
  for _, obj in ipairs(self.objects) do
    local set = frameset(self, obj)
    if set then
      obj.age = obj.age + 1
      self:moveObject(obj)
      obj.left = obj.left - 1
      if obj.left <= 0 then
        obj.frame = obj.frame + 1
        -- a $FE-terminated frameset restarts; $FF holds the last frame on
        -- hardware until the object's asm function deletes it, and with no
        -- function to run the object retires instead so the burst clears
        if not set.frames[obj.frame] and set.loop == "restart"
           and obj.cycles < 8 then
          obj.frame, obj.cycles = 1, obj.cycles + 1
        end
        local frame = set.frames[obj.frame]
        if frame then obj.left = frame.duration + 1 end
      end
      -- a $FE frameset restarts forever on hardware until the object's own
      -- function retires it, so the port bounds the lifetime instead
      if set.frames[obj.frame] and obj.age < MAX_OBJECT_AGE and not obj.dead then
        live[#live + 1] = obj
      end
    end
  end
  self.objects = live
end

function Gen2AnimPlayer:step(inst)
  local op = inst.op
  if op == "delay" then
    self.wait = inst.frames
    self.pc = self.pc + 1
    return
  elseif op == "obj" then
    local a = inst.args
    self:spawn(a[1], a[2], a[3], a[4])
  elseif op == "clearobjs" then
    self.objects = {}
  elseif op == "sound" then
    self:playSound(inst)
  elseif op == "cry" then
    self:playCry()
  elseif op == "setvar" then
    self.vars.var = inst.args[1]
  elseif op == "incvar" then
    self.vars.var = (self.vars.var + 1) % 256
  elseif op == "jump" then
    if inst.to then self.pc = inst.to end
    return
  elseif op == "call" then
    if inst.to then
      self.callStack[#self.callStack + 1] = self.pc + 1
      self.pc = inst.to
      return
    end
  elseif op == "ret" then
    local back = table.remove(self.callStack)
    if back then
      self.pc = back
    else
      self.done = true
      self.tail = TAIL_FRAMES
    end
    return
  elseif op == "loop" then
    -- anim_loop count, address: the count lives in the instruction, so the
    -- player keeps its own counter keyed by the instruction table itself
    self.loops = self.loops or {}
    local left = self.loops[inst]
    if left == nil then left = inst.args[1] end
    left = left - 1
    if left > 0 then
      self.loops[inst] = left
      if inst.to then self.pc = inst.to; return end
    else
      self.loops[inst] = nil
    end
  elseif op == "ifvarequal" then
    if self.vars.var == inst.args[1] and inst.to then
      self.pc = inst.to
      return
    end
  elseif op == "ifparamequal" then
    if self.vars.param == inst.args[1] and inst.to then
      self.pc = inst.to
      return
    end
  elseif op == "ifparamand" then
    if band(self.vars.param, inst.args[1]) ~= 0 and inst.to then
      self.pc = inst.to
      return
    end
  elseif op == "jumpuntil" then
    -- `anim_jumpuntil` spins on the same address until every queued object
    -- has retired, which is exactly the drain this player already does
    if #self.objects > 0 and inst.to then
      self.pc = inst.to
      self.wait = 1
      return
    end
  end
  self.pc = self.pc + 1
end

function Gen2AnimPlayer:playSound(inst)
  local Sound = require("src.core.Sound")
  -- `anim_sound duration, tracks, id` packs duration/tracks into the first
  -- byte and the SFX id into the second.  That id is the row of the ROM's
  -- SFX pointer table, which is exactly how audio.sfxIndex is keyed, so the
  -- animation names its own sample -- moves.lua's anim.sound is only the
  -- fallback for moves whose script the importer could not walk.
  local audio = self.data and self.data.audio
  local id = inst and inst.args and inst.args[2]
  local name = id and audio and audio.sfxIndex and audio.sfxIndex[tostring(id)]
  if name and audio.sfx and audio.sfx[name] then
    return Sound.play(self.data, name)
  end
  local moves = self.data and self.data.moves
  local def = moves and self.moveId and moves[self.moveId]
  if def and def.anim then
    pcall(Sound.playMove, self.data, def.anim)
  end
end

function Gen2AnimPlayer:playCry()
  -- anim_cry plays the attacker's cry; BattleState owns the battlers, so
  -- leave it to the fallback path rather than guess a species here.
end

function Gen2AnimPlayer:update()
  if self.done then
    if self.tail > 0 then self.tail = self.tail - 1 end
    if self.tail <= 0 then self.objects = {} end
    self:tickObjects()
    return
  end
  if self.wait > 0 then
    self.wait = self.wait - 1
    self:tickObjects()
    return
  end
  local code = self.script.code
  self.ranFrames = (self.ranFrames or 0) + 1
  -- a script whose branches depend on engine state the port does not model
  -- (Fury Cutter's hit count, Present's roll, Magnitude's roll) can spin;
  -- bound it well past the longest real animation
  if self.ranFrames > 180 then
    self.done = true
    self.tail = TAIL_FRAMES
    self:tickObjects()
    return
  end
  for _ = 1, MAX_STEPS_PER_FRAME do
    local inst = code[self.pc]
    if not inst then
      self.done = true
      self.tail = TAIL_FRAMES
      break
    end
    self:step(inst)
    if self.done or self.wait > 0 then break end
  end
  if self.wait > 0 then self.wait = self.wait - 1 end
  self:tickObjects()
end

function Gen2AnimPlayer:sheetImage(gfxId)
  local cached = self.images[gfxId]
  if cached ~= nil then return cached or nil end
  local sheet = self.anims.gfx and self.anims.gfx[gfxId]
  local img
  if sheet and love and love.graphics and love.graphics.newImage then
    local ok, loaded = pcall(love.graphics.newImage, sheet.image)
    if ok then img = loaded end
  end
  if not img then
    self:warnOnce("gfx:" .. tostring(gfxId),
                  "Gen2AnimPlayer: anim sheet %s unavailable",
                  tostring(sheet and sheet.image or gfxId))
  end
  self.images[gfxId] = img or false
  return img
end

function Gen2AnimPlayer:tileQuad(gfxId, tile)
  local sheet = self.anims.gfx and self.anims.gfx[gfxId]
  if not sheet or tile >= sheet.tiles then return nil end
  local perSheet = self.quads[gfxId]
  if not perSheet then
    perSheet = {}
    self.quads[gfxId] = perSheet
  end
  local q = perSheet[tile]
  if q == nil and love and love.graphics and love.graphics.newQuad then
    local cols = sheet.cols or 16
    local rows = math.ceil(sheet.tiles / cols)
    q = love.graphics.newQuad((tile % cols) * 8, math.floor(tile / cols) * 8,
                              8, 8, cols * 8, rows * 8)
    perSheet[tile] = q
  end
  return q
end

-- BattleObjectPals holds six palettes that CGBCopyBattleObjectPals loads
-- into OBJ slots 2..7; slots 0 and 1 are the two battlers' own palettes, so
-- an object using those falls back to the DMG greys.
local OBJ_PALETTE_BASE = 2

function Gen2AnimPlayer:paletteFor(index)
  self.palCache = self.palCache or {}
  local cached = self.palCache[index]
  if cached then return cached end
  local pals = self.anims.palettes
  local pal = pals and pals[index - OBJ_PALETTE_BASE]
  if not pal or #pal < 4 then return DEFAULT_PALETTE end
  -- the extractor stores BattleObjectPals as 0-255 channels; the shader
  -- takes 0-1 triples
  local out = {}
  for i = 1, 4 do
    out[i] = { pal[i][1] / 255, pal[i][2] / 255, pal[i][3] / 255 }
  end
  self.palCache[index] = out
  return out
end

-- Draw the live objects onto the 160x144 battle canvas.  Gen 2 is native
-- CGB, so the object palettes come straight from BattleObjectPals and
-- BattleState's SGB colorFn is ignored.
function Gen2AnimPlayer:draw()
  local g = love and love.graphics
  if not g then return end
  local shader = require("src.render.PaletteFX").shader()
  for _, obj in ipairs(self.objects) do
    local set = frameset(self, obj)
    local frame = set and set.frames[obj.frame]
    local row = frame and self.anims.oam and self.anims.oam[frame.oam]
    if row then
      local img = self:sheetImage(obj.def.gfx)
      local pal = self:paletteFor(obj.def.palette or 0)
      if img and shader and g.setShader then
        g.setShader(shader)
        shader:send("c0", pal[1])
        shader:send("c1", pal[2])
        shader:send("c2", pal[3])
        shader:send("c3", pal[4])
      end
      -- BattleAnimOAMUpdate keeps one flip state per object per frame
      -- ($CA19 = frameFlags XOR obj.oamFlags, masked $E0); it negates the
      -- sprite offsets and is then XORed into each sprite's own attribute.
      local flip = band(bxor((frame.xflip and 0x20 or 0)
                             + (frame.yflip and 0x40 or 0),
                             obj.def.oamFlags or 0), 0xE0)
      local xf = math.floor(flip / 32) % 2 == 1
      local yf = math.floor(flip / 64) % 2 == 1
      for _, sprite in ipairs(row.sprites) do
        local ox = obj.x + obj.xOffset + (xf and -sprite.x - 8 or sprite.x)
        local oy = obj.y + obj.yOffset + (yf and -sprite.y - 8 or sprite.y)
        local quad = img and self:tileQuad(obj.def.gfx, row.tile + sprite.tile)
        if quad and ox > 0 and ox < 168 and oy > 0 and oy < 160 then
          local attr = bxor(sprite.attr, flip)
          local sx = math.floor(attr / 32) % 2 == 1
          local sy = math.floor(attr / 64) % 2 == 1
          g.draw(img, quad,
                 ox - 8 + (sx and 8 or 0), oy - 16 + (sy and 8 or 0), 0,
                 sx and -1 or 1, sy and -1 or 1)
        end
      end
      if img and shader and g.setShader then g.setShader() end
    end
  end
end

-- BattleState keeps the resting ball on screen after a capture; Gen 2's
-- ball animation is scripted the same way, so there is nothing to freeze.
function Gen2AnimPlayer:finalSprites() return nil end
function Gen2AnimPlayer:drawSprites() end

return Gen2AnimPlayer
