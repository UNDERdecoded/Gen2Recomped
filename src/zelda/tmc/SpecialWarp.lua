-- Round 10: SPECIAL_WARP_MANAGER ($06, src/manager/specialWarpManager.c):
-- the Minish-sized warps (the ways into the Minish Village, Minish holes,
-- beanstalks).  The manager's paramA names a room property holding a list
-- of regions (exit_region_raw, 8 bytes: u16 centre x / y, u8 half width /
-- half height, u8 room property of the exit, u8 bits: 0-1 collision layer,
-- bit 2 = also at normal size), $FFFF-terminated.  Every frame (timer 0),
-- a region on Link's layer that holds Link at z 0 (and Link Minish, unless
-- bit 2) runs DoExitTransition on that property's exit_raw (a Transition,
-- the same 20-byte layout as the exit lists).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local W = {}

local function blob(f)
  local A = f.assets
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  return A.entityBlob, A.manifest.entityRegion
end

local function prop(f, k)
  local props = f.room.maps.header.props
  return props and props[k]
end

local function u8(b, o) return b:byte(o + 1) or 0 end
local function u16(b, o) return (b:byte(o + 1) or 0) + (b:byte(o + 2) or 0) * 256 end

-- the room's warp lists, from each manager entry
function W.add(f, d)
  local addr = prop(f, d.paramA)
  if not addr then return end
  local b, reg = blob(f)
  if not reg then return end
  local o = addr - reg.base
  if o < 0 or o + 8 > #b then return end
  local list = {}
  for i = 0, 31 do
    local q = o + 8 * i
    local x = u16(b, q)
    if x == 0xFFFF or q + 8 > #b then break end
    list[#list + 1] = { x = x, y = u16(b, q + 2), w = u8(b, q + 4), h = u8(b, q + 5),
                        prop = u8(b, q + 6), bits = u8(b, q + 7) }
  end
  f._specialWarps = f._specialWarps or {}
  f._specialWarps[#f._specialWarps + 1] = list
end

-- the exit_raw at room property k, as a port exit table
function W.exitAt(f, k)
  local addr = prop(f, k)
  if not addr then return nil end
  local b, reg = blob(f)
  local o = addr - reg.base
  if o < 0 or o + 20 > #b then return nil end
  return {
    warpType = u16(b, o), startX = u16(b, o + 2), startY = u16(b, o + 4),
    endX = u16(b, o + 6), endY = u16(b, o + 8), shape = u8(b, o + 10),
    area = u8(b, o + 11), room = u8(b, o + 12), layer = u8(b, o + 13),
    kind = u8(b, o + 14), facing = u8(b, o + 15), sfx = u16(b, o + 16),
  }
end

-- true when a warp started
function W.update(f)
  local lists = f._specialWarps
  if not lists or f.transition then return false end
  local p = f.player
  for _, list in ipairs(lists) do
    for _, w in ipairs(list) do
      if band(band(w.bits, 3), p.layer or 1) ~= 0 and (p.minish or band(w.bits, 4) ~= 0)
         and f:playerInRegion(w.x, w.y, w.w, w.h) and (p.z or 0) == 0 then
        local ex = W.exitAt(f, w.prop)
        if ex then f:startTransition(ex) return true end
      end
    end
  end
  return false
end

return W
