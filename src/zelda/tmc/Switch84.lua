-- Round 84: LIGHTABLE_SWITCH's ($9D) contact box as the cartridge has it.
--
-- CARTRIDGE BEHAVIOUR (src/object/lightableSwitch.c, src/data/hitbox.c,
-- asm/src/intr.s arm_CalcCollision):
--   * The switch's hitbox is gHitbox_0: offset (0, -3), half sizes 6 x 6
--     (read from the ROM: RomTablesCat "Beetle66.FLY_HB", the same table).
--   * arm_CalcCollision: the boxes touch when |dx| <= wA + wB and
--     |dy| <= hA + hB (unsigned (d + s) <= 2s: inclusive).
-- Before round 84 LightableSwitch tested an 8 x 8 box around the switch's
-- own position with strict comparisons.  The contacts themselves are
-- unchanged: Link's sword box, a bomb's blast / hit list, a thrown object,
-- an arrow (Arrow78), the Four Sword clones' sword boxes (Clone79).
local M = {}

M.HB = require("src.zelda.tmc.RomTables").t("Beetle66.FLY_HB") -- gHitbox_0

-- the switch's box: centre and half sizes; nil before a cache with the table is attached
function M.box(e)
  local ok, hb = pcall(function() return M.HB[0] end)
  if not ok or type(hb) ~= "table" or not hb.w then return nil end
  return e.x + hb.x, e.y + hb.y, hb.w, hb.h
end

local function touch(ax, ay, aw, ah, bx, by, bw, bh)
  return math.abs(ax - bx) <= aw + bw and math.abs(ay - by) <= ah + bh
end

-- true / false: a contact this frame; nil: no table (the caller keeps its old test)
function M.contact(f, e)
  local cx, cy, w, h = M.box(e)
  if not cx then return nil end
  local sb = f.swordBoxNow
  if sb and sb.t == f.frame and touch(sb.x, sb.y, sb.w, sb.h, cx, cy, w, h) then return true end
  for _, t in ipairs(f.entities) do
    if not t.deleted and t ~= e then
      if t.hitW and t.hitList and touch(t.x, t.y, t.hitW, t.hitW, cx, cy, w, h) then return true end
      if (t.thrown or (t.bomb and t.action == 2 and t.carrySub == 2)) and touch(t.x, t.y - (t.z or 0), 6, 6, cx, cy, w, h) then return true end
    end
  end
  local proxy = { x = cx, y = cy, z = e.z, layer = e.layer }
  if require("src.zelda.tmc.Arrow78").switchContact(f, proxy, w) then return true end -- (Arrow78 already tests inclusively)
  for _, b in ipairs(require("src.zelda.tmc.Clone79").boxes(f)) do
    if touch(b.x, b.y, b.w, b.h, cx, cy, w, h) then return true end
  end
  return false
end

return M
