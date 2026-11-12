-- Round 6: the Zelda follower (src/npc/zeldaFollower.c, NPC $2E) and the
-- zelda.c calls that hand Zelda over to it and back.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * CreateZeldaFollower: while global flag ZELDA_CHASE ($1C) is set, a
--     ZELDA_FOLLOWER (persistent) stands on Link when a room loads.
--   * sub_08068318: a 20-entry history of Link's {x, y, z, facing, layer};
--     a new entry is pushed whenever it changes, and also while Link is
--     more than 24 px from the oldest entry; Zelda stands on the oldest,
--     walking (animation 4 + facing / 2) on frames that pushed, standing
--     (0 + facing / 2) otherwise, a new animation held at least 30 frames.
--   * sub_08068578: the history is refilled on a straight line from Zelda
--     to Link (when she is shown again).
--   * zelda.c sub_08066D04 (find the follower), sub_08066D14 (the NPC
--     takes the follower's place, the follower hides), sub_08066D4C (the
--     NPC hands over: the follower appears where it stood, the NPC hides).
-- Round 23: z (her trail jumps with Link, drawn at y - z) and hiding on FALL
-- frames are ported; Not ported: the shadow under her in the air
-- (sub_0806F854), DROWN ($16, the port has no drowning framestate).
-- Old note (round 6): not ported were hiding while Link's framestate is $0A / $16 (falling /
-- warping), and her z (Link's jumps).

local Native = require("src.zelda.tmc.Native")
local N = Native.N

local ZF = {}
ZF.NPC_ID, ZF.ZELDA_CHASE, ZF.LEN = 0x2E, 0x1C, 20

-- round 23: the item is the cartridge's whole ZeldaFollowerItem: + z (Link's
-- height; the port's z is up-positive, the GBA's z.HALF.HI negative in the
-- air) and the framestate's FALL ($0A) / DROWN ($16) as `fall`.  Round 6 left
-- z out, so on Link's ledge jumps she slid down the cliff face on the ground
-- (drawn at her trail's ground point = "through the wall") instead of jumping.
local function link(field)
  local p = field.player
  return { x = math.floor(p.x), y = math.floor(p.y), z = math.floor(p.z or 0), s = p.animationState or 4,
           layer = p.layer or 1, fall = (p.falling or p.drowning) and true or nil }
end

-- sub_08068578: a straight line from Zelda to Link in 20 steps (FixedDiv,
-- >> 8); every entry has Link's z / framestate and ZELDA's own facing and
-- layer (super->animationState / collisionLayer)
function ZF.refill(field, z)
  local l = link(field)
  local function fixedDiv(a) local q = a * 256 / ZF.LEN; return q >= 0 and math.floor(q) or math.ceil(q) end
  local dx = fixedDiv(l.x - math.floor(z.x))
  local dy = fixedDiv(l.y - math.floor(z.y))
  z.heap = {}
  for i = 0, ZF.LEN - 1 do
    z.heap[i + 1] = { x = l.x - math.floor(i * dx / 256), y = l.y - math.floor(i * dy / 256), z = l.z, fall = l.fall,
                      s = z.animationState or l.s, layer = z.layer or l.layer }
  end
end

function ZF.new(field)
  local p = field.player
  local z = { kind = 7, id = ZF.NPC_ID, form = 0, x = p.x, y = p.y, z = 0, animationState = 4, -- ZeldaFollower action 0
              field80 = 0, field82 = 0, interactType = 0, follower = true, on = true, hold = 0 }
  local def = field.npcDef and field:npcDef(ZF.NPC_ID, 0)
  if def then
    z.def = def
    z.sprite = def.sprite
    z.palette = field.assets:objPalette(def.palette, field.room.atlas and field.room.atlas.palettes)
    z.gfx = (def.gfxType == 0 and def.gfx ~= 0) and def.gfx or nil
  end
  z.anim = require("src.zelda.tmc.Anim").new()
  ZF.refill(field, z)
  return z
end

-- CreateZeldaFollower / ENT_PERSIST across rooms: after a room loads
function ZF.ensure(field)
  if not field:flag("global", ZF.ZELDA_CHASE) then field.zeldaFollower = nil return end
  local z = field.zeldaFollower
  if not z then z = ZF.new(field); field.zeldaFollower = z end
  local p = field.player
  z.x, z.y = p.x, p.y
  ZF.refill(field, z)
  for _, e in ipairs(field.entities) do if e == z then return z end end
  field.entities[#field.entities + 1] = z
  return z
end

local function same(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z and a.s == b.s and a.layer == b.layer and a.fall == b.fall
end

-- sub_08068318, once a frame
function ZF.update(field, z)
  if not z.on then z.hidden = true return end
  z.hidden = nil
  -- round 10: Link fell into a hole / water and came back (framestate
  -- FALL $0A / DROWN $16 ends): Zelda appears at Link and her history is
  -- refilled from there (sub_08068318 + sub_08068578); the port's fall is
  -- instant, so the hidden frames of the fall itself are not shown
  if field.playerRespawned then
    field.playerRespawned = nil
    local p = field.player
    z.x, z.y = p.x, p.y
    ZF.refill(field, z)
  end
  local item = link(field)
  local heap = z.heap
  -- round 23: the cartridge's own test: the newest entry was a fall and Link's
  -- framestate no longer is -> Zelda at Link, history refilled
  if heap[1].fall and not item.fall then
    z.x, z.y = field.player.x, field.player.y
    ZF.refill(field, z)
    heap = z.heap
  end
  local walk = false
  -- round 11: framestate FALL ($0A) pushes every frame (PlayerFall.lua)
  if not same(item, heap[1]) or item.fall then
    table.insert(heap, 1, item); heap[ZF.LEN + 1] = nil
    walk = true
    if z.hold > 0 then z.hold = z.hold - 1 end
  else
    local last = heap[ZF.LEN]
    -- round 23: the oldest entry in the air (z.HALF.HI < 0) keeps her moving
    local d = math.sqrt((item.x - last.x) ^ 2 + (item.y - last.y) ^ 2)
    if (last.z or 0) > 0 or d > 0x18 then
      table.insert(heap, 1, heap[1]); heap[ZF.LEN + 1] = nil
      walk = true
    end
  end
  local h = heap[ZF.LEN]
  z.x, z.y, z.z, z.animationState, z.layer = h.x, h.y, h.z or 0, h.s, h.layer
  -- round 23: hidden while the oldest entry is a fall / drown frame
  z.hidden = h.fall or nil
  if z.hold > 0 then z.hold = z.hold - 1 end
  local idx = (walk and 4 or 0) + math.floor(z.animationState / 2)
  if idx ~= z.animIndexWant and not (not walk and z.hold > 0) then
    z.animIndexWant = idx
    z.hold = 30
  end
  z.forceAnim = z.animIndexWant or idx
end

-- zelda.c
N[0x08066D04] = function(f, e) e.parent = f.zeldaFollower end -- find the follower
N[0x08066D14] = function(f, e, ctx)                            -- the NPC takes over
  local z = e.parent
  if z then
    e.animationState = z.animationState
    e.hidden = nil
    e.x, e.y = z.x, z.y
    z.on = false; z.hidden = true -- ZeldaFollower_Hide
    ctx.condition = 1
  else
    ctx.condition = 0
  end
end
N[0x08066D4C] = function(f, e, ctx)                            -- the follower takes over
  local z = e.parent or f.zeldaFollower
  if z then
    z.x, z.y = e.x, e.y
    z.animationState = e.animationState
    e.hidden = true
    z.on = true; z.hidden = nil -- ZeldaFollower_Show
    ZF.refill(f, z)
    ctx.condition = 1
  else
    ctx.condition = 0
  end
end

return ZF
