-- Gen1Recomp-derived runtime: GPLv3 plus Additional Terms.
-- See compat/gen1-gsc/LICENSE.MD and pinned provenance.json.
-- The Gen 2 battle-animation OBJECT runtime.
--
-- pokegold engine/battle_anims/core.asm (the struct pool and the OAM writer),
-- engine/battle_anims/helpers.asm (GetBattleAnimFrame) and
-- engine/battle_anims/functions.asm (the 80 per-frame functions).  The DATA
-- these run on -- objects, framesets, OAM sets, GFX sheets -- is extracted
-- into `data/generated/battle_anims.lua`; nothing here is transcribed by hand.
--
-- Ten structs, and one of them is picked by QueueBattleAnimation the same way
-- _InitSpriteAnimStruct picks a sprite-anim slot: the first with INDEX == 0.
-- Every field is a byte and wraps, and several functions rely on that: an
-- object walks its Y offset down past 0 into $ff.. and reads the result back
-- as a negative pixel offset.
--
-- Coordinates are hardware OAM coordinates: an OBJ at struct (x, y) draws at
-- (x - 8, y - 16) on the 160x144 screen.  `xOffset`/`yOffset` are signed bytes
-- added on top, which is what every sine-driven function writes.
--
-- Two traps this file exists to get right:
--
--  * ASM fallthrough is not the same as a jumptable branch.  A dozen of these
--    functions end their `.zero` case by dropping straight into `.one` on the
--    SAME frame, so an object that only ran its init would be a frame late for
--    the rest of its life.  Every one of those is written out here.
--  * `ld a, [hl]` followed by `inc [hl]` leaves `a` holding the value from
--    BEFORE the increment.  Dizzy's frameset flip and Perish Song's descent
--    both read the pre-increment value, and using the new one desynchronises
--    the animation from its own frameset.
--
-- Love-free on purpose: src/ui/gen2/BattleAnimView.lua turns the OAM list into
-- draw calls, and the tests step whole animations with no window at all.

local bit = require("bit")
-- The sine table is engine/math/sine.asm's `sine_table 32`, shared with the
-- overworld/intro sprite anims: BattleAnim_Sine is `calc_sine_wave
-- BattleAnimSineWave`, the same macro over the same 32-entry quarter wave.
local SpriteAnims = require("src.battle.Gen2AnimMath")

local AnimObjects = {}

local NUM_STRUCTS = 10 -- NUM_BATTLE_ANIM_STRUCTS
-- wShadowOAM is 40 objects; BattleAnimOAMUpdate returns carry once it is full
-- and BattleAnim_UpdateOAM_All stops walking the structs.
local OAM_LIMIT = 40
local EMPTY = {}

local OAM_PRIO, OAM_YFLIP, OAM_XFLIP = 0x80, 0x40, 0x20
local OAM_FLAG_MASK = 0xe0
local OAM_PAL1 = 0x10
-- BATTLEANIMSTRUCT_OAMFLAGS_FIX_COORDS_F: bit 0 of the object's flags byte
-- means "mirror this object onto the other battler's side when the enemy is
-- the one attacking".
local FIX_COORDS = 0x01

--------------------------------------------------------------------------
-- Byte arithmetic
--------------------------------------------------------------------------

local function u8(value) return value % 256 end

-- The byte read as a signed value, which is what every `bit 7, a` test and
-- every coordinate add is really doing.
local function s8(value)
  value = value % 256
  return value < 0x80 and value or value - 256
end

-- `sra a`: arithmetic shift right, sign preserved.
local function sra(value) return u8(math.floor(s8(value) / 2)) end

-- `swap a`
local function swap(value)
  value = u8(value)
  return bit.bor(bit.rshift(value, 4), bit.band(bit.lshift(value, 4), 0xf0))
end

-- `rlca`
local function rlca(value)
  value = u8(value)
  return u8(bit.lshift(value, 1) + bit.rshift(value, 7))
end

local sine = SpriteAnims.sine
local cosine = SpriteAnims.cosine

--------------------------------------------------------------------------
-- The struct pool
--------------------------------------------------------------------------

local Pool = {}
Pool.__index = Pool

local function newStruct()
  return {
    index = 0, oamFlags = 0, fixY = 0, framesetId = 0, func = 0, palette = 0,
    tileId = 0, x = 0, y = 0, xOffset = 0, yOffset = 0, param = 0,
    duration = 0, frame = 0xff, jt = 0, var1 = 0, var2 = 0,
  }
end

-- `data` is the cache's battle_anims.lua table; `constants` the cache's
-- constants.lua (for the ordered name lists an id indexes into).
--
-- `env` is what the battle screen owns and this pool only reads:
--   env.battleTurn   hBattleTurn: 0 while the player is attacking
--   env.animId       wFXAnimID, the move whose script is running (KINESIS,
--                    SOFTBOILED and MILK_DRINK get their own Y nudge)
--   env.ballPalette  the PAL_BATTLE_OB_* name GetBallAnimPal resolves for
--                    wCurItem, or nil outside a ball throw
--   env.sgb          hSGB, which only Sky Attack's palette cycle reads
function AnimObjects.new(data, constants, env)
  local self = setmetatable({}, Pool)
  self.data = data or {}
  self.env = env or {}
  self.structs = {}
  for slot = 1, NUM_STRUCTS do self.structs[slot] = newStruct() end
  self.lastIndex = 0 -- wLastAnimObjectIndex
  self.oam = {}

  constants = constants or {}
  self.objectOrder = constants.battleAnimObjectOrder or {}
  self.framesetOrder = constants.battleAnimFramesetOrder or {}
  -- Name -> numeric id, because several functions do frameset ARITHMETIC
  -- (`ld a, BATTLE_ANIM_FRAMESET_SOUND_1; add [hl]`) while the extractor
  -- writes names.  Keeping the struct's FRAMESET_ID numeric is what makes
  -- those adds mean the same thing they do on the cart.
  self.framesetIds = {}
  for index, name in ipairs(self.framesetOrder) do
    self.framesetIds[name] = index - 1
  end
  -- engine/battle_anims/functions.asm:1158
  self.hram = nil
  self.obp0 = nil
  return self
end

function Pool:clear()
  for slot = 1, NUM_STRUCTS do self.structs[slot] = newStruct() end
  self.lastIndex = 0
  self.oam = {}
  self.obp0 = nil
end

-- BattleAnimCmd_ClearObjs.  The cart's loop clears $a0 bytes from
-- wActiveAnimObjects and BATTLEANIMSTRUCT_LENGTH is $18, so it reaches six
-- whole structs plus the first sixteen bytes of the seventh -- enough to zero
-- that one's INDEX, and no further.  Structs 8-10 keep running: that is the
-- documented bug (docs/bugs_and_glitches.md), and an animation that spawns
-- more than seven objects visibly depends on it.
function Pool:clearObjs()
  for slot = 1, 7 do self.structs[slot] = newStruct() end
end

function Pool:framesetId(name)
  local id = self.framesetIds[name]
  if not id then error("unknown battle anim frameset: " .. tostring(name)) end
  return id
end

-- ReinitBattleAnimFrameset: swap framesets and restart the frame walk.
local function reinit(st, framesetId)
  st.framesetId = u8(framesetId)
  st.duration = 0
  st.frame = 0xff -- `ld [hl], -1`
end

local function deinit(st) st.index = 0 end

-- InitBattleAnimation.  The object row's six bytes land in the struct in
-- order; the seventh field, TILEID, comes from the tile dict instead
-- (GetBattleAnimTileOffset), because where a sheet ended up in VRAM is a
-- property of the running script and not of the object.
function Pool:queue(objectId, x, y, param, tileOffsetFor)
  local name = objectId
  if type(objectId) == "number" then
    name = self.objectOrder[objectId + 1] or objectId
  end
  local object = (self.data.objects or {})[name]
  if not object then return nil end
  for slot = 1, NUM_STRUCTS do
    local st = self.structs[slot]
    if st.index == 0 then
      self.lastIndex = u8(self.lastIndex + 1)
      st.index = self.lastIndex
      st.oamFlags = object.flags or 0
      st.fixY = object.fixY or 0
      st.framesetId = self.framesetIds[object.frameset] or 0
      st.func = object.func or 0
      st.palette = object.palette or 0
      st.tileId = tileOffsetFor and tileOffsetFor(object.gfx) or 0
      st.x, st.y = u8(x), u8(y)
      st.xOffset, st.yOffset = 0, 0
      st.param = u8(param or 0)
      st.duration = 0
      st.frame = 0xff
      st.jt, st.var1, st.var2 = 0, 0, 0
      st.objectId = name
      return st
    end
  end
  -- QueueBattleAnimation returns carry when all ten are busy; the script does
  -- not look, and neither does anything here.
  return nil
end

function Pool:findByIndex(value)
  for slot = 1, NUM_STRUCTS do
    local st = self.structs[slot]
    if st.index == value then return st end
  end
  return nil
end

function Pool:activeCount()
  local count = 0
  for slot = 1, NUM_STRUCTS do
    if self.structs[slot].index ~= 0 then count = count + 1 end
  end
  return count
end

--------------------------------------------------------------------------
-- GetBattleAnimFrame (engine/battle_anims/helpers.asm)
--------------------------------------------------------------------------

-- What a frameset row yields: the OAM set name, or the "wait" / "delete"
-- pseudo-commands BattleAnimOAMUpdate acts on, plus the frame's flip flags.
local function frameYield(row)
  local kind = row[1]
  if kind == "wait" then return "wait", 0 end
  if kind == "delete" then return "delete", 0 end
  return row[2], row[4] or 0
end

-- `oamwait n` is not skipped here: GetBattleAnimFrame stores n as the struct's
-- duration and hands the command itself back, so the struct genuinely spends
-- n frames drawing nothing.  Only BattleAnimOAMUpdate knows what to do with it.
function Pool:getFrame(st)
  local frames = (self.data.framesets or {})[self.framesetOrder[st.framesetId + 1]]
  if not frames then return nil, 0 end
  for _ = 1, 64 do
    if st.duration ~= 0 then
      st.duration = st.duration - 1
      local row = frames[st.frame + 1]
      if not row then return nil, 0 end
      return frameYield(row)
    end
    st.frame = u8(st.frame + 1)
    local row = frames[st.frame + 1]
    if not row then return nil, 0 end
    local kind = row[1]
    if kind == "restart" then
      st.duration = 0
      st.frame = 0xff
    elseif kind == "end" then
      -- Step back two so the next pass lands on the frame before this one and
      -- then holds it forever.
      st.duration = 0
      st.frame = u8(st.frame - 2)
    elseif kind == "delete" then
      -- `oamdelete` carries no argument; the cart reads the next byte as a
      -- duration anyway and then throws the whole struct away, so it does not
      -- matter what lands here.
      st.duration = 0
      return "delete", 0
    elseif kind == "wait" then
      st.duration = u8(row[2])
      return "wait", 0
    else
      st.duration = u8(row[3])
      return frameYield(row)
    end
  end
  error("battle anim frameset never yields a frame: "
    .. tostring(self.framesetOrder[st.framesetId + 1]))
end

--------------------------------------------------------------------------
-- BattleAnimOAMUpdate (engine/battle_anims/core.asm)
--------------------------------------------------------------------------

-- AddOrSubtractY / AddOrSubtractX: a flipped entry mirrors around its own
-- 8-pixel cell, which is `-(offset + 8)`.
local function mirror(value, flip)
  if not flip then return value end
  return u8(-(u8(value) + 8))
end

-- InitBattleAnimBuffer.  On the enemy's turn the whole object is reflected
-- onto the other side of the field -- but only if its OAMFLAGS ask for it.
function Pool:initBuffer(st)
  local buf = {
    oamFlags = bit.band(st.oamFlags, OAM_PRIO),
    palette = st.palette,
    tileId = st.tileId,
    x = st.x, y = st.y,
    xOffset = st.xOffset, yOffset = st.yOffset,
  }
  if (self.env.battleTurn or 0) == 0 then return buf end
  buf.oamFlags = st.oamFlags
  if bit.band(st.oamFlags, FIX_COORDS) == 0 then return buf end
  -- x' = (-10 tiles + 4) - x: reflected about the middle of the field.
  buf.x = u8((-10 * 8 + 4) - st.x)
  if st.fixY == 0xff then
    buf.y = u8(5 * 8 + st.y)
  else
    local y = u8(st.fixY - st.y)
    local animId = self.env.animId
    -- The three self-targeting animations whose object sits one tile higher
    -- on the enemy's side.
    if animId == "KINESIS" or animId == "SOFTBOILED" or animId == "MILK_DRINK" then
      y = u8(y - 8)
    end
    buf.y = y
  end
  buf.xOffset = u8(-st.xOffset)
  return buf
end

-- One struct's OAM entries appended to self.oam.  Returns true once the
-- 40-object shadow OAM is full, which is the carry the caller stops on.
function Pool:updateOam(st)
  local buf = self:initBuffer(st)
  local oamsetName, frameFlags = self:getFrame(st)
  if oamsetName == "wait" or oamsetName == nil then return false end
  if oamsetName == "delete" then
    deinit(st)
    return false
  end
  buf.oamFlags = bit.band(bit.bxor(frameFlags, buf.oamFlags), OAM_FLAG_MASK)
  local set = (self.data.oamsets or {})[oamsetName]
  if not set then return false end
  local tileId = u8(buf.tileId + (set.vtile or 0))
  local yFlip = bit.band(buf.oamFlags, OAM_YFLIP) ~= 0
  local xFlip = bit.band(buf.oamFlags, OAM_XFLIP) ~= 0
  local oam = self.oam
  local pool = self.oamPool
  for _, entry in ipairs(set.sprites or EMPTY) do
    local n = #oam
    if n >= OAM_LIMIT then return true end
    -- GetSpriteOAMAttr: the frame's flip/priority flags toggle the entry's;
    -- OAM_PAL1 passes through from the entry, and the palette slot comes from
    -- the struct.
    local attr = bit.band(bit.bxor(entry.attr or 0, buf.oamFlags), OAM_FLAG_MASK)
    attr = attr + bit.band(entry.attr or 0, OAM_PAL1)
    -- Shadow OAM slots are recycled frame to frame (playFrame), the way the
    -- cart rewrites wShadowOAM in place: the 40 tables are made once.
    local out = pool and pool[n + 1]
    if not out then
      out = {}
      if pool then pool[n + 1] = out end
    end
    out.y = u8(buf.y + buf.yOffset + mirror(entry.y or 0, yFlip))
    out.x = u8(buf.x + buf.xOffset + mirror(entry.x or 0, xFlip))
    -- BATTLEANIM_BASE_TILE is added here on the cart and subtracted again by
    -- every sheet lookup, so the port keeps tiles in sheet-relative space.
    out.tile = u8(tileId + (entry.tile or 0))
    out.attr = attr
    out.palette = buf.palette
    oam[n + 1] = out
  end
  return false
end

-- BattleAnim_UpdateOAM_All: run every live struct's function, then let it
-- write its OAM entries.  A struct that deinitialises itself inside its
-- function still draws this frame, because the ASM calls BattleAnimOAMUpdate
-- unconditionally.
--
-- The OAM list and its entries are reused from frame to frame: what a frame
-- returns is valid until the next playFrame, which is all the draw needs.
function Pool:playFrame()
  local oam = self.oamList
  if not oam then
    oam = {}
    self.oamList = oam
    self.oamPool = {}
  end
  for i = #oam, 1, -1 do oam[i] = nil end
  self.oam = oam
  for slot = 1, NUM_STRUCTS do
    local st = self.structs[slot]
    if st.index ~= 0 then
      local fn = AnimObjects.FUNCTIONS[st.func]
      if fn then fn(self, st) end
      if self:updateOam(st) then break end
    end
  end
  return self.oam
end

--------------------------------------------------------------------------
-- engine/battle_anims/functions.asm
--------------------------------------------------------------------------

local function incJt(st) st.jt = u8(st.jt + 1) end

-- BattleAnim_StepToTarget: inches the object toward the opponent's side, half
-- as far vertically as horizontally.  The `dec [hl]` loop runs BEFORE `dec e`
-- is tested, so a vertical step of 0 walks the Y coordinate 256 times -- right
-- back where it started, which is the point.
local function stepToTarget(st, speed)
  local e = bit.band(speed, 0xf)
  st.x = u8(st.x + e)
  local steps = bit.rshift(e, 1)
  st.y = u8(st.y - (steps == 0 and 256 or steps))
end

-- BattleAnim_StepCircle: circular movement whose height is a quarter of its
-- width.
local function stepCircle(st, angle, radius)
  st.yOffset = sra(sra(sine(angle, radius)))
  st.xOffset = cosine(angle, radius)
end

-- A 16-bit accumulator spread over two byte fields, which is how every
-- sub-pixel movement here is done: the HIGH byte is the pixel coordinate and
-- the LOW byte the fraction.
local function add16(high, low, delta)
  local value = (u8(high) * 256 + u8(low) + delta) % 0x10000
  return math.floor(value / 256), value % 256
end

local F = {}

F.BATTLE_ANIM_FUNC_NULL = function(_, st)
  -- anim_incobj is what walks this one to `.one`, which deletes the object.
  if st.jt ~= 0 then deinit(st) end
end

-- BattleAnimFunction_ThrowFromUserToTarget: right 2 and up 1 a frame, with the
-- object's PARAM as the amplitude of a sine on the Y offset.  Returns true for
-- "still going", which is the carry the AndDisappear wrapper reads.
local function throwToTarget(st)
  if st.x >= 0x88 then return false end
  st.x = u8(st.x + 2)
  st.y = u8(st.y - 1)
  local angle = st.var1
  st.var1 = u8(st.var1 - 1)
  st.yOffset = sine(angle, st.param)
  return true
end

F.BATTLE_ANIM_FUNC_THROW_TO_TARGET = function(_, st) throwToTarget(st) end

F.BATTLE_ANIM_FUNC_THROW_TO_TARGET_DISAPPEAR = function(_, st)
  if not throwToTarget(st) then deinit(st) end
end

F.BATTLE_ANIM_FUNC_WAVE_TO_TARGET = function(_, st)
  if st.x >= 0x88 then
    deinit(st)
    return
  end
  st.x = u8(st.x + 2)
  st.y = u8(st.y - 1)
  local angle = st.var1
  st.var1 = u8(st.var1 + 4)
  st.yOffset = sine(angle, 0x10)
  -- The X offset is the cosine divided by sixteen, so the wave is much
  -- flatter across than it is up.
  st.xOffset = sra(sra(sra(sra(cosine(angle, 0x10)))))
end

F.BATTLE_ANIM_FUNC_MOVE_IN_CIRCLE = function(_, st)
  if st.jt == 0 then
    incJt(st)
    -- Bit 7 of PARAM starts the object half a turn round; the rest is the
    -- radius, so the flag has to come off before it is used as one.
    st.var1 = bit.band(st.param, 0x80) ~= 0 and 0x20 or 0
    st.param = bit.band(st.param, 0x7f)
  end
  local angle = st.var1
  st.yOffset = sine(angle, st.param)
  st.xOffset = cosine(angle, st.param)
  st.var1 = u8(st.var1 + 1)
end

F.BATTLE_ANIM_FUNC_USER_TO_TARGET = function(_, st)
  if st.jt ~= 0 then
    deinit(st)
    return
  end
  if st.x >= 0x84 then return end
  stepToTarget(st, st.param)
end

F.BATTLE_ANIM_FUNC_USER_TO_TARGET_DISAPPEAR = function(_, st)
  if st.x >= 0x84 then
    deinit(st)
    return
  end
  stepToTarget(st, st.param)
end

-- GetBallAnimPal: the thrown ball wears the colour of the ball being thrown
-- (data/battle_anims/ball_colors.asm).  The battle screen resolves that for
-- wCurItem and hands it over as env.ballPalette.
local function ballPal(self, st)
  if self.env.ballPalette then st.palette = self.env.ballPalette end
end

-- .four: the ball bounces on a shrinking sine while VAR2 steps down by four;
-- when it reaches zero the ball opens.
local function pokeballBounce(self, st)
  st.yOffset = sine(st.var1, st.var2)
  st.var1 = u8(st.var1 - 1)
  if bit.band(st.var1, 0x1f) ~= 0 then return end
  -- `ld [hl], a` after the mask: VAR1 is zeroed, not just left on a boundary,
  -- so every bounce starts from the same phase.
  st.var1 = 0
  st.var2 = u8(st.var2 - 4)
  if st.var2 ~= 0 then return end
  reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_POKE_BALL_4"))
  incJt(st)
end

-- .eight/.ten: the same sine, but every $10 steps the jumptable advances, so
-- the caught / broke-free branch is only ever reached on a shake boundary.
local function pokeballWobble(_, st)
  st.yOffset = sine(st.var1, st.var2)
  st.var1 = u8(st.var1 - 1)
  if bit.band(st.var1, 0x1f) == 0 then
    deinit(st)
    return
  end
  if bit.band(st.var1, 0xf) ~= 0 then return end
  incJt(st)
end

F.BATTLE_ANIM_FUNC_POKEBALL = function(self, st)
  local jt = st.jt
  if jt == 0 then
    ballPal(self, st)
    incJt(st)
  elseif jt == 1 then
    if throwToTarget(st) then return end
    -- The arc's Y offset is folded into the coordinate before the ball
    -- switches to its opening frameset, so it lands where it fell.
    st.y = u8(st.y + st.yOffset)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_POKE_BALL_3"))
    incJt(st)
  elseif jt == 3 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_POKE_BALL_1"))
    st.var1, st.var2 = 0, 0x10
    pokeballBounce(self, st) -- .three falls into .four
  elseif jt == 4 then
    pokeballBounce(self, st)
  elseif jt == 6 then
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_POKE_BALL_5"))
    st.jt = u8(st.jt - 1)
  elseif jt == 7 then
    ballPal(self, st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_POKE_BALL_2"))
    incJt(st)
    st.var2 = 0x20
    pokeballWobble(self, st) -- .seven falls into .eight
  elseif jt == 8 or jt == 10 then
    pokeballWobble(self, st)
  elseif jt == 11 then
    deinit(st)
  end
end

local function pokeballBlockedFall(_, st)
  if st.y >= 0x80 then
    deinit(st)
    return
  end
  st.y = u8(st.y + 4)
  st.x = u8(st.x - 2)
end

F.BATTLE_ANIM_FUNC_POKEBALL_BLOCKED = function(self, st)
  local jt = st.jt
  if jt == 0 then
    ballPal(self, st)
    incJt(st)
  elseif jt == 1 then
    if st.x < 0x70 then
      throwToTarget(st)
      return
    end
    incJt(st)
    pokeballBlockedFall(self, st) -- .next falls into .two
  elseif jt == 2 then
    pokeballBlockedFall(self, st)
  end
end

F.BATTLE_ANIM_FUNC_EMBER = function(self, st)
  local jt = st.jt
  if jt == 0 then
    -- The upper nybble of PARAM picks which branch this object runs.
    st.jt = bit.band(swap(st.param), 0xf)
  elseif jt == 1 then
    if st.x >= 0x88 then return end
    stepToTarget(st, st.param)
  elseif jt == 2 then
    deinit(st)
  elseif jt == 3 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_FLAMETHROWER"))
  end
end

F.BATTLE_ANIM_FUNC_DROP = function(_, st)
  if st.jt == 0 then
    incJt(st)
    st.var1, st.var2 = 0x30, 0x48
  end
  st.yOffset = sine(st.var1, st.var2)
  st.var1 = u8(st.var1 + 1)
  if bit.band(st.var1, 0x3f) ~= 0 then return end
  st.var1 = 0x20
  -- Each bounce loses PARAM off the amplitude; once that would go to zero or
  -- below, the object is done.
  local left = st.var2 - st.param
  if left <= 0 then
    deinit(st)
    return
  end
  st.var2 = left
end

F.BATTLE_ANIM_FUNC_USER_TO_TARGET_SPIN = function(_, st)
  -- .SetCoords: the lower nybble of PARAM is the horizontal step, half of it
  -- the vertical one.
  local function setCoords()
    local e = bit.band(st.param, 0xf)
    st.x = u8(st.x + e)
    local steps = bit.rshift(e, 1)
    st.y = u8(st.y - (steps == 0 and 256 or steps))
  end
  -- .two: a circle whose top is flattened -- the cosine is pulled down by its
  -- own radius and halved.
  local function orbit()
    if st.var1 < 0x40 then
      st.yOffset = sra(u8(cosine(st.var1, 0x18) - 0x18))
      st.xOffset = sine(st.var1, 0x18)
      st.var1 = u8(st.var1 + bit.band(st.param, 0xf))
      return
    end
    -- .loop_back: the upper nybble is a lap counter.
    local laps = bit.band(st.param, 0xf0)
    if laps == 0 then
      incJt(st) -- .finish falls into .three
      if st.x >= 0xb0 then
        deinit(st)
      else
        setCoords()
      end
      return
    end
    st.param = bit.band(st.param, 0xf) + (laps - 0x10)
    st.jt = u8(st.jt - 1)
  end
  local jt = st.jt
  if jt == 0 then
    if st.x < 0x80 then
      setCoords()
      return
    end
    -- .next -> .one -> .two, all on this frame.
    incJt(st)
    incJt(st)
    st.var1 = 0
    orbit()
  elseif jt == 1 then
    incJt(st)
    st.var1 = 0
    orbit()
  elseif jt == 2 then
    orbit()
  elseif jt == 3 then
    if st.x >= 0xb0 then
      deinit(st)
      return
    end
    setCoords()
  end
end

F.BATTLE_ANIM_FUNC_SHAKE = function(_, st)
  -- .done_one: hold for the upper nybble of PARAM, then jump to the other side.
  local function flip()
    st.var1 = bit.band(swap(st.param), 0xf)
    st.xOffset = u8(-st.xOffset)
  end
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var1 = 0
    st.xOffset = bit.band(st.param, 0xf)
    flip() -- .zero falls into .one, and VAR1 is 0, so .done_one runs at once
  elseif jt == 1 then
    if st.var1 ~= 0 then
      st.var1 = st.var1 - 1
      return
    end
    flip()
  elseif jt == 2 then
    deinit(st)
  end
end

F.BATTLE_ANIM_FUNC_FIRE_BLAST = function(self, st)
  -- .eight: the travelling flame spirals once it arrives.
  local function spin()
    local angle = st.var1
    st.yOffset = sine(angle, 0x10)
    st.xOffset = cosine(angle, 0x10)
    st.var1 = u8(st.var1 + 1)
  end
  -- .seven: straight across, then hand over to the spiral.
  local function travel()
    if st.x < 0x88 then
      st.x = u8(st.x + 2)
      st.y = u8(st.y - 1)
      return
    end
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_EMBER"))
    spin() -- .set_up_eight falls into .eight
  end
  local jt = st.jt
  if jt == 0 then
    -- PARAM picks the branch outright: 7 is the flame that travels, and the
    -- rest are the five arms of the blast, which only drift.
    st.jt = st.param
    if st.param == 7 then
      travel()
    else
      reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_BURNED"))
    end
  elseif jt == 1 then
    st.yOffset = u8(st.yOffset - 1)
  elseif jt == 2 then
    st.xOffset = u8(st.xOffset - 1)
  elseif jt == 3 then
    st.xOffset = u8(st.xOffset + 1)
  elseif jt == 4 then
    st.yOffset = u8(st.yOffset + 1)
    st.xOffset = u8(st.xOffset - 1)
  elseif jt == 5 then
    st.yOffset = u8(st.yOffset + 1)
    st.xOffset = u8(st.xOffset + 1)
  elseif jt == 7 then
    travel()
  elseif jt == 8 then
    spin()
  elseif jt == 9 then
    deinit(st)
  end
end

-- BattleAnim_ScatterHorizontal: a 16-bit per-frame X step picked from the
-- object's PARAM, so a screenful of leaves fans out instead of moving as one.
local function scatterHorizontal(st)
  local param = st.param
  if bit.band(param, 0x80) == 0 then
    if param >= 0x20 then return 0x100 end
    if param >= 0x18 then return 0x180 end
    return 0x200
  end
  local masked = bit.band(param, 0x3f)
  if masked >= 0x20 then return -0x100 end
  if masked >= 0x18 then return -0x180 end
  return -0x200
end

F.BATTLE_ANIM_FUNC_RAZOR_LEAF = function(self, st)
  local function arcStep()
    local radius = bit.band(st.param, 0x3f)
    local angle = st.var1
    st.var1 = u8(st.var1 - 1)
    st.yOffset = sine(angle, radius)
    st.x, st.var2 = add16(st.x, st.var2, scatterHorizontal(st))
  end
  local function arcOrLand()
    if st.var1 >= 0x30 then
      arcStep()
      return
    end
    incJt(st)
    st.var1, st.var2 = 0, 0
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_RAZOR_LEAF_2"))
    -- Bit 6 starts the second frameset six frames in, which is the leaf
    -- already half-turned.
    if bit.band(st.param, 0x40) ~= 0 then st.frame = 5 end
  end
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var1 = 0x40
    arcOrLand() -- .zero falls into .one
  elseif jt == 1 then
    arcOrLand()
  elseif jt == 2 then
    if st.yOffset == 0x20 then
      deinit(st)
      return
    end
    st.xOffset = sine(st.var1, 0x10)
    if bit.band(st.param, 0x40) ~= 0 then
      st.var1 = u8(st.var1 - 1)
    else
      st.var1 = u8(st.var1 + 1)
    end
    st.yOffset, st.var2 = add16(st.yOffset, st.var2, 0x80)
  elseif jt == 3 then
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_RAZOR_LEAF_1"))
    st.oamFlags = bit.band(st.oamFlags, 0xff - OAM_XFLIP)
    incJt(st)
  elseif jt >= 4 and jt <= 7 then
    incJt(st)
  elseif jt == 8 then
    if st.x >= 0xc0 then return end
    stepToTarget(st, 8)
  end
end

F.BATTLE_ANIM_FUNC_ROCK_SMASH = function(self, st)
  if st.jt == 0 then
    -- Bit 6 picks between the two rock framesets.
    st.framesetId = u8(rlca(rlca(bit.band(st.param, 0x40)))
      + self:framesetId("BATTLE_ANIM_FRAMESET_BIG_ROCK"))
    incJt(st)
    st.var1 = 0x40
  end
  if st.var1 < 0x30 then
    deinit(st)
    return
  end
  local radius = bit.band(st.param, 0x3f)
  local angle = st.var1
  st.var1 = u8(st.var1 - 1)
  st.yOffset = sine(angle, radius)
  st.x, st.var2 = add16(st.x, st.var2, scatterHorizontal(st))
end

F.BATTLE_ANIM_FUNC_BUBBLE = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var1 = 0xc
    jt = 1
  end
  if jt == 1 then
    if st.var1 ~= 0 then
      st.var1 = st.var1 - 1
      stepToTarget(st, st.param)
      return
    end
    incJt(st)
    st.var1 = 0
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_PULSING_BUBBLE"))
    return
  end
  if jt ~= 2 then return end
  if st.x < 0x98 then
    st.x, st.var1 = add16(st.x, st.var1, 0x60)
  end
  if st.y < 0x20 then return end
  -- The upper nybble of PARAM is a per-frame rise; `ld d, $ff` is what makes
  -- it a NEGATIVE 16-bit step.
  st.y, st.var2 = add16(st.y, st.var2, bit.band(st.param, 0xf0) - 0x100)
end

-- engine/battle_anims/functions.asm:1148
F.BATTLE_ANIM_FUNC_SURF = function(self, st)
  local hram = self.hram
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    if hram then
      hram.lcdc, hram.lyStart, hram.lyEnd = "SCY", 0x58, 0x5e
    end
    return
  end
  if jt == 1 then
    if st.y < st.param then
      incJt(st)
      if hram then hram.lyStart = 0 end
      return
    end
    st.y = u8(st.y - 1)
    st.yOffset = sine(st.var1, 0x10)
    local top = st.yOffset + st.y - 0x10
    -- `ret c`: the wave stops climbing entirely on the frames the subtraction
    -- underflows, offsets and all.
    if top < 0 then return end
    if hram then hram.lyStart = u8(top) end
    st.xOffset = bit.band(st.xOffset + 1, 7)
    st.var1 = u8(st.var1 + 2)
    return
  end
  if jt == 3 then
    if st.y >= 0x70 then
      if hram then
        hram.lcdc, hram.lyStart, hram.lyEnd = nil, 0, 0
      end
      deinit(st)
      return
    end
    st.y = u8(st.y + 2)
    local top = st.y - 0x10
    if top < 0 then return end
    if hram then hram.lyStart = u8(top) end
    return
  end
  if jt == 4 then deinit(st) end
end

F.BATTLE_ANIM_FUNC_SING = function(self, st)
  if st.jt == 0 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_MUSIC_NOTE_1") + st.param)
  end
  if st.x >= 0xb8 then
    deinit(st)
    return
  end
  stepToTarget(st, 2)
  local angle = st.var1
  st.var1 = u8(st.var1 - 1)
  st.yOffset = sine(angle, 8)
end

F.BATTLE_ANIM_FUNC_WATER_GUN = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    jt = 1
  end
  if jt == 1 then
    if st.y >= 0x30 then
      stepToTarget(st, 2)
      local angle = st.var1
      st.var1 = u8(st.var1 - 1)
      st.yOffset = sine(angle, 8)
      return
    end
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_WATER_GUN_2"))
    st.yOffset = 0
    st.y = 0x30
    -- Everything but FIX_COORDS is dropped, so the splash never flips.
    st.oamFlags = bit.band(st.oamFlags, FIX_COORDS)
    jt = 2
  end
  if jt ~= 2 then return end
  if st.yOffset >= 0x18 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_WATER_GUN_3"))
    return
  end
  st.yOffset = u8(st.yOffset + 1)
end

F.BATTLE_ANIM_FUNC_POWDER = function(_, st)
  if st.yOffset >= 0x38 then
    deinit(st)
    return
  end
  st.yOffset, st.var1 = add16(st.yOffset, st.var1, 0x80)
  -- Shakes sixteen pixels either side by toggling one bit.
  st.xOffset = bit.bxor(st.xOffset, 0x10)
end

F.BATTLE_ANIM_FUNC_RECOVER = function(_, st)
  if st.jt == 0 then
    incJt(st)
    st.var2 = bit.band(st.param, 0xf0) -- radius
    st.var1 = u8(bit.band(st.param, 0xf) * 8) -- starting angle
    st.param = 1 -- reused as an every-other-frame toggle
  end
  if st.var2 == 0 then
    deinit(st)
    return
  end
  local angle = st.var1
  st.var1 = u8(st.var1 + 1)
  st.yOffset = sine(angle, st.var2)
  st.xOffset = cosine(angle, st.var2)
  st.param = bit.bxor(st.param, 1)
  if st.param == 0 then return end
  st.var2 = u8(st.var2 - 1)
end

F.BATTLE_ANIM_FUNC_THUNDER_WAVE = function(self, st)
  if st.jt == 1 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_THUNDER_WAVE_EXTRA"))
  elseif st.jt == 3 then
    deinit(st)
  end
end

-- Clamp/Encore: two halves clap together, twice.  The frameset the object
-- switches to is the base or the base + 1 (CLAMP_FLIPPED / ENCORE_HAND_
-- FLIPPED), picked by the SIGN of the sine, so both halves close together.
F.BATTLE_ANIM_FUNC_CLAMP_ENCORE = function(self, st)
  local function step()
    local value = sine(st.var1, st.param)
    st.xOffset = value
    reinit(st, bit.band(value, 0x80) ~= 0 and st.var2 or u8(st.var2 + 1))
    st.var1 = u8(st.var1 + 1)
    if bit.band(st.var1, 0x1f) ~= 0 then return end
    incJt(st) -- falls into .two, which is a bare IncAnonJumptableIndex
  end
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var2 = st.framesetId
    st.var1 = bit.band(st.param, 0x80) ~= 0 and 0x30 or 0x10
    st.param = bit.band(st.param, 0x7f)
    step()
  elseif jt == 1 then
    step()
  elseif jt >= 2 and jt <= 5 then
    incJt(st)
  elseif jt == 6 then
    st.jt = 1
  end
end

F.BATTLE_ANIM_FUNC_BITE = function(self, st)
  local function step()
    local value = sine(st.var1, st.param)
    st.yOffset = value
    reinit(st, bit.band(value, 0x80) ~= 0
      and self:framesetId("BATTLE_ANIM_FRAMESET_BITE_1")
      or self:framesetId("BATTLE_ANIM_FRAMESET_BITE_2"))
    st.var1 = u8(st.var1 + 2)
    if bit.band(st.var1, 0x1f) ~= 0 then return end
    incJt(st)
  end
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var1 = bit.band(st.param, 0x80) ~= 0 and 0x30 or 0x10
    st.param = bit.band(st.param, 0x7f)
    step()
  elseif jt == 1 then
    step()
  elseif jt >= 2 and jt <= 5 then
    incJt(st)
  elseif jt == 6 then
    st.jt = 1
  end
end

F.BATTLE_ANIM_FUNC_SOLAR_BEAM = function(_, st)
  if st.jt == 0 then
    incJt(st)
    st.var1, st.var2 = 0x28, 0
  end
  local angle = st.param
  st.yOffset = sine(angle, st.var1)
  st.xOffset = cosine(angle, st.var1)
  if st.var1 == 0 then
    deinit(st)
    return
  end
  -- The radius is a 16-bit value shrinking half a pixel a frame.
  st.var1, st.var2 = add16(st.var1, st.var2, -0x80)
end

-- The gust's radius comes from a nine-entry table, so the whirl pulses rather
-- than turning at a constant width.
local GUST_OFFSETS = { [0] = 8, [1] = 6, [2] = 5, [3] = 4, [4] = 5, [5] = 6,
  [6] = 8, [7] = 12, [8] = 16 }

F.BATTLE_ANIM_FUNC_GUST = function(_, st)
  local function wobble()
    local radius = GUST_OFFSETS[st.var2] or 8
    local angle = st.var1
    -- Height is a sixteenth of the width, plus PARAM's own drift.
    st.yOffset = u8(sra(sra(sra(sra(sine(angle, radius))))) + st.param)
    st.xOffset = cosine(angle, radius)
    st.var1 = u8(st.var1 - 8)
    -- PARAM counts DOWN from 0 through $ff; once it drops below $c2 the whirl
    -- settles back to the middle.
    if st.param ~= 0 and st.param < 0xc2 then
      st.var2, st.param, st.xOffset, st.yOffset = 0, 0, 0, 0
      return
    end
    st.param = u8(st.param - 1)
    if bit.band(st.param, 7) ~= 0 then return end
    st.var2 = u8(st.var2 + 1)
  end
  local function move()
    wobble()
    st.x = u8(st.x + 1)
    if bit.band(st.x, 1) ~= 0 then return end
    st.y = u8(st.y - 1)
  end
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.param = 0
    wobble() -- .zero falls into .one
  elseif jt == 1 or jt == 3 then
    wobble()
  elseif jt == 2 then
    if st.x < 0x88 then
      move()
    else
      incJt(st)
    end
  elseif jt == 4 then
    if st.x < 0xb8 then
      move()
    else
      deinit(st)
    end
  end
end

F.BATTLE_ANIM_FUNC_ABSORB = function(_, st)
  if st.x < 0x30 then
    deinit(st)
    return
  end
  local e = bit.band(st.param, 0xf)
  st.x = u8(st.x - e)
  local steps = bit.rshift(e, 1)
  st.y = u8(st.y + (steps == 0 and 256 or steps))
end

F.BATTLE_ANIM_FUNC_WRAP = function(_, st)
  -- anim_incobj walks the frameset one step along the BIND_1..4 run.
  if st.jt ~= 1 then return end
  reinit(st, u8(st.framesetId + 1))
  incJt(st)
  st.var1 = 8
end

-- BattleAnim_StepThrownToTarget: a parabola whose horizontal step is PARAM's
-- two nybbles read as a 16-bit fixed-point number -- the LOW nybble is the
-- fraction and the HIGH nybble the whole pixels, which is the reverse of how
-- the macro's argument reads.
local function stepThrownToTarget(st)
  st.var2 = u8(st.var2 - 1)
  st.yOffset = sine(st.var2, 0x20)
  st.fixY = u8(st.fixY + 2)
  local step = bit.rshift(bit.band(st.param, 0xf0), 4) * 256
    + swap(bit.band(st.param, 0xf))
  st.x, st.var1 = add16(st.x, st.var1, step)
  if bit.band(st.var2, 1) ~= 0 then return end
  st.y = u8(st.y - 1)
end

F.BATTLE_ANIM_FUNC_LEECH_SEED = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var2 = 0x40
  elseif jt == 1 then
    if st.var2 >= 0x20 then
      stepThrownToTarget(st)
      return
    end
    st.var2 = 0x40
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_LEECH_SEED_2"))
    incJt(st)
  elseif jt == 2 then
    if st.var2 ~= 0 then
      st.var2 = st.var2 - 1
      return
    end
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_LEECH_SEED_3"))
  end
end

F.BATTLE_ANIM_FUNC_SPIKES = function(_, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var2 = 0x40
  elseif jt == 1 then
    if st.var2 >= 0x20 then
      stepThrownToTarget(st)
      return
    end
    incJt(st)
  end
end

F.BATTLE_ANIM_FUNC_RAZOR_WIND = function(self, st)
  F.BATTLE_ANIM_FUNC_MOVE_IN_CIRCLE(self, st)
  -- Fifteen extra steps a frame, so the object races round the circle.
  st.var1 = u8(st.var1 + 0xf)
end

local function kickRoll(_, st)
  if st.x >= 0x98 then return end
  st.x = u8(st.x + 2)
  local angle = st.var1
  st.var1 = u8(st.var1 + 1)
  st.yOffset = sine(angle, 8)
end

F.BATTLE_ANIM_FUNC_KICK = function(_, st)
  local jt = st.jt
  if jt == 1 then
    if st.y < 0x30 then
      st.y = u8(st.y + 4)
      return
    end
    st.jt = 0
  elseif jt == 2 then
    if st.x >= 0x98 then return end
    st.x = u8(st.x + 2)
    -- The kick pins itself to the target's side and holds one frame.
    st.oamFlags = bit.bor(st.oamFlags, FIX_COORDS)
    st.fixY = 0x90
    st.frame = 0
    st.duration = 2
    st.y = u8(st.y - 1)
  elseif jt == 3 then
    incJt(st)
    st.var1 = 0x2c
    st.frame = 0
    st.duration = 0x80
    kickRoll(_, st) -- .three falls into .four
  elseif jt == 4 then
    kickRoll(_, st)
  end
end

F.BATTLE_ANIM_FUNC_EGG = function(self, st)
  -- .EggVerticalWaveMotion, shared by both openings.
  local function wave()
    st.yOffset = sine(st.var1, st.var2)
    st.var1 = u8(st.var1 + 1)
    if bit.band(st.var1, 0x3f) ~= 0 then return end
    st.var1 = 0x20
    st.var2 = u8(st.var2 - 8)
    if st.var2 ~= 0 then return end
    st.var1, st.var2 = 0, 0
    incJt(st)
  end
  -- .egg_bomb_step: the egg drifts up half a pixel a frame while it travels.
  local function step()
    st.x = u8(st.x + 1)
    st.y, st.var1 = add16(st.y, st.var1, -0x80)
  end
  local jt = st.jt
  if jt == 0 then
    -- The object starts here and then jumps to whichever branch PARAM names,
    -- which is how one object serves both Egg Bomb and Softboiled.
    st.var1, st.var2 = 0x28, 0x10
    st.jt = st.param
  elseif jt == 1 then
    if st.x < 0x40 then st.x = u8(st.x + 1) end
    wave()
  elseif jt == 2 then
    if st.x >= 0x88 then
      incJt(st)
      incJt(st) -- .egg_bomb_done skips straight to .four
      return
    end
    if bit.band(st.x, 0xf) ~= 0 then
      step()
      return
    end
    st.var2 = 0x10
    incJt(st)
  elseif jt == 3 then
    if st.var2 ~= 0 then
      st.var2 = st.var2 - 1
      return
    end
    st.jt = u8(st.jt - 1)
    step()
  elseif jt == 5 then
    deinit(st)
  elseif jt == 6 then
    if st.x < 0x4b then st.x = u8(st.x + 1) end
    wave()
  elseif jt == 7 then
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_EGG_WOBBLE"))
    incJt(st)
  elseif jt == 8 then
    local angle = st.var1
    st.var1 = u8(st.var1 + 2)
    st.xOffset = sine(angle, 2)
  elseif jt == 9 then
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_EGG_CRACKED_BOTTOM"))
    st.yOffset = 4
    incJt(st)
  elseif jt == 11 then
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_EGG_CRACKED_TOP"))
    incJt(st)
    st.var1 = 0x40
  elseif jt == 12 then
    st.yOffset = sine(st.var1, 0x20)
    if st.var1 < 0x30 then
      incJt(st)
      return
    end
    st.var1 = u8(st.var1 - 1)
  end
end

F.BATTLE_ANIM_FUNC_MOVE_UP = function(_, st)
  -- Runs while the offset is 0 or already past $d8 going negative; anything
  -- in between is "far enough up" and ends the object.
  if st.yOffset ~= 0 and st.yOffset < 0xd8 then
    deinit(st)
    return
  end
  st.yOffset = u8(st.yOffset - st.param)
end

F.BATTLE_ANIM_FUNC_SOUND = function(self, st)
  local function motion()
    local angle = st.var2
    st.var2 = u8(st.var2 + 2)
    local value = sine(angle, 0x10)
    st.xOffset = value
    if st.param == 0 then
      st.yOffset = u8(-value)
    elseif st.param ~= 1 then
      st.yOffset = value
    end
    -- PARAM 1 leaves the Y offset alone: that is the flat sideways wave.
  end
  if st.jt == 0 then
    if (self.env.battleTurn or 0) ~= 0 then
      -- `xor $ff; add $3` is 2 - param: the enemy's three angles are the
      -- player's three mirrored, 0 <-> 2.
      st.param = u8(2 - st.param)
    end
    incJt(st)
    st.var1 = 8
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_SOUND_1") + st.param)
    return
  end
  if st.var1 == 0 then
    deinit(st)
    return
  end
  st.var1 = st.var1 - 1
  motion()
end

F.BATTLE_ANIM_FUNC_CONFUSE_RAY = function(self, st)
  if st.jt == 0 then
    incJt(st)
    st.var2 = bit.band(st.param, 0x3f)
    -- Bit 7 becomes both the frameset offset and, once swapped, the radius.
    st.param = rlca(bit.band(st.param, 0x80))
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_CONFUSE_RAY_1") + st.param)
    return
  end
  local radius = swap(st.param)
  local angle = st.var2
  st.var2 = u8(st.var2 + 1)
  st.yOffset = sine(angle, radius)
  st.xOffset = cosine(angle, radius)
  if st.x >= 0x80 then return end
  -- Both tests read the NEW VAR2, and the second `and $1` is applied to what
  -- the first `and $3` left, not to the register again.
  local phase = bit.band(st.var2, 3)
  if phase == 0 then st.y = u8(st.y - 1) end
  if bit.band(phase, 1) ~= 0 then return end
  st.x = u8(st.x + 1)
end

F.BATTLE_ANIM_FUNC_DIZZY = function(_, st)
  if st.jt == 0 then
    incJt(st)
    st.var1 = st.framesetId
    reinit(st, u8(st.var1 + rlca(bit.band(st.param, 0x80))))
    st.param = bit.band(st.param, 0x7f)
  end
  local angle = st.param
  st.yOffset = sra(sra(sine(angle, 0x10)))
  st.xOffset = cosine(angle, 0x10)
  -- `ld a, [hl]` then `inc [hl]`: the frameset flip tests the PRE-increment
  -- angle, so the two chick frames swap on the same beat as the circle.
  st.param = u8(st.param + 1)
  local phase = bit.band(angle, 0x3f)
  if phase == 0 then
    reinit(st, st.var1)
  elseif bit.band(phase, 0x1f) == 0 then
    reinit(st, u8(st.var1 + 1))
  end
end

-- Hardcoded Y offsets, one per PARAM.
local AMNESIA_OFFSETS = { [0] = 0xec, [1] = 0xf8, [2] = 0x00 }

F.BATTLE_ANIM_FUNC_AMNESIA = function(self, st)
  if st.jt == 0 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_AMNESIA_1") + st.param)
    st.yOffset = AMNESIA_OFFSETS[st.param] or 0
  elseif st.jt == 2 then
    -- anim_incobj forces the object to deinit; Present is what uses it.
    deinit(st)
  end
end

F.BATTLE_ANIM_FUNC_FLOAT_UP = function(_, st)
  local angle = st.var1
  st.var1 = u8(st.var1 + 2)
  st.xOffset = sine(angle, 4)
  -- `lb hl, -1, $a0` is the 16-bit constant $ffa0: up 3/8 of a pixel a frame.
  st.yOffset, st.var2 = add16(st.yOffset, st.var2, -0x60)
end

F.BATTLE_ANIM_FUNC_DIG = function(_, st)
  local angle = st.var1
  st.var1 = u8(st.var1 - 2)
  st.yOffset = sine(angle, 0x10)
  st.x = u8(st.x + 1)
end

F.BATTLE_ANIM_FUNC_STRING = function(self, st)
  if st.jt ~= 0 then return end
  incJt(st)
  -- PARAM 0 is the one that flips on the enemy's turn.
  if st.param == 0 then st.oamFlags = bit.bor(st.oamFlags, OAM_YFLIP) end
  reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_STRING_SHOT_1") + st.param)
end

F.BATTLE_ANIM_FUNC_PARALYZED = function(self, st)
  if st.jt == 0 then
    incJt(st)
    st.var1 = 0
    local param = st.param
    -- Bits 4-6 become the hold time; bit 7 flips the object, and the low
    -- nybble is how far it jitters.
    st.param = bit.band(swap(bit.band(param, 0x70)), 0xf)
    if bit.band(param, 0x80) == 0 then
      st.xOffset = bit.band(param, 0xf)
    else
      st.xOffset = u8(-bit.band(param, 0xf))
      reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_PARALYZED_FLIPPED"))
    end
    return
  end
  if st.var1 ~= 0 then
    st.var1 = st.var1 - 1
    return
  end
  st.var1 = st.param
  st.xOffset = u8(-st.xOffset)
end

-- A shared descent: a circle whose height is an eighth of its width, sinking
-- one pixel every few frames until it is $28 down.  Spiral Descent checks
-- every eight frames, Petal Dance every four.
local function spiralDescent(st, mask)
  local angle = st.var1
  st.yOffset = u8(sra(sra(sra(sine(angle, 0x18)))) + st.var2)
  st.xOffset = cosine(angle, 0x18)
  st.var1 = u8(st.var1 + 1)
  if bit.band(st.var1, mask) ~= 0 then return end
  if st.var2 >= 0x28 then
    deinit(st)
    return
  end
  st.var2 = u8(st.var2 + 1)
end

F.BATTLE_ANIM_FUNC_SPIRAL_DESCENT = function(_, st) spiralDescent(st, 7) end
F.BATTLE_ANIM_FUNC_PETAL_DANCE = function(_, st) spiralDescent(st, 3) end

F.BATTLE_ANIM_FUNC_POISON_GAS = function(_, st)
  if st.jt ~= 0 then
    spiralDescent(st, 7)
    return
  end
  if st.x >= 0x84 then
    incJt(st)
    return
  end
  st.x = u8(st.x + 1)
  local angle = st.var1
  st.var1 = u8(st.var1 + 1)
  st.xOffset = cosine(angle, 0x18)
  if bit.band(st.x, 1) ~= 0 then return end
  st.y = u8(st.y - 1)
end

F.BATTLE_ANIM_FUNC_SMOKE_FLAME_WHEEL = function(_, st)
  local angle = st.param
  st.yOffset = u8(sra(sra(sra(sine(angle, 0x18)))) + st.var2)
  st.xOffset = cosine(angle, 0x18)
  st.param = u8(st.param + 2)
  if bit.band(st.param, 7) ~= 0 then return end
  if st.var2 == 0xe8 then
    deinit(st)
    return
  end
  st.var2 = u8(st.var2 - 1)
end

F.BATTLE_ANIM_FUNC_SACRED_FIRE = function(_, st)
  local angle = st.param
  st.yOffset = u8(sra(sra(sra(sine(angle, 0x18)))) + st.var2)
  st.xOffset = cosine(angle, 0x18)
  st.param = u8(st.param + 2)
  if bit.band(st.param, 3) ~= 0 then return end
  if st.var2 == 0xd0 then
    deinit(st)
    return
  end
  st.var2 = u8(st.var2 - 2)
end

F.BATTLE_ANIM_FUNC_PRESENT_SMOKESCREEN = function(_, st)
  if st.jt == 0 then
    incJt(st)
    st.var1, st.var2 = 0x34, 0x10
  elseif st.jt == 2 then
    deinit(st)
    return
  end
  if st.jt ~= 1 then return end
  if st.x >= 0x6c then return end
  stepToTarget(st, 2)
  local value = sine(st.var1, st.var2)
  -- Only the upper half of the bounce shows: a positive sine is negated, so
  -- the puff always sits above its line.
  if bit.band(value, 0x80) == 0 then value = u8(-value) end
  st.yOffset = value
  st.var1 = u8(st.var1 - 4)
  -- The halving below is unreachable on the cart: `and $1f` can never leave
  -- $20, so Present's puff keeps its height the whole way across.
end

F.BATTLE_ANIM_FUNC_HORN = function(_, st)
  local function spin()
    local value = sine(st.var2, 8)
    st.xOffset = value
    st.y = u8(st.var1 - sra(value))
    st.var2 = u8(st.var2 + 8)
  end
  local jt = st.jt
  if jt == 0 then
    st.jt = st.param
    st.var1 = st.y
  elseif jt == 1 then
    if st.x >= 0x58 then return end
    stepToTarget(st, 2)
  elseif jt == 2 then
    if st.var2 >= 0x20 then
      deinit(st)
      return
    end
    spin()
  elseif jt == 3 then
    spin()
  end
end

F.BATTLE_ANIM_FUNC_NEEDLE = function(_, st)
  local function line()
    if st.x >= 0x84 then
      deinit(st)
      return
    end
    stepToTarget(st, st.param)
  end
  local jt = st.jt
  if jt == 0 then
    -- The upper nybble of PARAM picks straight line or arc.
    st.jt = bit.band(swap(st.param), 0xf)
  elseif jt == 1 then
    line()
  elseif jt == 2 then
    local value = sine(st.var1, 0x10)
    -- Only the negative half is written, so the needle arcs upward only.
    if bit.band(value, 0x80) ~= 0 then st.yOffset = value end
    st.var1 = u8(st.var1 - 4)
    line() -- .two falls into .one
  end
end

F.BATTLE_ANIM_FUNC_THIEF_PAYDAY = function(_, st)
  if st.jt == 0 then
    incJt(st)
    st.var1 = 0x28
    st.var2 = u8(st.y - 0x28)
  end
  st.yOffset = sine(st.var1, st.var2)
  -- PARAM is a MASK, so the coin only drifts left on the frames that clear it.
  if bit.band(st.var1, st.param) == 0 then st.x = u8(st.x - 1) end
  st.var1 = u8(st.var1 + 1)
  if bit.band(st.var1, 0x3f) ~= 0 then return end
  st.var1 = 0x20
  st.var2 = bit.rshift(st.var2, 1)
end

F.BATTLE_ANIM_FUNC_ABSORB_CIRCLE = function(_, st)
  local angle = st.param
  st.yOffset = sine(angle, st.var1)
  st.xOffset = cosine(angle, st.var1)
  st.param = u8(st.param + 1)
  if bit.band(st.param, 1) == 0 then st.x = u8(st.x - 1) end
  if bit.band(st.param, 3) == 0 then st.y = u8(st.y + 1) end
  if st.x >= 0x5a then
    st.var1 = u8(st.var1 + 1)
    return
  end
  if st.var1 == 0 then
    deinit(st)
    return
  end
  st.var1 = u8(st.var1 - 1)
end

F.BATTLE_ANIM_FUNC_CONVERSION = function(_, st)
  local angle = st.param
  st.param = u8(st.param + 1)
  st.yOffset = sine(angle, st.var1)
  st.xOffset = cosine(angle, st.var1)
  local age = st.var2
  st.var2 = u8(st.var2 + 1)
  if age < 0x40 then
    st.var1 = u8(st.var1 + 1)
    return
  end
  local radius = st.var1
  st.var1 = u8(st.var1 - 1)
  if radius ~= 0 then return end
  deinit(st)
end

F.BATTLE_ANIM_FUNC_BONEMERANG = function(_, st)
  if st.jt == 0 then
    incJt(st)
    st.var2 = st.y
  end
  st.y = u8(st.var2 + sine(st.param, 0x30))
  -- Eight steps of phase between the two axes is what bends the throw into a
  -- boomerang instead of a circle.
  st.xOffset = cosine(st.param + 8, 0x30)
  st.param = u8(st.param + 1)
end

F.BATTLE_ANIM_FUNC_SHINY = function(_, st)
  if st.jt ~= 0 then return end
  incJt(st)
  st.yOffset = sine(st.param, 0x10)
  st.xOffset = cosine(st.param, 0x10)
  st.var2 = 0xf
end

-- Sky Attack pulses OBP0 rather than moving anything, so the palette write is
-- what the view has to see.
local SKY_ATTACK_GBC = { [0] = 0xff, [1] = 0xaa, [2] = 0x55, [3] = 0xaa }
local SKY_ATTACK_SGB = { [0] = 0xff, [1] = 0xff, [2] = 0x00, [3] = 0x00 }

F.BATTLE_ANIM_FUNC_SKY_ATTACK = function(self, st)
  local function cyclePalette()
    local phase = bit.band(st.var2, 7)
    st.var2 = u8(st.var2 + 1)
    local pals = self.env.sgb and SKY_ATTACK_SGB or SKY_ATTACK_GBC
    self.obp0 = bit.band(pals[bit.rshift(phase, 1)] or 0xff, st.var1)
    if self.hram then self.hram.obp0 = self.obp0 end
  end
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var1 = (self.env.battleTurn or 0) == 0 and 0xf0 or 0xcc
  elseif jt == 1 then
    cyclePalette()
  elseif jt == 2 then
    cyclePalette()
    if st.x >= 0x84 then return end
    stepToTarget(st, 4)
  elseif jt == 3 then
    cyclePalette()
    if st.x >= 0xd0 then
      deinit(st)
      return
    end
    stepToTarget(st, 4)
  end
end

F.BATTLE_ANIM_FUNC_GROWTH_SWORDS_DANCE = function(_, st)
  local angle = st.param
  st.yOffset = u8(sra(sra(sra(sine(angle, 0x18)))) + st.var2)
  st.param = u8(st.param + 1)
  st.xOffset = cosine(angle, 0x18)
  st.var2 = u8(st.var2 - 2)
end

F.BATTLE_ANIM_FUNC_STRENGTH_SEISMIC_TOSS = function(_, st)
  local jt = st.jt
  if jt == 0 then
    if st.yOffset == 0xe0 then
      incJt(st)
      st.var1 = 2
      return
    end
    st.yOffset, st.var1 = add16(st.yOffset, st.var1, -0x80)
  elseif jt == 1 then
    if st.var2 ~= 0 then
      st.var2 = st.var2 - 1
      return
    end
    -- Shakes by negating the accumulated step and folding it into the offset
    -- every four frames.
    st.var2 = 4
    st.var1 = u8(-st.var1)
    st.yOffset = u8(st.yOffset + st.var1)
  elseif jt == 2 then
    if st.x >= 0x84 then
      deinit(st)
      return
    end
    stepToTarget(st, 4)
  end
end

F.BATTLE_ANIM_FUNC_SPEED_LINE = function(self, st)
  if st.jt == 0 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_SPEED_LINE_1")
      + bit.band(st.param, 0x7f))
  end
  if bit.band(st.param, 0x80) ~= 0 then
    st.xOffset = u8(st.xOffset - 1)
  else
    st.xOffset = u8(st.xOffset + 1)
  end
end

F.BATTLE_ANIM_FUNC_SLUDGE = function(self, st)
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var1 = 0xc
  elseif jt == 1 then
    if st.var1 ~= 0 then
      st.var1 = st.var1 - 1
      return
    end
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_SLUDGE_BUBBLE_BURST"))
    st.yOffset = u8(st.yOffset - 1) -- .done falls into .two
  elseif jt == 2 then
    st.yOffset = u8(st.yOffset - 1)
  end
end

F.BATTLE_ANIM_FUNC_METRONOME_HAND = function(_, st)
  local angle = st.var1
  st.var1 = u8(st.var1 + 2)
  st.yOffset = sine(angle, 2)
  st.xOffset = cosine(angle, 8)
end

F.BATTLE_ANIM_FUNC_METRONOME_SPARKLE_SKETCH = function(_, st)
  if st.yOffset >= 0x20 then
    deinit(st)
    return
  end
  st.xOffset = cosine(st.param, 8)
  st.param = u8(st.param + 2)
  if bit.band(st.param, 7) ~= 0 then return end
  st.yOffset = u8(st.yOffset + 1)
end

F.BATTLE_ANIM_FUNC_AGILITY = function(_, st)
  -- anim_incobj is what makes it disappear.
  if st.jt ~= 0 then
    deinit(st)
    return
  end
  st.x = u8(st.x + st.param)
end

F.BATTLE_ANIM_FUNC_SAFEGUARD_PROTECT = function(_, st)
  local angle = st.param
  st.yOffset = sine(angle, 0x18)
  st.xOffset = sra(cosine(angle, 0x18))
  st.param = u8(st.param + 1)
end

F.BATTLE_ANIM_FUNC_LOCK_ON_MIND_READER = function(_, st)
  -- .two: hold for $10 frames, then go.
  local function hold()
    local left = st.var1
    st.var1 = u8(st.var1 - 1)
    if left ~= 0 then return end
    deinit(st)
  end
  local jt = st.jt
  if jt == 0 then
    incJt(st)
    st.var1 = 0x28
    -- The low nybble walks along the four LOCK_ON / MIND_READER framesets,
    -- and the object's own frameset id is the base of that run.
    reinit(st, u8(st.framesetId + bit.band(st.param, 0xf)))
    st.param = bit.bor(bit.band(st.param, 0xf0), 8)
    jt = 1
  end
  if jt == 1 then
    if st.var1 ~= 0 then
      st.var1 = st.var1 - 1
      -- The radius is the distance still to run, so the ring converges.
      local radius = u8(st.var1 + 8)
      st.yOffset = sine(st.param, radius)
      st.xOffset = cosine(st.param, radius)
      return
    end
    st.var1 = 0x10
    incJt(st)
    hold() -- .done falls into .two
    return
  end
  if jt == 2 then hold() end
end

F.BATTLE_ANIM_FUNC_HEAL_BELL_NOTES = function(self, st)
  if st.jt == 0 then
    incJt(st)
    reinit(st, self:framesetId("BATTLE_ANIM_FRAMESET_MUSIC_NOTE_1") + st.param)
  end
  if st.yOffset >= 0x38 then
    deinit(st)
    return
  end
  st.yOffset = u8(st.yOffset + 1)
  local angle = st.var1
  st.var1 = u8(st.var1 + 1)
  st.xOffset = cosine(angle, 0x18)
  -- Tests the Y COORDINATE, not the counter: the note drifts left on the
  -- frames its row happens to be even.
  if bit.band(st.y, 1) ~= 0 then return end
  st.x = u8(st.x - 1)
end

F.BATTLE_ANIM_FUNC_BATON_PASS = function(_, st)
  if st.param == 0 then return end
  local angle = st.var1
  st.var1 = u8(st.var1 + 1)
  local value = sine(angle, st.param)
  if bit.band(value, 0x80) == 0 then value = u8(-value) end
  st.yOffset = value
  if bit.band(st.var1, 0x1f) ~= 0 then return end
  -- Each bounce is half the last.
  st.param = bit.rshift(st.param, 1)
end

F.BATTLE_ANIM_FUNC_ENCORE_BELLY_DRUM = function(_, st)
  if st.var1 >= 0x10 then
    deinit(st)
    return
  end
  local radius = st.var1
  st.var1 = u8(st.var1 + 2)
  st.yOffset = sine(st.param, radius)
  st.xOffset = cosine(st.param, radius)
end

F.BATTLE_ANIM_FUNC_SWAGGER_MORNING_SUN = function(_, st)
  -- The top two bits of PARAM are the speed and the low six the angle; the
  -- amplitude is VAR1 as it was BEFORE this frame's speed was added.
  local radius = st.var1
  st.var1 = u8(st.var1 + rlca(rlca(bit.band(st.param, 0xc0))))
  local angle = bit.band(st.param, 0x3f)
  st.yOffset = sine(angle, radius)
  st.xOffset = cosine(angle, radius)
end

F.BATTLE_ANIM_FUNC_HIDDEN_POWER = function(_, st)
  -- .two: the ring expands eight pixels a frame and then vanishes.
  local function expand()
    if st.var1 >= 0x80 then
      deinit(st)
      return
    end
    local radius = st.var1
    st.var1 = u8(st.var1 + 8)
    stepCircle(st, st.param, radius)
  end
  local jt = st.jt
  if jt == 0 then
    local angle = st.param
    st.param = u8(st.param + 1)
    stepCircle(st, angle, 0x18)
  elseif jt == 1 then
    incJt(st)
    st.var1 = 0x18
    expand() -- .one falls into .two
  elseif jt == 2 then
    expand()
  end
end

F.BATTLE_ANIM_FUNC_CURSE = function(_, st)
  if st.jt ~= 1 then return end
  if st.x < 0x30 then
    deinit(st)
    return
  end
  st.x = u8(st.x - 2)
  st.y = u8(st.y + 2)
end

F.BATTLE_ANIM_FUNC_PERISH_SONG = function(_, st)
  local angle = st.param
  st.param = u8(st.param + 2)
  -- VAR1 is both the sink and the counter: the sine is added to it and then
  -- it is stepped, so the ring drifts down as it turns.
  st.yOffset = u8(sra(sra(sine(angle, 0x50))) + st.var1)
  st.var1 = u8(st.var1 + 1)
  st.xOffset = cosine(angle, 0x50)
end

F.BATTLE_ANIM_FUNC_RAPID_SPIN = function(_, st)
  if st.yOffset == 0xd0 then
    deinit(st)
    return
  end
  st.yOffset = u8(st.yOffset - 4)
end

F.BATTLE_ANIM_FUNC_BETA_PURSUIT = function(_, st)
  local jt = st.jt
  if jt == 0 then
    if st.param ~= 0 then
      incJt(st)
      incJt(st)
      return
    end
    incJt(st)
    st.yOffset = 0xec
  elseif jt == 1 then
    if st.yOffset == 4 then
      deinit(st)
      return
    end
    st.yOffset = u8(st.yOffset + 4)
  elseif jt == 2 then
    if st.yOffset == 0xd8 then return end
    st.yOffset = u8(st.yOffset - 4)
  elseif jt == 3 then
    deinit(st)
  end
end

F.BATTLE_ANIM_FUNC_RAIN_SANDSTORM = function(_, st)
  -- The Y offset wraps at $70, which is what makes a single object read as a
  -- continuous fall of rain.
  local function fall(step)
    local y = st.yOffset + 4
    st.yOffset = (y < 0x70) and y or 0
    st.xOffset = u8(st.xOffset + step)
  end
  local jt = st.jt
  if jt == 0 then
    st.jt = u8(st.param + 1) -- .zero sets the index from PARAM and then incs
  elseif jt == 1 then
    fall(2)
  elseif jt == 2 then
    fall(8)
  elseif jt == 3 then
    fall(4)
  end
end

F.BATTLE_ANIM_FUNC_BATTLE_ANIM_OBJ_B0 = function(_, st)
  -- Unused on the cart (nothing names BATTLE_ANIM_OBJ_B0), transcribed
  -- because the jumptable slot is real: PARAM's nybbles become a 16-bit step
  -- over XCOORD:VAR1, the high nybble duplicated into both halves of the
  -- whole-pixel byte.
  local high = bit.band(st.param, 0xf0)
  high = bit.bor(high, bit.rshift(high, 4))
  st.x, st.var1 = add16(st.x, st.var1,
    high * 256 + swap(bit.band(st.param, 0xf)))
end

F.BATTLE_ANIM_FUNC_PSYCH_UP = function(_, st)
  local angle = st.param
  st.param = u8(st.param + 1)
  stepCircle(st, angle, 0x18)
end

F.BATTLE_ANIM_FUNC_COTTON = function(_, st)
  local phase = st.var2
  st.var2 = u8(st.var2 + 1)
  stepCircle(st, u8(bit.rshift(phase, 1) + st.param), 0x18)
end

F.BATTLE_ANIM_FUNC_ANCIENT_POWER = function(_, st)
  if st.var1 >= 0x20 then
    deinit(st)
    return
  end
  local angle = st.var1
  st.var1 = u8(st.var1 + 1)
  st.yOffset = u8(-sine(angle, st.param))
end

AnimObjects.FUNCTIONS = F
AnimObjects.NUM_STRUCTS = NUM_STRUCTS
AnimObjects.OAM_LIMIT = OAM_LIMIT
AnimObjects.OAM_XFLIP = OAM_XFLIP
AnimObjects.OAM_YFLIP = OAM_YFLIP
AnimObjects.OAM_PRIO = OAM_PRIO
AnimObjects.OAM_PAL1 = OAM_PAL1
AnimObjects.FIX_COORDS = FIX_COORDS
AnimObjects.sine, AnimObjects.cosine = sine, cosine
AnimObjects.u8, AnimObjects.s8, AnimObjects.sra = u8, s8, sra
AnimObjects.swap, AnimObjects.rlca = swap, rlca

return AnimObjects
