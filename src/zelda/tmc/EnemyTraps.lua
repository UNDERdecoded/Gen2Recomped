-- Round 17: enemies that were blank because their own code draws / moves
-- them: BLADE_TRAP ($2F), SENSOR_BLADE_TRAP ($1F), WALL_MASTER ($1A) /
-- WALL_MASTER_2 ($23), TORCH_TRAP ($49).  Enemies.lua dispatches here.
--
-- CARTRIDGE BEHAVIOUR (ported)
--   * An entity's room data (EntityData, 16 bytes) is copied to +$78
--     (RegisterRoomEntity): +$84 / +$86 are the entry's last two halfwords
--     (the port's paramC low / high).  None of these set an animation: a
--     zeroed entity shows frameIndex 0 (the definition's draw bit decides).
--   * BLADE_TRAP (bladeTrap.c): its rail is room property [type]
--     (GetCurrentRoomProperty), u16 triplets {direction, frames, speed};
--     $FE jumps back ptr[1] entries, $FF stops (UpdateRailMovement).  It
--     moves by LinearMoveUpdate (no collision); each leg's end plays
--     SFX_METAL_CLINK when it was moving.
--   * SENSOR_BLADE_TRAP (sensorBladeTrap.c): speed gUnk_080CD3D4[type]
--     ($100 / $180 / $200 / $280), ranges x = +$84, y = +$86; action 1
--     waits for Link in line (sub_0804A024(1, $E): Link's hitbox centre
--     within 7 px of its axis, the tiles between clear), not when the next
--     tile that way is solid (gUnk_080CD3DC: 12 px); action 2 rushes until
--     the range or a wall, then SFX_METAL_CLINK and back at $C0 (action 3)
--     until it stops against its start (ProcessMovement12 fails).
--   * WALL_MASTER (wallMaster.c): hidden (draw 0, collision off) for
--     type2 * 60 frames of Link in the room (sub_0802A78C), then it appears
--     over Link at z -$80 with animation 2 and a shadow, falls after 90
--     frames (+3 a frame, SFX_12D, animation 0), lands (animation 1, hit
--     type $75 on the keyframe), waits, rises (-2 a frame) out of sight and
--     starts over after timer * 60 frames.  Its affine size breathes by
--     gUnk_080CD0B0 (sub_0802A7D0).  Touching Link while down grabs him
--     (action 5: animation 1, Link held and hidden, then action 6: up 2 a
--     frame for 30 frames and DoExitTransition(gWallMasterScreenTransitions
--     [dungeon])).
--   * TORCH_TRAP (torchTrap.c): never drawn (no animation, its definition
--     does not draw) -- only its TORCH_TRAP_PROJECTILE is seen.  Blank on
--     the cartridge too.
--   * CUCCO_CHICK_AGGR ($0C, cuccoChickAggr.c): action 1 waits (R & $F) + 8
--     frames (frame 0); action 2 hops (R & 3) + 1 times at $80 -- toward
--     home when outside it (3 in 4), else direction R >> 16 & $1F --
--     zVelocity 1.0, gravity 32/256, frame 1 in the air, SFX_VO_CHEEP; on
--     the ground with Link (full size) within 36 px: action 3, three quick
--     hops in place (gravity 40/256), then action 4: six hops at him at
--     $C0 (zVelocity 0.75, facing him each hop).
--   * MOLDORM ($0D, moldorm.c): the head (type 0) makes three tail parts
--     (types 1-3); every 4 frames it turns by unk_78 (+-1, re-rolled each
--     8 turns from gUnk_080CBBC4), steering home when outside its home
--     rectangle, moves by ProcessMovement0 and bounces off walls
--     (sub_0800417E); frame = animationState = ((dir + 2) & $1C) >> 2.
--     Each tail part replays the part before it 8 frames late (the 8-entry
--     delta ring of sub_08022EAC / sub_08022E40); frames 8 / 9 for parts 1 /
--     2, 10 + animationState for the tip.  Hit, it spins its frame for 30
--     frames (unk_7b).
-- Round 19: the Wall Master's grab uses gWallMasterScreenTransitions for
-- Deepwood Shrine and the Cave of Flames (decomp data, see action 6); other
-- areas still go to the port's field.entry.  TORCH_TRAP_PROJECTILE is not
-- ported (the trap does not fire).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local T = {}
T.BLADE_TRAP, T.SENSOR_BLADE_TRAP, T.WALL_MASTER, T.WALL_MASTER_2, T.TORCH_TRAP = 0x2F, 0x1F, 0x1A, 0x23, 0x49
T.CUCCO_CHICK_AGGR, T.MOLDORM = 0x0C, 0x0D
local SFX_VO_CHEEP = 0xD6
local SFX_METAL_CLINK, SFX_12D = 0x74, 0x12D
local SENSOR_SPEED = { [0] = 0x100, 0x180, 0x200, 0x280 }
local SENSOR_PROBE = { [0] = { 0, -12 }, { 12, 0 }, { 0, 12 }, { -12, 0 } }
local BREATHE = { [0] = -2, -4, -2, 0, 2, 4, 2, 0 }

function T.handles(e)
  local id = e.id
  return id == T.BLADE_TRAP or id == T.SENSOR_BLADE_TRAP or id == T.WALL_MASTER or id == T.WALL_MASTER_2 or id == T.TORCH_TRAP
      or id == T.CUCCO_CHICK_AGGR or id == T.MOLDORM
end

local function dirVec(d) local a = (d % 32) / 32 * 2 * math.pi return math.sin(a), -math.cos(a) end

-- the rail data at room property k (u16 triplets in the entity region)
local function rail(f, k)
  local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
  local addr = props and props[k]
  if not addr then return nil end
  local A = f.assets
  local reg = A.manifest.entityRegion
  if not reg then return nil end
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  local o = addr - reg.base
  if o < 0 or o + 6 > #A.entityBlob then return nil end
  return { blob = A.entityBlob, o = o, u16 = A.u16 }
end

-- UpdateRailMovement
local function railNext(e)
  local r = e.rail
  if not r then e.direction, e.speed, e.legT = 0x80, 0, 0x7FFFFFFF return end
  local v = r.u16(r.blob, r.o)
  if v == 0xFE then r.o = r.o - r.u16(r.blob, r.o + 2) * 6; v = r.u16(r.blob, r.o) end
  if v == 0xFF then e.direction, e.speed = 0x80, 0
  else e.direction, e.speed = band(v, 0xFF), r.u16(r.blob, r.o + 4) end
  e.legT = r.u16(r.blob, r.o + 2)
  r.o = r.o + 6
end

function T.init(E, e, dat)
  if not T.handles(e) then return end
  e.staticFrame = 0
  e.rawY = dat.y
  e.p84, e.p86 = band(dat.paramC or 0, 0xFFFF), rshift(dat.paramC or 0, 16)
  e.trapType = dat.paramA or 0
  e.timerByte = band(rshift(dat.paramB or 0, 8), 0xFF)
  e.type2 = band(dat.paramB or 0, 0xFF)
  if e.id == T.TORCH_TRAP then e.hidden = true; e.inertTrap = true end
  if e.id == T.WALL_MASTER or e.id == T.WALL_MASTER_2 then e.hidden = true; e.noTouch = true; e.staticFrame = nil end
  if e.id == T.MOLDORM and (dat.paramA or 0) ~= 0 then e.moldTail = true end
end

-- ProcessMovement12-like: move with tile collision; false when blocked
local function moveSolid(E, e, dir, speed)
  local vx, vy = dirVec(dir)
  local s = speed / 256
  local nx, ny = e.x + vx * s, e.y + vy * s
  local hb = e.hitbox
  local hw, hh = math.max(2, hb.w), math.max(2, hb.h)
  local room = E.field.room
  local cx, cy = nx + (hb.x or 0), ny + (hb.y or 0)
  if room:isSolid(cx - hw, cy - hh) or room:isSolid(cx + hw - 1, cy - hh) or room:isSolid(cx - hw, cy + hh - 1) or room:isSolid(cx + hw - 1, cy + hh - 1) then
    return false
  end
  e.x, e.y = nx, ny
  return true
end

-- sub_0804A024(1, $E): the way to Link when he is in line and in sight
local function sensor(E, e)
  local f = E.field
  local p = f.player
  if p.minish or p.state == "dead" or p.state == "portal" or (p.z or 0) > 0 then return nil end
  local px, py = p.x, p.y - 3
  local dx, dy = math.floor(px) - math.floor(e.x + (e.hitbox.x or 0)), math.floor(py) - math.floor(e.y + (e.hitbox.y or 0))
  local alignX = dx + 7 >= 0 and dx + 7 <= 14   -- same column
  local alignY = dy + 7 >= 0 and dy + 7 <= 14   -- same row
  local function clear(tx, ty)
    local sx, sy = (tx == e.x) and 0 or (tx > e.x and 1 or -1), (ty == e.y) and 0 or (ty > e.y and 1 or -1)
    local n = math.floor(math.max(math.abs(tx - e.x), math.abs(ty - e.y)) / 8)
    for i = 1, n do
      if f.room:isSolid(e.x + sx * i * 8, e.y + sy * i * 8, p.layer or 1) then return false end
    end
    return true
  end
  local function vert() if clear(e.x, py) then return (py > e.y) and 16 or 0 end end
  local function horiz() if clear(px, e.y) then return (px > e.x) and 8 or 24 end end
  local r
  if math.abs(dx) < math.abs(dy) then
    if alignX then r = vert() end
    if not r and alignY then r = horiz() end
  else
    if alignY then r = horiz() end
    if not r and alignX then r = vert() end
  end
  return r
end

local function blade(E, e)
  local f = E.field
  if e.action == 0 then
    e.action = 1
    e.rail = rail(f, e.trapType)
    railNext(e)
  end
  if band(e.direction or 0x80, 0x80) == 0 then
    local vx, vy = dirVec(e.direction)
    e.x, e.y = e.x + vx * e.speed / 256, e.y + vy * e.speed / 256
  end
  e.legT = (e.legT or 1) - 1
  if e.legT == 0 then
    if band(e.direction or 0x80, 0x80) == 0 then f:sound(SFX_METAL_CLINK) end
    railNext(e)
  end
end

local function sensorBlade(E, e)
  local f = E.field
  if e.action == 0 then
    e.action = 1
    e.rushSpeed = SENSOR_SPEED[band(e.trapType, 3)]
    e.rangeX, e.rangeY = e.p84, e.p86
  elseif e.action == 1 then
    local d = sensor(E, e)
    if not d then return end
    local pr = SENSOR_PROBE[rshift(d, 3)]
    if f.room:isSolid(e.x + pr[1], e.y + pr[2], 1) then return end
    e.action, e.speed, e.direction = 2, e.rushSpeed, d
    local q = rshift(d, 3)
    if q == 0 then e.stopAt = e.y - e.rangeY elseif q == 1 then e.stopAt = e.x + e.rangeX
    elseif q == 2 then e.stopAt = e.y + e.rangeY else e.stopAt = e.x - e.rangeX end
  elseif e.action == 2 then
    local back = false
    if not moveSolid(E, e, e.direction, e.speed) then back = true
    else
      local q = rshift(e.direction, 3)
      if q == 0 then back = e.stopAt >= math.floor(e.y) elseif q == 1 then back = e.stopAt <= math.floor(e.x)
      elseif q == 2 then back = e.stopAt <= math.floor(e.y) else back = e.stopAt >= math.floor(e.x) end
    end
    if back then
      e.action, e.speed, e.direction = 3, 0xC0, bit.bxor(e.direction, 16)
      f:sound(SFX_METAL_CLINK)
    end
  elseif e.action == 3 then
    if not moveSolid(E, e, e.direction, e.speed) then e.action = 1 end
  end
end

local function wallMaster(E, e)
  local f = E.field
  local p = f.player
  e.breathe = (e.breathe or math.random(0, 255)) + 1
  local s = BREATHE[band(rshift(e.breathe, 3), 7)] + 0x100
  e.affine = { s = 256 / s, r = 0 }
  if e.action == 0 then
    e.action = 1
    e.waitIn = e.type2 * 60
    e.waitOut = e.timerByte * 60
    e.noTouch, e.hidden = true, true
    return
  end
  -- sub_0802A78C: Link must stay in the room type2 * 60 frames
  if e.action == 1 then
    if e.waitOut > 0 then e.waitOut = e.waitOut - 1
    elseif e.waitIn > 0 then e.waitIn = e.waitIn - 1
    elseif not p.minish and p.state ~= "dead" then
      e.action, e.timer = 2, 90
      e.noTouch, e.hidden = false, false
      e.x, e.y, e.z = p.x, p.y, 0x80
      E:setAnim(e, 2)
    end
  elseif e.action == 2 then
    if e.timer > 0 then
      e.timer = e.timer - 1
      if e.timer == 0 then f:sound(SFX_12D); E:setAnim(e, 0) end
    else
      e.z = e.z - 3
      if e.z <= 0 then e.z = 0; e.action = 3; E:setAnim(e, 1) end
    end
  elseif e.action == 3 then
    e.anim:update(1)
    if e.anim.done then e.action, e.timer = 4, 30 end
  elseif e.action == 4 then
    e.z = e.z + 2
    if e.z > 0xA0 then
      e.action = 1
      e.noTouch, e.hidden = true, true
      e.waitOut = e.timerByte * 60
      e.waitIn = e.type2 * 60
    end
  elseif e.action == 5 then
    -- the grab: Link held under it, hidden once the hand closes
    p.x, p.y = e.grabX, e.grabY
    p.state = "ext"; p.extUpdate = function() end
    e.anim:update(1)
    if e.anim.frame and band(e.anim.flags or 0, 1) ~= 0 then p.hidden = true end
    if e.anim.done then e.action, e.timer = 6, 30; p.hidden = true end
  elseif e.action == 6 then
    e.z = e.z + 2
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.action = 7
      p.hidden = nil; p.state = "normal"; p.extUpdate = nil
      -- round 19: DoExitTransition(gWallMasterScreenTransitions[dungeon_idx])
      -- (data/screenTransitions.c): Deepwood Shrine -> its entrance room
      -- ($0B) at ($A8, $B8), the Cave of Flames -> its main cart room ($04)
      -- at ($98, $A8); type 2, facing 0.  Other areas keep field.entry.
      local WM = { [0x48] = { 0x48, 0x0B, 0xA8, 0xB8 }, [0x49] = { 0x48, 0x0B, 0xA8, 0xB8 },
                   [0x50] = { 0x50, 0x04, 0x98, 0xA8 }, [0x51] = { 0x50, 0x04, 0x98, 0xA8 } }
      local wm = WM[f.room.area]
      if wm then
        f:startTransition({ warpType = 1, area = wm[1], room = wm[2], endX = wm[3], endY = wm[4], facing = 0, kind = 2 })
      else
        local to = f.entry or {}
        f:startTransition({ warpType = 1, area = to.area or f.room.area, room = to.room or f.room.room,
                            endX = to.x or p.x, endY = to.y or p.y, facing = to.facing or 4, kind = 0 })
      end
    end
  end
  if e.action ~= 3 and e.action ~= 5 then e.anim:update(1) end
  -- the grab (WallMaster_OnCollision): Link touched while it is down
  if (e.action == 3 or e.action == 4) and e.z <= 8 and not p.minish and p.state ~= "dead" and (p.invuln or 0) == 0 then
    if math.abs(p.x - e.x) < e.hitbox.w + 6 and math.abs((p.y - 3) - (e.y + (e.hitbox.y or 0))) < e.hitbox.h + 6 then
      e.action = 5
      e.grabX, e.grabY = p.x, p.y
      e.noTouch = true
      E:setAnim(e, 1)
      e.anim:set(E.A:sprite(e.sprite), 1, true)
    end
  end
end

local function rnd() return math.random(0, 0xFFFF) end
local function towardHome(E, e)
  local hx, hy = e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2
  local a = math.atan2(hx - e.x, -(hy - e.y))
  return band(math.floor(a / (2 * math.pi) * 32 + 0.5), 31)
end
local function gravity(e, g)
  e.z = e.z + e.zv; e.zv = e.zv - g
  if e.z <= 0 then e.z, e.zv = 0, 0 return false end
  return true
end

local function chick(E, e)
  local f, p = E.field, E.field.player
  local function near() return not p.minish and p.state ~= "dead" and math.abs(p.x - e.x) <= 36 and math.abs(p.y - e.y) <= 36 end
  local function face(dir) if band(dir, 0xF) ~= 0 then e.flipX = band(rshift(dir, 4), 1) == 0 end end
  local function atLink()
    e.zv = 0.75
    local a = math.atan2(p.x - e.x, -(p.y - e.y))
    e.direction = band(math.floor(a / (2 * math.pi) * 32 + 0.5), 31)
    face(e.direction)
    f:sound(SFX_VO_CHEEP)
  end
  local function rest() e.action = 1; e.timer = band(rnd(), 0xF) + 8; e.staticFrame = 0 end
  e.zv = e.zv or 0
  if e.action == 0 then rest()
  elseif e.action == 1 then
    e.timer = e.timer - 1
    if e.timer <= 0 then
      local r = rnd()
      e.action, e.timer, e.subtimer, e.speed = 2, band(r, 3) + 1, 1, 0x80
      if not E:inHome(e, e.x, e.y) and band(rshift(r, 8), 3) ~= 0 then e.direction = towardHome(E, e)
      else e.direction = band(rnd(), 0x1F) end
      face(e.direction)
    end
  elseif e.action == 2 then
    if e.z == 0 and near() then e.action, e.timer, e.subtimer = 3, 3, 8; atLink() return end
    if e.subtimer > 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer > 0 then return end
      e.staticFrame = 1; e.zv = 1.0; f:sound(SFX_VO_CHEEP)
    end
    E:move(e, e.direction, e.speed)
    if not gravity(e, 0.125) then
      e.timer = e.timer - 1
      if e.timer <= 0 then rest() else e.subtimer, e.staticFrame = 4, 0 end
    end
  elseif e.action == 3 then
    if not gravity(e, 40 / 256) then
      e.timer = e.timer - 1
      if e.timer <= 0 then e.action, e.timer, e.subtimer, e.staticFrame, e.speed = 4, 6, 8, 0, 0xC0; atLink()
      else e.zv = 1.0; f:sound(SFX_VO_CHEEP) end
    end
  elseif e.action == 4 then
    if e.subtimer > 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer > 0 then return end
      e.staticFrame = 1
    end
    E:move(e, e.direction, e.speed)
    if not gravity(e, 0.125) then
      e.timer = e.timer - 1
      if e.timer <= 0 then rest() else atLink() end
    end
  end
end

local TURN = { [0] = 1, -1 }
local function moldorm(E, e)
  local f = E.field
  if e.moldTail then return end -- the head moves its parts
  if e.action == 0 then
    e.action, e.timer, e.subtimer = 1, 1, 1
    e.direction = band(rnd(), 0x1F)
    e.turn = 1
    e.hist = {}
    e.lastHealth = e.health
    e.moldParts = e.moldParts or {}
    -- the three tail parts (types 1-3), drawn under the head
    for t = 1, 3 do
      local d = E:def(T.MOLDORM, t) or e.def
      local part = { kind = 3, id = T.MOLDORM, form = t, x = e.x, y = e.y, z = 0, enemy = true, moldTail = true, moldHead = e,
                     sprite = d.sprite or e.sprite, palette = E.A:objPalette(d.palette or 0, f.room.atlas and f.room.atlas.palettes),
                     gfx = require("src.zelda.tmc.Assets").gfxSource("enemy", d.gfx), anim = require("src.zelda.tmc.Anim").new(),
                     hitType = d.damageType or e.hitType, hitbox = d.hitbox or { x = 0, y = 0, w = 4, h = 4 }, def = d,
                     health = 0xFF, iframes = 0, kbt = 0, action = 1, timer = 0, literalAnim = true, field82 = 0, interactType = 0,
                     spritePriority = 5, staticFrame = (t == 3) and 10 or (t + 7) }
      e.moldParts[t] = part
      f.entities[#f.entities + 1] = part
    end
  end
  local function st() return rshift(band(e.direction + 2, 0x1C), 2) end
  if e.health ~= e.lastHealth then e.spin = 30 end
  e.lastHealth = e.health
  if e.spin and e.spin > 0 then
    if band(e.spin, 1) == 1 then e.animState = band((e.animState or st()) + 1, 7) end
    e.spin = e.spin - 1
  else
    -- sub_08022F14
    if not E:inHome(e, e.x, e.y) then
      local b = band(towardHome(E, e) - e.direction, 0x1F)
      if band(b + 4, 0x1F) > 8 then e.subtimer = 8; e.turn = (b < 0x10) and 1 or -1 end
    end
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.timer = 4
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then e.subtimer = 8; e.turn = TURN[band(rnd(), 1)] end
      e.direction = band(e.direction + e.turn, 0x1F)
    end
    if not E:move(e, e.direction, e.speed) then
      -- sub_0800417E: bounce off the wall
      local vx = dirVec(e.direction)
      local hb = e.hitbox
      local blockedX = f.room:isSolid(e.x + (vx > 0 and 1 or -1) * (hb.w + 1), e.y, 1)
      if blockedX then e.direction = band(32 - e.direction, 0x1F) else e.direction = band(16 - e.direction, 0x1F) end
    end
    e.animState = st()
  end
  e.staticFrame = e.animState
  -- the tail: each part 8 frames behind the one before it
  table.insert(e.hist, 1, { e.x, e.y, e.animState })
  if #e.hist > 25 then e.hist[#e.hist] = nil end
  for t = 1, 3 do
    local part = e.moldParts[t]
    local h = e.hist[math.min(#e.hist, 8 * t + 1)]
    if part and not part.deleted and h then
      part.x, part.y = h[1], h[2]
      if t == 3 then part.staticFrame = 10 + h[3] end
      if e.deleted or e.dying then part.deleted = true end
    end
  end
end

function T.update(E, e)
  if e.id == T.BLADE_TRAP then blade(E, e)
  elseif e.id == T.SENSOR_BLADE_TRAP then sensorBlade(E, e)
  elseif e.id == T.WALL_MASTER or e.id == T.WALL_MASTER_2 then wallMaster(E, e)
  elseif e.id == T.CUCCO_CHICK_AGGR then chick(E, e)
  elseif e.id == T.MOLDORM then moldorm(E, e)
  end
end

return T
