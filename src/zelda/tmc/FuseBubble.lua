-- The fusion bubble over a fuser's head (round 7): object CAMERA_TARGET
-- (src/object/cameraTarget.c), created by AddInteractableObject whenever an
-- interactable carries a Kinstone offer.
--
-- It follows gPossibleInteraction.currentObject: four frames after the
-- current interactable has an offer in 1..100 it shows (sub_08083A40: draw,
-- animation 0 with x offset +8 when the fuser is right of Link, else
-- animation 1 and -8; y offset -18) and runs GetNextFrame on the fuser's
-- position. It hides (sub_080838DC, timer 4) when the current object
-- changes, its offer goes, a message shows or a fusion runs.
--
-- Graphics: CameraTarget_Init points gfx slot 1 at the bubble tiles
-- ($027820 in gGlobalGfxAndPalettes) and lowers spriteVramOffset by $10, and
-- Action2 points slot 0 at the piece's icon (gUnk_0811F744[bubbleIcon]), so
-- frame tiles 0-15 are the icon and 16-31 the bubble. Palette: fixed OBJ
-- slot (bubbleIcon & 1). Both are read from the player's ROM (menudata
-- ranges `fuseBubble` and `fuseBubbleIcons`).
local bit = require("bit")
local band = bit.band

local FuseBubble = {}

local BUBBLE = 0x085A2E80 + 0x027820 -- gGlobalGfxAndPalettes + $027820
local CAMERA_TARGET = 0x09

local function range(A, name)
  local e = A.manifest and A.manifest.menuData and A.manifest.menuData[name]
  if not e then return nil end
  A.menuBlob = A.menuBlob or (A.store and A.store:read("menudata.bin")) or ""
  return A.menuBlob, e[1], e[2], e[3]
end

-- 32 tiles: the icon (slot 0) then the bubble (slot 1)
function FuseBubble.tiles(A, icon)
  A._fuseTiles = A._fuseTiles or {}
  local c = A._fuseTiles[icon]
  if c ~= nil then return c or nil end
  local blob, base, off, size = range(A, "fuseBubble")
  local iblob, ibase, ioff = range(A, "fuseBubbleIcons")
  if not (blob and iblob) then A._fuseTiles[icon] = false return nil end
  local function u32(a)
    local o = ioff + (a - ibase)
    local b1, b2, b3, b4 = iblob:byte(o + 1, o + 4)
    return (b1 or 0) + 256 * (b2 or 0) + 65536 * (b3 or 0) + 16777216 * (b4 or 0)
  end
  local function slice(addr)
    local o = addr - base
    if o < 0 or o + 0x200 > size then return string.rep("\0", 0x200) end
    return blob:sub(off + o + 1, off + o + 0x200)
  end
  local ic = band(u32(0x0811F744 + 4 * band(icon, 3)), 0xFFFFFC)
  c = slice(0x085A2E80 + ic) .. slice(BUBBLE)
  A._fuseTiles[icon] = c
  return c
end

local function hide(st)
  st.shown = false
  st.timer = 4
  st.child = nil
  st.action = 0
end

local function current(field)
  local p = field.player
  if not p or not p.frontPoint then return nil end
  local fx, fy = p:frontPoint(10)
  local best, bestD
  for _, e in ipairs(field.entities) do
    if e.talkable and not e.hidden and not e.deleted and not e.unplaced then
      local d = math.abs(e.x - fx) + math.abs(e.y - fy)
      if d < 18 and (not bestD or d < bestD) then best, bestD = e, d end
    end
  end
  return best
end

local function offerOf(e) return e and e.fuser and e.fuser >= 1 and e.fuser <= 100 and e.fuser or nil end

-- every game frame (the object's update)
function FuseBubble.update(field)
  local st = field.fuseBubble
  if not st then st = {}; hide(st); field.fuseBubble = st end
  local busy = field.textbox or (field.kinstone and field.kinstone.active)
  for _, e in ipairs(field.entities) do if e.fusing then busy = true break end end
  if busy then hide(st) return end
  local cur = current(field)
  if st.action ~= 2 then
    if st.timer > 0 then st.timer = st.timer - 1 return end
    local k = offerOf(cur)
    if not k then return end
    -- sub_08083A40
    st.child, st.kinstone, st.action, st.shown = cur, k, 2, true
    local right = cur.x > field.player.x
    st.ox, st.oy = right and 8 or -8, -18
    local d = field._objects and field._objects:def(CAMERA_TARGET, 0)
    st.def = d
    st.anim = require("src.zelda.tmc.Anim").new()
    local spr = d and field.assets:sprite(d.sprite)
    st.anim:set(spr, right and 0 or 1, true)
    return
  end
  if offerOf(cur) == nil or cur ~= st.child then hide(st) return end
  st.kinstone = offerOf(cur)
  st.anim:update(1)
end

function FuseBubble.draw(field)
  local st = field.fuseBubble
  if not (st and st.shown and st.child and st.def and st.anim) then return end
  local frame = st.anim.frame
  if not frame or frame == 0xFF then return end
  local A = field.assets
  local ev = A.manifest.kinstones and A.manifest.kinstones.events and A.manifest.kinstones.events[st.kinstone]
  local icon = ev and ev.bubble or 0
  local tiles = FuseBubble.tiles(A, icon)
  if not tiles then return end
  local img, ox, oy = A:spriteFrame(st.def.sprite, frame, A:objPalette(band(icon, 1)), "fusebubble",
    { raw = tiles, key = "fb" .. icon })
  if not img then return end
  local e = st.child
  local x = math.floor(e.x - field.camX + st.ox)
  local y = math.floor(e.y - field.camY - (e.z or 0) + st.oy)
  if st.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
end

return FuseBubble
