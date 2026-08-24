-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

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

-- DoBattleAnimFrame's 80 object functions are hand-written asm, so the port
-- reads their names out of the manifest (BATTLE_ANIM_FUNC_*) and sorts them
-- into the motion archetypes below.  This is an approximation of the paths,
-- not a recompilation of them: what it buys is that every object actually
-- travels the way its routine travels instead of sitting where the script
-- spawned it.  Anchors are OAM coordinates: an animation is written from the
-- player's side, with the user around (64, 96) and the target pic around
-- (136, 48); InitBattleAnimBuffer's mirror maps those to the enemy's side as
-- x' = 180 - x and y' = 40 + y.
local TARGET_ANCHOR = { x = 136, y = 48 }
local TARGET_ANCHOR_MIRRORED = { x = 44, y = 88 }
local USER_ANCHOR = { x = 64, y = 96 }
local USER_ANCHOR_MIRRORED = { x = 116, y = 136 }

-- name -> archetype.  "gone" suffixes delete the object when it arrives,
-- matching the routines whose names end in Disappear.
local MOTION = {
  Null = "static", LockOnMindReader = "static", AnimObjB0 = "static",
  Sound = "static",

  MoveFromUserToTarget = "toTarget",
  MoveFromUserToTargetSpinAround = "toTarget",
  MoveFromUserToTargetAndDisappear = "toTargetGone",
  Kick = "toTargetGone", SpeedLine = "toTargetGone",
  Bite = "toTarget", Horn = "toTarget", Needle = "toTarget",
  WaterGun = "toTarget", Surf = "toTarget", String = "toTarget",
  SkyAttack = "toTarget", RockSmash = "toTarget", BetaPursuit = "toTarget",
  PresentSmokescreen = "toTarget", Clamp_Encore = "toTarget",
  Wrap = "toTarget", Dig = "toTarget",

  MoveWaveToTarget = "wave", RazorLeaf = "wave", Gust = "wave",
  RazorWind = "wave", PetalDance = "wave", Sing = "wave",
  PoisonGas = "wave", Powder = "wave", Cotton = "wave",

  ThrowFromUserToTarget = "arc", PokeBall = "arc", PokeBallBlocked = "arc",
  ThrowFromUserToTargetAndDisappear = "arcGone",
  Ember = "arc", FireBlast = "arc", SacredFire = "arc",
  SmokeFlameWheel = "arc", Sludge = "arc", Egg = "arc",
  LeechSeed = "arc", Spikes = "arc", ThiefPayday = "arc",
  Bonemerang = "arc", StrengthSeismicToss = "arc", BatonPass = "arc",

  Absorb = "toUser", AbsorbCircle = "circle", Bubble = "toUser",

  MoveInCircle = "circle", ConfuseRay = "circle", Dizzy = "circle",
  RapidSpin = "circle", SafeguardProtect = "circle", Conversion = "circle",
  HiddenPower = "circle", SolarBeam = "circle", Shiny = "circle",
  MetronomeSparkleSketch = "circle",

  MoveUp = "rise", FloatUp = "rise", Recover = "rise", Amnesia = "rise",
  GrowthSwordsDance = "rise", HealBellNotes = "rise", PerishSong = "rise",
  PsychUp = "rise", AncientPower = "rise", SwaggerMorningSun = "rise",
  Agility = "rise",

  Drop = "fall", Curse = "fall", RainSandstorm = "fall",
  SpiralDescent = "spiral",

  Shake = "shake", ThunderWave = "shake", Paralyzed = "shake",
  EncoreBellyDrum = "shake", MetronomeHand = "shake",
}

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
    effects = {},
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

-- BattleState drives the ball toss and the send-out with Gen 1's animation
-- ids (TossBallAnimation's TOSS/POOF/HIDEPIC/SHAKE chain).  Gen 2 keeps the
-- whole toss in one script -- ANIM_THROW_POKE_BALL reads wPokeBallAnimData
-- through anim_checkpokeball and wobbles or breaks out by itself -- so the
-- toss row maps onto it and the chain's remaining rows have nothing of their
-- own to play.  Without this nothing resolved and no ball was ever thrown.
local GEN1_BALL_ANIMS = {
  TOSS_ANIM = "throwPokeBall",
  GREATTOSS_ANIM = "throwPokeBall",
  ULTRATOSS_ANIM = "throwPokeBall",
  BLOCKBALL_ANIM = "throwPokeBall",
  POOF_ANIM = "sendOutMon",
  -- The shiny sparkle is not an animation of its own: BattleAnim_SendOutMon
  -- opens `anim_if_param_equal $1, .Shiny`, and core.asm plays the SAME
  -- animation a SECOND time with wBattleAnimParam = 1 whenever
  -- CheckShininess returns carry (:3566 the enemy's send-out, :4057 the
  -- player's, :9091 a wild encounter, which plays only this pass).  That
  -- branch is eight SFX_SHINE stars over an inverted flash and a
  -- gray/yellow OBJ-palette cycle.  Both Gold and Crystal carry it; Prism's
  -- script is shorter but has the same param-1 arm.
  SHINY_ANIM = "sendOutMon",
  SHAKE_ANIM = false,
  HIDEPIC_ANIM = false,
  SHOWPIC_ANIM = false,
}

-- Resolve a move id (or one of the misc animation names) to a script.
function Gen2AnimPlayer:scriptFor(moveId)
  local anims = self.anims
  local id = anims.moveAnims and anims.moveAnims[moveId]
  if not id then
    local alias = GEN1_BALL_ANIMS[moveId]
    if alias == false then return nil end
    id = anims.misc and anims.misc[alias or moveId]
  end
  if not id and type(moveId) == "number" then id = moveId end
  return id and anims.scripts and anims.scripts[id] or nil
end

-- BattleAnim_ThrowPokeBall opens with
--   anim_if_param_equal NO_ITEM,     .TheTrainerBlockedTheBall
--   anim_if_param_equal MASTER_BALL, .MasterBall
--   anim_if_param_equal ULTRA_BALL,  .UltraBall
--   anim_if_param_equal GREAT_BALL,  .GreatBall
-- so wBattleAnimParam is the ball's ITEM INDEX, and 0 is the trainer-battle
-- block.  Leaving it at 0 sent every toss down .TheTrainerBlockedTheBall,
-- which spawns BATTLE_ANIM_OBJ_HIT_YFIX off BATTLE_ANIM_GFX_HIT -- the stray
-- "attack" flash over the throw -- and skipped the whole capture tail (the
-- mon being drawn in, the wobbles, the click).
local DEFAULT_BALL_ITEM = 5   -- POKE_BALL, the generic-arc branch

local function itemIndex(self, id)
  local items = id and self.data and self.data.items
  if not items then return nil end
  local def = items[id]
  if not def then
    -- Gen2's item ids are ITEM_nnn while the battle code keys balls by
    -- Gen1's name-derived ids, so match on either
    for _, entry in pairs(items) do
      if entry.key == id then def = entry; break end
    end
  end
  local index = def and tonumber(def.index)
  return (index and index > 0) and index or nil
end

local function ballParam(self, opts)
  if self.moveId == "BLOCKBALL_ANIM" then return 0 end
  local index = opts and tonumber(opts.ballIndex)
  if index and index > 0 then return index end
  return itemIndex(self, opts and opts.ball)
    or itemIndex(self, "POKE_BALL")
    or DEFAULT_BALL_ITEM
end

function Gen2AnimPlayer:start(moveId, attackerIsPlayer, opts)
  self.objects = {}
  self.effects = {}
  self.callStack = {}
  self.vars = { var = 0, param = 0, loop = nil }
  self.wait = 0
  self.tail = 0
  self.ranFrames = 0
  self.wobbles = 0
  self.keepSprites = false
  self.keptSprites = nil
  -- Gen 1 queues its send-out poof with attackerIsPlayer = false, because
  -- TossBallAnimation's flag names the animation's ATTACKER and the poof has
  -- to land on the player's own pic (the toss row passes true, for the ball
  -- reaching the foe).  Gen 2's BattleAnim_SendOutMon is already authored on
  -- the sender's side, so reading that flag straight through mirrored the
  -- player's own release onto the wild mon.
  -- SHINY_ANIM is the same script on the same side as the send-out it
  -- follows, so it takes the same flag flip.
  if moveId == "POOF_ANIM" or moveId == "SHINY_ANIM" then
    attackerIsPlayer = not attackerIsPlayer
  end
  self.enemySide = not attackerIsPlayer
  self.opts = opts
  self.moveId = moveId
  self.loops = {}
  self.bgSides = {}
  self.script = self:scriptFor(moveId)
  if not self.script then
    if GEN1_BALL_ANIMS[moveId] == nil then
      self:warnOnce("anim:" .. tostring(moveId),
                    "Gen2AnimPlayer: no animation data for move %s",
                    tostring(moveId))
    end
    self.done = true
    return false
  end
  if GEN1_BALL_ANIMS[moveId] == "throwPokeBall" then
    self.vars.param = ballParam(self, opts)
  elseif moveId == "SHINY_ANIM" then
    self.vars.param = 1   -- wBattleAnimParam = 1 -> .Shiny
  end
  -- objects the script addresses by index outlive the port's usual object
  -- bound: on hardware they only retire when their asm function says so,
  -- and the ball has to sit through four 48-frame wobbles
  self.objIndex = 0
  self.scriptObjs = {}
  for _, inst in ipairs(self.script.code or {}) do
    if inst.op == "incobj" or inst.op == "setobj" then
      self.scriptObjs[inst.args[1]] = true
    end
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

-- `anim_bgeffect` queues one of BattleBGEffects' asm routines
-- (BATTLE_BG_EFFECT_*, constants/battle_anim_constants.asm).  Those are the
-- screen shakes, palette flashes and mon-pic moves -- everything an
-- animation does outside its own objects -- so without them a Gen 2 battle
-- showed the sprites and none of the impact.  BattleState already implements
-- Gen 1's SE_* vocabulary for exactly these effects, so each id routes onto
-- its closest counterpart rather than a second fx layer.
--
-- The side each one acts on is NOT baked into the id: every routine resolves
-- it through BGEffect_CheckBattleTurn, which is `hBattleTurn XOR
-- BG_EFFECT_STRUCT_BATTLE_TURN` -- the third `anim_bgeffect` argument, 1 for
-- the user and 0 for the target.  So the names below are all the unflipped
-- SE_* row and `side` on the queued event picks the battler.
local BG_EFFECTS = {
  [0x01] = "SE_DARK_SCREEN_FLASH",   -- FLASH_INVERTED
  [0x02] = "SE_DARK_SCREEN_FLASH",   -- FLASH_WHITE
  [0x03] = "SE_LIGHT_SCREEN_PALETTE",-- WHITE_HUES
  [0x04] = "SE_DARK_SCREEN_PALETTE", -- BLACK_HUES
  [0x05] = "SE_FLASH_SCREEN_LONG",   -- ALTERNATE_HUES
  [0x08] = "SE_FLASH_SCREEN_LONG",   -- CYCLE_BGPALS_INVERTED
  [0x09] = "SE_HIDE_MON_PIC",        -- HIDE_MON
  [0x0A] = "SE_SHOW_MON_PIC",        -- SHOW_MON
  [0x0B] = "SE_SHOW_MON_PIC",        -- ENTER_MON
  [0x0C] = "SE_HIDE_MON_PIC",        -- RETURN_MON
  [0x0F] = "SE_SLIDE_MON_UP",        -- TELEPORT
  [0x13] = "SE_BLINK_MON",           -- DOUBLE_TEAM
  [0x14] = "SE_HIDE_MON_PIC",        -- ACID_ARMOR
  [0x15] = "SE_FLASH_SCREEN_LONG",   -- RAPID_FLASH
  [0x16] = "SE_LIGHT_SCREEN_PALETTE",-- FADE_MON_TO_LIGHT
  [0x17] = "SE_DARKEN_MON_PALETTE",  -- FADE_MON_TO_BLACK
  [0x18] = "SE_LIGHT_SCREEN_PALETTE",-- FADE_MON_TO_LIGHT_REPEATING
  [0x19] = "SE_DARKEN_MON_PALETTE",  -- FADE_MON_TO_BLACK_REPEATING
  [0x1A] = "SE_FLASH_SCREEN_LONG",   -- CYCLE_MON_LIGHT_DARK_REPEATING
  [0x1B] = "SE_BLINK_MON",           -- FLASH_MON_REPEATING
  [0x1C] = "SE_DARKEN_MON_PALETTE",  -- FADE_MONS_TO_BLACK_REPEATING
  [0x1D] = "SE_LIGHT_SCREEN_PALETTE",-- FADE_MON_TO_WHITE_WAIT_FADE_BACK
  [0x1E] = "SE_RESET_SCREEN_PALETTE",-- FADE_MON_FROM_WHITE
  [0x1F] = "SE_SHAKE_SCREEN",        -- SHAKE_SCREEN_X
  [0x20] = "SE_ROCK_SLIDE_SHAKE",    -- SHAKE_SCREEN_Y
  [0x21] = "SE_SQUISH_MON_PIC",      -- WITHDRAW
  [0x22] = "SE_BOUNCE_UP_AND_DOWN",  -- BOUNCE_DOWN
  [0x23] = "SE_SLIDE_MON_DOWN_AND_HIDE", -- DIG
  [0x24] = "SE_MOVE_MON_HORIZONTALLY",   -- TACKLE
  [0x25] = "SE_SHAKE_BACK_AND_FORTH",-- WOBBLE_MON
  [0x26] = "SE_HIDE_MON_PIC",        -- REMOVE_MON
  [0x27] = "SE_WAVY_SCREEN",         -- WAVE_DEFORM_MON
  [0x28] = "SE_WAVY_SCREEN",         -- PSYCHIC
  [0x2B] = "SE_SHAKE_BACK_AND_FORTH",-- FLAIL
  [0x2D] = "SE_SHAKE_SCREEN",        -- ROLLOUT
  [0x2E] = "SE_SHAKE_SCREEN",        -- VITAL_THROW
  [0x32] = "SE_SHAKE_BACK_AND_FORTH",-- VIBRATE_MON
  [0x33] = "SE_SHAKE_BACK_AND_FORTH",-- WOBBLE_PLAYER
  [0x34] = "SE_WAVY_SCREEN",         -- WOBBLE_SCREEN
}

-- `anim_incbgeffect id` bumps that effect's BG_EFFECT_STRUCT_JT_INDEX, and
-- for every routine a script ends this way the state it lands on is the one
-- that puts back what the effect changed and calls EndBattleBGEffect:
-- BGEffect_RapidCyclePals' .two_dmg reloads rBGP with $e4, the deformations'
-- last state is BattleAnim_ResetLCDStatCustom.  The port ran none of it, so
-- Growl's FADE_MON_TO_BLACK_REPEATING left its darkened palette up for the
-- rest of the battle and Tail Whip's WOBBLE_MON never put the mon back.
local BG_EFFECTS_END = {
  [0x03] = "SE_RESET_SCREEN_PALETTE", -- WHITE_HUES
  [0x04] = "SE_RESET_SCREEN_PALETTE", -- BLACK_HUES
  [0x05] = "SE_RESET_SCREEN_PALETTE", -- ALTERNATE_HUES
  [0x08] = "SE_RESET_SCREEN_PALETTE", -- CYCLE_BGPALS_INVERTED
  [0x15] = "SE_RESET_SCREEN_PALETTE", -- RAPID_FLASH
  [0x16] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_LIGHT
  [0x17] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_BLACK
  [0x18] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_LIGHT_REPEATING
  [0x19] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_BLACK_REPEATING
  [0x1A] = "SE_RESET_SCREEN_PALETTE", -- CYCLE_MON_LIGHT_DARK_REPEATING
  [0x1C] = "SE_RESET_SCREEN_PALETTE", -- FADE_MONS_TO_BLACK_REPEATING
  [0x1D] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_WHITE_WAIT_FADE_BACK
  [0x1E] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_FROM_WHITE
  [0x1B] = "SE_RESET_MON_POSITION",   -- FLASH_MON_REPEATING
  [0x21] = "SE_RESET_MON_POSITION",   -- WITHDRAW
  [0x22] = "SE_RESET_MON_POSITION",   -- BOUNCE_DOWN
  [0x24] = "SE_RESET_MON_POSITION",   -- TACKLE
  [0x25] = "SE_RESET_MON_POSITION",   -- WOBBLE_MON
  [0x27] = "SE_RESET_MON_POSITION",   -- WAVE_DEFORM_MON
  [0x2B] = "SE_RESET_MON_POSITION",   -- FLAIL
  [0x32] = "SE_RESET_MON_POSITION",   -- VIBRATE_MON
  [0x33] = "SE_RESET_MON_POSITION",   -- WOBBLE_PLAYER
}
Gen2AnimPlayer.BG_EFFECTS_END = BG_EFFECTS_END

-- BGEffect_CheckBattleTurn: BG_EFFECT_STRUCT_BATTLE_TURN is 1 for the move's
-- user and 0 for its target.  Anything else (the flash routines reuse the
-- field as a repeat count) only ever drives screen-wide effects, which
-- ignore the side.
local function bgSide(turn)
  return turn == 1 and "user" or "target"
end

-- The effects that are deliberately dropped rather than unhandled, so the
-- coverage test can tell the two apart.
Gen2AnimPlayer.BG_EFFECTS_DROPPED = {
  -- object palette cycling; the port draws each object with its own
  -- BattleObjectPals entry and has no OBP timer to cycle
  [0x06] = true, [0x07] = true,
  -- per-scanline BG raster (Surf/Whirlpool/the water backdrop)
  [0x0D] = true, [0x0E] = true, [0x2F] = true, [0x30] = true, [0x31] = true,
  -- BG tilemap dissolve
  [0x10] = true,
  -- BATTLEROBJ_1ROW/2ROW copy rows of the battler's own picture into the
  -- object tiles.  With no VRAM to copy into, the objects that depend on it
  -- would draw the raw PLAYERHEAD/ENEMYFEET sheets instead -- the stray foot
  -- that turned up in half the physical moves -- so spawn drops them.
  [0x11] = true, [0x12] = true,
  -- unused beta routines
  [0x29] = true, [0x2A] = true, [0x2C] = true,
}

-- BATTLE_ANIM_GFX_PLAYERHEAD / _ENEMYFEET: these two sheets are placeholders
-- that BATTLE_BG_EFFECT_BATTLEROBJ_*ROW overwrites with a slice of the
-- battler's pic before the object appears.  See BG_EFFECTS_DROPPED.
local BATTLER_PIC_GFX = { [0x28] = true, [0x29] = true }

-- BattleState drains this every frame and routes each row through
-- applyAnimEffect, the same path Gen 1's player uses.
function Gen2AnimPlayer:pollEffects()
  local out = self.effects or {}
  self.effects = {}
  return out
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
  if BATTLER_PIC_GFX[def.gfx] then return end
  if self.enemySide and (def.oamFlags or 0) % 2 == 1 then
    ox = 180 - x
    if (def.fixY or 0) == 0xFF then oy = 40 + y else oy = (def.fixY or 0) - y end
    xOffset = -xOffset
  end
  local set = self.anims.framesets and self.anims.framesets[def.frameset]
  local first = set and set.frames[1]
  if not first then return end
  -- BATTLEANIMSTRUCT_INDEX is wLastAnimObjectIndex, bumped once per queued
  -- object, and it is what anim_incobj/anim_setobj address.
  local index = (self.objIndex or 0) + 1
  self.objIndex = index
  self.objects[#self.objects + 1] = {
    def = def, x = ox, y = oy, xOffset = xOffset, yOffset = 0,
    fn = self.anims.functions and self.anims.functions[def.fn or 0],
    param = param, frame = 1, left = first.duration + 1, cycles = 0, age = 0,
    index = index, frameset = def.frameset,
    -- BATTLEANIMSTRUCT_JUMPTABLE_INDEX / VAR1 / VAR2
    state = 0, var1 = 0, var2 = 0,
    persistent = self.scriptObjs and self.scriptObjs[index] or nil,
  }
end

local function frameset(self, obj)
  local sets = self.anims.framesets
  return sets and sets[obj.frameset or obj.def.frameset]
end

local function objectByIndex(self, index)
  for _, obj in ipairs(self.objects) do
    if obj.index == index then return obj end
  end
  return nil
end

-- ReinitBattleAnimFrameset: point an object at a frameset and restart it
local function reframe(self, obj, framesetId)
  local set = self.anims.framesets and self.anims.framesets[framesetId]
  local first = set and set.frames[1]
  if not first then return end
  obj.frameset = framesetId
  obj.frame, obj.cycles, obj.age = 1, 0, 0
  obj.left = first.duration + 1
end

-- BattleAnim_Sine: a = d * sin(a * pi/32), with `a` a wrapping byte angle
local function animSine(a, d)
  return math.floor(d * math.sin((a % 64) * math.pi / 32))
end

-- BATTLE_ANIM_FRAMESET_POKE_BALL_1..5
local BALL_FRAMESET_1 = 9
local BALL_FRAMESET_2 = 10
local BALL_FRAMESET_3 = 11
local BALL_FRAMESET_4 = 12
local BALL_FRAMESET_5 = 13

-- BattleAnimFunc_PokeBall's twelve-state jumptable.  anim_setobj/anim_incobj
-- only write BATTLEANIMSTRUCT_JUMPTABLE_INDEX; it is each state that picks
-- the next frameset, so the port has to run the machine.  Treating
-- anim_incobj as "next frameset" instead re-ran ReinitBattleAnimFrameset on
-- the thrown ball, which reset its travel and made it look like a fresh ball
-- was hurled at the mon once per wobble, and left the resting ball stuck on
-- POKE_BALL_2 -- the squat 16x8 tile that reads as half a ball.
local function pokeBallStep(self, obj)
  local s = obj.state or 0
  if s == 0 then -- init (GetBallAnimPal)
    obj.state = 1
  elseif s == 1 then -- BattleAnimFunc_ThrowFromUserToTarget
    if obj.x >= 0x88 then
      obj.y = obj.y + obj.yOffset
      obj.yOffset = 0
      reframe(self, obj, BALL_FRAMESET_3)
      obj.state = 2
      return
    end
    obj.x = obj.x + 2
    obj.y = obj.y - 1
    obj.yOffset = animSine(obj.var1, obj.param or 0)
    obj.var1 = (obj.var1 - 1) % 256
  elseif s == 3 then
    obj.state = 4
    reframe(self, obj, BALL_FRAMESET_1)
    obj.var1, obj.var2 = 0, 0x10
  elseif s == 4 then
    obj.yOffset = animSine(obj.var1, obj.var2)
    obj.var1 = (obj.var1 - 1) % 256
    if obj.var1 % 32 == 0 then
      obj.var1 = 0
      obj.var2 = obj.var2 - 4
      if obj.var2 <= 0 then
        reframe(self, obj, BALL_FRAMESET_4)
        obj.state = 5
      end
    end
  elseif s == 6 then
    reframe(self, obj, BALL_FRAMESET_5)
    obj.state = 5 -- .six falls through to .five after decrementing the index
  elseif s == 7 then
    reframe(self, obj, BALL_FRAMESET_2)
    obj.state = 8
    obj.var2 = 0x20
  elseif s == 8 or s == 10 then
    obj.yOffset = animSine(obj.var1, obj.var2)
    obj.var1 = (obj.var1 - 1) % 256
    if obj.var1 % 32 == 0 then
      obj.state = 11
    elseif obj.var1 % 16 == 0 then
      obj.state = s + 1
    end
  elseif s == 11 then
    obj.dead = true
  end
  -- .two/.five/.nine simply hold the object where it is
end

function Gen2AnimPlayer:moveObject(obj)
  if obj.fn == "PokeBall" then return pokeBallStep(self, obj) end
  local kind = MOTION[obj.fn or "Null"]
  if not kind or kind == "static" then return end
  local t = math.min(1, obj.age / TRAVEL_FRAMES)
  local age = obj.age

  if kind == "circle" then
    local angle = age / 6
    obj.xOffset = math.floor(math.cos(angle) * 16 + 0.5)
    obj.yOffset = math.floor(math.sin(angle) * 10 + 0.5)
    return
  elseif kind == "spiral" then
    local angle = age / 6
    obj.xOffset = math.floor(math.cos(angle) * (4 + age / 3) + 0.5)
    obj.yOffset = math.floor(math.sin(angle) * 6 + 0.5) + age
    return
  elseif kind == "shake" then
    obj.xOffset = (math.floor(age / 2) % 2 == 0) and 1 or -1
    obj.yOffset = 0
    return
  elseif kind == "rise" then
    obj.xOffset = 0
    obj.yOffset = -age
    return
  elseif kind == "fall" then
    obj.xOffset = 0
    obj.yOffset = age
    return
  end

  -- everything left travels between the two battlers
  local anchor
  if kind == "toUser" then
    anchor = self.enemySide and USER_ANCHOR_MIRRORED or USER_ANCHOR
  else
    anchor = self.enemySide and TARGET_ANCHOR_MIRRORED or TARGET_ANCHOR
  end
  obj.xOffset = math.floor((anchor.x - obj.x) * t + 0.5)
  obj.yOffset = math.floor((anchor.y - obj.y) * t + 0.5)
  if kind == "arc" or kind == "arcGone" then
    obj.yOffset = obj.yOffset - math.floor(math.sin(t * math.pi) * 16 + 0.5)
  elseif kind == "wave" then
    obj.yOffset = obj.yOffset + math.floor(math.sin(t * math.pi * 4) * 6 + 0.5)
  end
  if t >= 1 and (kind == "toTargetGone" or kind == "arcGone") then
    obj.dead = true
  end
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
           and (obj.persistent or obj.cycles < 8) then
          obj.frame, obj.cycles = 1, obj.cycles + 1
        elseif not set.frames[obj.frame] and obj.persistent then
          -- ...unless the script is still driving this object by index, in
          -- which case it really does hold its last frame until told
          -- otherwise (the thrown ball waiting out a wobble)
          obj.frame = #set.frames
        end
        local frame = set.frames[obj.frame]
        if frame then obj.left = frame.duration + 1 end
      end
      -- a $FE frameset restarts forever on hardware until the object's own
      -- function retires it, so the port bounds the lifetime instead
      if set.frames[obj.frame] and not obj.dead
         and (obj.persistent or obj.age < MAX_OBJECT_AGE) then
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
  elseif op == "incobj" then
    -- BattleAnimCmd_IncObj bumps the addressed object's
    -- BATTLEANIMSTRUCT_JUMPTABLE_INDEX, i.e. it advances that object's asm
    -- state machine one step; for every object a script drives this way the
    -- state's job is to reinit the frameset to the next one in the run
    -- (BattleAnimFunction_PokeBall's wobble, Bind, the Amnesia letters).
    -- The port has no asm to run, so it advances the frameset directly --
    -- without it the thrown ball never rocked.
    local obj = objectByIndex(self, inst.args[1])
    if obj and obj.fn == "PokeBall" then
      obj.state = (obj.state or 0) + 1
    elseif obj then
      reframe(self, obj, (obj.frameset or obj.def.frameset) + 1)
    end
  elseif op == "setobj" then
    -- the same field, written outright.  Only the Poké Ball's jumptable is
    -- modelled, so everything else still just restarts its own frameset.
    local obj = objectByIndex(self, inst.args[1])
    if obj and obj.fn == "PokeBall" then
      obj.state = inst.args[2] or 0
    elseif obj then
      reframe(self, obj, obj.def.frameset)
    end
  elseif op == "bgeffect" then
    local id = inst.args[1]
    local side = bgSide(inst.args[3])
    -- anim_incbgeffect addresses a running effect by id alone, so keep the
    -- side the queue entry was made with
    self.bgSides = self.bgSides or {}
    self.bgSides[id] = side
    local se = BG_EFFECTS[id]
    if se then
      self.effects[#self.effects + 1] = { effect = se, side = side, gen2 = true }
    end
  elseif op == "incbgeffect" then
    local id = inst.args[1]
    local se = BG_EFFECTS_END[id]
    if se then
      local side = self.bgSides and self.bgSides[id] or "target"
      self.effects[#self.effects + 1] = { effect = se, side = side, gen2 = true }
    end
  elseif op == "checkpokeball" then
    -- BattleAnimCmd_CheckPokeball calls GetPokeBallWobble and stores its `c`
    -- into wBattleAnimVar, which the toss script then compares against 1 and
    -- 2: 0 = wobble once more, 1 = the click (caught), 2 = it broke free.
    -- It is read once per wobble, so count them off against the roll
    -- BattleState already made and finish on the branch it decided.
    self.wobbles = (self.wobbles or 0) + 1
    local opts = self.opts or {}
    if self.wobbles <= (opts.shakes or 0) then
      self.vars.var = 0
    else
      self.vars.var = opts.caught and 1 or 2
    end
  elseif op == "keepsprites" then
    -- the capture branch ends on anim_keepsprites: the GB never clears the
    -- resting closed ball's OAM, so it stays up through the caught text.
    -- Snapshot it here rather than at the end of the script -- the object
    -- would otherwise retire itself during the drain.
    self.keepSprites = true
    local kept = {}
    for i, obj in ipairs(self.objects) do kept[i] = obj end
    self.keptSprites = #kept > 0 and kept or nil
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
    -- BattleAnimCmd_JumpUntil is a countdown, not a wait: it jumps while
    -- wBattleAnimParam is nonzero and DECREMENTS it on the way, so a script
    -- like Fury Cutter's repeats its slash `param` extra times and then
    -- falls through.  Spinning on the object list instead never terminated
    -- (each pass respawns objects), so those moves only ever ended on the
    -- runaway bound below -- the "glitchy and far too long" animations.
    if self.vars.param ~= 0 and inst.to then
      self.vars.param = self.vars.param - 1
      self.pc = inst.to
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
  -- anim_cry plays the ATTACKER's cry -- GROWL and ROAR are the two moves
  -- that use it (Gen 1 spelled the same rule IsCryMove).
  --
  -- This player does not own the battlers, so it cannot name the species
  -- itself; queue the request on the very same effect channel every other op
  -- reports through and let BattleState, which does know who is attacking,
  -- resolve it.  Leaving this an empty stub is why Growl fell silent in Gen 2:
  -- the "no subanimation player" fallback in BattleState only runs when there
  -- is no player at all, and for a Gen 2 move there always is one.
  self.effects[#self.effects + 1] = { cry = true }
end

function Gen2AnimPlayer:update()
  if self.done then
    if self.tail > 0 then self.tail = self.tail - 1 end
    if self.tail <= 0 and not self.keepSprites then self.objects = {} end
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
  -- can still spin; bound it well past the longest real animation
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
  self:drawSprites(self.objects)
end

-- BattleState keeps the resting closed ball on screen after a capture; Gen 2
-- marks it with anim_keepsprites at the end of the .Click branch, so hand
-- back whatever OAM the script deliberately left behind.
function Gen2AnimPlayer:finalSprites()
  return self.keptSprites
end

function Gen2AnimPlayer:drawSprites(objects)
  local g = love and love.graphics
  if not g or not objects then return end
  local shader = require("src.render.PaletteFX").shader()
  for _, obj in ipairs(objects) do
    local set = frameset(self, obj)
    local frame = set and set.frames[obj.frame]
    -- an oamwait row holds the object in place with nothing drawn
    local row = frame and frame.oam and self.anims.oam
                and self.anims.oam[frame.oam]
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

return Gen2AnimPlayer
