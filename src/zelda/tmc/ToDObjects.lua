-- Round 26 (team B): the Temple of Droplets' objects and managers, the dark
-- rooms' light managers ($60 / $62 / $68 / $70 / $88), and Link's ice floor.
--
-- OBJECTS (src/object/*.c):
--   SMALL_ICE_BLOCK $84 (smallIceBlock.c) types 0-2: gone at Init when its
--     flag ($86) is set; its tile becomes SPECIAL_TILE_90 (sub_08099468, the
--     old tile remembered) and a type-3 child shows the shine (animation 3,
--     every keyframe with bit 0 held (Random & $78) + $78 frames, drawn
--     while the block's action < 3, 1 px lower and $11 px up).
--     Action1: melting (sub_0809963C: a room property list [type2] = {flag,
--     x, y, w, h} -- the light ray's region once its flag is set -- or a
--     contact $87 = fire) -> Action3; else (no hazard under it) the tile:
--     SPECIAL_TILE_91-94 (Link pushed it, UpdatePlayerCollision) -> Action2
--     (22 frames of speed $20 + $10 a frame, then $200, direction from the
--     tile, SFX_ICE_BLOCK_SLIDE, the old tile back, -2 px toward stairs);
--     TILE_TYPE_120 / 122 (a button put under it) -> remembered as its tile;
--     any other tile -> FX_ICE, the tile back, gone.  Action2 slides
--     (ProcessMovement2, pushing Link out) until it hits something: lined up
--     ((pos & $F) - 7 < 3) it snaps to the tile centre, SFX_ICE_BLOCK_STOP,
--     Action1; else FX_ICE and gone.  Action3 (melt): SFX_ICE_BLOCK_MELT, the
--     y scale gUnk_08123748[timer >> 5]; type 0 sets its flag, type 1 drops
--     a small key, type 2 the big key (CreateGroundItemWithFlags, SFX_SECRET);
--     Action4: 60 frames squashing (y scale (60 - t) * $20 + $100), the old
--     tile back at 48, FX_DASH every other frame at a random spot.
--   BIG_ICE_BLOCK $85 (bigIceBlock.c) types 0-2: 2x2 / 2x3 / 3x2 / 3x3 tiles
--     by its x & 8, y & 8 (SPECIAL_TILE_34 inside, 35-42 edges, 117-124 where
--     the floor is ice ACT_TILE_18); melting as above; type 0 sets its flag,
--     type 1 nothing, type 2 drops a small key; 60 frames squashing, the
--     tiles restored at 48, FX_DASH every frame.  Child type 4 = the shine.
--   FROZEN_FLOWER $31: frameIndex = type, priority 3, static.
--   FROZEN_WATER_ELEMENT $8F (frozenWaterElement.c): gone when local flag
--     $9B is set; makes FROZEN_OCTOROK (whichever module ports it: the
--     child gets .frozenElement), 27 SPECIAL_TILE_34 tiles, scale $CC.
--     When local flag $37 (OUGONTEKI_G: LIGHT_RAY type 3 sets it) is set: a
--     WATER_ELEMENT 4 px below (the camera on it), $140 frames of melting
--     (SFX_ICE_BLOCK_MELT every 32, the scale growing under $78, FX_DASH +
--     FX_DEATH around its spot), then child.subtimer = 1, tiles restored,
--     gone.  The Water Element itself comes from the Big Octorok fight.
--   LIGHT_DOOR $12 (lightDoor.c): type 0 gone once its flag is set, else
--     SPECIAL_TILE_61 on the 3x3 tiles round it; type 1 waits 240 frames,
--     30 more, then drifts west at $80 for 96 frames and is gone.
--   LIT_AREA $BC (litArea.c): once its flag (or none) -- an OBJ-window
--     sprite (frame 3, affine $80 pulsing $78-$88 every 2 frames): the
--     darkness is not drawn inside it.
--   PUSHABLE_LEVER $7B / BIG_PUSHABLE_LEVER $83 (pushableLever.c,
--     bigPushableLever.c): SPECIAL_TILE_83 (82 pushed) on the tile north
--     (west); Link pushing it the right way (UpdatePlayerCollision: facing
--     west for 83, north for 82; the big lever's 85-88 need a Four Sword
--     clone pushing too) makes it SPECIAL_TILE_84 (89); 60 frames of that
--     -> SFX_16A (SFX_132), Link PLAYER_PUSH $90 ($98), the lever's
--     animation; done: its flag set (cleared when it was pushed), tiles again.
--     The 60 frames shake it (offset tables) with SFX_PLACE_OBJ (SFX_131).
--   LIGHT_RAY $8E (lightRay.c, made by the managers): the camera on the ray,
--     Link turned to it, the window growing / shrinking with SFX_133 every 32
--     frames, SFX_134; type 2 sets local flag $35 (+ SFX_SECRET) and room
--     flag 100, type 3 local flag $37; then the manager's subAction = 1.
-- MANAGERS (src/manager/*.c):
--   TEMPLE_OF_DROPLETS_MANAGER $15 (templeOfDropletsManager.c): types 0-7.
--     2/3: its flag follows the light (localFlag): set -> LIGHT_RAY 0, then
--     the flag; cleared -> LIGHT_RAY 1, then cleared (the ice blocks' melt
--     region).  1: the light frees the Big Blue Chuchu (list gUnk_080E4C08,
--     SONG_STOP_BGM; local $48 once it is type 4 / gone).  4: local $34 ->
--     LIGHT_RAY 2, $36 -> LIGHT_RAY 3.  6: the entrance light: Link idle /
--     walking inside its 12x12 box (after leaving it once) -> PLAYER_WARP:
--     30 frames, up at 1.0 (gravity 8 / 4), 120 frames hovering, 80 frames
--     rising, DoExitTransition(gUnk_0813AD88[0]) = Lake Hylia.  7: rays type
--     4 following its local flag.
--   LIGHT_LEVEL_SET_MANAGER $23 (lightLevelSetManager.c) types 0-3: the
--     torch at (x, y) on layer type2 (TILE_TYPE_117 unlit, 118 lit):
--     type 2: lit -> its flag, ChangeLightLevel(timer), gone; type 3: lit ->
--     flag, light, burns field_0x36 * 60 frames, then FX_DEATH, flag
--     cleared, the torch out, the light back -- unless flag $3C got set
--     (FLAME, kept); types 0/1: the torch lit by the flag (FLAME every 30).
--   MISC_MANAGER $0F types 4 / 5: 4: local $4A = $6C && $4B; 5: TILE_TYPE_869
--     at (x, y) until flag2, then 45 frames, FX_DEATH, the tile back,
--     SFX_TASK_COMPLETE.
--   WATERFALL_BOTTOM_MANAGER $2D: SPECIAL_TILE_20 at (3, 23); Link below
--     y 200 with x - $30 < $11 goes to layer 3.
--   SPECIAL_WARP_MANAGER $06: already SpecialWarp.lua (paramA = the room
--     property; $60:08 uses $0A, Minish-only by its bits).
-- DARK ROOMS (room.c LoadDarknessTile, lightManager.c, gameUtils.c):
--   a DARKNESS tile entity (type 9) sets lightType 1 and the room's light
--   level (its _3); every room starts at 256 otherwise; the area's level
--   lerps to the room's by 4 a frame; BG3 is black blended by
--   gUnk_08108CA8[level >> 4] (EVA = 16 - level / 16); WIN0 cuts a circle
--   of radius 17 round Link ($11; with the Lantern in use up to $48 and a
--   sine wobble) out of it, the lit areas' OBJ window too.
-- ICE FLOOR (asm/src/player.s sub_08008942): on ACT_TILE_18 (SURFACE_ICE)
--   Link's input adds ice_velocities[dir8] (10 a frame per axis, clamped to
--   $180), he moves by the velocity, then it decays by 3 a frame; off the
--   ice the velocity is the walk direction * 256 (sub_08008AA0).
-- SIMPLIFIED:
--   * the light rays' / ToD managers' BG3 shafts of light (gfx groups
--     $31-$35, palette cycling, WIN1) are not drawn; the windows of
--     LIGHT_RAY / LIGHT_DOOR are not drawn either -- only their timing,
--     camera, sounds and flags are ported;
--   * RequestPriorityDuration: Link's input is locked while a ray runs;
--   * a lit area's window is an ellipse the size of its frame 3;
--   * fire (contact $87) = an entity with .fire (+ hitW / hitH) or
--     ToDObjects.fireAt(f, x, y, w, h) (the Lantern, owned by another
--     team, calls it); the Lantern in use = player.usingLantern;
--   * the big lever's Four Sword clones = f.playerClones (other team);
--   * hazards under a sliding block: holes / water / lava only (FX);
--   * the ice floor runs for the normal state only (not rolling / carrying /
--     jumping);
--   * the darkness is drawn for areas in M.DARK_AREAS only.
local bit = require("bit")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local M = {}
local ID = { SMALL_ICE = 0x84, BIG_ICE = 0x85, FROZEN_FLOWER = 0x31, FROZEN_WATER_ELEMENT = 0x8F, LIGHT_DOOR = 0x12,
             LIT_AREA = 0xBC, LEVER = 0x7B, BIG_LEVER = 0x83, LIGHT_RAY = 0x8E, WATER_ELEMENT = 0x90,
             FROZEN_OCTOROK = 0x91, FLAME = 0x2A }
local MGR = { TOD = 0x15, LIGHT_LEVEL = 0x23, MISC = 0x0F, WATERFALL_BOTTOM = 0x2D }
M.ID, M.MGR = ID, MGR
M.DARK_AREAS = { [0x60] = true, [0x62] = true, [0x68] = true, [0x70] = true, [0x88] = true }

local SFX = { MELT = 0x1B3, SLIDE = 0x1B1, STOP = 0x1B2, SECRET = 0x72, TASK_COMPLETE = 0xCD, S16A = 0x16A,
              PLACE_OBJ = 0x104, S131 = 0x131, S132 = 0x132, S133 = 0x133, S134 = 0x134, S124 = 0x124 }
M.SFX = SFX
local SPECIAL_FX, FX_FALL, FX_DEATH, FX_SPLASH, FX_LAVA, FX_ICE, FX_DASH, FX_SPARKLE = 0x0F, 0x00, 0x02, 0x0B, 0x0C, 0x0D, 0x11, 0x07
local ITEM_SMALL_KEY, ITEM_BIG_KEY = 0x53, 0x52
local function SP(n) return 0x4000 + n end
local TT_TORCH_OFF, TT_TORCH_ON, TT_BUTTON_HELD, TT_BUTTON_DOWN, TT_869, TT_784 = 117, 118, 120, 122, 0x365, 0x310
local ACT_ICE, ACT_HOLE, ACT_WATER, ACT_LAVA = 0x12, 0x19, 0x10, 0x5A
local DV = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }  -- by direction >> 3

-- small tables written out in the decomp's .c files
local SMALL_MELT_SCALE = { [0] = 256, 264, 271, 277 }          -- gUnk_08123748
local BIG_MELT_SCALE = { [0] = 256, 266, 275, 284, 293 }        -- gUnk_081237B0
local SMALL_TILE_KIND = { [SP(91)] = 1, [SP(92)] = 1, [SP(93)] = 1, [SP(94)] = 1, [TT_BUTTON_DOWN] = 2, [TT_BUTTON_HELD] = 2 } -- gUnk_08123750
local LEVER_OFFS = { [0] = { [0] = { 0, 0 }, { 0, 0 }, { -1, 0 }, { 0, 0 } },  -- PushableLever_InitialOffsets
                     [1] = { [0] = { 0, 0 }, { 0, 0 }, { 0, -1 }, { 0, 0 } } } -- PushableLever_PushedOffsets
local FWE_DASH = { [0] = 3, 7, 15, 31, 63, 63, 63, 63, 63, 63, 63, 0 } -- gUnk_08123DC0
local ICE_VEL = { [0] = { 0, -10 }, { 10, -10 }, { 10, 0 }, { 10, 10 }, { 0, 10 }, { -10, 10 }, { -10, 0 }, { -10, -10 } } -- asm ice_velocities
local LIGHT_ALPHA = {} -- gUnk_08108CA8: (i << 8) | (16 - i)
for i = 0, 16 do LIGHT_ALPHA[i] = (16 - i) / 16 end
LIGHT_ALPHA[17] = 0
-- gUnk_0813AD88[0] (screenTransitions.c): the ToD entrance light's warp
local WARP_LAKE = { warpType = 1, endX = 0x128, endY = 0x188, shape = 0, area = 0x0B, room = 0x00, layer = 1, kind = 9, facing = 4, sfx = 0 }
M.WARP_LAKE = WARP_LAKE
-- the Temple of Droplets' room code lists (src/roomInit.c, entity_headers.s)
local LISTS = { bigOcto = 0x080E49F4, blueChu = 0x080E4BD8, blueChuFreed = 0x080E4C08, chuKey6C = 0x080E4CD8,
                chuKey = 0x080E4CF8, lilyA = 0x080E5660, lilyB = 0x080E5680, leverA = 0x080E5E3C, leverB = 0x080E5E5C }
M.LISTS = LISTS

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function D() return require("src.zelda.tmc.Drops") end
local function rnd(f) local Dr = D() return Dr.random(Dr.rngOf(f)) end
local function sfx(f, id) if f.sound then f:sound(id) end end
local function fx(f, x, y, kind) if f.addFx then f:addFx(x, y, SPECIAL_FX, kind) end end
local function lflag(f, i) return f:flag("local", i) end
local function setL(f, i, v) f:setFlag("local", i, v == nil and true or v) end

local function anim(d, e, a)
  e.objAnim, e.animIndex = a, a
  if e.anim and e.sprite then e.anim:set(d.field.assets:sprite(e.sprite), a, true) end
  e.flagKey = nil
end
local function fflags(e)
  if not e.anim then return 0 end
  if e.flagKey == e.anim.key then return band(e.anim.flags or 0, 0x80) end
  return e.anim.flags or 0
end
local function take(e) e.flagKey = e.anim and e.anim.key end
local function dress(d, e, id, form)
  local O = d.field.objects and d.field:objects()
  local def = O and O:def(id, form or 0)
  if def then O:dress(e, def, 0) end
  return def
end

local function mapName(layer) return layer == 2 and "top" or "bottom" end
local function tileIndex(f, layer, tx, ty)
  local r = f.room
  local m = r.maps[mapName(layer)]
  return m and m[ty * r.tw + tx]
end
local function tileType(f, layer, tx, ty) return (f.room:tileType(layer == 2 and 2 or 1, tx, ty)) end
local function actAt(f, layer, tx, ty)
  local tt = tileType(f, layer, tx, ty)
  if not tt or tt >= 0x4000 then return 0 end
  return f.assets.actTile and f.assets.actTile[tt] or 0
end
local function inRoom(f, tx, ty) local r = f.room return tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th end
-- SetTile / SetTileType with the old tile kept for RestorePrevTileEntity
local function remember(f, layer, tx, ty)
  f._todPrev = f._todPrev or {}
  local k = (layer == 2 and 2 or 1) * 65536 + ty * 256 + tx
  if f._todPrev[k] == nil then f._todPrev[k] = tileIndex(f, layer, tx, ty) or false end
end
local function setTile(f, layer, tx, ty, mt)
  if not inRoom(f, tx, ty) then return end
  remember(f, layer, tx, ty)
  f.room:setTile(layer == 2 and 2 or 1, tx, ty, mt)
end
local function setTileType(f, layer, tx, ty, tt)
  if not inRoom(f, tx, ty) then return end
  if tt >= 0x4000 then return setTile(f, layer, tx, ty, tt) end
  remember(f, layer, tx, ty)
  f:objects():setTileType(layer == 2 and 2 or 1, tx, ty, tt)
end
local function restoreTile(f, layer, tx, ty, fallbackType)
  if not inRoom(f, tx, ty) then return end
  local k = (layer == 2 and 2 or 1) * 65536 + ty * 256 + tx
  local old = f._todPrev and f._todPrev[k]
  if old then
    f._todPrev[k] = nil
    f.room:setTile(layer == 2 and 2 or 1, tx, ty, old)
  elseif fallbackType then
    f:objects():setTileType(layer == 2 and 2 or 1, tx, ty, fallbackType)
  end
end
M._tiles = { set = setTile, setType = setTileType, restore = restoreTile, index = tileIndex, type = tileType }

-- room property reads (the entity region the importer copied)
local function region(f)
  local A = f.assets
  local reg = A.manifest and A.manifest.entityRegion
  if not reg then return nil end
  A.entityBlob = A.entityBlob or (A.store and A.store:read("entities.bin")) or ""
  return A.entityBlob, reg.base
end
local function rdU16(f, a)
  local b, base = region(f)
  if not b or not a then return nil end
  local lo, hi = b:byte(a - base + 1), b:byte(a - base + 2)
  if not lo or not hi then return nil end
  return lo + 256 * hi
end
local function prop(f, k)
  local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
  return props and props[k]
end
M._rd = { u16 = rdU16, prop = prop }

-- a fire contact (CONTACT_NOW | 7) on box (x, y, w, h)
function M.fireAt(f, x, y, w, h, layer)
  f._todFire = f._todFire or {}
  f._todFire[#f._todFire + 1] = { x = x, y = y, w = w or 6, h = h or 6, layer = layer, t = f.frame }
end
local function fireContact(f, e, hw, hh)
  for _, b in ipairs(f._todFire or {}) do
    if (b.t or 0) >= (f.frame or 0) - 1 and math.abs(b.x - e.x) < b.w + hw and math.abs(b.y - e.y) < b.h + hh then return true end
  end
  for _, t in ipairs(f.entities) do
    if t.fire and not t.deleted and t ~= e then
      if math.abs(t.x - e.x) < (t.hitW or 6) + hw and math.abs(t.y - e.y) < (t.hitH or t.hitW or 6) + hh then return true end
    end
  end
  return false
end
M.fireContact = fireContact

-- the camera has not moved since the last call (lightRay.c sub_0809BE78)
local function settled(f, e)
  local r = e.lastCamX == f.camX and e.lastCamY == f.camY
  e.lastCamX, e.lastCamY = f.camX, f.camY
  return r
end

-- ---------------------------------------------------------------------------
-- light level (gArea / gRoomVars) and the darkness
-- ---------------------------------------------------------------------------
local function light(f)
  local l = f._todLight
  if not l then l = { type = 0, level = 256, target = 256, radius = 0x11, sub = 0, wob = 0 } f._todLight = l end
  return l
end
M.light = light
function M.changeLightLevel(f, n)
  local l = light(f)
  l.target = math.max(0, math.min(256, l.target + n))
end
function M.lanternOn(f) local p = f.player return p and p.usingLantern and true or false end

-- every frame in a dark area: LerpLightLevel, UpdateLightAlpha, the circle
function M.lightUpdate(f)
  local l = light(f)
  if l.type == 0 then return end
  local tgt = math.max(0, math.min(256, l.target))
  if l.level ~= tgt then
    if math.abs(tgt - l.level) <= 4 then l.level = tgt
    elseif tgt < l.level then l.level = l.level - 4 else l.level = l.level + 4 end
  end
  if l.type == 1 then
    local r = l.radius
    if M.lanternOn(f) then
      if r < 0x48 then r = r + 4; l.wob = 0
      elseif band(f.frame or 0, 3) == 0 then
        l.sub = band(l.sub + 16, 0xFF)
        l.wob = math.floor(math.floor(math.sin(l.sub * math.pi / 128) * 256) / 128)
      end
    else
      l.wob = 0
      if r > 0x11 then r = r - 4; if r < 0x11 then r = 0x11 end end
    end
    l.radius = r
  end
  f.lightLevel = l.level
  if false then
  end
end

function M.darkAlpha(level) return LIGHT_ALPHA[math.max(0, math.min(17, rshift(math.floor(level), 4)))] or 0 end

-- the windows where the darkness is not drawn, per row: { {x0, x1}, ... }
local function holesAt(f, l, y, camX, camY, out)
  local n = 0
  local p = f.player
  if l.type == 1 and p then
    local cx, cy = p.x - camX, p.y - camY - 9 - (p.z or 0)
    local r = l.radius + l.wob
    local dy = y - cy
    if math.abs(dy) <= r then
      local w = math.floor(math.sqrt(r * r - dy * dy))
      n = n + 1; out[n] = { cx - w, cx + w }
    end
  end
  for _, e in ipairs(f.entities) do
    if e.litArea and e.lit and not e.deleted then
      local s = 256 / (e.litScale or 0x80)
      local hw, hh = (e.litW or 16) / 2 * s, (e.litH or 16) / 2 * s
      local cx, cy = e.x - camX, e.y - camY + (e.litOY or 0) * s
      local dy = y - cy
      if math.abs(dy) <= hh and hh > 0 then
        local w = hw * math.sqrt(1 - (dy / hh) ^ 2)
        n = n + 1; out[n] = { cx - w, cx + w }
      end
    end
  end
  for i = n + 1, #out do out[i] = nil end
  return n
end

function M.drawDark(f)
  local l = f._todLight
  if not l or l.type == 0 or l.area ~= f.room.area then return end
  local a = M.darkAlpha(l.level)
  if a <= 0 then return end
  local g = love.graphics
  g.setColor(0, 0, 0, a)
  local camX, camY = f.camX or 0, f.camY or 0
  local x0, x1, y0, y1 = -240, 480, -160, 320
  local out = {}
  local runY
  for y = y0, y1 - 1 do
    local n = holesAt(f, l, y + 0.5, camX, camY, out)
    if n == 0 then
      runY = runY or y
    else
      if runY then g.rectangle("fill", x0, runY, x1 - x0, y - runY); runY = nil end
      table.sort(out, function(p, q) return p[1] < q[1] end)
      local x = x0
      for i = 1, n do
        local h = out[i]
        if h[1] > x then g.rectangle("fill", x, y, h[1] - x, 1) end
        if h[2] > x then x = h[2] end
      end
      if x < x1 then g.rectangle("fill", x, y, x1 - x, 1) end
    end
  end
  if runY then g.rectangle("fill", x0, runY, x1 - x0, y1 - runY) end
  g.setColor(1, 1, 1, 1)
end

-- the room's DARKNESS tile entity (room.c LoadDarknessTile -> sub_0805BB00)
function M.darkRoomInit(f)
  local l = light(f)
  local area = f.room.area
  if l.area ~= area then l.type, l.level, l.target, l.radius = 0, 256, 256, 0x11 end
  l.area = area
  l.target = 256 -- gRoomVars.lightLevel = 256 (sub_08052EA0)
  if M.DARK_AREAS[area] then
    for _, te in ipairs(f.room.tileEntities or {}) do
      if te.type == 9 then l.target = te.b or 0; l.type = 1 end
    end
  end
  l.level = l.target -- sub_0805BB74(-1)
  f.lightLevel = l.level -- (EnemyDHC.lua reads gArea.lightLevel here)
end

-- ---------------------------------------------------------------------------
-- SMALL_ICE_BLOCK / BIG_ICE_BLOCK
-- ---------------------------------------------------------------------------
-- sub_0809963C: in the light (room property [type2]) or touched by fire
local function melting(d, e)
  local f = d.field
  if (e.type2 or 0) ~= 0 then
    local a = prop(f, e.type2)
    local fl = a and rdU16(f, a)
    if fl and d:check(fl) then
      local x, y, w, h = rdU16(f, a + 2), rdU16(f, a + 4), rdU16(f, a + 6), rdU16(f, a + 8)
      if x and w and math.floor(e.x) - x >= 0 and math.floor(e.x) - x <= w
         and math.floor(e.y) - y >= 0 and math.floor(e.y) - y <= h then return true end
    end
  end
  return fireContact(f, e, e.hitHW or 4, e.hitHH or 4)
end
M.melting = melting

-- sub_0800442E: a hole / water / lava under it -> the fall / splash, gone
local function hazard(d, e)
  local f = d.field
  local a = actAt(f, e.layer, math.floor(e.x / 16), math.floor(e.y / 16))
  local k = (a == ACT_HOLE and FX_FALL) or (a == ACT_WATER and FX_SPLASH) or (a == ACT_LAVA and FX_LAVA) or nil
  if not k then return false end
  fx(f, e.x, e.y, k)
  e.deleted = true
  return true
end

local function smallPlace(d, e) -- sub_08099468
  local f = d.field
  e.tx, e.ty = math.floor(e.x / 16), math.floor(e.y / 16)
  e.unk6c = tileIndex(f, e.layer, e.tx, e.ty)
  f.room:setTile(e.layer, e.tx, e.ty, SP(90))
end

local function smallSlideStart(d, e) -- sub_080994B8
  local f = d.field
  sfx(f, SFX.SLIDE)
  if e.unk6c then f.room:setTile(e.layer, e.tx, e.ty, e.unk6c) end
  if e.layer == 2 and tileType(f, 1, e.tx, e.ty) == SP(90) then f:objects():setTileType(1, e.tx, e.ty, TT_784) end
  local v = DV[rshift(e.direction, 3)]
  local tt = tileType(f, e.layer, e.tx + v[1], e.ty + v[2])
  if tt == 0x79 or tt == 0x77 then e.spriteOY = -2 end
end

local function shatter(d, e) -- sub_0809969C
  fx(d.field, e.x, e.y, FX_ICE)
  e.deleted = true
end

-- the cell ahead takes a sliding block? (IsTileCollision of the block)
local function cellSolid(f, layer, tx, ty)
  if not inRoom(f, tx, ty) then return true end
  local r = f.room
  local v = r.coll[(layer == 2) and 2 or 1][ty * r.tw + tx] or 0xFF
  return not require("src.zelda.tmc.PushableRock").collisionFreeB(v)
end

-- sub_0809953C: TRUE when it stopped lined up
local function smallSlide(d, e)
  local f = d.field
  if hazard(d, e) then return false end
  local v = DV[rshift(e.direction, 3)]
  local step = e.speed / 256
  local nx, ny = e.x + v[1] * step, e.y + v[2] * step
  -- ProcessMovement2: the leading edge (8 px out) in a solid cell stops it
  -- against that cell (east / south at & $F = 8, west / north at 7)
  local hit = false
  local px, py = math.floor(nx) + v[1] * 8, math.floor(ny) + v[2] * 8
  if cellSolid(f, e.layer, math.floor(px / 16), math.floor(py / 16)) then
    hit = true
    local T = v[1] ~= 0 and math.floor(px / 16) or math.floor(py / 16)
    local stop = (v[1] + v[2] > 0) and (T * 16 - 8) or (T * 16 + 15 + 8)
    if v[1] ~= 0 then nx = stop else ny = stop end
    if v[1] > 0 and nx < e.x then nx = e.x elseif v[1] < 0 and nx > e.x then nx = e.x end
    if v[2] > 0 and ny < e.y then ny = e.y elseif v[2] < 0 and ny > e.y then ny = e.y end
  end
  e.x, e.y = nx, ny
  require("src.zelda.tmc.Hitboxes").pushOut(f, e, { x = 0, y = 0, w = 6, h = 6 }) -- sub_0800445C
  if e.timer ~= 0 then
    e.speed = e.speed + 0x10
    e.timer = e.timer - 1
    if e.timer == 0 then e.speed = 0x200 end
  end
  if not hit then return false end
  local c = v[1] ~= 0 and math.floor(e.x) or math.floor(e.y)
  if band(c, 0xF) - 7 >= 0 and band(c, 0xF) - 7 < 3 then
    if v[1] ~= 0 then e.x = band(c, 0xFFF0) + 8 else e.y = band(c, 0xFFF0) + 8 end
    return true
  end
  shatter(d, e)
  return false
end

local function keyDrop(d, e, item)
  local f = d.field
  local g = f:objects():groundItem(item, 0, e.x, e.y, { kind = 5 })
  if g then g.flagSpec = e.flag end
  sfx(f, SFX.SECRET)
end

local function smallAction3(d, e)
  if not melting(d, e) then
    e.timer = e.timer >= 2 and e.timer - 2 or 0
    if e.timer == 0 then e.action = 1; e.affY = nil return end
  else
    e.timer = e.timer + 1
  end
  e.affY = SMALL_MELT_SCALE[math.min(3, rshift(e.timer, 5))]
  if e.form == 1 then keyDrop(d, e, ITEM_SMALL_KEY)
  elseif e.form == 2 then keyDrop(d, e, ITEM_BIG_KEY) end
  e.action = 4
  e.timer = 60
  e.collide = false
end

local function smallUpdate(d, e)
  local f = d.field
  if e.deleted then return end
  local a = e.action
  if a == 1 then
    if melting(d, e) then
      e.action, e.timer = 3, 0
      sfx(f, SFX.MELT)
      smallAction3(d, e)
      if e.form == 0 then d:set(e.flag) end
    elseif not hazard(d, e) then
      local tt = tileType(f, e.layer, e.tx, e.ty)
      if tt ~= SP(90) then
        local k = SMALL_TILE_KIND[tt]
        if k == 1 then
          e.action, e.timer = 2, 22
          e.direction = lshift(band(tt - 0x5B, 3), 3)
          e.speed = 0x20
          smallSlideStart(d, e)
        elseif k == 2 then
          -- a button pressed under it: that tile is its own now; the block's
          -- tile stays SPECIAL_TILE_90 (the cartridge's button writes under it)
          e.unk6c = tileIndex(f, e.layer, e.tx, e.ty)
          f.room:setTile(e.layer, e.tx, e.ty, SP(90))
        else
          fx(f, e.x, e.y, FX_ICE)
          if e.unk6c then f.room:setTile(e.layer, e.tx, e.ty, e.unk6c) end
          e.deleted = true
        end
      end
    end
  elseif a == 2 then
    if smallSlide(d, e) then
      e.action = 1
      e.spriteOY = 0
      smallPlace(d, e)
      sfx(f, SFX.STOP)
    end
  elseif a == 3 then
    smallAction3(d, e)
  elseif a == 4 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.deleted = true return end
    if e.timer == 0x30 and e.unk6c then f.room:setTile(e.layer, e.tx, e.ty, e.unk6c) end
    e.affY = (0x3C - e.timer) * 0x20 + 0x100
    if band(e.timer, 1) ~= 0 then
      local r = rnd(f)
      local x = (rshift(r, 16) % 9) - 4
      local y = band(r, 0xF)
      fx(f, e.x + x, e.y - y, FX_DASH)
    end
  end
end

-- the shine (types 3 / 4): sub_080996AC / sub_08099D30
local function shineUpdate(d, s)
  local f = d.field
  local par = s.parent
  if not par or par.deleted then s.deleted = true return end
  if (s.action or 0) == 0 then
    s.action = 1
    anim(d, s, s.bigShine and 4 or 3)
    if s.bigShine then s.x, s.y, s.spriteOY = par.x, par.y + 1, (par.spriteOY or 0) - 1 end
  end
  if par.action < (s.bigShine and 2 or 3) then
    s.hidden = false
    if band(fflags(s), 1) ~= 0 then
      take(s)
      if s.anim then s.anim.timer = band(rnd(f), 0x78) + 0x78 end
    end
    if s.anim then s.anim:update(1) end
    if not s.bigShine then s.x, s.y, s.spriteOY = par.x, par.y + 1, (par.spriteOY or 0) - 0x11 end
  else
    s.hidden = true
  end
end

local function addShine(d, e, big)
  local f = d.field
  local s = { kind = 6, id = e.id, form = big and 4 or 3, x = e.x, y = e.y, z = 0, layer = e.layer, parent = e,
              bigShine = big, action = 0, animationState = 0, field80 = 0, field82 = 0, interactType = 0, dungeon = true }
  if not dress(d, s, e.id, s.form) then dress(d, s, e.id, 0) end
  s.extUpdate = function(dd, me) shineUpdate(dd, me) end
  f.entities[#f.entities + 1] = s
  d:track(s)
  return s
end

-- affine y scale (SetAffineInfo(0x100, ys)): the picture squashed
local function drawAffine(e, f, camX, camY)
  local A = f.assets
  local frame = e.staticFrame or (e.anim and e.anim.frame)
  if not frame or frame == 0xFF or e.hidden then return end
  local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette, "e" .. tostring(e.def and e.def.palette) .. ":6", e.gfx)
  if not img then return end
  local sx, sy = 256 / (e.affX or 256), 256 / (e.affY or 256)
  local x = math.floor(e.x - camX + (e.spriteOX or 0))
  local y = math.floor(e.y - camY - (e.z or 0) + (e.spriteOY or 0))
  local w, h = img:getWidth(), img:getHeight()
  local cx, cy = ox + w / 2, oy + h / 2
  love.graphics.draw(img, x + cx, y + cy, 0, sx, sy, w / 2, h / 2)
end
M.drawAffine = drawAffine

function M.spawnSmallIce(d, e)
  local f = d.field
  if (e.form or 0) <= 2 and d:check(e.flag) then return nil end
  if (e.form or 0) > 2 then return false end -- types 3+ are its children
  dress(d, e, ID.SMALL_ICE, e.form)
  e.iceBlock = true
  e.todSmallIce = true
  e.action = 1
  e.collide = true
  e.hitHW, e.hitHH = 4, 4 -- gUnk_080FD408
  smallPlace(d, e)
  anim(d, e, e.form)
  e.drawGhost = function(me, ff, cx, cy) drawAffine(me, ff, cx, cy) end
  e.extUpdate = function(dd, me) smallUpdate(dd, me) end
  d:track(e)
  addShine(d, e, false)
  return e
end

-- sub_08099910: the block's tiles by its alignment
local function bigTiles(d, e, restore)
  local f = d.field
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  local L = e.layer
  local k = e.unk6c
  local function put(dx, dy, edge, iceEdge)
    local x, y = tx + dx, ty + dy
    if restore then restoreTile(f, L, x, y) return end
    local t = edge
    if iceEdge and actAt(f, L, x, y) == ACT_ICE then t = iceEdge end
    setTile(f, L, x, y, SP(t))
  end
  if k == 1 then
    put(-1, -1, 36, 121); put(0, -1, 34); put(1, -1, 37, 123)
    put(-1, 0, 36, 121); put(0, 0, 34); put(1, 0, 37, 123)
  elseif k == 2 then
    put(-1, -1, 35, 119); put(0, -1, 35, 119)
    put(-1, 0, 34); put(0, 0, 34)
    put(-1, 1, 38, 124); put(0, 1, 38, 124)
  elseif k == 3 then
    put(-1, -1, 39, 117); put(0, -1, 35, 119); put(1, -1, 40, 118)
    put(-1, 0, 36, 121); put(0, 0, 34); put(1, 0, 37, 123)
    put(-1, 1, 41, 120); put(0, 1, 38, 124); put(1, 1, 42, 122)
  else
    put(-1, -1, 34); put(0, -1, 34); put(-1, 0, 34); put(0, 0, 34)
  end
end
M.bigTiles = bigTiles

local function bigUpdate(d, e)
  local f = d.field
  if e.deleted then return end
  local a = e.action
  if a == 1 then
    if melting(d, e) then
      e.action, e.timer = 2, 0
      sfx(f, SFX.MELT)
      a = 2
    end
  end
  if a == 2 then
    if not melting(d, e) then
      e.timer = e.timer >= 2 and e.timer - 2 or 0
      if e.timer == 0 then e.action = 1; e.affY = nil return end
    else
      e.timer = e.timer + 1
    end
    e.affY = BIG_MELT_SCALE[math.min(4, rshift(e.timer, 5))]
    if e.form ~= 1 then
      if e.form ~= 2 then d:set(e.flag) else keyDrop(d, e, ITEM_SMALL_KEY) end
    end
    e.action, e.timer, e.collide = 3, 60, false
  elseif a == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.deleted = true return end
    if e.timer == 0x30 then bigTiles(d, e, true) end
    local ys = (0x3C - e.timer) * 0x20 + 0x100
    e.affY = ys
    e.spriteOY = -(2 - rshift(2 * math.floor(0x10000 / ys), 8)) -- sub_0806FCF4(super, ys, 2, 0)
    local r = rnd(f)
    local x = (rshift(r, 16) % 0x21) - 0x10
    local y = band(r, 0xF) - 4
    fx(f, e.x + x, e.y + y, FX_DASH)
  end
end

function M.spawnBigIce(d, e)
  if (e.form or 0) >= 4 then return false end
  if d:check(e.flag) then return nil end
  dress(d, e, ID.BIG_ICE, e.form)
  e.todBigIce = true
  e.action = 1
  e.collide = true
  e.hitHW, e.hitHH = 14, 14 -- gUnk_080FD190
  e.unk6c = rshift(band(math.floor(e.x), 8), 3) + rshift(band(math.floor(e.y), 8), 2)
  bigTiles(d, e, false)
  anim(d, e, e.form)
  e.drawGhost = function(me, ff, cx, cy) drawAffine(me, ff, cx, cy) end
  e.extUpdate = function(dd, me) bigUpdate(dd, me) end
  d:track(e)
  addShine(d, e, true)
  return e
end

-- ice blocks sitting on a button's tile (button.c: the tile under it changed)
function M.blockOn(f, tx, ty)
  for _, e in ipairs(f.entities) do
    if e.todSmallIce and not e.deleted and e.action == 1 and e.tx == tx and e.ty == ty then return true end
  end
  return false
end

-- UpdatePlayerCollision, SPECIAL_TILE_90: Link pushes a small ice block
local PDV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
local function pushUpdate(p)
  local ps = p.todPush
  if p.anim then p.anim:update(1) end
  ps.left = ps.left - 1
  local v = PDV[p.animationState] or PDV[4]
  p:moveBy(v[1] * 0.5, v[2] * 0.5) -- kPushSpeed
  if ps.left <= 0 then p.todPush = nil; p.extUpdate = nil; p.state = "normal"; p.pushT = 0 end
end
-- PLAYER_PUSH with pushedObject n (n & $7F frames at kPushSpeed)
function M.playerPush(p, n)
  p.state = "ext"
  p.x, p.y = math.floor(p.x), math.floor(p.y)
  p.todPush = { left = band(n, 0x7F) }
  p.extUpdate = pushUpdate
end
function M.tryPush(p)
  local f = p.field
  if p.state ~= "normal" or not p.probe or not (f.room and f.room.tileType) then return false end
  local v = PDV[p.animationState]
  if not v then return false end
  local fx_, fy_ = p:probe()
  local tx, ty = math.floor(fx_ / 16), math.floor(fy_ / 16)
  local layer = p.layer == 2 and 2 or 1
  if f.room:tileType(layer, tx, ty) ~= SP(90) then return false end
  -- sub_0801A2B0(.., 2): the tile beyond free
  if not require("src.zelda.tmc.PushableRock").beyondFree(f, layer, tx + v[1], ty + v[2]) then return false end
  f.room:setTile(layer, tx, ty, SP(91) + p.animationState / 2)
  M.playerPush(p, 0x98)
  return true
end

-- ---------------------------------------------------------------------------
-- FROZEN_FLOWER / FROZEN_WATER_ELEMENT
-- ---------------------------------------------------------------------------
function M.spawnFlower(d, e)
  dress(d, e, ID.FROZEN_FLOWER, e.form)
  e.action = 1
  e.staticFrame = e.form or 0
  e.spritePriority = 7
  return e
end

local FWE_TILES = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -2, 0 }, { -1, 0 }, { 0, 0 }, { 1, 0 }, { 2, 0 }, { -2, 1 }, { -1, 1 },
                    { 0, 1 }, { 1, 1 }, { 2, 1 }, { -1, 2 }, { 0, 2 }, { 1, 2 }, { -1, 5 }, { 0, 5 }, { 1, 5 }, { -1, 6 },
                    { 1, 6 }, { -3, 7 }, { -2, 7 }, { -1, 7 }, { 1, 7 }, { 2, 7 }, { 3, 7 } }
M.FWE_TILES = FWE_TILES
local function fweTiles(d, e, restore)
  local f = d.field
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  for _, t in ipairs(FWE_TILES) do
    if restore then restoreTile(f, e.layer, tx + t[1], ty + t[2]) else setTile(f, e.layer, tx + t[1], ty + t[2], SP(34)) end
  end
end

local function fweUpdate(d, e)
  local f = d.field
  if e.deleted then return end
  if e.action == 1 then
    e.affX, e.affY = 0xCC, 0xCC
    if lflag(f, 0x37) then -- OUGONTEKI_G
      local w = { kind = 6, id = ID.WATER_ELEMENT, form = 0, x = e.x, y = e.y + 4, z = 0, layer = e.layer, action = 1,
                  animationState = 0, field80 = 0, field82 = 0, interactType = 0, dungeon = true }
      dress(d, w, ID.WATER_ELEMENT, 0)
      w.staticFrame = 0
      w.spritePriority = 5
      f.entities[#f.entities + 1] = w
      e.water = w
      f.cameraTarget = w
      if e.child then e.child.child = w end
      e.action = 2
      e.unk74 = 0x140
      sfx(f, SFX.MELT)
    end
  elseif e.action == 2 then
    e.unk74 = e.unk74 - 1
    if e.unk74 == 0 then
      if e.child then e.child.subtimer = 1 end
      fweTiles(d, e, true)
      e.deleted = true
      return
    end
    if band(e.unk74, 0x1F) == 0 then sfx(f, SFX.MELT) end
    if e.unk74 < 0x78 then
      local t = 0x78 - e.unk74
      local ys = t * 32 + 0xCC
      e.affX, e.affY = t * 16 + 0xCC, ys
      e.spriteOY = -(8 - rshift(8 * math.floor(0x10000 / ys), 8)) + 8
    end
    local v = FWE_DASH[rshift(e.unk74, 5)] or 0
    local ox, oy = e.dataX or e.x, e.dataY or e.y
    local r = rnd(f)
    fx(f, ox + band(rshift(r, 16), v) - rshift(v + 1, 1), oy + band(rshift(v, 1), r) - rshift(v + 1, 2), FX_DASH)
    r = rnd(f)
    fx(f, ox + band(rshift(r, 16), v) - rshift(v + 1, 1), oy + band(rshift(v, 1), r), FX_DEATH)
  end
end

function M.spawnFrozenElement(d, e)
  local f = d.field
  if lflag(f, 0x9B) then return nil end
  -- CreateObject(FROZEN_OCTOROK, 0, 0): whichever module ports it
  local okc, child = pcall(function()
    return d:spawnObject({ kind = 6, id = ID.FROZEN_OCTOROK, paramA = 0, paramB = 0, paramC = 0, pool = 0x0F,
                           x = e.x, y = e.y, collision = e.layer })
  end)
  if okc and type(child) == "table" then
    child.frozenElement = e
    local seen = false
    for _, t in ipairs(f.entities) do if t == child then seen = true break end end
    if not seen then f.entities[#f.entities + 1] = child end
  else
    child = { stub = true }
  end
  e.child = child
  dress(d, e, ID.FROZEN_WATER_ELEMENT, 0)
  e.action = 1
  e.staticFrame = 0
  e.dataX, e.dataY = e.data and e.data.x or e.x, e.data and e.data.y or e.y
  fweTiles(d, e, false)
  e.affX, e.affY = 0xCC, 0xCC
  e.todFrozenElement = true
  e.drawGhost = function(me, ff, cx, cy) drawAffine(me, ff, cx, cy) end
  e.extUpdate = function(dd, me) fweUpdate(dd, me) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- LIGHT_DOOR / LIT_AREA
-- ---------------------------------------------------------------------------
local function lightDoorUpdate(d, e)
  if e.deleted then return end
  if e.action == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.timer, e.spriteOY = 3, 30, 4 end
  elseif e.action == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.timer = 4, 96 end
  elseif e.action == 4 then
    e.x = e.x - e.speed / 256 -- LinearMoveUpdate, direction $18
    e.timer = e.timer - 1
    if e.timer == 0 then e.deleted = true end
  end
end

function M.spawnLightDoor(d, e)
  local f = d.field
  dress(d, e, ID.LIGHT_DOOR, e.form)
  e.staticFrame = 0
  if (e.form or 0) == 0 then
    if d:check(e.flag) then return nil end
    e.action = 1
    e.spritePriority = 7
    local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
    for dy = -1, 1 do for dx = -1, 1 do setTile(f, e.layer, tx + dx, ty + dy, SP(61)) end end
  else
    e.action, e.timer, e.speed, e.direction = 2, 240, 0x80, 0x18
  end
  e.lightDoor = true
  e.extUpdate = function(dd, me) lightDoorUpdate(dd, me) end
  d:track(e)
  return e
end

local function litUpdate(d, e)
  local f = d.field
  if e.deleted then return end
  if not e.lit then
    if e.flag ~= 0 and not d:check(e.flag) then return end
    e.lit = true
    e.litScale, e.litStep, e.timer = 0x80, -2, 2
    local A = f.assets
    local img, ox, oy
    if A.spriteFrame then img, ox, oy = A:spriteFrame(e.sprite, 3, e.palette, "litarea", e.gfx) end
    if img then
      e.litW, e.litH = img:getWidth(), img:getHeight()
      e.litOY = (oy or -e.litH / 2) + e.litH / 2
    end
  else
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.timer = 2
      e.litScale = e.litScale + e.litStep
      if e.litScale < 0x78 then e.litStep = 1 end
      if e.litScale > 0x88 then e.litStep = -1 end
    end
  end
end

function M.spawnLitArea(d, e)
  dress(d, e, ID.LIT_AREA, e.form)
  e.litArea = true
  e.hidden = true -- an OBJ window: never drawn itself
  e.staticFrame = 3
  e.extUpdate = function(dd, me) litUpdate(dd, me) end
  d:track(e)
  litUpdate(d, e)
  return e
end

-- ---------------------------------------------------------------------------
-- PUSHABLE_LEVER / BIG_PUSHABLE_LEVER
-- ---------------------------------------------------------------------------
local function leverSetTiles(d, e)
  local f = d.field
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  if not d:check(e.flag) then
    e.type2 = 0
    if e.bigLever then
      e.upX, e.upY, e.loX, e.loY = tx, ty - 1, tx, ty - 2
      e.upIdx, e.loIdx = tileIndex(f, e.layer, e.upX, e.upY), tileIndex(f, e.layer, e.loX, e.loY)
      f.room:setTile(e.layer, e.upX, e.upY, SP(87))
      f.room:setTile(e.layer, e.loX, e.loY, SP(88))
    else
      e.loX, e.loY = tx, ty - 1
      e.loIdx = tileIndex(f, e.layer, e.loX, e.loY)
      f.room:setTile(e.layer, e.loX, e.loY, SP(83))
    end
    anim(d, e, 1)
  else
    e.type2 = 1
    if e.bigLever then
      e.upX, e.upY, e.loX, e.loY = tx - 1, ty, tx - 2, ty
      e.upIdx, e.loIdx = tileIndex(f, e.layer, e.upX, e.upY), tileIndex(f, e.layer, e.loX, e.loY)
      f.room:setTile(e.layer, e.upX, e.upY, SP(85))
      f.room:setTile(e.layer, e.loX, e.loY, SP(86))
    else
      e.loX, e.loY = tx - 1, ty
      e.loIdx = tileIndex(f, e.layer, e.loX, e.loY)
      f.room:setTile(e.layer, e.loX, e.loY, SP(82))
    end
    anim(d, e, 0)
  end
end

local function leverIdle(d, e)
  e.action = 1
  e.ltimer = 60
  leverSetTiles(d, e)
end

local function leverUpdate(d, e)
  local f = d.field
  if e.deleted then return end
  if e.action == 1 then
    local start = false
    if tileIndex(f, e.layer, e.loX, e.loY) == (e.bigLever and SP(89) or SP(84)) then
      e.ltimer = e.ltimer - 1
      if e.ltimer == 0 then start = true
      else
        local o = LEVER_OFFS[e.type2][band(rshift(e.ltimer, 2), 6) / 2]
        e.spriteOX, e.spriteOY = o[1], o[2]
        if band(e.ltimer, 3) == 0 then sfx(f, e.bigLever and SFX.S131 or SFX.PLACE_OBJ) end
        local back = e.bigLever and (e.type2 == 0 and SP(88) or SP(86)) or (e.type2 == 0 and SP(83) or SP(82))
        f.room:setTile(e.layer, e.loX, e.loY, back)
      end
    else
      e.ltimer = 60
      e.spriteOX, e.spriteOY = 0, 0
    end
    if start then
      e.action = 2
      e.spriteOX, e.spriteOY = 0, 0
      if e.bigLever and e.upIdx then f.room:setTile(e.layer, e.upX, e.upY, e.upIdx) end
      if e.loIdx then f.room:setTile(e.layer, e.loX, e.loY, e.loIdx) end
      sfx(f, e.bigLever and SFX.S132 or SFX.S16A)
      local p = f.player
      if p and p.state == "normal" then M.playerPush(p, e.bigLever and 0x98 or 0x90) end
    end
  elseif e.action == 2 then
    if e.anim then e.anim:update(1) end
    if not e.anim or e.anim.done then
      if e.type2 == 0 then d:set(e.flag) else d:set(e.flag, false) end
      leverIdle(d, e)
    end
  end
end

function M.spawnLever(d, e, big)
  dress(d, e, big and ID.BIG_LEVER or ID.LEVER, e.form)
  e.bigLever = big or nil
  e.todLever = true
  e.spritePriority = 5
  leverIdle(d, e)
  e.extUpdate = function(dd, me) leverUpdate(dd, me) end
  d:track(e)
  return e
end

-- sub_0801A8D0: the lever tile a clone pushes (mode 0: north, 6: west)
local function cloneLever(f, c, mode)
  if not c or c.deleted then return nil end
  local layer = c.layer == 2 and 2 or 1
  if mode == 0 then
    local tx, ty = math.floor(c.x / 16), math.floor((c.y - 8) / 16)
    local t = tileIndex(f, layer, tx, ty)
    if t == SP(85) then return tx - 1, ty end
    if t == SP(86) then return tx, ty end
  else
    local tx, ty = math.floor((c.x - 8) / 16), math.floor(c.y / 16)
    local t = tileIndex(f, layer, tx, ty)
    if t == SP(87) then return tx, ty - 1 end
    if t == SP(88) then return tx, ty end
  end
  return nil
end

-- UpdatePlayerCollision's lever cases (Link in PL_STATE_PUSH, field_0x35 = facing)
function M.leverPush(p)
  local f = p.field
  if not p.pushing or p.state ~= "normal" or not p.probe then return false end
  local px, py = p:probe()
  local tx, ty = math.floor(px / 16), math.floor(py / 16)
  local layer = p.layer == 2 and 2 or 1
  local t = tileIndex(f, layer, tx, ty)
  local s = p.animationState
  if t == SP(82) then
    if s ~= 0 then return false end
    f.room:setTile(layer, tx, ty, SP(84)) return true
  elseif t == SP(83) then
    if s ~= 6 then return false end
    f.room:setTile(layer, tx, ty, SP(84)) return true
  elseif t == SP(85) or t == SP(86) then
    if t == SP(85) then tx = tx - 1 end
    if s ~= 0 or band(math.floor(p.y), 0xF) < 10 then return false end
    for _, c in ipairs(f.playerClones or {}) do
      local cx, cy = cloneLever(f, c, 0)
      if cx == tx and cy == ty then f.room:setTile(layer, tx, ty, SP(89)) return true end
    end
  elseif t == SP(87) or t == SP(88) then
    if t == SP(87) then ty = ty - 1 end
    if s ~= 6 or band(math.floor(p.x), 0xF) < 10 then return false end
    for _, c in ipairs(f.playerClones or {}) do
      local cx, cy = cloneLever(f, c, 6)
      if cx == tx and cy == ty then f.room:setTile(layer, tx, ty, SP(89)) return true end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- LIGHT_RAY (made by the Temple of Droplets managers)
-- ---------------------------------------------------------------------------
local function rayEnd(f, e)
  if e.parent then e.parent.subAction = 1 end
  e.deleted = true
  if f.cameraTarget == e then f.cameraTarget = nil end
  if f.player then f.player.control = true end
end

local function rayUpdate(d, e)
  local f = d.field
  if e.deleted then return end
  local p = f.player
  local t = e.form
  if p then p.control = false end -- RequestPriorityDuration
  if e.action == 0 then
    e.action, e.timer = 1, 60
    f.cameraTarget = e
    f.scrollSpeed = 1
    if p then p.animationState = e.x > p.x and 2 or 6 end
    if t == 0 then e.subtimer = 0 elseif t == 1 then e.subtimer = 32 elseif t == 4 then e.subtimer = 128
    elseif t == 2 then e.win = 0x60 elseif t == 3 then e.subAction = 0x80 end
    settled(f, e)
    return
  end
  local frame = f.frame or 0
  if t == 0 or t == 1 or t == 4 then
    if e.action == 1 then
      if e.timer ~= 0 then e.timer = e.timer - 1
      else
        local more
        if t == 0 then more = e.subtimer < 0x20 elseif t == 1 then more = e.subtimer ~= 0
        else e.subtimer = e.subtimer - 1; more = e.subtimer ~= 0 end
        if more then
          if band(frame, 0x1F) == 0 then sfx(f, SFX.S133) end
          if t ~= 4 and band(frame, 3) == 0 then e.subtimer = e.subtimer + (t == 0 and 1 or -1) end
        else
          e.action, e.timer = 2, 60
          f.cameraTarget = nil
          sfx(f, SFX.S134)
        end
      end
    elseif e.action == 2 then
      e.timer = e.timer - 1
      if e.timer == 0 then f.scrollSpeed = 4; rayEnd(f, e) end
    end
  elseif t == 2 then
    if e.action == 1 then
      if settled(f, e) then
        if e.timer ~= 0 then e.timer = e.timer - 1
        elseif e.win < 0xE0 then
          if band(frame, 0x1F) == 0 then sfx(f, SFX.S133) end
          if band(frame, 1) == 0 then e.win = e.win + 1 end
        else
          e.action, e.timer = 2, 30
          e.x, e.y = e.x + 0x68, e.y + 0x28
          sfx(f, SFX.S134)
        end
      end
    elseif e.action == 2 then
      if settled(f, e) then
        e.timer = e.timer - 1
        if e.timer == 0 then
          e.timer, e.action = 120, 3
          setL(f, 0x35)
          sfx(f, SFX.SECRET)
        end
      end
    elseif e.action == 3 then
      e.timer = e.timer - 1
      if e.timer == 0 then e.action = 4; f.cameraTarget = nil; f.scrollSpeed = 2 end
    elseif e.action == 4 then
      if settled(f, e) then
        f.scrollSpeed = 4
        f:setFlag("room", 100, true)
        rayEnd(f, e)
      end
    end
  elseif t == 3 then
    if e.action == 1 then
      if settled(f, e) then
        if e.timer ~= 0 then e.timer = e.timer - 1
        elseif e.subAction ~= 0 then
          if band(frame, 0x1F) == 0 then sfx(f, SFX.S133) end
          if band(frame, 1) == 0 then e.subAction = e.subAction - 1 end
        else
          e.action, e.timer = 2, 120
          setL(f, 0x37) -- OUGONTEKI_G
          sfx(f, SFX.S134)
        end
      end
    elseif e.action == 2 then
      e.timer = e.timer - 1
      if e.timer == 0 then rayEnd(f, e) end
    end
  end
end

-- sub_0805A4CC: CreateObject(LIGHT_RAY, type) 48 px above the manager's spot
local function makeRay(d, m, t)
  local e = { kind = 6, id = ID.LIGHT_RAY, form = t, x = m.x, y = m.y - 0x30, z = 0, layer = 1, action = 0, timer = 0,
              parent = m, hidden = true, animationState = 0, field80 = 0, field82 = 0, interactType = 0, dungeon = true,
              lightRay = true }
  e.extUpdate = function(dd, me) rayUpdate(dd, me) end
  d:track(e)
  m.subAction = 0
  m.ray = e
  return e
end
M.makeRay = makeRay

-- ---------------------------------------------------------------------------
-- TEMPLE_OF_DROPLETS_MANAGER
-- ---------------------------------------------------------------------------
-- PLAYER_WARP (field_0x38 = 0, field_0x39 = 0): sub_0807B1A8's steps
local function warpUpdate(p)
  local f = p.field
  local w = p.todWarp
  if band(f.frame or 0, 7) == 0 then fx(f, p.x, p.y - (p.z or 0), FX_SPARKLE) end
  if w.step == 0 then w.step, w.t = 1, 30
  elseif w.step == 1 then
    w.t = w.t - 1
    if w.t == 0 then w.step, w.zv = 2, 1.0; p:setAnim(0x2C2, true) end -- ANIM_PORTAL
  elseif w.step == 2 then
    if p.anim then p.anim:update(1) end
    p.z = (p.z or 0) + w.zv
    w.zv = w.zv - (w.zv < 0 and 4 / 256 or 8 / 256)
    if w.zv < -0.5 then w.step, w.t, w.sub, w.z0 = 3, 120, 0, p.z end
  elseif w.step == 3 then
    if p.anim then p.anim:update(1) end
    w.sub = band(w.sub + 2, 0xFF)
    p.z = w.z0 + math.floor(math.sin(w.sub * math.pi / 128) * 256 / 128)
    w.t = w.t - 1
    if w.t == 0 then w.step, w.t, w.zv = 4, 80, 0.5 end
  elseif w.step == 4 then
    p.z = p.z + w.zv
    w.zv = w.zv + 32 / 256
    if p.anim then p.anim:update(1) end
    if w.t ~= 0 then
      w.t = w.t - 1
      if w.t == 0 then f:startTransition(WARP_LAKE) end
    end
  end
end
function M.startWarp(p)
  p.state = "ext"
  p.todWarp = { step = 0 }
  p.extUpdate = warpUpdate
end

local function todBg(m, on) m.bg3 = on end -- the BG3 light (not drawn: SIMPLIFIED)

local function todType6Near(f, m) return f:playerInRegion(m.x, m.y, 6, 6) end -- CheckPlayerProximity(x-6, y-6, 12, 12)

local function todUpdate(d, m)
  local f = d.field
  local t = m.type
  local lf = m.c1 -- localFlag
  if t == 0 then
    if m.action == 0 then m.action = 1; m.unk23 = lflag(f, lf) and 2 or 1; todBg(m, true) end
  elseif t == 1 then
    if m.action == 0 then
      m.unk23 = 1
      if not lflag(f, lf) then m.action = 1; todBg(m, false)
      else m.action = lflag(f, 0x48) and 4 or 3; todBg(m, true) end
    elseif m.action == 1 then
      if lflag(f, lf) then m.action = 2; makeRay(d, m, 0) end
    elseif m.action == 2 then
      if m.subAction ~= 0 then
        f:loadEntityList(LISTS.blueChuFreed)
        m.action = 3
        if f.bgm then f:bgm(nil) end
      end
    elseif m.action == 3 then
      local boss
      for _, e in ipairs(f.entities) do if e.enemy and e.id == 0x13 and not e.deleted then boss = e break end end
      if boss and (boss.form or boss.type) ~= 4 then return end
      setL(f, 0x48) -- LV1_16_1STEND
      f:setFlag("room", 0, false)
      todBg(m, false)
      m.deleted = true
    end
  elseif t == 2 or t == 3 then
    if m.action == 0 then
      m.unk23 = t == 3 and 2 or 1
      if not lflag(f, lf) then d:set(m.c0, false); m.action = 1; todBg(m, false)
      else d:set(m.c0); m.action = 3; todBg(m, true) end
    elseif m.action == 1 then
      if lflag(f, lf) then m.action = 2; makeRay(d, m, 0) end
    elseif m.action == 2 then
      if m.subAction ~= 0 then m.action = 3; d:set(m.c0) end
    elseif m.action == 3 then
      if not lflag(f, lf) then m.action = 4; makeRay(d, m, 1) end
    elseif m.action == 4 then
      if m.subAction ~= 0 then m.action = 1; d:set(m.c0, false) end
    end
  elseif t == 4 then
    if m.action == 0 then
      if lflag(f, 0x36) then m.unk23, m.action = 3, 5; todBg(m, true)
      elseif lflag(f, 0x34) then m.unk23, m.action = 4, 3; todBg(m, true)
      else m.unk23, m.action = 4, 1; todBg(m, false) end
    elseif m.action == 1 then
      if lflag(f, 0x34) then m.action = 2; makeRay(d, m, 2) end
    elseif m.action == 2 then
      if m.subAction ~= 0 then m.action = 3 end
    elseif m.action == 3 then
      if lflag(f, 0x36) then m.action, m.unk23 = 4, 3; makeRay(d, m, 3) end
    elseif m.action == 4 then
      if m.subAction ~= 0 then m.action = 5 end
    end
  elseif t == 6 then
    if m.action == 0 then
      m.unk23 = 0
      m.action = todType6Near(f, m) and 1 or 2
      m.alpha = 0x1000
      todBg(m, true)
    elseif m.action == 1 then
      if not todType6Near(f, m) then m.action = 2 end
    elseif m.action == 2 then
      local p = f.player
      if p and (f.save and f.save.stats and (f.save.stats.health or 1) > 0) and (p.z or 0) == 0 and p.state == "normal"
         and todType6Near(f, m) then
        m.action = 3
        p.x, p.y = math.floor(p.x / 16) * 16 + 8, math.floor(p.y / 16) * 16 + 8 -- SnapToTile
        p.animationState = 4
        f.cameraTarget = nil
        M.startWarp(p)
      end
    end
    -- sub_0805A68C: the light's blend toward Link
    if f:playerInRegion(m.x, m.y, 0x18, 0x18) then
      if m.alpha <= 0x1007 then m.alpha = m.alpha + 1 end
    elseif m.alpha > 0x1000 then m.alpha = m.alpha - 1 end
  elseif t == 7 then
    if m.action == 0 then m.action = lflag(f, lf) and 1 or 2; m.subAction = 1
    elseif m.action == 1 then
      if not lflag(f, lf) then m.action = 2; makeRay(d, m, 4) end
    elseif m.action == 2 then
      if m.subAction ~= 0 then m.action = 3 end
    elseif m.action == 3 then
      if lflag(f, lf) then m.action = 4; makeRay(d, m, 4) end
    elseif m.action == 4 then
      if m.subAction ~= 0 then m.action = 1 end
    end
  end
end

-- ---------------------------------------------------------------------------
-- LIGHT_LEVEL_SET_MANAGER
-- ---------------------------------------------------------------------------
local function flameAt(d, m) -- sub_0805BEC4: FLAME type 1 at the torch
  local f = d.field
  local e = { kind = 6, id = ID.FLAME, form = 1, x = m.x, y = m.y - 8, z = 0, layer = m.type2 == 2 and 2 or 1,
              animationState = 0, field80 = 0, field82 = 0, interactType = 0, dungeon = true, timer = 40 }
  if dress(d, e, ID.FLAME, 1) then
    anim(d, e, 0)
    e.spritePriority = 2
    e.extUpdate = function(dd, me)
      if me.anim then me.anim:update(1) end
      me.timer = me.timer - 1
      if me.timer < 0 then me.deleted = true end
    end
    f.entities[#f.entities + 1] = e
    d:track(e)
  end
  sfx(f, SFX.S124)
end

local function torch(m) return band(rshift(m.x, 4), 0x3F), band(rshift(m.y, 4), 0x3F) end
local function llsLit(d, m) -- sub_0805BE94
  local f = d.field
  local tx, ty = torch(m)
  setTileType(f, m.type2, tx, ty, TT_TORCH_ON)
  M.changeLightLevel(f, m.amount)
  m.deleted = true
end

local function llsUpdate(d, m)
  local f = d.field
  if m.deleted then return end
  local t = m.type
  local tx, ty = torch(m)
  local lit = tileType(f, m.type2, tx, ty) == TT_TORCH_ON
  if t == 0 then
    if m.action == 0 then
      m.action, m.subtimer = 1, 30
      if d:check(m.c1) then llsLit(d, m) return end
    end
    if d:check(m.c1) then
      m.subtimer = m.subtimer - 1
      if m.subtimer == 0 then flameAt(d, m); llsLit(d, m) end
    end
  elseif t == 1 then
    if m.action == 0 then
      m.action, m.subtimer = 1, 30
      if d:check(m.c1) then setTileType(f, m.type2, tx, ty, TT_TORCH_OFF); m.action = 2 end
    elseif m.action == 1 then
      if d:check(m.c1) then
        m.subtimer = m.subtimer - 1
        if m.subtimer == 0 then m.subtimer = 30; flameAt(d, m); setTileType(f, m.type2, tx, ty, TT_TORCH_ON) end
      end
    elseif m.action == 2 then
      if not d:check(m.c1) then
        m.subtimer = m.subtimer - 1
        if m.subtimer == 0 then m.subtimer = 30; setTileType(f, m.type2, tx, ty, TT_TORCH_OFF) end
      end
    end
  elseif t == 2 then
    if m.action == 0 then
      if d:check(m.c1) then llsLit(d, m) return end
      m.action = 1
    elseif lit then
      d:set(m.c1)
      M.changeLightLevel(f, m.amount)
      m.deleted = true
    end
  elseif t == 3 then
    if m.action == 0 then
      if d:check(m.c1) or d:check(m.c0) then llsLit(d, m) return end
      m.action = 1
    elseif m.action == 1 then
      if not lit then return end
      d:set(m.c1)
      M.changeLightLevel(f, m.amount)
      m.action = 2
      m.t22 = m.burn * 60
    else
      m.t22 = m.t22 - 1
      if m.t22 == 0 then
        fx(f, m.x, m.y, FX_DEATH) -- CreateDeathFxAt
        d:set(m.c1, false)
        restoreTile(f, m.type2, tx, ty, TT_TORCH_OFF)
        M.changeLightLevel(f, -m.amount)
        m.action = 1
      elseif d:check(m.c0) then
        flameAt(d, m)
        m.deleted = true
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- MISC_MANAGER types 4 / 5, WATERFALL_BOTTOM_MANAGER
-- ---------------------------------------------------------------------------
local function miscUpdate(d, m)
  local f = d.field
  if m.deleted then return end
  if m.type == 4 then
    m.action = 1
    setL(f, 0x4A, lflag(f, 0x6C) and lflag(f, 0x4B) or false)
  elseif m.type == 5 then
    local tx, ty = torch(m)
    if m.action == 0 then
      if d:check(m.c1) then m.deleted = true return end
      m.action = 1
      setTileType(f, m.type2, tx, ty, TT_869)
    elseif m.action == 1 then
      if d:check(m.c1) then m.timer, m.action = 45, 2 end
    else
      m.timer = m.timer - 1
      if m.timer <= 0 then
        fx(f, m.x, m.y, FX_DEATH)
        restoreTile(f, m.type2, tx, ty)
        sfx(f, SFX.TASK_COMPLETE)
        m.deleted = true
      end
    end
  end
end

function M.waterfallBottom(f)
  setTile(f, 1, 3, 23, SP(20))
  local p = f.player
  if p and p.y > 200 and p.x - 0x30 >= 0 and p.x - 0x30 < 0x11 then p.layer = 3 end
end

-- ---------------------------------------------------------------------------
-- the ice floor (asm/src/player.s sub_08008942)
-- ---------------------------------------------------------------------------
function M.onIce(f, p)
  local layer = p.layer == 2 and 2 or 1
  return actAt(f, layer, math.floor(p.x / 16), math.floor(p.y / 16)) == ACT_ICE
end
local function dir8(dx, dy)
  if dx == 0 and dy < 0 then return 0 elseif dx > 0 and dy < 0 then return 1 elseif dx > 0 and dy == 0 then return 2
  elseif dx > 0 and dy > 0 then return 3 elseif dx == 0 and dy > 0 then return 4 elseif dx < 0 and dy > 0 then return 5
  elseif dx < 0 and dy == 0 then return 6 elseif dx < 0 and dy < 0 then return 7 end
  return nil
end
M.dir8 = dir8
local function facingFor(dx, dy, cur)
  if dy < 0 and cur == 0 then return 0 end
  if dx > 0 and cur == 2 then return 2 end
  if dy > 0 and cur == 4 then return 4 end
  if dx < 0 and cur == 6 then return 6 end
  if dy < 0 then return 0 end
  if dy > 0 then return 4 end
  if dx > 0 then return 2 end
  if dx < 0 then return 6 end
  return cur
end
local function clampV(v) if v >= 0x180 then return 0x180 end if v < -0x180 then return -0x180 end return v end
local function decay(v) if v > 0 then v = v - 3; if v < 0 then v = 0 end elseif v < 0 then v = v + 3; if v > 0 then v = 0 end end return v end
M._ice = { clamp = clampV, decay = decay, VEL = ICE_VEL }

-- one frame of ice movement; true while a direction is held
function M.iceStep(p, dx, dy)
  local d8 = dir8(dx, dy)
  p.iceVx, p.iceVy = p.iceVx or 0, p.iceVy or 0
  if d8 then
    local a = ICE_VEL[d8]
    p.iceVx, p.iceVy = clampV(p.iceVx + a[1]), clampV(p.iceVy + a[2])
  end
  if p.iceVx ~= 0 then p:moveBy(p.iceVx / 256, 0) end
  if p.iceVy ~= 0 then p:moveBy(0, p.iceVy / 256) end
  p.iceVx, p.iceVy = decay(p.iceVx), decay(p.iceVy)
  return d8 ~= nil
end

-- ---------------------------------------------------------------------------
-- hooks (installed once, the first time a room of ours loads)
-- ---------------------------------------------------------------------------
function M.install()
  if M._installed then return end
  M._installed = true
  -- Link pushing a small ice block (UpdatePlayerCollision SPECIAL_TILE_90)
  local PR = require("src.zelda.tmc.PushableRock")
  local tryPush = PR.tryPush
  PR.tryPush = function(p) return tryPush(p) or M.tryPush(p) end
  -- the levers' tiles: every frame Link leans on them in PL_STATE_PUSH
  local PA = require("src.zelda.tmc.PushAnim")
  local paUpdate = PA.update
  PA.update = function(p, ...)
    local r = paUpdate(p, ...)
    if p.pushing then M.leverPush(p) end
    return r
  end
  -- buttons see an ice block on them
  local Dungeon = require("src.zelda.tmc.Dungeon")
  local somethingOn = Dungeon.somethingOn
  Dungeon.somethingOn = function(self, tx, ty, who)
    return somethingOn(self, tx, ty, who) or M.blockOn(self.field, tx, ty)
  end
  -- the ice floor (player.c PlayerNormal: SURFACE_ICE -> sub_08008926)
  local Player = require("src.zelda.tmc.Player")
  local walk = Player.walk
  Player.walk = function(self, dx, dy, speed, anim_, idle)
    local f = self.field
    if self.state == "normal" and (self.z or 0) == 0 and not self.swimming and not self.minish and f and f.room
       and M.onIce(f, self) then
      if (dx ~= 0 or dy ~= 0) and not self.lockFacing then self.animationState = facingFor(dx, dy, self.animationState) end
      local held = M.iceStep(self, dx, dy)
      self.moving = held
      self:setAnim(held and anim_ or idle)
      return held
    end
    local r = walk(self, dx, dy, speed, anim_, idle)
    -- sub_08008AA0: off the ice the velocity is the walk direction
    if dx ~= 0 or dy ~= 0 then
      local n = math.sqrt(dx * dx + dy * dy)
      self.iceVx, self.iceVy = math.floor(dx / n * 256), math.floor(dy / n * 256)
    end
    return r
  end
  -- the darkness over the room picture (BG3 at priority 0, blended)
  local Field = require("src.zelda.tmc.Field")
  local drawWorld = Field.drawWorld
  Field.drawWorld = function(self, ...)
    local r = drawWorld(self, ...)
    if self._todLight and self._todLight.type ~= 0 then M.drawDark(self) end
    return r
  end
end

-- ---------------------------------------------------------------------------
-- R26 entry points
-- ---------------------------------------------------------------------------
function M.spawnObject(d, e)
  local id = e.id
  if id == ID.SMALL_ICE then M.install() return M.spawnSmallIce(d, e) end
  if id == ID.BIG_ICE then M.install() return M.spawnBigIce(d, e) end
  if id == ID.FROZEN_FLOWER then return M.spawnFlower(d, e) end
  if id == ID.FROZEN_WATER_ELEMENT then return M.spawnFrozenElement(d, e) end
  if id == ID.LIGHT_DOOR then return M.spawnLightDoor(d, e) end
  if id == ID.LIT_AREA then M.install() return M.spawnLitArea(d, e) end
  if id == ID.LEVER then M.install() return M.spawnLever(d, e, false) end
  if id == ID.BIG_LEVER then M.install() return M.spawnLever(d, e, true) end
  return nil
end

function M.spawnManager(d, m, dat)
  local R26 = require("src.zelda.tmc.R26")
  if m.id == MGR.TOD then
    m.subAction = 0
    R26.ticker(d, function(dd, me) if not me.deleted then todUpdate(dd, me) end end, m)
    return true
  elseif m.id == MGR.LIGHT_LEVEL then
    M.install()
    m.amount = m.b1                       -- super->timer (paramB byte 1)
    m.burn = band(m.b32, 0xFF)            -- field_0x36
    R26.ticker(d, function(dd, me) llsUpdate(dd, me) end, m)
    return true
  elseif m.id == MGR.MISC and (m.type == 4 or m.type == 5) then
    R26.ticker(d, function(dd, me) miscUpdate(dd, me) end, m)
    return true
  elseif m.id == MGR.WATERFALL_BOTTOM then
    M.waterfallBottom(d.field)
    return true
  end
  return nil
end

-- the Temple of Droplets' sub_StateChange_* (src/roomInit.c)
local function westHoleFlags(f) -- sub_0804D0B4
  if not lflag(f, 0x29) then setL(f, 0x29); setL(f, 0x4B); setL(f, 0x4E) end
end
local ROOM_INIT = {
  [0x00] = westHoleFlags,
  [0x0E] = function(f)
    M.changeLightLevel(f, 0x100)
    if f:flag("global", 5) then f:loadEntityList(LISTS.bigOcto) -- LV4_CLEAR
    elseif f.bgm then f:bgm(nil) end
  end,
  [0x10] = function(f)
    if not lflag(f, 0x48) then setL(f, 0x46, false); f:loadEntityList(LISTS.blueChu) end
  end,
  [0x11] = function(f)
    westHoleFlags(f)
    if lflag(f, 0x6C) then f:loadEntityList(LISTS.chuKey6C) else f:loadEntityList(LISTS.chuKey) end
    if not lflag(f, 0x4B) then setL(f, 0x49, false) end
  end,
  [0x28] = function(f)
    if not lflag(f, 0x59) then f:loadEntityList(LISTS.lilyA) else f:loadEntityList(LISTS.lilyB) end
  end,
  [0x2E] = function(f)
    westHoleFlags(f)
    if not lflag(f, 0x4B) then f:loadEntityList(LISTS.leverA) else f:loadEntityList(LISTS.leverB) end
  end,
}
M.ROOM_INIT = ROOM_INIT

function M.roomInit(f)
  if not (f.room and f.room.area) then return end
  f._todPrev = nil
  local area = f.room.area
  if M.DARK_AREAS[area] or (f._todLight and f._todLight.type ~= 0) then
    M.install()
    M.darkRoomInit(f)
  end
  if area == 0x60 then
    M.install()
    local fn = ROOM_INIT[f.room.room]
    if fn then fn(f) end
  end
  local l = f._todLight
  if l and l.type ~= 0 and f._dungeon then
    require("src.zelda.tmc.R26").ticker(f._dungeon, function(dd) M.lightUpdate(dd.field) end)
  end
end

return M
