-- Round 73: TORCH_TRAP ($49, src/enemy/torchTrap.c) and TORCH_TRAP_PROJECTILE ($16, src/projectile/
-- torchTrapProjectile.c).  Round 17 left the trap inert ("the trap does not fire"); the Royal Crypt's torch room
-- $68:01 has four: once its four torches are lit (room flags 0 .. 3, the FIGHT_MANAGER's start flag) they fire at
-- Link until the fight's flag (local $19) is set, then their torches go out.
--
-- CARTRIDGE BEHAVIOUR (ported).  The EntityData copy at +$78 gives: flag1 (+$7C) = the type2 field's low half,
-- flag2 (+$80) = xPos, unk_82 = yPos, unk_84 = the spritePtr field's low half.
--   * Init: speed = (unk_84 & $F000) >> 5; tilePos = unk_82 & $FFF; x, y = that tile's centre; direction =
--     ((s16)unk_82 & $F000) >> 10; unk_78 = type << 2; sub_0803CFF0 -> sub_0803D0B0.  Action 1.
--   * sub_0803CFF0: flag2 == 0 -> false; flag2 == flag1 -> !CheckFlags(flag2); else CheckFlags(flag2).
--   * sub_0803D0B0: action 3, TILE_TYPE_117 (the unlit torch) at tilePos.
--   * Action 1: flag1 == 0 or CheckFlags(flag1) -> TorchTrap_Reset.
--   * Action 2: sub_0803CFF0 -> sub_0803D0B0; else Link in its home rectangle and not within $20 px:
--     --projectileTimer == 0 -> the projectile, TorchTrap_Reset.
--   * Action 3: TILE_TYPE_118 (lit) at tilePos -> flag2 = 0, Reset; else flag1 and CheckFlags(flag1) -> Reset.
--   * TorchTrap_Reset: action 2, projectileTimer = unk_78, or gTorchTrapTimerLengths[Random & 7] when 0.
--   * The projectile: speed = the trap's speed, else gTorchTrapProjectileSpeeds[Random & 3]; direction = facing
--     Link when the trap's direction has bit $20, else that direction.  Init: timer 30, animation 0.  Action 1:
--     GetNextFrame; the timer runs out, then ProcessMovement3 -- free -> LinearMoveUpdate, else action 2.
--     Action 2: ProcessMovement3; a collision or off screen -> gone.  OnCollision (it touched Link) -> gone.
-- The two tables are read from the player's ROM (RomTables "TorchTrap73.TIMERS" / ".SPEEDS").
-- SIMPLIFIED: ProcessMovement3's tile collision is the projectile's centre on its layer.
local bit = require("bit")
local band, rshift, arshift = bit.band, bit.rshift, bit.arshift

local M = {}

M.PROJ_ID = 0x16
M.TILE_TYPE_117, M.TILE_TYPE_118 = 117, 118
local function tables()
  if M.TIMERS == nil then
    local RT = require("src.zelda.tmc.RomTables")
    local ok1, t1 = pcall(RT.t, "TorchTrap73.TIMERS")
    local ok2, t2 = pcall(RT.t, "TorchTrap73.SPEEDS")
    M.TIMERS, M.SPEEDS = ok1 and t1 or false, ok2 and t2 or false
  end
  return M.TIMERS, M.SPEEDS
end

local function rnd(f)
  if M.random then return M.random() end -- tests
  local D = require("src.zelda.tmc.Drops")
  return D.random(D.rngOf(f))
end

local function check(f, spec) return f:dungeon():check(spec) end

local function unlitWanted(f, e) -- sub_0803CFF0
  if (e.flag2 or 0) == 0 then return false end
  if e.flag2 == e.flag1 then return not check(f, e.flag2) end
  return check(f, e.flag2)
end

local function setTile(f, e, t)
  local O = f:objects()
  if O and O.setTileType then O:setTileType(e.layer == 2 and 2 or 1, band(e.tilePos, 0x3F), rshift(band(e.tilePos, 0xFC0), 6), t) end
end

local function goUnlit(f, e) e.action = 3; setTile(f, e, M.TILE_TYPE_117) end -- sub_0803D0B0

local function reset(f, e) -- TorchTrap_Reset
  e.action = 2
  if (e.unk78 or 0) ~= 0 then e.ptimer = e.unk78
  else
    local T = tables()
    e.ptimer = (T and T[band(rnd(f), 7)]) or 60
  end
end
M.reset = reset

function M.init(f, e)
  local u82 = band(e.rawY or 0, 0xFFFF)
  local u84 = e.p84 or 0
  e.flag2x = e.flag2x or math.floor(e.x or 0) -- flag2 = the EntityData xPos (before x is set from the tile)
  e.tspeed = rshift(band(u84, 0xF000), 5)
  e.u84 = band(u84, 0xFFF)
  e.action = 1
  e.tilePos = band(u82, 0xFFF)
  e.x = band(u82, 0x3F) * 16 + 8
  e.y = rshift(band(u82, 0xFC0), 2) + 8
  local s16 = u82 >= 0x8000 and u82 - 0x10000 or u82
  e.tdir = band(arshift(band(s16, -4096), 10), 0xFF) -- ((s16)unk_82 & $F000) >> 10, kept in a u8
  e.unk78 = (e.trapType or 0) * 4
  e.flag1 = (e.timerByte or 0) * 256 + (e.type2 or 0)
  e.flag2 = e.flag2x or 0
  e.hidden = true
  if unlitWanted(f, e) then goUnlit(f, e) end
end

local function inHome(e, t)
  if not e.homeX or not e.rangeW or e.rangeW == 0 then return true end
  local dx, dy = math.floor(t.x) - e.homeX, math.floor(t.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH
end

local function facing(e, t) -- GetFacingDirection: 0 .. $1F
  local a = math.atan2(t.x - e.x, -(t.y - e.y))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end

local function fire(E, e)
  local f = E.field
  local p = f.player
  local c = require("src.zelda.tmc.EnemyPoW")._child(E, e, M.PROJ_ID, { torch73 = true, hidden = false })
  if not c then return end
  local _, S = tables()
  c.speed = (e.tspeed ~= 0) and e.tspeed or ((S and S[band(rnd(f), 3)]) or 0x100)
  c.dir = (band(e.tdir or 0, 0x20) ~= 0) and facing(e, p) or band(e.tdir or 0, 0x1F)
  c.action = 0
  return c
end
M.fire = fire

function M.update(E, e)
  local f = E.field
  if not e.ttInit then e.ttInit = true; M.init(f, e) return end
  local a = e.action
  if a == 1 then
    if (e.flag1 or 0) == 0 or check(f, e.flag1) then reset(f, e) end
  elseif a == 2 then
    if unlitWanted(f, e) then goUnlit(f, e)
    else
      local p = f.player
      local dx, dy = p.x - e.x, p.y - e.y
      if inHome(e, p) and (dx * dx + dy * dy) >= 0x20 * 0x20 then
        e.ptimer = (e.ptimer or 1) - 1
        if e.ptimer <= 0 then fire(E, e); reset(f, e) end
      end
    end
  elseif a == 3 then
    local r = f.room
    local tt = r:tileType(e.layer == 2 and 2 or 1, band(e.tilePos, 0x3F), rshift(band(e.tilePos, 0xFC0), 6))
    if tt == M.TILE_TYPE_118 then e.flag2 = 0; reset(f, e)
    elseif (e.flag1 or 0) ~= 0 and check(f, e.flag1) then reset(f, e) end
  end
end

local function step(f, c, spd) -- LinearMoveUpdate (direction 0 .. $1F, speed Q8)
  local ang = (c.dir or 0) / 32 * 2 * math.pi
  c.x = c.x + math.sin(ang) * spd / 256
  c.y = c.y - math.cos(ang) * spd / 256
end
local function blocked(f, c) return f.room:isSolid(c.x, c.y, c.layer == 2 and 2 or 1) end
local function offScreen(f, c) return not require("src.zelda.tmc.EnemyPoW")._h.onScreen(f, c) end -- IsProjectileOffScreen

-- one line in EnemyPoW.update (powChild with torch73)
function M.projUpdate(E, c)
  local f = E.field
  if c.action == 0 then
    c.action, c.ttimer = 1, 30
    c.onCollision = function(EE, x, fl) if fl == 0x80 or fl == 0x81 then x.deleted = true end end
    c.forceAnim = 0
  end
  if c.anim then c.anim:update(1) end
  if c.action == 1 then
    if c.ttimer > 0 then c.ttimer = c.ttimer - 1
    else
      step(f, c, c.speed)
      if not blocked(f, c) then step(f, c, c.speed) else c.action = 2 end
    end
  else
    step(f, c, c.speed)
    if blocked(f, c) or offScreen(f, c) then c.deleted = true end
  end
end

return M
