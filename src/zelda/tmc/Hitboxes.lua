-- Round 11: the cartridge's hitboxes for Link, NPCs and objects, solid
-- NPCs, the A-button interaction test and Link's contact with enemies.
--
-- CARTRIDGE BEHAVIOUR
--   * Link's hitbox is gPlayerHitbox (offset 0,-3, half size 6x6); Minish
--     Link's is player.c sMinishHitbox (offset 0,-1, half size 2x2), set by
--     sub_08073C80.  NPCs take gNPCHitboxes[definition.hitbox], objects
--     gObjectHitboxes[definition.hitbox] (NPCInit / ObjectInit).  All of them
--     are read from the player's ROM (ExtractR11.lua).
--   * Solid NPCs: only NPCs whose own code calls sub_0806ED78 push Link
--     out (sub_0800445C -> CalcCollisionStaticEntity, arm_sub_080B227C):
--     when the boxes overlap (|d| <= wA + wB on both axes), Link is moved
--     out along the axis of the smaller overlap by min(overlap, 4) px
--     (sub_08079E58, with his tile collision).  The Forest Minish, Gentari,
--     Zelda and Ezlo do not call it, so Link walks through them.
--     PlayerCanBeMoved gates it (not while falling, using a portal,
--     climbing, in a cart...).
--   * A (sub_080784E4): the interaction point is Link's position plus
--     gPlayerInteractHitboxOffsetNormal / Minish[facing]; a candidate is hit
--     when -w <= px - x < w and -h <= py - y < h, with x, y the entity's own
--     position (no hitbox offset) and w, h its hitbox's half sizes.
--     INTERACTION_CHECK objects (the Jabber Nut) answer only to full-size
--     Link; Minish Link reaches only INTERACTION_TALK_MINISH ones.
--   * Contact with an enemy (arm_CalcCollision) uses Link's hurtType: 0 at
--     full size, 1 as Minish (PlayerMinish sets hurtType 1 every frame), so
--     gCollisionMtx[hitType * 34 + 1] decides; most enemies have the
--     CollisionNoOp handler ($FF, 1 or 2) there: they pass through Minish
--     Link.  Handler 16 (sub_08018228) only pushes Link out
--     (CalcCollisionStaticEntity), no damage.
--   * Minish Link's sword (itemSword.c sub_08075338, PL_MINISH branch) only
--     plays ANIM_SWORD_MINISH: no PLAYER_ITEM_SWORD entity is created
--     (sub_08077B98 is skipped), so it has no hitbox and cuts nothing.
local bit = require("bit")
local band = bit.band

local HB = {}

-- NPC ids whose code calls sub_0806ED78 (src/npc/*.c): beedle, bladeBrothers,
-- brocco, castorWildsStatue, cat, cow, cuccoChick, dog, epona, festari,
-- ghostBrothers, gorman, goron, goronMerchant, guard (+ guard_1, spear
-- guards), kid, kingDaltus, mailbox, malon, melari, milkCart, ministerPotho,
-- mountainMinish, npc23, npc26, npc9, percy, pina, postman, rem, smith,
-- stamp, stockwell, sturgeon, syrup, talon, townMinish, townsperson
HB.SOLID_NPC = {}
for _, id in ipairs({ 0x02, 0x04, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x10, 0x11, 0x12, 0x14, 0x15, 0x1A, 0x1C, 0x1D,
                      0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x2B, 0x2C, 0x2D, 0x2F, 0x30, 0x31,
                      0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x3A, 0x55 }) do
  HB.SOLID_NPC[id] = true
end

function HB.data(f)
  local m = f.assets and f.assets.manifest
  return m and m.r11
end

-- Link's hitbox (nil when the cache predates round 11)
function HB.player(f, p)
  local r = HB.data(f)
  if not r then return nil end
  p = p or f.player
  return p.minish and r.minishHitbox or r.playerHitbox
end

function HB.npc(f, e)
  local r = HB.data(f)
  if not r or not e.def then return nil end
  local b = r.npcHitboxes and r.npcHitboxes[e.def.hitbox or 0]
  return b or nil
end

function HB.object(f, e)
  local r = HB.data(f)
  if not r then return nil end
  local defs = f.assets.manifest.objectDefs
  local d = defs and defs[e.id]
  if d and d.forms then d = d.forms[e.form or 0] or d.forms[0] end
  local b = d and r.objectHitboxes and r.objectHitboxes[d.hitbox or 0]
  return b or nil
end

-- is this NPC one the cartridge makes solid?
function HB.solidNpc(f, e)
  return HB.data(f) ~= nil and e.kind == 7 and HB.SOLID_NPC[e.id] == true
end

local BUSY = { fall = true, ext = true, portal = true, dead = true, climb = true, cart = true, hole = true,
               itemget = true, drown = true, swim = true }

-- CalcCollisionStaticEntity(npc, player): push Link out of a solid box
function HB.pushOut(f, e, eb)
  local p = f.player
  local pb = HB.player(f, p)
  if not pb or not eb then return false end
  if BUSY[p.state or "normal"] or p.portalMode or p.onPortal or (p.z or 0) > 0 or p.hidden then return false end
  local px, py = math.floor(p.x), math.floor(p.y)
  local dx = (px + pb.x) - (math.floor(e.x) + eb.x)
  local sw = pb.w + eb.w
  if dx < -sw or dx > sw then return false end
  local dy = (py + pb.y) - (math.floor(e.y) + eb.y)
  local sh = pb.h + eb.h
  if dy < -sh or dy > sh then return false end
  local penX, penY = sw - math.abs(dx), sh - math.abs(dy)
  local mx, my = 0, 0
  local pen
  if penY >= penX then pen = penX; mx = dx >= 0 and 1 or -1
  else pen = penY; my = dy >= 0 and 1 or -1 end
  if pen == 0 then return false end
  if pen >= 5 then pen = 4 end
  p:moveBy(mx * pen, my * pen)
  return true
end

-- every frame after the entities: solid NPCs push Link out
function HB.update(f)
  if not HB.data(f) then return end
  for _, e in ipairs(f.entities) do
    if e.kind == 7 and HB.SOLID_NPC[e.id] and not e.hidden and not e.deleted and not e.unplaced and e.def
       and e.def.type ~= 0 and not e.noHitbox then
      HB.pushOut(f, e, HB.npc(f, e))
    end
  end
end

-- the A-button candidate under Link's interaction point, or nil when the
-- cache predates round 11 (Field:tryInteract keeps its old reach then)
function HB.interactHit(f, player, e)
  local r = HB.data(f)
  if not r then return nil end
  local off = (player.minish and r.interactMinish or r.interactNormal)[band(player.animationState or 4, 6) / 2]
  if not off then return nil end
  local ix, iy = math.floor(player.x) + off[1], math.floor(player.y) + off[2]
  if e.interactBox then return require("src.zelda.tmc.Story27Town").interactHit(e, ix, iy, player) end -- round 27A: SetInteractableObjectCollision's custom box
  local b
  if e.kind == 7 then b = HB.npc(f, e) else b = HB.object(f, e) end
  if not b then return nil end
  local dx, dy = ix - math.floor(e.x), iy - math.floor(e.y)
  return dx >= -b.w and dx < b.w and dy >= -b.h and dy < b.h
end

-- Link's hurtType against enemies
function HB.hurtType(p) return p.minish and 1 or 0 end

-- the raw gCollisionMtx entry: handler id when the first byte is $FF
function HB.handler(mtx, hitType, hurtType)
  local o = (hitType * 34 + hurtType) * 12
  local b0 = mtx:byte(o + 1)
  if b0 ~= 0xFF then return nil end
  return (mtx:byte(o + 3) or 0) + 256 * (mtx:byte(o + 4) or 0)
end

-- contact box test: Link's hitbox against an enemy's (|d| <= wA + wB)
function HB.touches(f, p, e)
  local pb = HB.player(f, p)
  local hb = e.hitbox
  if not pb or not hb then return nil end
  local dx = (math.floor(p.x) + pb.x) - (math.floor(e.x) + (hb.x or 0))
  local dy = (math.floor(p.y) + pb.y) - (math.floor(e.y) + (hb.y or 0))
  return math.abs(dx) <= pb.w + hb.w and math.abs(dy) <= pb.h + hb.h
end

return HB
