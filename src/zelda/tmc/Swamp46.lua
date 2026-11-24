-- Round 46: SURFACE_SWAMP (src/player.c SurfaceAction_Swamp), Castor Wilds'
-- marsh.  An R27A module: it wraps Dungeon.checkFall, Dungeon.unsafeAt and
-- Player.walk when it is required.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * gMapActTileToSurfaceType: ACT_TILE_19 ($13) -> SURFACE_SWAMP.
--   * sub_080741C4: jumping (jump_status not 3) or off the ground -> nothing,
--     the surface timers reset.
--   * sub_08079C30: Minish Link always counts as in it; full-size Link only
--     when the act tiles at (0, -1), (+2, 0) and (-2, 0) are all swamp (else
--     nothing, the timers reset).
--   * Full size: running with the Pegasus Boots (dash_state & $40) -> nothing
--     (the timers reset: the boots cross the marsh).  Else (not charging
--     the boots) PutAwayItems; surfaceTimer 1: SFX_161 (with OBJECT_70 and
--     FX_GREEN_SPLASH), then SFX_161 on a new d-pad press or every 16th
--     frame; speed_modifier -$F0 (walking $140 -> $50); while surfaceTimer
--     is below $F0 Link sinks; at $F0 (and Minish Link at once):
--     FX_GREEN_SPLASH, iframes $20, ModHealth(-4), RespawnPlayer.
--   * gUnk_0811C268: a swamp tile is no safe spot for the path memory
--     (RespawnPlayer never puts Link back on it).
-- SIMPLIFIED: the sinking sprite offset, OBJECT_70 and FX_GREEN_SPLASH are
--   not drawn.
local M = {}

M.ACT_SWAMP = 0x13
M.SINK_TIME = 0xF0
M.SLOW = 0xF0 / 256
M.SFX_161 = 0x161

local Dungeon = require("src.zelda.tmc.Dungeon")
local Player = require("src.zelda.tmc.Player")

-- sub_08079C30 for the swamp
function M.inSwamp(d, p)
  if d:actAt(p.x, p.y - 1, p.layer) ~= M.ACT_SWAMP then return false end
  if p.minish then return true end
  return d:actAt(p.x + 2, p.y, p.layer) == M.ACT_SWAMP and d:actAt(p.x - 2, p.y, p.layer) == M.ACT_SWAMP
end

local function reset(p) p.swampTimer, p.swampSlow = nil, nil end

-- one frame of SurfaceAction_Swamp; true when Link was sent back
function M.update(d)
  local f = d.field
  local p = f.player
  if not p or (p.state ~= "normal" and not (p.state == "ext" and p.dash)) then reset(p or {}) return false end
  if (p.z or 0) ~= 0 or p.jumping then reset(p) return false end -- sub_080741C4
  if not M.inSwamp(d, p) then reset(p) return false end
  local hp = f.save and f.save.stats and f.save.stats.health or 1
  if hp <= 0 then reset(p) return false end
  if not p.minish then
    if p.dash and p.dash.stage == 2 then reset(p) return false end -- dash_state & $40
    p.swampTimer = (p.swampTimer or 0) + 1
    if p.swampTimer < M.SINK_TIME then
      if p.swampTimer == 1 or p.swampTimer % 16 == 0 then f:sound(M.SFX_161) end
      p.swampSlow = true
      return false
    end
  end
  -- FX_GREEN_SPLASH, iframes $20, ModHealth(-4), RespawnPlayer
  reset(p)
  f:modStat("health", -4)
  p.invuln = 0x20
  local st = d:respawnSpot()
  p.x, p.y = st.x, st.y
  if st.layer then p.layer = st.layer end
  f.playerRespawned = true
  return true
end

if not Dungeon._swamp46 then
  Dungeon._swamp46 = true
  local checkFall = Dungeon.checkFall
  Dungeon.checkFall = function(self, ...)
    if M.update(self) then return end
    return checkFall(self, ...)
  end
  local unsafeAt = Dungeon.unsafeAt
  Dungeon.unsafeAt = function(self, x, y, layer)
    if unsafeAt(self, x, y, layer) then return true end
    return self:actAt(x, y - 1, layer) == M.ACT_SWAMP -- gUnk_0811C268
  end
  local walk = Player.walk
  Player.walk = function(self, dx, dy, speed, ...)
    if self.swampSlow and speed then speed = math.max(0, speed - M.SLOW) end -- speed_modifier -$F0
    return walk(self, dx, dy, speed, ...)
  end
end

return M
