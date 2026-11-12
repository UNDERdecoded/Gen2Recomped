-- Round 26 (team B): Fortress of Winds (areas $58 / $59) objects, managers
-- and room projectiles, ported from the decomp (dispatched by R26.lua).
--
-- EYE_SWITCH $23 (src/object/eyeSwitch.c): Init: animationState = type & 3,
--   spritePriority 6, hurtType $48, hitType 1, gHitbox_1 (6x6); fields
--   $84 / $86 (EntityData paramC low / high) = eyeSwitchFlags / Flags2.
--   Flags already set -> action 3, animation state + 4 (open); else action 1,
--   animation state (shut).  Action1: contactFlags $95 or $8E (an arrow,
--   hurtType $15, or a charged arrow $0E) whose DirectionRoundUp(direction)
--   >> 3 is the eye's state -> action 2, COLLISION_OFF, SFX_111, SetFlag
--   (Flags2).  Action2: GetNextFrame to ANIM_DONE -> action 3, unk70 = timer
--   (EntityData paramB >> 8) * 2, animation state + 4.  Action3 (timer != 0
--   only): Flags2 != Flags and Flags set -> timer 0 (stays open); else unk70
--   runs out -> action 4, ClearFlag(Flags2).  Action4: GetNextFrame to
--   ANIM_DONE -> action 1, COLLISION_ON, animation state.  The sword does
--   not open it (only those two contact values do).  The Bow is another
--   team's item: arrows reach it through M.arrowHit(f, x, y, hurtType,
--   direction[, w, h]).
-- FLOATING_PLATFORM $16 (src/object/floatingPlatform.c): Init: speed $100,
--   frameIndex = type, spritePriority 7, the rail = room property type2
--   (UpdateRailMovement: {direction, frames, speed} legs, $FE loops, $FF
--   stops; CoFObjects.railNext).  Action1: sub_08086168: Link within
--   gUnk_08120658[type] (x, y radii) and PlayerCanBeMoved -> field_0x14 (the
--   pit under him does not count: Dungeon.checkFall asks M.supports), and
--   when on the ground (z 0) he is carried: SyncPlayerToPlatform moves the
--   platform (LinearMoveUpdate) and Link by the whole-pixel change on the
--   axis of its direction (with his collision).  A platform with a timer
--   only carries while its parent's timer is 0 (and bumps it).  unk70 runs
--   out -> the next rail leg.
-- MINISH_SIZED_ENTRANCE $4E (src/object/minishSizedEntrance.c): frameIndex =
--   type2 (+4 and fixed gfx $184 in a dungeon), spritePriority 7, OAM
--   priority 3.  Action1: Minish Link within 4 px, z 0, holding the
--   direction gUnk_0812225C[type2] (up, right, down, left) -> DoExitTransition
--   (room property `timer`, the EntityData paramB >> 8).  Type 1 (deleted
--   with its parent's bit) is only ever made by another object.
-- STONE_TABLET $72 (src/object/stoneTablet.c): frameIndex = type (type 3:
--   0); SetMultipleTiles gUnk_081232EC (four SPECIAL_TILE_34 at -2..+1) or,
--   type 3, gUnk_081232FE (SPECIAL_TILE_101/34/102 above, 41/38/42 on its
--   row).  Action1 does nothing.
-- BIRD $95 (src/object/bird.c):
--   types 3-7 (Bird_Type3): layer 2; each time the animation is done
--   (frame starts at $80): animation Random & 3, frameDuration (Random &
--   $F) + $10, flipX on Random & 1; else GetNextFrame.
--   type 0 (Zeffa over the Fortress top, gUnk_080E3830 from the text
--   board's script): from the camera's left edge at z -56.75, zVelocity
--   -1.5, gravity -8 (Q8.8), speed $280 east, SFX_123, animation 0; makes
--   a type 1 (the Ocarina, animation $17) 8 px below; after 49 frames the
--   Ocarina is let go (subtimer 0) and the bird leaves (deleted off screen).
--   type 1: follows (PositionRelative) until let go, then BounceUpdate(24
--   Q8.8); landed -> type 2, z 0, layer 1, local flag LV3_OCARINA_FALL,
--   SFX_SECRET, FX_DASH.  type 2 (Bird_Type2_Action1): Minish Link is pushed
--   out (sub_0800445C); full-size Link touching it -> ITEM_OCARINA (item
--   get), windcrest bit $10000000, gone.
-- FLOATING_BLOCK $AE (floatingBlock.c, the Pit room's blocks): frameIndex =
--   type, spritePriority $E (b0 = 6), layer 1.
-- MISC_MANAGER $0F (src/manager/miscManager.c; x, y = fields $38 / $3A,
--   flag1 / flag2 = paramC low / high):
--   types 1 / 2 (MiscManager_Type1, the West / East key levers): Init:
--     subAction / subtimer = 7 / 6 (type 1) or 8 / 2 (type 2); flag2 set ->
--     gone.  Action1: flag2 set -> action 2, timer 120,
--     RequestPriorityDuration(240), sub_08059064 (a GROUND_ITEM small key,
--     kind 2: it drops from z -$80 with SFX_12D, at x, y).  Action2: at 90
--     SetPlayerControl(2) + PutAwayItems, at 60 Link faces subtimer, at 0
--     MenuFadeIn(5, subAction) (the aux cutscene) -> action 3.  Then:
--     SetFlag(flag2), SetPlayerControl(1), gone.
--   type 3 (MiscManager_Type3, the Mole Mitts room, area $18 room 3 = $58
--     room 5): local flag $60 (the big chest) -> LoadRoomEntityList
--     (gUnk_080F4B88) and gone; until then local flag $5F is set (cleared
--     once $60 is).
-- ENEMY_INTERACTION_MANAGER $28 (src/manager/enemyInteractionManager.c):
--   type 0 Init: the enemies of room property type2 listed before the
--   manager's own entry (kind 9, id $28), matched to live enemies by data
--   position, id and type (8 at most); 2+ -> a type 1 manager with them.
--   Type 1: every frame drops deleted ones (gone at <= 1) and pushes each
--   pair apart (CalcCollisionStaticEntity: the second of each pair on odd
--   frames, the first on even ones; the smaller overlap axis, at most 4 px,
--   with the pushed one's tile collision).
-- WINDER projectile $1D (src/projectile/winder.c): type 0 (head) direction
--   Random & $18, speed $140, animation 0; types 0-3 make the next segment
--   (up to type 4, the tail).  Each segment keeps 8 past positions; a body
--   segment sits at the one ahead of it's oldest one.  The head:
--   ProcessMovement0, a wall on its side (COL_*_ANY) or a railing (the
--   collision value $20-$3F of the tile ahead, gUnk_080B4488) -> one of the
--   two perpendicular directions (Random & 1).  hitType $73: Link's contact
--   is CollisionFire (damage 4, knockback 12 frames at $180, iframes 30).
-- SPIKED_ROLLERS projectile $1E (src/projectile/spikedRollers.c): speed =
--   field $86 (paramC high), range = field $84 (paramC low, signed); types
--   0-6 roll east-west with their centre gSpikedRollersOffsets[type] below
--   (y), 7-13 north-south with it to the right (x); hitboxes
--   gUnk_080FD4B8.. (3 x 8n / 8n x 3); animation = type.  ProcessMovement3;
--   past the range (the decomp's unsigned compare) the direction flips, the
--   sprite flips, the position snaps to the start (or start + range).
--   hitType $66: the matrix (Link: 2 damage, knockback; the shield only
--   pushes Link back).
-- ROOM CODE (src/roomInit.c): FortressOfWindsTop_Main ($59:00):
--   SetGlobalFlag(LV3_CLEAR), UpdateGlobalProgress, the dropped Ocarina's
--   list gUnk_080E3850 when LV3_OCARINA_FALL is set and the Ocarina is not
--   owned (LoadStaticBackground(3) is the room's own BG3 manager here).
-- CLONES (button.c sub_08081D74): a BUTTON is also held by any of
--   gPlayerClones[0..2] within 5 x 6 of it.  The Four Sword clones are
--   another team's item: they are found as f.playerClones (array) or any
--   entity with e.playerClone (Dungeon.somethingOn asks M.cloneOn).
--
-- SIMPLIFIED: the aux cutscene of MiscManager types 1 / 2 (sCutsceneData 7 /
--   8: 120 frames on each of the two stairs rooms where the keys fall) is
--   not shown; RequestPriorityDuration pauses only the enemies
--   (f.enemyHold); the Winder's LINK_FIRE (Link burning) is not modelled,
--   only its damage / knockback; ProcessMovement3 of the rollers keeps
--   sub_080AF0C8's tile types ($87-$8A) but not CalculateEntityTileCollisions;
--   the shield against a roller only blocks (its push back on Link is not
--   modelled); the eye switch's arrow contact needs the Bow to call
--   M.arrowHit (ItemBow.lua's collide() only looks at enemies so far);
--   sub_080300E8 (the Armos return position of rooms $58:02 / $58:04)
--   belongs to the Armos port.
local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift
local Drops = require("src.zelda.tmc.Drops")

local M = {}
M.EYE_SWITCH, M.FLOATING_PLATFORM, M.MINISH_SIZED_ENTRANCE, M.STONE_TABLET, M.BIRD, M.FLOATING_BLOCK = 0x23, 0x16, 0x4E, 0x72, 0x95, 0xAE
M.MISC_MANAGER, M.ENEMY_INTERACTION_MANAGER = 0x0F, 0x28
M.WINDER, M.SPIKED_ROLLERS = 0x1D, 0x1E
local SFX_111, SFX_123, SFX_SECRET, SFX_12D = 0x111, 0x123, 0x72, 0x12D
local SPECIAL_FX, FX_DASH = 0x0F, 0x11
local ITEM_OCARINA, ITEM_SMALL_KEY = 0x17, 0x53
local LV3_CLEAR, LV3_OCARINA_FALL = 0x04, 0x45
local CONTACT_ARROW, CONTACT_LIGHT_ARROW = 0x80 + 0x15, 0x80 + 0x0E

M.ROM_RANGES = {
  winderTileOffsets = { 0x080B4488, 0x080B4490 }, -- gUnk_080B4488 (data_080B4410/gUnk_080B4488.bin, 4 x s16)
}

local function R(f) return Drops.random(Drops.rngOf(f)) end

-- ---------------------------------------------------------------------------
-- helpers (as CoFObjects.lua)
-- ---------------------------------------------------------------------------
local function anim(d, e, a)
  e.objAnim, e.animIndex = a, a
  if e.anim and e.sprite then e.anim:set(d.field.assets:sprite(e.sprite), a, true) end
end
local function animDone(e) return e.anim ~= nil and band(e.anim.flags or 0, 0x80) ~= 0 end
local function sfx(d, id) d.field:sound(id) end
local function dress(d, e, id, form)
  local O = d.field:objects()
  local def = O:def(id, form or 0) or O:def(id, 0)
  if def then O:dress(e, def, 0) end
  return def
end
local function isDungeon(f)
  local ok, MM = pcall(require, "src.zelda.tmc.MapMenu")
  if ok and MM.isDungeon then
    local ok2, v = pcall(MM.isDungeon, f)
    if ok2 then return v end
  end
  local a = f.room and f.room.area or 0
  return a >= 0x48 and a < 0x90
end

-- LinearMoveUpdate (8.8 speed, 32 directions)
local function linear(e)
  local dir = e.direction or 0xFF
  if band(dir, 0x80) ~= 0 or (e.speed or 0) == 0 then return end
  local a = (dir % 32) / 32 * 2 * math.pi
  e.x = e.x + math.sin(a) * e.speed / 256
  e.y = e.y - math.cos(a) * e.speed / 256
end

-- PlayerCanBeMoved
local MOVABLE = { normal = true, shield = true, gust = true }
local function playerCanBeMoved(p) return MOVABLE[p.state or "normal"] == true and not p.hidden end
M.playerCanBeMoved = playerCanBeMoved

local function inRect(a, b, rx, ry) -- EntityInRectRadius
  return math.abs(math.floor(b.x) - math.floor(a.x)) <= rx and math.abs(math.floor(b.y) - math.floor(a.y)) <= ry
end

-- ---------------------------------------------------------------------------
-- EYE_SWITCH
-- ---------------------------------------------------------------------------
local function eyeUpdate(d, e)
  local a = e.action
  if a == 2 then
    e.anim:update(1)
    if animDone(e) then
      e.action = 3
      e.unk70 = e.timer * 2
      anim(d, e, e.animationState + 4)
    end
  elseif a == 3 then
    if e.timer ~= 0 then
      if e.flag ~= e.flags and d:check(e.flags) then
        e.timer = 0
      else
        e.unk70 = e.unk70 - 1
        if e.unk70 == 0 then
          e.action = 4
          d:set(e.flag, false)
        end
      end
    end
  elseif a == 4 then
    e.anim:update(1)
    if animDone(e) then
      e.action = 1
      e.collide = true
      anim(d, e, e.animationState)
    end
  end
end

-- EyeSwitch_Action1's contact test (contactFlags = the hitter's hurtType |
-- CONTACT_NOW, its direction 0-31)
function M.eyeContact(d, e, contact, direction)
  if e.action ~= 1 or not e.collide then return false end
  if contact ~= CONTACT_ARROW and contact ~= CONTACT_LIGHT_ARROW then return false end
  if rshift(band((direction or 0) + 4, 0x18), 3) ~= band(e.animationState, 3) then return false end -- DirectionRoundUp >> 3
  e.action = 2
  e.collide = false
  sfx(d, SFX_111)
  d:set(e.flag)
  return true
end

function M.spawnEyeSwitch(d, e)
  dress(d, e, M.EYE_SWITCH, e.form or 0)
  e.eyeSwitch = true
  e.animationState = band(e.form or 0, 3)
  e.spritePriority = 6
  e.hurtType, e.hitType = 0x48, 1
  e.hitbox = { x = 0, y = 0, w = 6, h = 6 } -- gHitbox_1
  e.timer = e.timer0 or 0
  e.unk70 = 0
  if d:check(e.flags) then
    e.action = 3
    anim(d, e, e.animationState + 4)
  else
    e.action = 1
    e.collide = true
    anim(d, e, e.animationState)
  end
  e.extUpdate = function(dd, me) eyeUpdate(dd, me) end
  d:track(e)
  return e
end

-- an arrow (hurtType $15, light $0E) at x, y moving `direction` (0-31) with
-- half size w x h: true when it hit an eye switch's box
function M.arrowHit(f, x, y, hurtType, direction, w, h)
  local d = f._dungeon
  if not d then return false end
  w, h = w or 2, h or 2
  for _, e in ipairs(f.entities) do
    if e.eyeSwitch and not e.deleted and e.collide then
      local hb = e.hitbox
      if math.abs((e.x + hb.x) - x) <= hb.w + w and math.abs((e.y + hb.y) - y) <= hb.h + h then
        if M.eyeContact(d, e, 0x80 + band(hurtType or 0, 0x7F), direction) then return true end
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- FLOATING_PLATFORM
-- ---------------------------------------------------------------------------
local PLATFORM_RADII = { [0] = { 0x12, 0x0A }, { 0x0A, 0x12 }, { 0x12, 0x12 }, { 0x1A, 0x1A } } -- gUnk_08120658
M.PLATFORM_RADII = PLATFORM_RADII

local function platformOn(f, e) -- sub_08086168
  local p = f.player
  local r = PLATFORM_RADII[e.form or 0] or PLATFORM_RADII[2]
  if inRect(e, p, r[1], r[2]) and playerCanBeMoved(p) then
    e.field14 = true -- gPlayerState.field_0x14
    return (p.z or 0) == 0
  end
  return false
end

-- SyncPlayerToPlatform: the platform moves; Link by the whole-pixel change
-- on the axis of its direction
function M.syncPlayer(f, e, carry)
  local dir = e.direction or 0xFF
  if band(dir, 0x80) ~= 0 then return end
  local q = rshift(dir, 3) % 4
  local ox, oy = math.floor(e.x), math.floor(e.y)
  linear(e)
  if not carry then return end
  local p = f.player
  if q == 0 or q == 2 then
    local dy = math.floor(e.y) - oy
    if dy ~= 0 then p:moveBy(0, dy) end
  else
    local dx = math.floor(e.x) - ox
    if dx ~= 0 then p:moveBy(dx, 0) end
  end
end

local function platformUpdate(d, e)
  local f = d.field
  e.field14 = nil
  local on = platformOn(f, e)
  local t = e.timer0 or 0
  if t ~= 0 and e.parent and (e.parent.timer or 0) == 0 then
    if on then e.parent.timer = (e.parent.timer or 0) + 1 end
    M.syncPlayer(f, e, on)
  elseif t == 0 then
    M.syncPlayer(f, e, on)
  else
    M.syncPlayer(f, e, false)
  end
  e.unk70 = band((e.unk70 or 0) - 1, 0xFFFF)
  if e.unk70 == 0 then M.railNext(f, e) end
end

function M.railNext(f, e)
  local CO = require("src.zelda.tmc.CoFObjects")
  e.railPtr = e.child
  CO.railNext(f, e) -- direction / speed / u76 from the leg
  e.child = e.railPtr
  e.unk70 = e.u76 or 0
end

function M.spawnPlatform(d, e)
  local f = d.field
  dress(d, e, M.FLOATING_PLATFORM, e.form or 0)
  e.fowPlatform = true
  e.action = 1
  e.speed = 0x100
  e.staticFrame = e.form or 0
  e.spritePriority = 7
  local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
  e.child = props and props[e.type2 or 0] or nil -- GetCurrentRoomProperty(type2)
  e.direction = 0xFF
  M.railNext(f, e)
  e.extUpdate = function(dd, me) platformUpdate(dd, me) end
  d:track(e)
  return e
end

-- field_0x14: Link is held up by a platform this frame
function M.supports(f)
  for _, e in ipairs(f.entities) do
    if e.fowPlatform and not e.deleted and e.field14 then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- MINISH_SIZED_ENTRANCE
-- ---------------------------------------------------------------------------
local ENTRANCE_KEY = { [0] = "up", "right", "down", "left" } -- gUnk_0812225C: INPUT_UP, RIGHT, DOWN, LEFT
M.ENTRANCE_KEY = ENTRANCE_KEY

local function entranceUpdate(d, e, input)
  local f = d.field
  local p = f.player
  if f.transition then return end
  local key = ENTRANCE_KEY[band(e.type2 or 0, 3)]
  if p.minish and inRect(e, p, 4, 4) and (p.z or 0) == 0 and input and input.down and input.down(key) then
    local ex = require("src.zelda.tmc.SpecialWarp").exitAt(f, e.timer0 or 0)
    if ex then f:startTransition(ex) end
  end
end

function M.spawnEntrance(d, e)
  local f = d.field
  dress(d, e, M.MINISH_SIZED_ENTRANCE, e.form or 0)
  e.action = 1
  e.oamPrio, e.spritePriority = 3, 7
  e.staticFrame = e.type2 or 0
  if isDungeon(f) then
    e.staticFrame = e.staticFrame + 4
    e.gfx = 0x184 -- LoadFixedGFX(this, $184)
  end
  e.extUpdate = function(dd, me, input) entranceUpdate(dd, me, input) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- STONE_TABLET
-- ---------------------------------------------------------------------------
local TABLET_TILES = { 0x4022, -2, 0x4022, -1, 0x4022, 0, 0x4022, 1 } -- gUnk_081232EC (SPECIAL_TILE_34)
local TABLET_TILES3 = { 0x4065, -65, 0x4022, -64, 0x4066, -63, 0x4029, -1, 0x4026, 0, 0x402A, 1 } -- gUnk_081232FE
M.TABLET_TILES, M.TABLET_TILES3 = TABLET_TILES, TABLET_TILES3

-- SetMultipleTiles (offsets in the 64-wide tile grid)
function M.setTiles(f, list, x, y, layer)
  local r = f.room
  local pos = math.floor(x / 16) % 64 + (math.floor(y / 16) % 64) * 64
  for i = 1, #list, 2 do
    local q = pos + list[i + 1]
    local tx, ty = q % 64, math.floor(q / 64)
    if tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th then r:setTile(layer or 1, tx, ty, list[i]) end
  end
end

function M.spawnTablet(d, e)
  dress(d, e, M.STONE_TABLET, e.form or 0)
  e.action = 1
  if (e.form or 0) == 3 then
    e.staticFrame = 0
    M.setTiles(d.field, TABLET_TILES3, e.x, e.y, e.layer)
  else
    e.staticFrame = e.form or 0
    M.setTiles(d.field, TABLET_TILES, e.x, e.y, e.layer)
  end
  return e
end

-- ---------------------------------------------------------------------------
-- BIRD
-- ---------------------------------------------------------------------------
-- CheckOnScreen
local function onScreen(f, e)
  local sx = math.floor(e.x) - math.floor(f.camX or 0) + 0x3F
  local sy = math.floor(e.y) - math.floor(f.camY or 0) - (e.z or 0) + 0x3F
  return sx >= 0 and sx < 0x16E and sy >= 0 and sy < 0x11E
end

-- GravityUpdate on the Q16 z (negative = up); e.z is the drawn height
local function gravityQ(e, g)
  local nz = e.cz - e.czv
  if nz >= 0 then e.cz, e.czv = 0, 0
  else e.cz, e.czv = nz, e.czv - g end
  e.z = -e.cz / 65536
end
-- BounceUpdate: 2 airborne, 1 bouncing on, 0 done
local function bounceQ(e, acc)
  local nz = e.cz - e.czv
  if nz < 0 then
    e.cz, e.czv = nz, e.czv - acc
    e.z = -e.cz / 65536
    return 2
  end
  e.cz = 1
  local v = rshift(-(e.czv - acc), 1)
  v = v + rshift(v, 2)
  e.z = 0
  if rshift(v, 12) >= 0xC then e.czv = v return 1 end
  e.czv = 0
  return 0
end
M.bounceQ, M.gravityQ = bounceQ, gravityQ

local function birdAmbient(d, e)
  local f = d.field
  if e.action == 0 then
    e.action = 1
    e.layer = 2
    e.ambientDone = true -- frame = $80
  end
  if e.ambientDone or animDone(e) then
    e.ambientDone = nil
    anim(d, e, band(R(f), 3))
    if e.anim then e.anim.timer = band(R(f), 0xF) + 0x10 end
    e.flipX = band(R(f), 1) ~= 0
  else
    e.anim:update(1)
  end
end

-- IsCollidingPlayer: Link's hitbox against the object's (gObjectHitboxes)
local function birdTouches(f, p, e)
  local HB = require("src.zelda.tmc.Hitboxes")
  local hb = HB.object(f, e) or { x = 0, y = 0, w = 6, h = 6 }
  local t = HB.touches(f, p, { x = e.x, y = e.y, hitbox = hb })
  if t == nil then t = math.abs(math.floor(p.x) - math.floor(e.x)) <= hb.w + 6 and math.abs(math.floor(p.y) - 3 - math.floor(e.y)) <= hb.h + 6 end
  return t
end

local function birdType2(d, e)
  local f = d.field
  local p = f.player
  if p.minish then
    require("src.zelda.tmc.Hitboxes").pushOut(f, e, require("src.zelda.tmc.Hitboxes").object(f, e) or { x = 0, y = 0, w = 6, h = 6 })
  elseif p.state ~= "dead" and birdTouches(f, p, e) then
    -- IsCollidingPlayer: CreateItemEntity(ITEM_OCARINA), windcrests |= $10000000
    e.deleted = true
    f.save.windcrests = bor(f.save.windcrests or 0, 0x10000000)
    f:giveItem(ITEM_OCARINA, 0)
  end
end

local function birdType1(d, e)
  local f = d.field
  if e.subAction == 0 then
    local par = e.parent
    if par then
      if (par.subtimer or 0) ~= 0 then
        e.x, e.y, e.cz, e.z, e.layer = par.x, par.y + 8, par.cz, par.z, par.layer
      else
        e.subAction = 1
        e.czv = 0
      end
    end
  else
    if bounceQ(e, 24 * 256) < 2 then
      e.form = 2
      e.action = 1
      e.cz, e.z = 0, 0
      e.layer = 1
      f:setFlag("local", LV3_OCARINA_FALL, true)
      sfx(d, SFX_SECRET)
      f:addFx(e.x, e.y, SPECIAL_FX, FX_DASH)
    end
  end
end

local function birdType0(d, e)
  local f = d.field
  linear(e)
  gravityQ(e, e.gravity)
  if e.subtimer ~= 0 then
    e.subtimer2 = (e.subtimer2 or 0) - 1
    if e.subtimer2 == 0 then e.subtimer = 0 end
  elseif not onScreen(f, e) then
    e.deleted = true
  end
  e.anim:update(1)
end

local function birdUpdate(d, e)
  local t = e.form or 0
  if t >= 3 and t <= 7 then return birdAmbient(d, e) end
  if t == 0 then return birdType0(d, e) end
  if t == 1 then return birdType1(d, e) end
  if t == 2 then return birdType2(d, e) end
end

function M.spawnBird(d, e)
  local f = d.field
  local t = e.form or 0
  if t > 7 then return nil end -- types 8-10: the Ocarina warp (not this room's)
  dress(d, e, M.BIRD, t)
  e.fowBird = true
  e.action = 0
  e.subAction = 0
  if t == 0 then
    e.action = 1
    e.hidden = false
    e.subtimer2, e.subtimer = 49, 1
    e.czv = math.floor(-1.5 * 65536)
    e.cz = math.floor(-56.75 * 65536)
    e.z = -e.cz / 65536
    e.gravity = -8 * 256 -- Q_8_8(-8.0) on the Q16 z
    e.speed = 0x280
    e.direction = 8
    e.layer = 2
    e.x = math.floor(f.camX or 0)
    sfx(d, SFX_123)
    anim(d, e, 0)
    local c = { kind = 6, id = M.BIRD, form = 1, x = e.x, y = e.y + 8, z = e.z, cz = e.cz, czv = 0, layer = e.layer,
                animationState = 0, field80 = 0, field82 = 0, interactType = 0, dungeon = true, parent = e }
    dress(d, c, M.BIRD, 1)
    c.fowBird, c.action, c.subAction = true, 1, 0
    c.spritePriority = 5
    anim(d, c, 0x17)
    c.extUpdate = function(dd, me) birdUpdate(dd, me) end
    f.entities[#f.entities + 1] = c
    e.child = c
  elseif t == 1 or t == 2 then
    e.action = 1
    e.layer = 1
    e.cz, e.czv = e.cz or 0, e.czv or 0
    anim(d, e, 0x17)
  end
  e.extUpdate = function(dd, me) birdUpdate(dd, me) end
  d:track(e)
  if e.child then d:track(e.child) end -- updated after its parent (appended after it)
  return e
end

-- ---------------------------------------------------------------------------
-- FLOATING_BLOCK
-- ---------------------------------------------------------------------------
function M.spawnBlock(d, e)
  dress(d, e, M.FLOATING_BLOCK, e.form or 0)
  e.action = 1
  e.staticFrame = e.form or 0
  e.spritePriority = band(0x0E, 7)
  e.layer = 1
  return e
end

-- ---------------------------------------------------------------------------
-- MISC_MANAGER types 1 / 2 / 3
-- ---------------------------------------------------------------------------
local function holdLink(p) p.state, p.extUpdate = "ext", function() end end -- SetPlayerControl(2)
local function freeLink(p) if p.state == "ext" then p.state, p.extUpdate, p.animId = "normal", nil, -1 end end -- SetPlayerControl(1)

-- sub_08059064: GROUND_ITEM ITEM_SMALL_KEY with timer 2 (Kind2: from z -$80)
function M.dropKey(f, x, y)
  local g = f:objects():groundItem(ITEM_SMALL_KEY, 0, x, y, { kind = 2 })
  if g then
    g.static = nil
    g.act = 2
    g.cz, g.czv, g.bounced = -0x80 * 65536, 0, false
    g.noDespawn = true
    g.z = 0x80
    f:sound(SFX_12D)
  end
  return g
end

local function miscKeyTick(d, m)
  local f = d.field
  local p = f.player
  if m.action == 0 then
    m.action = 1
    if m.type == 1 then m.subAction, m.subtimer = 7, 6 else m.subAction, m.subtimer = 8, 2 end
    if d:check(m.c1) then m.deleted = true end
  elseif m.action == 1 then
    if d:check(m.c1) then
      m.action = 2
      m.timer = 120
      f.enemyHold = math.max(f.enemyHold or 0, 240) -- RequestPriorityDuration(this, 240)
      M.dropKey(f, m.x, m.y)
    end
  elseif m.action == 2 then
    if m.timer == 90 then holdLink(p) end
    if m.timer == 60 then p.animationState = m.subtimer end
    m.timer = m.timer - 1
    if m.timer == 0 then
      m.action = 3
      m.cutscene = m.subAction -- MenuFadeIn(5, subAction): sCutsceneData[7 / 8] (not shown)
    end
  else
    d:set(m.c1)
    freeLink(p)
    m.deleted = true
  end
end

local MOLE_MITTS_LIST = 0x080F4B88 -- gUnk_080F4B88
local function miscType3Tick(d, m)
  local f = d.field
  local got = false
  if m.action == 0 then
    m.action = 1
    if f:flag("local", 0x60) then got = true else f:setFlag("local", 0x5F, true) end
  elseif f:flag("local", 0x60) then
    f:setFlag("local", 0x5F, false)
    got = true
  end
  if got then
    f:loadEntityList(MOLE_MITTS_LIST)
    m.deleted = true
  end
end

-- ---------------------------------------------------------------------------
-- ENEMY_INTERACTION_MANAGER
-- ---------------------------------------------------------------------------
-- CalcCollisionStaticEntity(tgt, org): org moved out of tgt (sub_080044AE)
local function solidAt(f, e, x, y)
  local r = f.room
  local hb = e.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local L = (e.layer == 2) and 2 or 1
  local cx, cy = x + (hb.x or 0), y + (hb.y or 0)
  local hw, hh = math.max(1, hb.w or 4), math.max(1, hb.h or 4)
  return r:isSolid(cx - hw, cy - hh, L) or r:isSolid(cx + hw - 1, cy - hh, L)
      or r:isSolid(cx - hw, cy + hh - 1, L) or r:isSolid(cx + hw - 1, cy + hh - 1, L)
end
-- the two corners on the side it moves to (CalculateEntityTileCollisions)
local function edgeSolid(f, e, x, y, vx, vy)
  local r = f.room
  local hb = e.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local L = (e.layer == 2) and 2 or 1
  local cx, cy = x + (hb.x or 0), y + (hb.y or 0)
  local hw, hh = math.max(1, hb.w or 4), math.max(1, hb.h or 4)
  if vx ~= 0 then
    local ex = vx > 0 and cx + hw - 1 or cx - hw
    return r:isSolid(ex, cy - hh + 1, L) or r:isSolid(ex, cy + hh - 2, L)
  end
  local ey = vy > 0 and cy + hh - 1 or cy - hh
  return r:isSolid(cx - hw + 1, ey, L) or r:isSolid(cx + hw - 2, ey, L)
end
M.edgeSolid = edgeSolid

function M.staticPush(f, tgt, org)
  local tb, ob = tgt.hitbox, org.hitbox
  if not tb or not ob then return false end
  local dx = (math.floor(org.x) + (ob.x or 0)) - (math.floor(tgt.x) + (tb.x or 0))
  local sw = (tb.w or 0) + (ob.w or 0)
  if dx < -sw or dx > sw then return false end
  local ip = dx >= 0 and 8 or 0x18
  local penX = sw - math.abs(dx)
  local dy = (math.floor(org.y) + (ob.y or 0)) - (math.floor(tgt.y) + (tb.y or 0))
  local sh = (tb.h or 0) + (ob.h or 0)
  if dy < -sh or dy > sh then return false end
  local dir = dy >= 0 and 0x10 or 0
  local pen = sh - math.abs(dy)
  if pen >= penX then pen, dir = penX, ip end
  if pen == 0 then return false end
  if pen >= 5 then pen = 4 end
  local vx = (dir == 8 and 1) or (dir == 0x18 and -1) or 0
  local vy = (dir == 0x10 and 1) or (dir == 0 and -1) or 0
  local nx, ny = org.x + vx * pen, org.y + vy * pen
  if f.room and f.room.isSolid and edgeSolid(f, org, nx, ny, vx, vy) then return true end
  org.x, org.y = nx, ny
  return true
end

-- EnemyInteractionManager_FindMatchingEntities
function M.matchEnemies(f, list)
  local out = {}
  for _, dat in ipairs(list or {}) do
    if dat.kind == 9 and dat.id == M.ENEMY_INTERACTION_MANAGER then break end
    if dat.kind == 3 then
      local hit
      for _, e in ipairs(f.entities) do
        if e.enemy and not e.deleted and e.id == dat.id and (e.form or 0) == (dat.paramA or 0)
           and math.floor(e.x) == dat.x and math.floor(e.y) == dat.y then hit = e break end
      end
      if hit then
        local dup = false
        for _, o in ipairs(out) do if o == hit then dup = true end end
        if not dup then
          out[#out + 1] = hit
          if #out == 8 then return out end
        end
      end
    end
  end
  return out
end

local function interactionTick(d, m)
  local f = d.field
  if m.action == 0 then
    -- type 0 Init (on its first update, as the cartridge)
    local found = M.matchEnemies(f, d:propList(m.type2))
    if #found > 1 then m.action, m.enemies, m.subtimer = 1, found, 0 else m.deleted = true end
    return
  end
  -- RemoveDeletedEntities
  local list = m.enemies
  local i = 1
  while i <= #list do
    if list[i].deleted then list[i] = list[#list]; list[#list] = nil else i = i + 1 end
  end
  if #list <= 1 then m.deleted = true return end
  local odd = band(m.subtimer, 1) ~= 0
  m.subtimer = band(m.subtimer + 1, 0xFF)
  local n = #list
  for a = 1, n - 1 do
    for b = a + 1, n do
      if odd then M.staticPush(f, list[a], list[b]) else M.staticPush(f, list[b], list[a]) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- room projectiles: contact with Link
-- ---------------------------------------------------------------------------
local function touchLink(f, e)
  local p = f.player
  if p.state == "dead" or (p.invuln or 0) > 0 or e.hidden then return false end
  local HB = require("src.zelda.tmc.Hitboxes")
  local hb = e.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local t = HB.touches(f, p, e)
  if t == nil then t = math.abs((e.x + (hb.x or 0)) - p.x) < hb.w + 5 and math.abs((e.y + (hb.y or 0)) - (p.y - 3)) < hb.h + 6 end
  return t
end
local function knockLink(p, x, y, spd, dur, ifr)
  p.invuln = math.max(ifr or 30, 1)
  p.timer = math.max(dur or 8, 4)
  local dx, dy = p.x - x, p.y - y
  local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
  p.kbx, p.kby = dx / dd * spd, dy / dd * spd
end

-- CollisionFire (handler 11): damage 4, knockback 12 frames at $180, iframes 30
function M.fireTouch(f, e)
  if not touchLink(f, e) then return false end
  local p = f.player
  if p:hurt(4, e.x, e.y) then knockLink(p, e.x, e.y, 0x180 / 256, 12, 30) end
  return true
end

-- the matrix entry (hitType, Link's hurtType)
function M.matrixTouch(f, e)
  if not touchLink(f, e) then return false end
  local p = f.player
  local HB = require("src.zelda.tmc.Hitboxes")
  local En = f:enemies()
  if p.blocksFrom and p:blocksFrom(e.x, e.y) then
    f:sound(0x118) -- the shield's entry: no damage (its push back on Link is not modelled)
    return true
  end
  local s = En and En:settings(e.hitType, HB.hurtType(p)) or { tgtDmg = 2, orgIfr = 30, orgKbDur = 8, orgKbSpd = 24 }
  if (s.tgtDmg or 0) > 0 then
    if p:hurt(math.max(s.tgtDmg, 1), e.x, e.y) then knockLink(p, e.x, e.y, (s.orgKbSpd * 16) / 256, s.orgKbDur, math.max(s.orgIfr, 30)) end
  end
  return true
end

local function projDef(d, id, form)
  local defs = d.field.assets.manifest.projectileDefs
  local def = defs and defs[id]
  if def and def.multi then def = def.forms[form] or def.forms[0] end
  return def
end
local function projDress(d, e, id, form)
  local def = projDef(d, id, form)
  if def then
    local Assets = require("src.zelda.tmc.Assets")
    d:dress(e, def.sprite, def.palette, Assets.gfxSource("enemy", def.gfx), 0)
    e.def = def
  end
  return def
end

-- ---------------------------------------------------------------------------
-- WINDER
-- ---------------------------------------------------------------------------
local WINDER_SEGMENTS = 8
local WINDER_TAIL = 4
local WINDER_TURN = { [0] = { 8, 0x18 }, { 0, 0x10 }, { 8, 0x18 }, { 0, 0x10 } } -- nextDirections
local WINDER_HB_HEAD = { x = 0, y = 0, w = 4, h = 4 } -- gUnk_080FD558
local WINDER_HB_BODY = { x = 0, y = 0, w = 1, h = 1 } -- gUnk_080FD560
M.WINDER_TURN = WINDER_TURN

local function winderOffsets(f)
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "winderTileOffsets")
  if T then
    local base = M.ROM_RANGES.winderTileOffsets[1]
    return { [0] = T.s16(base), T.s16(base + 2), T.s16(base + 4), T.s16(base + 6) }
  end
  return nil
end

-- Winder_CheckForRailings: the collision value of the tile ahead is $20-$3F
function M.winderRailing(f, e, dir)
  local r = f.room
  local offs = winderOffsets(f)
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  local q = rshift(dir, 3) % 4
  if offs then
    local pos = tx + ty * 64 + offs[q]
    tx, ty = pos % 64, math.floor(pos / 64)
  else
    -- (an old cache: the neighbouring tile that way)
    local v = ({ [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } })[q]
    tx, ty = tx + v[1], ty + v[2]
  end
  local c = r.coll and r.coll[(e.layer == 2) and 2 or 1]
  local v = c and c[ty * r.tw + tx] or 0
  return v > 0x1F and v <= 0x3F
end

-- ProcessMovement0 for the head: true when blocked on the side it moves to
local function winderMove(f, e)
  local a = (e.direction % 32) / 32 * 2 * math.pi
  local s = (e.speed or 0x140) / 256
  local vx, vy = math.sin(a) * s, -math.cos(a) * s
  if math.abs(vx) < 1e-6 then vx = 0 end
  if math.abs(vy) < 1e-6 then vy = 0 end
  local blocked = false
  if vx ~= 0 then if solidAt(f, e, e.x + vx, e.y) then blocked = true else e.x = e.x + vx end end
  if vy ~= 0 then if solidAt(f, e, e.x, e.y + vy) then blocked = true else e.y = e.y + vy end end
  return blocked
end

local function winderSetPositions(e)
  local pos = e.positions
  for i = 1, 2 * (WINDER_SEGMENTS - 1) do pos[i] = pos[i + 2] end
  pos[2 * WINDER_SEGMENTS - 1], pos[2 * WINDER_SEGMENTS] = math.floor(e.x), math.floor(e.y)
end

local function winderUpdate(d, head)
  local f = d.field
  -- the head (Winder_Move type 0)
  local q = rshift(head.direction, 3) % 4
  if winderMove(f, head) or M.winderRailing(f, head, head.direction) then
    head.direction = WINDER_TURN[q][band(R(f), 1) + 1]
  end
  head.anim:update(1)
  winderSetPositions(head)
  -- the segments, each at the oldest position of the one ahead
  local ahead = head
  for _, s in ipairs(head.segments) do
    if s.deleted or ahead.deleted then s.deleted = true
    else
      s.x, s.y = ahead.positions[1], ahead.positions[2]
      s.anim:update(1)
      winderSetPositions(s)
    end
    ahead = s
  end
  -- contact (every segment: hitType $73, CollisionFire)
  if not M.fireTouch(f, head) then
    for _, s in ipairs(head.segments) do if not s.deleted and M.fireTouch(f, s) then break end end
  end
end

local function winderSegment(d, x, y, t, layer)
  local e = { kind = 4, id = M.WINDER, form = t, type = t, x = x, y = y, z = 0, layer = layer, animationState = 0,
              field80 = 0, field82 = 0, interactType = 0, dungeon = true, action = 1, speed = 0x140, winder = true }
  local def = projDress(d, e, M.WINDER, t)
  e.hitType = def and def.damageType or 0x73
  e.hitbox = t == 0 and WINDER_HB_HEAD or WINDER_HB_BODY
  anim(d, e, 0)
  e.positions = {}
  for i = 1, WINDER_SEGMENTS do e.positions[2 * i - 1], e.positions[2 * i] = math.floor(x), math.floor(y) end
  return e
end

function M.spawnWinder(d, dat)
  local f = d.field
  local layer = (band(dat.collision or 0, 3) == 2) and 2 or 1
  local head = winderSegment(d, dat.x, dat.y, dat.paramA or 0, layer)
  head.direction = band(R(f), 0x18)
  head.segments = {}
  local t = head.type
  while t < WINDER_TAIL do
    t = t + 1
    local s = winderSegment(d, head.x, head.y, t, layer)
    s.direction = head.direction
    head.segments[#head.segments + 1] = s
    f.entities[#f.entities + 1] = s
  end
  head.extUpdate = function(dd, me) winderUpdate(dd, me) end
  d:track(head)
  return head
end

-- ---------------------------------------------------------------------------
-- SPIKED_ROLLERS
-- ---------------------------------------------------------------------------
local ROLLER_OFFSETS = { [0] = 8, 16, 24, 32, 40, 48, 56, 16, 24, 32, 40, 48, 56, 64 } -- gSpikedRollersOffsets
local ROLLER_HB = { [0] = { 3, 8 }, { 3, 16 }, { 3, 24 }, { 3, 32 }, { 3, 40 }, { 3, 48 }, { 3, 56 },
                    { 16, 3 }, { 24, 3 }, { 32, 3 }, { 40, 3 }, { 48, 3 }, { 56, 3 }, { 64, 3 } } -- gUnk_080FD4B8 .. gUnk_080FD520
M.ROLLER_OFFSETS, M.ROLLER_HB = ROLLER_OFFSETS, ROLLER_HB

local function s16(v) v = band(v or 0, 0xFFFF) if v >= 0x8000 then return v - 0x10000 end return v end

-- sub_080AF0C8: one-way tiles $87-$8A stop it on that side
local function oneWayStops(f, e)
  local tt = f.room:tileType((e.layer == 2) and 2 or 1, math.floor(e.x / 16), math.floor(e.y / 16))
  local d = e.direction
  if tt == 0x87 then return band(d + 7, 0x1F) < 0x10 end
  if tt == 0x8A then return band(d - 1, 0x1F) < 0x10 end
  if tt == 0x88 then return band(d - 9, 0x1F) < 0x10 end
  if tt == 0x89 then return band(d - 0x11, 0x1F) < 0x10 end
  return false
end

-- SpikedRollers_Action1
function M.rollerStep(f, e)
  if not oneWayStops(f, e) then linear(e) end -- ProcessMovement3
  local diff
  if e.type2 == 0 then diff = math.floor(e.x) - e.x2 else diff = math.floor(e.y) - e.y2 end
  local range = e.range
  if range < 0 then diff, range = -diff, -range end
  -- (u32)(diff << 16) > (range << 16): negative diffs count as huge
  local du = band(diff, 0xFFFF)
  local ru = band(range, 0xFFFF)
  if du > ru then
    e.direction = bxor(e.direction, 0x10)
    if e.type2 == 0 then
      e.x = e.x2 + (e.x - math.floor(e.x))
      e.flipX = not e.flipX
    else
      e.y = e.y2 + (e.y - math.floor(e.y))
      e.flipY = not e.flipY
    end
    if diff > 0 then
      if e.type2 == 0 then e.x = e.x + e.range else e.y = e.y + e.range end
    end
  end
end

local function rollerUpdate(d, e)
  local f = d.field
  M.rollerStep(f, e)
  e.anim:update(1)
  M.matrixTouch(f, e)
end

function M.spawnRollers(d, dat)
  local t = dat.paramA or 0
  if t > 13 then return false end
  local e = { kind = 4, id = M.SPIKED_ROLLERS, form = t, type = t, x = dat.x, y = dat.y, z = 0, animationState = 0,
              field80 = 0, field82 = 0, interactType = 0, dungeon = true, action = 1, rollers = true,
              layer = (band(dat.collision or 0, 3) == 2) and 2 or 1 }
  local def = projDress(d, e, M.SPIKED_ROLLERS, t)
  e.hitType = def and def.damageType or 0x66
  e.hitbox = { x = 0, y = 0, w = ROLLER_HB[t][1], h = ROLLER_HB[t][2] }
  e.speed = rshift(dat.paramC or 0, 16)    -- speed2 (+$86)
  e.range = s16(band(dat.paramC or 0, 0xFFFF)) -- unk_0x84
  e.x2, e.y2 = math.floor(e.x), math.floor(e.y)
  e.type2 = t <= 6 and 0 or 1
  local off = ROLLER_OFFSETS[t]
  if e.type2 == 0 then e.direction = 8; e.y = e.y + off
  else e.direction = 0x10; e.x = e.x + off end
  anim(d, e, t)
  e.extUpdate = function(dd, me) rollerUpdate(dd, me) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- Four Sword clones on buttons (button.c sub_08081D74)
-- ---------------------------------------------------------------------------
function M.clones(f)
  local out = {}
  for _, c in ipairs(f.playerClones or {}) do if c and not c.deleted then out[#out + 1] = c end end
  for _, e in ipairs(f.entities or {}) do if e.playerClone and not e.deleted then out[#out + 1] = e end end
  return out
end
function M.cloneOn(f, tx, ty)
  local bx, by = tx * 16 + 8, ty * 16 + 9 -- the button's y is one down (Button_Init)
  for _, c in ipairs(M.clones(f)) do
    if (c.z or 0) == 0 and math.abs(math.floor(c.x) - bx) <= 5 and math.abs(math.floor(c.y) - by) <= 6 then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- hooks (installed once)
-- ---------------------------------------------------------------------------
function M.install()
  if M._installed then return end
  M._installed = true
  local Dungeon = require("src.zelda.tmc.Dungeon")
  local checkFall = Dungeon.checkFall
  Dungeon.checkFall = function(self, ...)
    if M.supports(self.field) then return end -- field_0x14: on a floating platform
    return checkFall(self, ...)
  end
  local somethingOn = Dungeon.somethingOn
  Dungeon.somethingOn = function(self, tx, ty, who)
    if somethingOn(self, tx, ty, who) then return true end
    return M.cloneOn(self.field, tx, ty)
  end
end

-- ---------------------------------------------------------------------------
-- R26 entry points
-- ---------------------------------------------------------------------------
local function fowArea(f) local a = f and f.room and f.room.area return a == 0x58 or a == 0x59 end

function M.spawnObject(d, e)
  local id = e.id
  if id == M.EYE_SWITCH then M.install(); return M.spawnEyeSwitch(d, e) end
  if id == M.FLOATING_PLATFORM then M.install(); return M.spawnPlatform(d, e) end
  if id == M.MINISH_SIZED_ENTRANCE then return M.spawnEntrance(d, e) end
  if id == M.STONE_TABLET then return M.spawnTablet(d, e) end
  if id == M.BIRD then return M.spawnBird(d, e) end
  if id == M.FLOATING_BLOCK and fowArea(d.field) then return M.spawnBlock(d, e) end
  return nil
end

function M.spawnManager(d, m)
  local R26 = require("src.zelda.tmc.R26")
  if m.id == M.MISC_MANAGER and (m.type == 1 or m.type == 2) then
    R26.ticker(d, function(dd, me) if not me.deleted then miscKeyTick(dd, me) end end, m)
    return true
  end
  if m.id == M.MISC_MANAGER and m.type == 3 then
    R26.ticker(d, function(dd, me) if not me.deleted then miscType3Tick(dd, me) end end, m)
    return true
  end
  if m.id == M.ENEMY_INTERACTION_MANAGER then
    m.action = m.type == 0 and 0 or 1
    m.enemies = m.enemies or {}
    m.subtimer = 0
    R26.ticker(d, function(dd, me) if not me.deleted then interactionTick(dd, me) end end, m)
    return true
  end
  return nil
end

function M.spawnProjectile(d, dat)
  if dat.id == M.WINDER then M.install(); return M.spawnWinder(d, dat) end
  if dat.id == M.SPIKED_ROLLERS then M.install(); return M.spawnRollers(d, dat) end
  return nil
end

local OCARINA_LIST = 0x080E3850 -- gUnk_080E3850 (BIRD type 2 at $A0, $B0)
function M.roomInit(f)
  local r = f.room
  if not r then return end
  M.install()
  if r.area == 0x59 and r.room == 0x00 then
    -- sub_StateChange_FortressOfWindsTop_Main
    f:setFlag("global", LV3_CLEAR, true)
    if f.updateProgress then f:updateProgress() end
    local has = f.inventory and f:inventory(ITEM_OCARINA) or 0
    if (has == 0 or has == nil) and f:flag("local", LV3_OCARINA_FALL) then
      local list = f.entityListAt and f:entityListAt(OCARINA_LIST)
      if list and #list > 0 then f:loadEntityList(OCARINA_LIST)
      else f:spawn({ kind = 6, id = M.BIRD, paramA = 2, paramB = 0, paramC = 0, pool = 0x0F, x = 0xA0, y = 0xB0, collision = 0 }) end
    end
  end
end

return M
