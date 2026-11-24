-- Round 64: down a waterfall (player.c SurfaceAction_14).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * The surface under Link is gMapActTileToSurfaceType[act tile at (0, -1)]
--     (read from the ROM: Hole42.surfaceOf); a waterfall's current
--     (ACT_TILE_17) is SURFACE_14.
--   * SurfaceAction_14: not jumping and z == 0 (sub_080741C4), and
--     sub_08079C30 (not on a floating board / the large lily pad
--     (field_0x14, PL_FLAGS2); Minish: at once; else the last surface was
--     already a conveyer / SURFACE_14 / ice / auto ladder, or the same
--     surface at (0, -1), (2, 0) and (-2, 0)) -> sub_0807AABC (collision
--     layer 1: the falls are on the bottom map), sub_08074808 (the swim /
--     drown test -- Link keeps swimming with the Flippers), and Link is
--     moved south at $300 (3 px a frame, LinearMoveUpdate: no tile
--     collision) with the d-pad ignored (field_0xa |= $80).
--   * At the foot of the falls the next surface takes over (the Temple of
--     Droplets' West Waterfall South-west: the pit row -> its hole manager).
-- SIMPLIFIED: Link's sprite stays the swim animation of the frame he went
-- over (the cartridge keeps animating the swim stroke).
local W = {}
W.SURFACE_14 = 0x14
W.SPEED = 0x300 / 256

local function surf(d, p, dx, dy)
  local a = d:actAt(p.x + dx, p.y + dy, p.layer)
  return a and require("src.zelda.tmc.Hole42").surfaceOf(a) or nil
end

-- Player:update (first thing after the layer pick); true while the falls
-- carry Link this frame
function W.frame(p)
  local f = p.field
  local d = f and f._dungeon
  if not d or p.hidden or p.state == "dead" or (p.z or 0) ~= 0 or f.transition then p.wf64 = nil return false end
  if d:onLily(p) then p.wf64 = nil return false end -- PL_FLAGS2
  if surf(d, p, 0, -1) ~= W.SURFACE_14 then p.wf64 = nil return false end
  if not p.wf64 and not p.minish then
    if surf(d, p, 2, 0) ~= W.SURFACE_14 or surf(d, p, -2, 0) ~= W.SURFACE_14 then return false end
  end
  p.wf64 = true
  p.layer = 1 -- sub_0807AABC
  p.y = p.y + W.SPEED
  if p.anim then p.anim:update(1) end
  return true
end

return W
