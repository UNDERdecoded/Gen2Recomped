-- Round 13: HOLE_MANAGER ($1A, src/manager/holeManager.c).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * HoleManager_Init: gHoleTransitions[type] (read from the ROM,
--     ExtractR13: manifest.r13.holes); a hole width of 0 means the whole
--     room, else the box is (hole_x, hole_y, w, h) in tiles.
--   * IsPlayerOnHole: Link inside the box while falling (PL_DROWNING |
--     PL_BUSY) marks the pit as an exit (PL_PIT_IS_EXIT); PlayerFallUpdate
--     then does not respawn him, and DoHoleTransition takes him to the
--     table's area / room / layer: type 0 at (x, y), type 1 at his own
--     position + (x, y), type 2 at (x, y) as Minish; spawn type DROP
--     (PL_SPAWN_DROP_MINISH when Minish), TRANSITION_CUT.
-- NOT PORTED: the parallax backgrounds / PARALLAX_ROOM_VIEW objects the
-- table can point at (Deepwood's barrel hole has none).
local H = {}

local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

function H.spawn(d, m)
  local f = d.field
  local r13 = f.assets.manifest.r13
  local t = r13 and r13.holes and r13.holes[m.type]
  if not t then return false end
  local box
  if t.hw == 0 then box = { x = 0, y = 0, w = f.room.width, h = f.room.height }
  else box = { x = t.hx * 16, y = t.hy * 16, w = t.hw * 16, h = t.hh * 16 } end
  d.holeMgrs = d.holeMgrs or {}
  d.holeMgrs[#d.holeMgrs + 1] = { t = t, box = box }
  return true
end

-- the exit a pit under Link leads to (nil: a plain pit, respawn)
function H.exitFor(d, p)
  for _, h in ipairs(d.holeMgrs or {}) do
    local b = h.box
    if p.x >= b.x and p.x < b.x + b.w and p.y >= b.y and p.y < b.y + b.h then
      local t = h.t
      local x, y = t.x, t.y
      if t.type == 1 then x, y = math.floor(p.x) + s16(t.x), math.floor(p.y) + s16(t.y) end
      local minish = t.type == 2 or p.minish
      return { warpType = 1, area = t.area, room = t.room, endX = x, endY = y, facing = 4,
               kind = minish and 6 or 5, layer = t.layer, hole = true }
    end
  end
  return nil
end

return H
