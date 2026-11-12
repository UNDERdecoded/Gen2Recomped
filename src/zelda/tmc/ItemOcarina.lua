-- Round 26 (team A): the OCARINA OF WIND ($17) and the wind-crest warp:
-- src/item/itemOcarina.c (OcarinaUse, OcarinaUpdate), src/object/bird.c
-- (BIRD $95: CreateBird, Bird_Type0/1/2/3/8/9/10, sub_0809D738),
-- src/subtask/subtaskFastTravel.c (Subtask_FastTravel_0..4, sub_080A6D74,
-- sub_080A6E70, sub_080A6EE0) and the warp table gUnk_08128024
-- (src/menu/kinstoneMenu.c).
--
--   OcarinaUse: Link faces south (animationState 4, no flip), out of the
--     collision, PL_USE_OCARINA, the item animation ANIM_OCARINA ($8E1;
--     SetItemAnim adds the facing: $8E3), SFX_216.
--   OcarinaUpdate: the animation runs; its frame bit $80 -> collision back,
--     CreateBird: only where the area allows warps (gArea.areaMetadata bit 7,
--     AreaAllowsWarp) and no type-8 bird is out yet.
--   Bird type 8 (Zeffa): from the left screen edge (scroll_x) at Link's y,
--     z -20, speed $180 + 8 a frame up to $300, east (8); Link (normal, not
--     climbing / jumping / gliding, no message) within 14 px and the height
--     gap < $20 -> picked up: type 10 (Link hanging, animation $E0) under
--     the bird, Link hidden and paused, gravity Q_8_8(-32) (it climbs);
--     the first 8 frames the hanging Link stays on Link's spot.  Off screen
--     with Link: gSave.windcrests |= $10000000, the fast-travel subtask.
--   Subtask_FastTravel: the cursor runs over the warp points whose bit
--     (24 + i) is set (sub_080A6D74 wraps over 8); A / START: message
--     TEXT_WINDCRESTS 4 ($0704), YES -> the fade and DoExitTransition
--     (gUnk_08128024[i]); B or NO: back to the field, SFX_MENU_CANCEL.
--     Markers: sprite DRAW_DIRECT $5C on each crest, the cursor $5D / $5E
--     blinking every 16 frames, at (map x * 160 / $F90 + $28, map y * 160
--     / $F90 + $C).
--   Arrival (transition type 12, sub_0807B2F8 -> sub_0809D738): bird type 9
--     carries Link in: z -75.25, zVelocity -2.5, gravity Q_8_8(-16), speed
--     $300 east from scroll_x at Link's y; past scroll_x + $78 Link drops
--     (drawn again, normal) and the first time WARP_1ST ($?) is not set
--     the Ezlo talk (script_EzloTalkOcarina) would run.
--   Bird types 0 / 1 / 2 (the Ocarina falling to the ground, LV3_OCARINA_FALL)
--     and type 3 (perched birds picking random animations) spawn from room
--     lists; type 2 gives ITEM_OCARINA when Link touches it.
-- SIMPLIFIED: script_EzloTalkOcarina (WARP_1ST) is not run; the bird's
--   OAM priority / flipY layering is a plain draw over the field; the map
--   picture is the pause menu's world map page (screen 4).
local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local O = {}
O.ITEM = 0x17
O.BIRD = 0x95
O.ANIM_OCARINA = 0x8E1
O.SFX_OCARINA, O.SFX_BIRD, O.SFX_SECRET = 0x216, 0x123, 0x72
O.SFX_CHOICE, O.SFX_CANCEL = 0x69, 0x6C
O.MSG_WARP = 0x0704 -- TEXT_INDEX(TEXT_WINDCRESTS, 4)
O.WARP_BIT = 0x10000000
-- gUnk_08128024: { endX, endY, area, room } (warp_type 1, layer 1, transition type 12, facing 4)
O.WARPS = {
  [0] = { 0x98, 0xF8, 0x06, 0x02 },   -- Mt. Crenel, Cave of Flames entrance
  { 0xF8, 0xF8, 0x0A, 0x00 },         -- Veil Falls
  { 0x1E8, 0x1A8, 0x08, 0x00 },       -- Cloud Tops
  { 0x278, 0x58, 0x02, 0x00 },        -- Hyrule Town
  { 0xA8, 0x1B8, 0x0B, 0x00 },        -- Lake Hylia
  { 0x228, 0x398, 0x04, 0x00 },       -- Castor Wilds
  { 0x2C8, 0x128, 0x03, 0x01 },       -- South Hyrule Field
  { 0x128, 0x2A8, 0x00, 0x00 },       -- Minish Woods
}

local function windcrests(f) return f.save.windcrests or 0 end

-- sub_080A6D74
function O.nextCrest(w, cur, step)
  local m = band(rshift(w, 24), 0xFF)
  if step == 0 then
    local i = 0
    if band(m, 1) == 0 then
      repeat i = i + 1 until i >= 8 or band(lshift(1, i), m) ~= 0
    end
    return band(i, 7)
  end
  if m == 0 then return band(cur, 7) end
  local i = cur
  repeat i = band(i + step + 8, 7) until band(lshift(1, i), m) ~= 0
  return i
end

-- AreaAllowsWarp
function O.allowsWarp(f)
  local info = f.room and f.room.areaInfo
  return band(info and info.flags or 0, 0x80) ~= 0
end

-- -------------------------------------------------------------- the bird
local function birdDef(f, form)
  local ok, d = pcall(function() return f:objects():def(O.BIRD, form) end)
  return ok and d or nil
end

local function newBird(f, form, x, y, z)
  local A = f.assets
  local d = birdDef(f, form)
  local b = { kind = 6, id = O.BIRD, form = form, x = x, y = y, z = z or 0, zv = 0, grav = 0, speed = 0, action = 0, timer = 0,
              birdObj = true, layer = 1, anim = require("src.zelda.tmc.Anim").new(), literalAnim = true, objAnim = 0, animIndex = 0 }
  if d then
    b.sprite = d.sprite
    b.palette = A:objPalette(d.palette, f.room.atlas and f.room.atlas.palettes)
    b.gfx = require("src.zelda.tmc.Assets").gfxSource(d.gfxType, d.gfx)
  end
  return b
end

local function setAnim(f, b, i)
  if not b.sprite then return end
  local spr = f.assets:sprite(b.sprite)
  if spr then b.anim:set(spr, i, true) end
  b.literalAnim, b.objAnim, b.animIndex = true, i, i -- Field's entity loop leaves a literal animation alone
end

local function drawSprite(f, b, sprite, palette, gfx, frame, x, y, flip)
  if not sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = f.assets:spriteFrame(sprite, frame, palette, "bird" .. sprite, gfx)
  if not img then return end
  if flip then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
end

function O.drawBird(f, b, camX, camY)
  if b.hidden then return end
  local x, y = math.floor(b.x - camX), math.floor(b.y - camY - (b.z or 0))
  drawSprite(f, b, b.sprite, b.palette, b.gfx, b.anim.frame, x, y, b.anim:hflip() ~= (b.flipX or false))
  local c = b.child
  if c then
    local cx, cy = math.floor(c.x - camX), math.floor(c.y - camY - (c.z or 0))
    if c.sprite then drawSprite(f, c, c.sprite, f.assets:objPalette(0x16), c.gfx, c.anim.frame, cx, cy, false)
    else f.player.hidden = false; f.player:draw(camX + (f.player.x - c.x), camY + (f.player.y - c.y) + (c.z or 0)); f.player.hidden = true end
  end
end

local function onScreen(f, b)
  local x, y = b.x - (f.camX or 0), b.y - (f.camY or 0)
  return x > -32 and x < 240 + 32 and y > -32 and y < 160 + 64
end

local function linearMove(b)
  local a = (b.direction or 8) / 32 * 2 * math.pi
  b.x = b.x + math.sin(a) * b.speed
  b.y = b.y - math.cos(a) * b.speed
end
local function gravity(b) b.z = b.z + b.zv; b.zv = b.zv - b.grav end

local function pause(p)
  p.state = "ext"
  p.extUpdate = function(pl) end
end

-- Bird_Type8 (the pick-up)
local function type8(f, b)
  local p = f.player
  if b.action == 1 then
    b.speed = math.min(b.speed + 8 / 256, 3)
    local free = p.state == "normal" and not f.textbox and not p.minish and not p.climbing and (p.z or 0) == 0
    if free and math.abs(p.x - b.x) <= 14 and math.abs(p.y - b.y) <= 14 then
      local gap = (b.z - (p.z or 0)) - 8
      if gap >= 0 and gap < 0x20 and (f.save.stats.health or 0) > 0 then
        local c = newBird(f, 10, p.x, p.y, 0)
        setAnim(f, c, 0xE0)
        b.child, b.action, b.timer, b.speed = c, 2, 8, 3
        b.grav = -0x2000 / 0x10000
        if p.carried then f:objects():dropCarried(p) end
        pause(p)
        p.swimming, p.jump, p.jumping = nil, nil, nil
        p.hidden = true
      end
    end
  elseif b.action >= 2 then
    pause(p); p.hidden = true
  end
  linearMove(b); gravity(b)
  b.anim:update(1)
  local c = b.child
  if c then
    if p.x < b.x - 8 then b.timer = 0 end
    if b.timer == 0 then c.x, c.y, c.z = b.x - 8, b.y, b.z - 0x18
    else b.timer = b.timer - 1; c.x, c.y, c.z = p.x, p.y, 0 end
    c.anim:update(1)
  end
  if not onScreen(f, b) then
    b.deleted = true
    if b.action == 2 then
      f.save.windcrests = bor(windcrests(f), O.WARP_BIT)
      O.openFastTravel(f)
    end
  end
end

-- Bird_Type9 (the drop at the warp point)
local function type9(f, b)
  local p = f.player
  if b.action == 1 then
    p.hidden = true
    pause(p)
    local c = b.child
    if c then c.x, c.y, c.z = b.x - 8, b.y, b.z - 0x18; c.anim:update(1) end
    if b.x > (f.camX or 0) + 0x78 then
      b.action, b.child = 2, nil
      p.hidden = false
      p.state, p.extUpdate = "normal", nil
      p.x = math.max(8, math.min(f.room.width - 8, p.x))
      p.z = 0
      p.animId = -1
    end
  end
  linearMove(b); gravity(b)
  b.anim:update(1)
  if not onScreen(f, b) then b.deleted = true end
end

-- Bird_Type0/1/2/3 (room-list birds)
local function typeRoom(f, b)
  local p = f.player
  if b.form == 0 then
    linearMove(b); gravity(b); b.anim:update(1)
    if b.subtimer then b.timer = b.timer - 1; if b.timer <= 0 then b.subtimer = nil end
    elseif not onScreen(f, b) then b.deleted = true end
    local c = b.child
    if c then
      if b.subtimer then c.x, c.y, c.z = b.x, b.y, b.z - 8
      else -- Bird_Type1 subaction 1: BounceUpdate(Q_8_8(24)) until it rests
        c.z = c.z + c.zv; c.zv = c.zv - 24 / 256
        if c.z <= 0 then
          c.z, c.zv = 0, 0
          c.form, c.action = 2, 1
          setAnim(f, c, 0x17)
          f:setFlag("local", 0x45, true) -- LV3_OCARINA_FALL
          f:sound(O.SFX_SECRET)
          f.entities[#f.entities + 1] = c
          f._dungeon:track(c)
          b.child = nil
        end
      end
    end
  elseif b.form == 2 then
    if not p.minish and math.abs(p.x - b.x) < 10 and math.abs(p.y - b.y) < 10 then
      f:giveItem(O.ITEM, 0, 0)
      f.save.windcrests = bor(windcrests(f), O.WARP_BIT)
      b.deleted = true
    end
  elseif b.form >= 3 and b.form <= 7 then
    if b.anim.done or b.action == 0 then
      b.action = 1
      setAnim(f, b, math.random(0, 3))
      b.flipX = math.random(0, 1) == 1
    else b.anim:update(1) end
  end
end

function O.updateBird(f, b)
  if b.form == 8 then return type8(f, b) end
  if b.form == 9 then return type9(f, b) end
  return typeRoom(f, b)
end

local function track(f, b)
  b.drawGhost = function(me, field, camX, camY) O.drawBird(field, me, camX, camY) end
  b.extUpdate = function(_, me) O.updateBird(f, me) end
  f.entities[#f.entities + 1] = b
  if f._dungeon then f._dungeon:track(b) end
  return b
end

-- CreateBird
function O.createBird(f)
  if not O.allowsWarp(f) then return nil end
  for _, e in ipairs(f.entities) do if e.birdObj and e.form == 8 and not e.deleted then return nil end end
  local b = newBird(f, 8, f.camX or 0, f.player.y, 20)
  b.action, b.speed, b.direction = 1, 0x180 / 256, 8
  setAnim(f, b, 0)
  f:sound(O.SFX_BIRD)
  return track(f, b)
end

-- sub_0809D738
function O.arrive(f)
  local p = f.player
  local b = newBird(f, 9, f.camX or 0, p.y, 75.25)
  b.action, b.zv, b.grav, b.speed, b.direction = 1, -2.5, -0x1000 / 0x10000, 3, 8
  local c = newBird(f, 10, b.x - 8, b.y, b.z - 0x18)
  setAnim(f, c, 0xE0)
  b.child = c
  setAnim(f, b, 0)
  f:sound(O.SFX_BIRD)
  p.hidden = true
  pause(p)
  return track(f, b)
end

-- room-list birds (Crenel.spawnObject -> ItemOcarina.spawnObject)
function O.spawnObject(dungeon, d)
  if d.id ~= O.BIRD then return nil end
  local f = dungeon.field
  local b = newBird(f, d.form or d.paramA or 0, d.x, d.y, 0)
  if b.form == 0 then
    b.action, b.timer, b.subtimer, b.zv, b.z, b.grav, b.speed, b.direction = 1, 49, true, -1.5, 56.75, -8 / 256, 0x280 / 256, 8
    b.x = f.camX or 0
    setAnim(f, b, 0)
    f:sound(O.SFX_BIRD)
    local c = newBird(f, 1, b.x, b.y, b.z - 8)
    setAnim(f, c, 0x17)
    b.child = c
  elseif b.form == 2 then setAnim(f, b, 0x17) end
  b.drawGhost = function(me, field, camX, camY) O.drawBird(field, me, camX, camY) end
  b.extUpdate = function(_, me) O.updateBird(f, me) end
  dungeon:track(b)
  return b
end

-- ---------------------------------------------------------- the ocarina
function O.use(p, item, button, input)
  if item ~= O.ITEM then return nil end
  if p.state ~= "normal" or p.minish or p.carried then return nil end
  local f = p.field
  p.animationState, p.entFlip = 4, false
  p.state = "ext"
  p.ocarina = true
  p:setAnim(O.ANIM_OCARINA, true)
  f:sound(O.SFX_OCARINA)
  p.extUpdate = function(pl)
    pl.anim:update(1)
    if band(pl.anim.flags or 0, 0x80) ~= 0 or pl.anim.done then
      pl.ocarina = nil
      pl.state, pl.extUpdate = "normal", nil
      pl.animId = -1
      O.createBird(f)
    end
  end
  return true
end

-- --------------------------------------------------- Subtask_FastTravel
function O.openFastTravel(f)
  local m = f.menu
  if not m then return false end
  m.screen = 4
  local ok = pcall(m.openMenu, m)
  if not ok then return false end
  local ft = { cursor = O.nextCrest(windcrests(f), 0, 0), ticks = 0, state = 1 }
  m.fastTravel = ft
  m.update = O.menuUpdate
  m.draw = O.menuDraw
  f:sound(0x65)
  return true
end

local function closeFastTravel(f, m)
  m.update, m.draw, m.fastTravel = nil, nil, nil
  m.open = false
  local p = f.player
  p.hidden = false
  p.state, p.extUpdate = "normal", nil
  p.animId = -1
end

function O.warpTo(f, i)
  local w = O.WARPS[i]
  if not w then return false end
  local exit = { area = w[3], room = w[4], endX = w[1], endY = w[2], kind = 12, layer = 1, facing = 4, sfx = 0 }
  f.ocarinaArrive = true
  f.player.hidden = true
  f.transition = nil
  f:startTransition(exit, nil)
  if f.transition then f.transition.kind = nil; f.transition.phase = "out"; f.fadeTarget = 1 end
  return true
end

function O.menuUpdate(m, input)
  local f, ft = m.field, m.fastTravel
  ft.ticks = ft.ticks + 1
  m.ticks = (m.ticks or 0) + 1
  if ft.state == 2 then -- Subtask_FastTravel_2: the YES / NO message
    if f.textbox then return end
    if (f.textResult or 1) == 0 then
      closeFastTravel(f, m)
      O.warpTo(f, ft.cursor)
    else ft.state = 1 end
    return
  end
  local step = 0
  if input.pressed("left") or input.pressed("up") then step = -1
  elseif input.pressed("right") or input.pressed("down") then step = 1
  elseif input.pressed("a") or input.pressed("start") then
    ft.state = 2
    f.textResult = nil
    f:message(O.MSG_WARP)
    return
  elseif input.pressed("b") then
    f:sound(O.SFX_CANCEL)
    closeFastTravel(f, m)
    return
  end
  if step ~= 0 then
    local c = O.nextCrest(windcrests(f), ft.cursor, step)
    if c ~= ft.cursor then ft.cursor = c; f:sound(O.SFX_CHOICE) end
  end
end

-- sub_080A6EE0
function O.markerPos(f, i)
  local w = O.WARPS[i]
  local r = require("src.zelda.tmc.Room").load(f.assets, w[3], w[4])
  local x, y = w[1] + (r and r.x or 0), w[2] + (r and r.y or 0)
  return math.floor(x * 160 / 0xF90) + 0x28, math.floor(y * 160 / 0xF90) + 0xC
end

function O.menuDraw(m)
  if not m.ppu then return end
  local f, ft, p = m.field, m.fastTravel, m.ppu
  p:flush()
  local SPRITE = 0x1FB
  ft.pos = ft.pos or {}
  local function pos(i) if not ft.pos[i] then ft.pos[i] = { O.markerPos(f, i) } end return ft.pos[i][1], ft.pos[i][2] end
  local cx, cy = pos(ft.cursor)
  p:drawDirect(SPRITE, band(ft.ticks, 0x10) ~= 0 and 0x5D or 0x5E, { x = cx, y = cy, _4 = 0, _6 = 0, _8 = 0x400 })
  local w = windcrests(f)
  for i = 0, 7 do
    if band(w, lshift(1, i + 24)) ~= 0 then
      local x, y = pos(i)
      p:drawDirect(SPRITE, 0x5C, { x = x, y = y, _4 = 0, _6 = 0, _8 = 0x400 })
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  require("src.zelda.tmc.MapMenu").compose(m)
end

-- the arrival: once the warp's fade is over, the bird carries Link in
function O.frame(p)
  local f = p.field
  if f.ocarinaArrive and not f.transition and f.room then
    f.ocarinaArrive = nil
    O.arrive(f)
  end
  return nil
end

return O
