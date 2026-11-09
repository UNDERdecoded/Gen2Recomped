-- The Minish Cap script interpreter: runs the cartridge's own script
-- bytecode (the data/scripts region the importer copied) the way
-- src/script.c ExecuteScript does.
--
-- FORMAT.  A command is one halfword: bits 0-9 the command index, bits
-- 10-15 its length in halfwords (itself included); arguments follow.  $FFFF
-- ends a script.  Because every command states its own length, a command we
-- have not ported is skipped cleanly instead of derailing the script.
--
-- EXECUTION.  Each frame: if `wait` > 0 count it down; otherwise run
-- commands until one leaves flags & 3 clear (bit 0 = "keep going this
-- frame", set by the instant commands; bit 1 = inside BeginBlock/EndBlock).
-- A command that must wait sets commandSize = 0, so the same command runs
-- again next frame.
--
-- The host (Field) supplies the world: flags, inventory, messages, the
-- player, sounds.  `entity` is any table with x, y (room pixels),
-- animationState, direction, speed, interactType, anim (Anim) and the
-- NPC animation fields field80 / field82.

local bit = require("bit")
local band, bor, bnot, rshift, lshift = bit.band, bit.bor, bit.bnot, bit.rshift, bit.lshift

local Script = {}
Script.__index = Script

-- the shared gActiveScriptInfo
local active = { flags = 0, commandSize = 0, syncFlags = 0 }
Script.active = active

function Script.resetSync() active.syncFlags = 0 end

-- ---------------------------------------------------------------------------
-- reading the script region
-- ---------------------------------------------------------------------------
local Mem = {}
Mem.__index = Mem

function Script.memory(blob, base)
  return setmetatable({ blob = blob or "", base = base or 0 }, Mem)
end

function Mem:valid(addr)
  local o = addr - self.base
  return o >= 0 and o + 1 < #self.blob
end

function Mem:u16(addr)
  local o = addr - self.base
  local lo, hi = self.blob:byte(o + 1, o + 2)
  if not lo then return 0xFFFF end
  return lo + (hi or 0) * 256
end

function Mem:s16(addr)
  local v = self:u16(addr)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

-- words in scripts are two halfwords, low first (GetNextScriptCommandWord)
function Mem:u32(addr)
  return self:u16(addr) + self:u16(addr + 2) * 65536
end

-- ---------------------------------------------------------------------------
-- context
-- ---------------------------------------------------------------------------
function Script.new(mem, ip)
  return setmetatable({
    mem = mem, ip = ip, wait = 0, condition = 0, intVariable = 0,
    unk18 = 0, unk19 = 0, unk12 = 0, unk1A = 0, postScriptActions = 0,
    tx = 0, ty = 0, vx = 0, vy = 0, stopped = false, unknown = {},
  }, Script)
end

local function arg(ctx, i) return ctx.mem:u16(ctx.ip + 2 * i) end
local function sarg(ctx, i) return ctx.mem:s16(ctx.ip + 2 * i) end
local function word(ctx) return ctx.mem:u32(ctx.ip + 2) end

local function keepGoing() active.flags = bor(active.flags, 1) end
local function stay() active.commandSize = 0 end

-- direction helpers: 8-bit angles, 0 = north, clockwise
local function angleTo(dx, dy)
  if dx == 0 and dy == 0 then return 0 end
  local a = math.atan2(dx, -dy) -- 0 north, +pi/2 east
  local v = math.floor(a / (2 * math.pi) * 256 + 0.5) % 256
  return v
end
Script.angleTo = angleTo

local function animStateFor(angle)
  -- GetAnimationStateForDirection8 on an 8-bit angle: nearest of 8 states,
  -- NPC sprites use the 4 cardinal ones (even states)
  local s = math.floor(((angle + 16) % 256) / 32)
  return s
end

local DIR_TABLE = { [0] = 0, 0, 2, 2, 2, 2, 4, 4, 4, 4, 6, 6, 6, 6, 0, 0 }

local function lookAt(ent, ctx, x, y)
  ctx.unk19 = 8
  ctx.postScriptActions = bor(ctx.postScriptActions, 2)
  ctx.condition = 0
  ctx.tx, ctx.ty = x, y
  local d = angleTo(x - ent.x, y - ent.y)
  ent.angle = d
  ent.animationState = bor(band(ent.animationState or 0, 0x80), DIR_TABLE[rshift(d, 4)])
end

local function moveAngle(ent, speed, angle)
  local a = angle / 256 * 2 * math.pi
  local s = (speed or 0x100) / 256
  ent.x = ent.x + math.sin(a) * s
  ent.y = ent.y - math.cos(a) * s
end
Script.moveAngle = moveAngle

local function moveTowards(ent, ctx)
  ctx.unk19 = ctx.unk19 - 1
  if ctx.unk19 <= 0 then
    ctx.unk19 = 8
    ent.angle = angleTo(ctx.tx - ent.x, ctx.ty - ent.y)
  end
  local bx, by = ent.x - ctx.tx, ent.y - ctx.ty
  moveAngle(ent, ent.speed or 0x100, ent.angle or 0)
  if bx * (ent.x - ctx.tx) <= 0 and by * (ent.y - ctx.ty) <= 0 then
    ent.x, ent.y = ctx.tx, ctx.ty
    ctx.condition = 1
  else
    ctx.condition = 0
  end
end

local function walk(ent, ctx, state, dir5)
  if ctx.unk18 == 0 then
    ctx.unk18 = 1
    ctx.unk12 = arg(ctx, 1)
    if state then ent.animationState = state end
    if dir5 then ent.angle = dir5 * 8 end
    ctx.postScriptActions = bor(ctx.postScriptActions, 2)
  end
  moveAngle(ent, ent.speed or 0x100, ent.angle or 0)
  ctx.unk12 = ctx.unk12 - 1
  if ctx.unk12 > 0 then stay() end
end

-- ---------------------------------------------------------------------------
-- the command table (indices from src/script.c gScriptCommands)
-- ---------------------------------------------------------------------------
local C = {}
Script.commands = C

C[0x00] = function() end
C[0x01] = function() active.flags = bor(active.flags, 2) end
C[0x02] = function() active.flags = band(active.flags, bnot(2)) end
local function jump(ent, ctx)
  ctx.ip = ctx.ip + 2
  local off = ctx.mem:s16(ctx.ip)
  ctx.ip = ctx.ip + math.floor(off / 2) * 2
  if off < 0 and off % 2 ~= 0 then ctx.ip = ctx.ip + 2 end -- C division truncates
  active.commandSize = 0
end
C[0x03] = jump
C[0x04] = function(e, ctx) if ctx.condition ~= 0 then jump(e, ctx) end end
C[0x05] = function(e, ctx) if ctx.condition == 0 then jump(e, ctx) end end
C[0x06] = function(e, ctx)
  if active.commandSize > ctx.intVariable then
    ctx.ip = ctx.ip + 2 * ctx.intVariable
    jump(e, ctx)
  end
end
local function jumpAbs(e, ctx)
  ctx.ip = word(ctx)
  active.commandSize = 0
end
C[0x07] = jumpAbs
C[0x08] = function(e, ctx) if ctx.condition ~= 0 then jumpAbs(e, ctx) end end
C[0x09] = function(e, ctx) if ctx.condition == 0 then jumpAbs(e, ctx) end end
C[0x0A] = function(e, ctx)
  if active.commandSize > ctx.intVariable * 2 + 1 then
    ctx.ip = ctx.ip + 4 * ctx.intVariable
    jumpAbs(e, ctx)
  end
end
-- Call / CallWithArg run native code: Native.lua ports the ones scenes
-- need, by address; the rest are skipped (and counted in Script.missing)
Script.missing = {}
local function callNative(e, ctx, host, fn)
  if host.callNative and host:callNative(fn, e, ctx) then return end
  ctx.unknown[fn] = true
  Script.missing[fn] = (Script.missing[fn] or 0) + 1
  keepGoing()
end
C[0x0B] = function(e, ctx, host) callNative(e, ctx, host, word(ctx)) end
C[0x0C] = function(e, ctx, host)
  local fn = word(ctx)
  ctx.intVariable = ctx.mem:u32(ctx.ip + 6)
  callNative(e, ctx, host, fn)
end
C[0x0D] = function(e, ctx, host) if host.loadEntityList then host:loadEntityList(word(ctx)) end end
C[0x0E] = function(e, ctx)
  local f = word(ctx)
  ctx.condition = band(active.syncFlags, f) == f and 1 or 0
  active.syncFlags = band(active.syncFlags, bnot(f))
  keepGoing()
end
C[0x0F] = function(e, ctx, host) ctx.condition = host:inventory(arg(ctx, 1)); keepGoing() end
C[0x10] = function(e, ctx, host) ctx.condition = host:inventory(arg(ctx, 1)) == 2 and 1 or 0; keepGoing() end
C[0x11] = function(e, ctx, host) ctx.condition = (host.shopItem and host.shopItem ~= 0) and 1 or 0; keepGoing() end
C[0x12] = function(e, ctx, host) ctx.condition = host:flag("local", arg(ctx, 1)) and 1 or 0; keepGoing() end
C[0x13] = function(e, ctx, host) ctx.condition = host:flag("bank", arg(ctx, 2), arg(ctx, 1)) and 1 or 0; keepGoing() end
C[0x14] = function(e, ctx, host) ctx.condition = host:flag("global", arg(ctx, 1)) and 1 or 0; keepGoing() end
C[0x15] = function(e, ctx, host) ctx.condition = host:flag("room", arg(ctx, 1)) and 1 or 0; keepGoing() end
C[0x16] = function(e, ctx, host)
  local wh = arg(ctx, 3)
  ctx.condition = host:playerInRegion(arg(ctx, 1), arg(ctx, 2), band(wh, 0xFF), rshift(wh, 8)) and 1 or 0
  keepGoing()
end
C[0x17] = function(e, ctx, host)
  local wh = arg(ctx, 1)
  ctx.condition = host:playerInRegion(e.x, e.y, band(wh, 0xFF), rshift(wh, 8)) and 1 or 0
  keepGoing()
end
C[0x18] = function(e, ctx)
  if (e.interactType or 0) ~= 0 then e.interactType = 0; ctx.condition = 1 else ctx.condition = 0 end
  keepGoing()
end
C[0x19] = function(e, ctx, host)
  local p = host.player
  if band(ctx.unk1A, 0xF) == 0 and not p.minish and math.abs(p.x - e.x) <= 40 and math.abs(p.y - e.y) <= 40 then
    e.animationState = band(animStateFor(angleTo(p.x - e.x, p.y - e.y)), 6)
  end
  ctx.unk1A = ctx.unk1A + 1
  if (e.interactType or 0) ~= 0 then
    e.interactType = 0
    ctx.condition = 1
    e.animationState = band(animStateFor(angleTo(p.x - e.x, p.y - e.y)), 6)
  else
    ctx.condition = 0
  end
  keepGoing()
end
C[0x1A] = function(e, ctx, host) ctx.condition = arg(ctx, 1) <= host:stat("rupees") and 1 or 0; keepGoing() end
C[0x1B] = function(e, ctx, host) ctx.condition = arg(ctx, 1) <= host:stat("shells") and 1 or 0; keepGoing() end
C[0x1C] = function(e, ctx, host) ctx.condition = (host.textResult or 0) == 0 and 1 or 0; keepGoing() end
C[0x1D] = function(e, ctx, host) ctx.condition = host:kinstoneFused(arg(ctx, 1)) and 1 or 0; keepGoing() end
C[0x20] = function(e, ctx) ctx.condition = band(ctx.intVariable, arg(ctx, 1)) ~= 0 and 1 or 0; keepGoing() end
C[0x21] = function(e, ctx) local t = arg(ctx, 1); ctx.condition = band(t, ctx.intVariable) == t and 1 or 0; keepGoing() end
C[0x22] = function(e, ctx) ctx.condition = arg(ctx, 1) == ctx.intVariable and 1 or 0; keepGoing() end
C[0x23] = function(e, ctx, host) ctx.condition = band(word(ctx), host.player.flags or 0) ~= 0 and 1 or 0; keepGoing() end
C[0x24] = function(e, ctx, host) ctx.condition = host.player.minish and 1 or 0; keepGoing() end
C[0x25] = function(e, ctx) ctx.condition = (e.z or 0) ~= 0 and 1 or 0; keepGoing() end
C[0x26] = function(e, ctx, host) ctx.condition = arg(ctx, 1) == (host.player.action or 1) and 1 or 0; keepGoing() end
C[0x27] = function(e, ctx, host) ctx.condition = arg(ctx, 1) == host.player.animationState and 1 or 0; keepGoing() end
C[0x28] = function(e, ctx) active.syncFlags = bor(active.syncFlags, word(ctx)) end
C[0x29] = function(e, ctx) active.syncFlags = band(active.syncFlags, bnot(word(ctx))) end
C[0x2A] = function(e, ctx, host) host:setFlag("local", arg(ctx, 1), true) end
C[0x2B] = function(e, ctx, host) host:setFlag("bank", arg(ctx, 2), true, arg(ctx, 1)) end
C[0x2C] = function(e, ctx, host) host:setFlag("local", arg(ctx, 1), false) end
C[0x2D] = function(e, ctx, host) host:setFlag("global", arg(ctx, 1), true) end
C[0x2E] = function(e, ctx, host) host:setFlag("global", arg(ctx, 1), false) end
C[0x2F] = function(e, ctx, host) host:setFlag("room", arg(ctx, 1), true) end
C[0x30] = function(e, ctx, host) host:setFlag("room", arg(ctx, 1), false) end
C[0x31] = function(e, ctx) ctx.wait = arg(ctx, 1) end
C[0x32] = function(e, ctx)
  local f = word(ctx)
  if band(active.syncFlags, f) ~= f then stay() end
end
C[0x33] = function(e, ctx)
  local f = word(ctx)
  if band(active.syncFlags, f) ~= f then stay()
  else active.syncFlags = band(active.syncFlags, bnot(f)); keepGoing() end
end
C[0x34] = function(e, ctx, host)
  if host.player.itemGet then stay() else ctx.wait = 45 end
end
C[0x35] = function(e, ctx, host)
  if host.player.entering then stay() else keepGoing() end
end
C[0x36] = function(e, ctx, host) if host.scrolling then stay() else keepGoing() end end
C[0x37] = function(e, ctx, host) if host:fadeActive() then stay() end end
-- fades: SetFade4..7 = FADE_INSTANT (in), | IN_OUT (out), | BLACK_WHITE
-- (white); iris fades as plain ones; all at the SetFadeTime speed
C[0x38] = function(e, ctx, host) host.fadeSpeed = arg(ctx, 1) end
C[0x39] = function() end
C[0x3A] = function(e, ctx, host) host:fade("invert", nil, host.fadeSpeed) end
C[0x3B] = function() end
C[0x3C] = function(e, ctx, host) host:fade("in", false, host.fadeSpeed) end
C[0x3D] = function(e, ctx, host) host:fade("out", false, host.fadeSpeed) end
C[0x3E] = function(e, ctx, host) host:fade("in", true, host.fadeSpeed) end
C[0x3F] = function(e, ctx, host) host:fade("out", true, host.fadeSpeed) end
C[0x40] = function(e, ctx, host) host:fade("in", false, host.fadeSpeed) end
C[0x41] = function(e, ctx, host) host:fade("out", false, host.fadeSpeed) end
C[0x42] = function() end
C[0x43] = function(e, ctx, host) host.player.control = false; host.player.moving = false end
C[0x44] = function(e, ctx, host) host.player.control = true end
C[0x45] = function(e, ctx, host) host.player.control = false end
C[0x46] = function() end
C[0x47] = function(e, ctx, host) if host.startPlayerScript then host:startPlayerScript(word(ctx)) end end
C[0x48] = function(e, ctx, host) host.player.scriptAnim = arg(ctx, 1) end
-- 0x49..0x4C: face up/right/down/left (commandIndex - first) << 1
C[0x49] = function(e, ctx, host) host.player.animationState = 0 end
C[0x4A] = function(e, ctx, host) host.player.animationState = 2 end
C[0x4B] = function(e, ctx, host) host.player.animationState = 4 end
C[0x4C] = function(e, ctx, host) host.player.animationState = 6 end
C[0x4D] = function(e, ctx) e.action = arg(ctx, 1); e.subAction = 0 end
C[0x4E] = function(e, ctx) ctx.intVariable = word(ctx) end
C[0x4F] = function(e, ctx) ctx.intVariable = e.frameFlags or 0; e.frameFlags = 0 end
C[0x50] = function(e, ctx) e.field80 = arg(ctx, 1); e.forceAnim = arg(ctx, 1) end
C[0x51] = function(e, ctx)
  if (e.interactType or 0) ~= 0 then e.interactType = 0; keepGoing() else stay() end
end
C[0x52] = function(e, ctx, host)
  if ctx.unk18 == 0 then
    if (e.interactType or 0) ~= 0 then
      e.interactType = 0
      ctx.unk18 = 1
      host:message(arg(ctx, 1), e)
    end
  elseif ctx.unk18 == 1 then
    if not host:messageActive() then ctx.unk18 = 2; ctx.unk19 = 0xF end
  else
    ctx.unk19 = ctx.unk19 - 1
    if ctx.unk19 <= 0 then return end
  end
  stay()
end
C[0x53] = function(e) e.talkable = true end
C[0x54] = function(e) e.talkable = false end
C[0x55] = function(e, ctx) e.talkable = true; e.fuser = arg(ctx, 1) end
C[0x56] = function(e, ctx, host)
  local st = host.fusionState and host:fusionState() or 2
  if st == 2 then ctx.condition = 1
  elseif st == 1 then ctx.condition = 0
  else stay() end
end
C[0x57] = function(e, ctx, host)
  if e.interactType == 2 then e.interactType = 0; keepGoing() else stay() end
end
C[0x58] = function(e, ctx) e.talkable = true; e.fuser = arg(ctx, 1) end
C[0x59] = function(e, ctx, host) if host:messageActive() then stay() end end
C[0x5A] = function(e, ctx, host) host:message(arg(ctx, 1), e) end
C[0x5B] = function(e, ctx, host) host:message(arg(ctx, 1), e) end
C[0x5C] = function(e, ctx, host) host:message(arg(ctx, 1), e, arg(ctx, 2)) end
C[0x5D] = function(e, ctx, host)
  if active.commandSize > ctx.intVariable then host:message(arg(ctx, 1 + ctx.intVariable), e)
  else host:message(0, e) end
end
C[0x5E] = function(e, ctx, host) host:message(ctx.intVariable, e) end
C[0x5F] = function(e, ctx, host) host:message(arg(ctx, 1), e, nil, "ezlo") end
C[0x60] = function(e, ctx, host) ctx.intVariable = host.textResult or 0 end
C[0x61] = function(e, ctx) e.animationState = arg(ctx, 1) end
C[0x62] = function(e, ctx)
  e.animationState = band(animStateFor(angleTo(arg(ctx, 1) - e.x, arg(ctx, 2) - e.y)), 6)
end
C[0x63] = function(e, ctx, host)
  local p = host.player
  e.animationState = band(animStateFor(angleTo(p.x - e.x, p.y - e.y)), 6)
end
C[0x64] = function(e, ctx, host)
  local p = host.player
  p.animationState = band(animStateFor(angleTo(e.x - p.x, e.y - p.y)), 6)
end
C[0x65] = function(e, ctx) e.angle = arg(ctx, 1) * 8 end
C[0x66] = function(e, ctx) e.angle = arg(ctx, 1) * 8; e.animationState = math.floor(arg(ctx, 1) / 4) end
C[0x67] = function(e, ctx) e.speed = arg(ctx, 1) end
C[0x68] = function(e, ctx) e.zVelocity = word(ctx) end
C[0x69] = function(e, ctx) e.x, e.y = arg(ctx, 1), arg(ctx, 2) end
C[0x6A] = function(e, ctx) e.x, e.y = e.x + sarg(ctx, 1), e.y + sarg(ctx, 2) end
C[0x6B] = function(e, ctx, host) e.x, e.y = host.player.x, host.player.y end
C[0x6C] = function() end
C[0x6D] = function(e, ctx) walk(e, ctx) end
C[0x6E] = function(e, ctx) walk(e, ctx, 0, 0) end
C[0x6F] = function(e, ctx) walk(e, ctx, 2, 8) end
C[0x70] = function(e, ctx) walk(e, ctx, 4, 16) end
C[0x71] = function(e, ctx) walk(e, ctx, 6, 24) end
C[0x72] = function(e, ctx)
  if ctx.unk18 == 0 then
    ctx.unk18 = 1
    ctx.unk12 = math.max(1, arg(ctx, 3))
    ctx.vx = (arg(ctx, 1) - e.x) / ctx.unk12
    ctx.vy = (arg(ctx, 2) - e.y) / ctx.unk12
    e.animationState = band(animStateFor(angleTo(arg(ctx, 1) - e.x, arg(ctx, 2) - e.y)), 6)
    ctx.postScriptActions = bor(ctx.postScriptActions, 2)
  else
    ctx.unk12 = ctx.unk12 - 1
    if ctx.unk12 <= 0 then e.x, e.y = arg(ctx, 1), arg(ctx, 2); return end
    e.x, e.y = e.x + ctx.vx, e.y + ctx.vy
  end
  stay()
end
C[0x74] = function(e, ctx) lookAt(e, ctx, arg(ctx, 1), arg(ctx, 2)); keepGoing() end
C[0x73] = function(e, ctx)
  if ctx.unk18 == 0 then ctx.unk18 = 1; C[0x74](e, ctx) end
  moveTowards(e, ctx)
  if ctx.condition == 0 then stay() end
end
C[0x75] = function(e, ctx) moveTowards(e, ctx) end
C[0x76] = function(e, ctx, host)
  if ctx.unk18 == 0 then ctx.unk18 = 1; lookAt(e, ctx, host.player.x, host.player.y) end
  moveTowards(e, ctx)
  if ctx.condition == 0 then stay() end
end
C[0x77] = function(e, ctx)
  if ctx.unk18 == 0 then ctx.unk18 = 1; lookAt(e, ctx, e.x + sarg(ctx, 1), e.y + sarg(ctx, 2)) end
  moveTowards(e, ctx)
  if ctx.condition == 0 then stay() end
end
C[0x78] = function(e, ctx)
  -- a hop: z velocity, then gravity until landing
  if ctx.unk18 == 0 then
    ctx.unk18 = 1
    e.zVelocity = sarg(ctx, 1) * 256
    ctx.gravity = arg(ctx, 2) * 256
  end
  e.zVelocity = (e.zVelocity or 0) - (ctx.gravity or 0x2000)
  e.z = (e.z or 0) - (e.zVelocity or 0) / 65536
  if e.z >= 0 then e.z = 0; return end
  stay()
end
C[0x79] = function(e, ctx) ctx.postScriptActions = bor(ctx.postScriptActions, lshift(1, arg(ctx, 1))) end
C[0x7A] = C[0x79]
C[0x7B] = function(e, ctx, host) host:sound(arg(ctx, 1)) end
C[0x7C] = function(e, ctx, host)
  local s = arg(ctx, 1)
  host:bgm(s >= 100 and "area" or s)
end
C[0x7D] = function(e, ctx, host) host:sound(word(ctx)) end
C[0x7E] = function(e, ctx, host) host:bgm(nil) end
C[0x7F] = function(e, ctx, host) host:modStat("rupees", sarg(ctx, 1)) end
C[0x80] = function(e, ctx, host) host:modStat("health", sarg(ctx, 1)) end
C[0x81] = function(e, ctx, host)
  local s = host.save.stats
  s.maxHealth = math.min(s.maxHealth + 8, 0xA0)
  s.health = s.maxHealth
end
-- GivePlayerItem: ITEM_SHELLS ($3F) takes its amount from intVariable
C[0x82] = function(e, ctx, host) host:giveItem(arg(ctx, 1), arg(ctx, 1) == 0x3F and ctx.intVariable or 0) end
C[0x83] = function(e, ctx, host) host:giveItem(0x5C, arg(ctx, 1)) end
C[0x84] = function(e, ctx, host)
  ctx.intVariable = host:inventory(arg(ctx, 1))
  ctx.condition = ctx.intVariable ~= 0 and 1 or 0
end
C[0x85] = function(e, ctx, host) host:setInventory(arg(ctx, 1), arg(ctx, 2)) end
C[0x86] = function(e, ctx, host) host:giveItem(arg(ctx, 1), 0) end
C[0x87] = function(e, ctx, host) host.cameraTarget = e end
C[0x88] = function(e, ctx, host) host.cameraTarget = nil end
C[0x89] = function(e, ctx, host) host.scrollSpeed = math.max(1, band(arg(ctx, 1), 7)) end
C[0x8A] = function(e, ctx, host) if host.shake then host:shake(arg(ctx, 1), arg(ctx, 2)) end end

-- ---------------------------------------------------------------------------
-- one frame of a script (ExecuteScript); returns false once it has ended
-- ---------------------------------------------------------------------------
local MAX_STEPS = 256

function Script:run(entity, host)
  if self.stopped or not self.ip then return false end
  if self.wait > 0 then
    self.wait = self.wait - 1
    return true
  end
  active.flags = 0
  local steps = 0
  repeat
    local cmd = self.mem:u16(self.ip)
    if cmd == 0xFFFF or not self.mem:valid(self.ip) then
      self.stopped = true
      return false
    end
    active.commandSize = rshift(cmd, 10)
    active.commandIndex = band(cmd, 0x3FF)
    local last = self.ip
    active.flags = band(active.flags, bnot(1))
    local fn = C[active.commandIndex]
    if fn then
      fn(entity, self, host)
    else
      self.unknown[active.commandIndex] = true
      keepGoing()
    end
    if active.commandSize == 0 and fn == nil then active.commandSize = 1 end
    self.ip = self.ip + 2 * active.commandSize
    if last ~= self.ip then self.unk18 = 0 end
    steps = steps + 1
    if steps > MAX_STEPS then break end -- a runaway loop must not hang a frame
  until band(active.flags, 3) == 0
  return true
end

-- HandlePostScriptActions (the bits a script asked for this frame)
function Script:postActions(e)
  local a = self.postScriptActions
  if a == 0 then return end
  self.postScriptActions = 0
  if band(a, 1) ~= 0 then e.field80 = 0 end
  if band(a, 2) ~= 0 then e.field80 = 4 end
  if band(a, 0x40) ~= 0 then e.deleted = true end
  if band(a, 0x80) ~= 0 then e.hidden = false end
  if band(a, 0x100) ~= 0 then e.hidden = true end
  if band(a, 0x200) ~= 0 then e.field82 = 0 end
  if band(a, 0x400) ~= 0 then e.field82 = bor(e.field82 or 0, 2) end
  if band(a, 0x800) ~= 0 then e.field82 = band(e.field82 or 0, bnot(2)) end
  if band(a, 0x1000) ~= 0 then e.field82 = band(e.field82 or 0, bnot(1)) end
  if band(a, 0x2000) ~= 0 then e.field82 = bor(e.field82 or 0, 1) end
  if band(a, 0x4000) ~= 0 then e.field82 = bor(e.field82 or 0, 8) end
  if band(a, 0x10) ~= 0 then e.bubble = "!" end
  if band(a, 0x20) ~= 0 then e.bubble = "?" end
end

-- the NPC's animation index (sub_0807DE80): below 8 it is a base plus the
-- facing, at 8 and up a literal animation
function Script.npcAnimIndex(e)
  local base = e.field80 or 0
  if base < 8 then
    return band(base, 0xFC) + rshift(e.animationState or 4, 1)
  end
  return base
end

return Script
