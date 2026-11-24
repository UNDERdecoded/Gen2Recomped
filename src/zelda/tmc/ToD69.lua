-- Round 69: Temple of Droplets, second half (SpikeBar $26 onward).
--
-- * room.c LoadRoomEntity: an entity-list entry whose collision byte names no layer ($10 -> 1, $20 -> 2,
--   else) goes through ResolveCollisionLayer (the top map's tile under it) -- projectiles included.  The
--   SPIKED_ROLLERS / WINDER spawners took layer 1 for "no layer": SpikeBar $26 lies wholly on the top map, so its
--   four rollers sat on layer 1 (drawn under BG1, out of the collision layer test of arm_CollideAll).
--   M.listLayer(d, dat) is that rule (Dungeon:spawnObject's, round 12 / 55).
local bit = require("bit")
local band = bit.band

local M = {}

-- the collisionLayer a room-list entry gets (LoadRoomEntity)
function M.listLayer(d, dat)
  local c = band(dat.collision or 0, 3)
  if c == 2 then return 2 end
  if c == 1 or c == 3 then return 1 end
  local f = d and d.field
  local rm = f and f.room
  if not rm then return 1 end
  if require("src.zelda.tmc.Room").MERGE_TOP_AREAS[rm.area or -1] then return 1 end
  return require("src.zelda.tmc.Layers").resolve(f, { x = dat.x or 0, y = dat.y or 0 })
end

-- Field:spawnEntity's projectiles (the list spawners that set layer 1 themselves, e.g. Dungeon:spawnProjectile's
-- SPIDER_WEB): in the Temple of Droplets' areas ($60-$62) the entry's no-layer case is resolved as the cartridge
-- does (Madderpillars $2C's webs on the top map).  Other areas keep their tested layers.
M.AREAS = { [0x60] = true, [0x61] = true, [0x62] = true }
function M.projLayer(f, d, pe)
  if type(pe) ~= "table" or band(d.collision or 0, 3) ~= 0 then return end
  local rm = f.room
  if not rm or not M.AREAS[rm.area or -1] then return end
  if pe.id == 0x1D or pe.id == 0x1E then return end -- listLayer already (FoWObjects)
  pe.layer = M.listLayer(f._dungeon or { field = f }, d)
end

-- * beanstalkSubtask.c's ACT_TILE_40 case (stairs / house doors): PLAYER_ROOM_EXIT is queued only while Link is
--   blocked on the side he faces (sub_08079778) -- the port started the 5-frame walk as soon as the stairs tile
--   was 8 px ahead, so a Link coming up the ice bridge of BlockCloneIceBridge $24 (stopping 1-2 px short) walked
--   6 px into the doorway, short of the transition at (136,24), and slid back.
local STEP = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
function M.stairsBlocked(f, p)
  local d = STEP[p.animationState or 0]
  if not d then return true end
  local nx, ny = math.floor(p.x) + d[1], math.floor(p.y) + d[2]
  if p.leadFree then return not p:leadFree(nx, ny, d[1], d[2]) end
  return p:blocked(nx, ny)
end

-- * specialWarpManager.h: the region's byte 7 is { layer : 2, unk1 : 2, unk2 : 1, unk3 : 3 }; unk2 (bit 4, $10) lets
--   a normal-size Link take the warp (SpecialWarpManager_Main).  The port read bit 2 ($04): the Element room's south
--   region ($60:08 (264,414), bits $11) never took Link down to BigOcto $0E.
M.WARP_NORMAL_BIT = 0x10

return M
