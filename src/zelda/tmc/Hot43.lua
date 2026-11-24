-- Round 43: hot floor and spike tiles hurt Link (player.c SurfaceAction_16).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * UpdateFloorType: the surface is gMapActTileToSurfaceType[act tile]
--     (read from the ROM, Hole42.SURFACE).  ACT_TILE_24 -> SURFACE_16 and
--     ACT_TILE_98 -> SURFACE_21 both run SurfaceAction_16 (gSurfaceActions
--     $16 and $21): the Cave of Flames' burning floor ($50:17's west strip,
--     the upper island, the ledge by the east Cane hole) and spikes.
--   * SurfaceAction_16: nothing while in the air (sub_080741C4: jump_status
--     other than 3, or z != 0) or carried by a platform (field_0x14).  With
--     iframes 0: ModHealth(-2), SFX_PLY_VO6, iframes 24, knockbackDuration 4,
--     knockbackDirection = CalculateDirectionTo(the tile's centre -> Link).
--   * Minish Link is hurt as well (only DoTileInteractionHere is skipped).
-- Before round 43 these tiles did nothing: Link walked through the fire.
-- SIMPLIFIED: DoTileInteractionHere(Link, 7) (what the hot floor does to
-- a tile under full-size Link) is not modelled; the knockback runs at the
-- port's usual hurt speed (2 px a frame).
local Hot43 = {}

local SURFACE_16, SURFACE_21 = 0x16, 0x21
local SFX_PLY_VO6 = 0x7A
local OK_STATE = { normal = true, shield = true, gust = true, carry = true }

function Hot43.isHot(act)
  local s = require("src.zelda.tmc.Hole42").surfaceOf(act)
  return s == SURFACE_16 or s == SURFACE_21
end

-- each frame from Dungeon:update
function Hot43.check(d)
  local f = d.field
  local p = f.player
  if not p or not OK_STATE[p.state] then return false end
  if (p.z or 0) ~= 0 or p.inCart or p.para or p.fall then return false end
  local a = d:actAt(p.x, p.y - 1, p.layer)
  if not Hot43.isHot(a) then return false end
  -- field_0x14: Link carried by a lava platform / lily pad
  if require("src.zelda.tmc.CoFObjects").supports(f, p.x, p.y) then return false end
  if require("src.zelda.tmc.Objects37").supports(f) then return false end
  if (p.invuln or 0) > 0 then return false end
  f:modStat("health", -2)
  f:sound(SFX_PLY_VO6)
  p.invuln = 24
  local cx, cy = math.floor(p.x / 16) * 16 + 8, math.floor((p.y - 1) / 16) * 16 + 8
  local dx, dy = p.x - cx, p.y - cy
  local n = math.sqrt(dx * dx + dy * dy)
  if n < 0.01 then dx, dy, n = 0, -1, 1 end -- CalculateDirectionTo of the same point: north
  p.kbx, p.kby = dx / n * 2, dy / n * 2
  if p.state == "carry" then f:objects():dropCarried(p) end
  p.state, p.timer = "hurt", 4
  if (f.save.stats.health or 0) <= 0 then
    p.state, p.timer = "dead", 90
    f:sound(0x87) -- SFX_PLY_DIE
  end
  return true
end

return Hot43
