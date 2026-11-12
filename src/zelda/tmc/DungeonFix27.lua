-- Round 28: dungeon leftovers.  R27B.lua dispatches here.
--
-- The throne push in Dark Hyrule Castle ($88:$1F, OBJECT_BLOCKING_STAIRS,
--   DHCObjects.tryStairsPush): the cartridge stops Link at a wall with the
--   sensors of gPlayerHitbox (playerHitbox.c: offset 0 / -3, unk2 5 / 3 --
--   CalculateEntityTileCollisions tests x + 5 going east, x - 5 going west);
--   Player.lua's box is x - 4 .. x + 3, so walking east Link went 2 px
--   further into SPECIAL_TILE_44 (collision 5: its east half solid) than
--   the cartridge lets him, and the push probe (beanstalkSubtask.c,
--   gUnk_080B4468: x + 12, y - 3) landed on the throne's middle tile
--   (SPECIAL_TILE_43) instead of the side tile the throne watches
--   (tilePos - 1, objectBlockingStairs.c) -- nothing moved.  Here, before
--   the push test, Link facing east with his cartridge sensor (x + 5) in a
--   SPECIAL_TILE_44's solid half stands where that sensor stops him (the
--   first solid pixel - 5), as on the cartridge.  (West is unaffected: x - 4
--   vs x - 5 still probes the side tile.)
-- The Gleerok heart container ($51:00): no change needed -- the round-26
--   note came from a check made before list `a` loads.  FIGHT_MANAGER sets
--   LV2_CLEAR ($4003 = global 3) when Gleerok is gone, EntitySpawnManager
--   type 9 loads list 9 (the Fire Element + EntitySpawnManager type $A),
--   the element's text closing sets room flag 0 ($8000) and list a loads
--   (the warp point and HEART_CONTAINER $47, shown on $4003); scene
--   r28/heart.lua: shown, touched, max health +8.
local bit = require("bit")
local band = bit.band

local M = {}

M.SENSOR_X = 5 -- gPlayerHitbox.unk2[0]
local SPECIAL_TILE_44 = 0x402C

-- the x the cartridge's east sensor stops Link at, or nil
function M.throneStop(f, p)
  if not (f.room and p) or p.minish or p.animationState ~= 2 then return nil end
  local x, y = math.floor(p.x), math.floor(p.y) - 3
  local sx = x + M.SENSOR_X
  local tx, ty = math.floor(sx / 16), math.floor(y / 16)
  local layer = p.layer or 1
  if f.room:tileType(layer, tx, ty) ~= SPECIAL_TILE_44 then return nil end
  if not f.room:isSolidPlayer(sx, y, layer) then return nil end
  -- the first solid pixel of the tile's row going east
  local edge = tx * 16
  while edge < tx * 16 + 16 and not f.room:isSolidPlayer(edge, y, layer) do edge = edge + 1 end
  local stop = edge - M.SENSOR_X
  if x > stop then return stop end
  return nil
end

do
  local ok, D = pcall(require, "src.zelda.tmc.DHCObjects")
  if ok and type(D) == "table" and D.tryStairsPush and not D._r28push then
    D._r28push = true
    local push = D.tryStairsPush
    D.tryStairsPush = function(f, p)
      if p and p.state == "normal" and p.pushFrame then
        local s = M.throneStop(f, p)
        if s then p.x = s end
      end
      return push(f, p)
    end
  end
end

return M
