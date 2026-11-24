-- Round 96: an arrow's layer follows the act tiles it flies over, and tiles flagged $80 do not stop it -- as
-- PlayerItemBow_Action1 does.  ($88:11, Dark Hyrule Castle 2F's west room: the arrow shot north from the floating
-- platform under the grating crosses the ledge row (tile flag $80) and an ACT_TILE_12 row (-> layer 2) and lights the
-- LIGHTABLE_SWITCH on the upper level that opens the north door; the port stopped it at the ledge, on layer 1.)
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc src/playerItem/playerItemBow.c, PlayerItemBow_Action1, type != 0):
--   * Init: type2 = (collisionLayer == 2) ? 1 : 0.
--   * each frame after LinearMoveUpdate and DoTileInteractionOffset: `if (super->type2 == 0) sub_0800451C(super);`
--     asm/src/code_080043E8.s sub_0800451C: GetActTileAtEntity (the act tile under the arrow on its own layer):
--     ACT_TILE 11 / 12 -> collisionLayer 2, 9 / 10 -> collisionLayer 1, $26 / $27 -> collisionLayer 3.
--   * the wall: `sub_080B1BA4(COORD_TO_TILE(super), gPlayerEntity.base.collisionLayer, 0x80) == 0 && !tmp2 &&
--     sub_080040D8(super, &gUnk_08003E44, x, y)`: the tile-type flags (gUnk_08000360 / gUnk_080B7A3E, the table
--     ExtractR23.tileFlags reads from the player's ROM) of the tile under the arrow on LINK's layer; bit $80 set ->
--     no wall test.  sub_080040D8 reads gCollisionDataPtrs[the arrow's layer] (asm/src/veneer.s: layer 3 = the
--     bottom map, as layer 1).
-- Numbers here are engine enum values / bit masks; the flags come from the ROM import (manifest.r23).
--
-- Wraps ItemBow.spawnArrow (type2), ItemBow.updateArrow (the layer step) and GustJar.wall while an arrow is being
-- updated (the $80 test, the arrow's current layer); guard ItemBow.arrow96Installed; listed in R27A.MODULES.
local bit = require("bit")
local band = bit.band

local M = {}

M.ACT_TO_LAYER = { [0x0B] = 2, [0x0C] = 2, [0x09] = 1, [0x0A] = 1, [0x26] = 3, [0x27] = 3 }
M.FLAG_NO_WALL = 0x80

local function tileTypeAt(f, x, y, layer)
  local r = f.room
  if not (r and r.tileType) then return nil end
  local l = (layer == 2) and 2 or 1
  return r:tileType(l, math.floor(x / 16), math.floor(y / 16))
end

-- sub_0800451C: the arrow's new layer (or its own) from the act tile under it on its layer
function M.layerByTile(f, a)
  local tt = tileTypeAt(f, a.x, a.y, a.layer or 1)
  if not tt or tt >= 0x4000 then return a.layer end
  local act = f.assets and f.assets.actTile and f.assets.actTile[tt]
  return M.ACT_TO_LAYER[act or -1] or a.layer
end

-- sub_080B1BA4(tile, Link's layer, $80) ~= 0
function M.passes(f, a)
  local p = f.player
  local tt = tileTypeAt(f, a.x, a.y, (p and p.layer) or 1)
  if not tt then return false end
  local ok, X = pcall(require, "src.zelda.tmc.ExtractR23")
  if not ok then return false end
  return band(X.flags(f.assets and f.assets.manifest, tt), M.FLAG_NO_WALL) ~= 0
end

function M.install()
  local okB, IB = pcall(require, "src.zelda.tmc.ItemBow")
  local okG, GJ = pcall(require, "src.zelda.tmc.GustJar")
  if not okB or not okG or type(IB) ~= "table" or IB.arrow96Installed then return end
  IB.arrow96Installed = true
  local spawn0, upd0, wall0 = IB.spawnArrow, IB.updateArrow, GJ.wall
  IB.spawnArrow = function(f, p, hurtType)
    local a = spawn0(f, p, hurtType)
    if a then a.type2_96 = (a.layer == 2) and 1 or 0 end
    return a
  end
  local cur -- the arrow being updated (f, a)
  GJ.wall = function(f, x, y, layer)
    local c = cur
    if c and c.f == f and c.a.x == x and c.a.y == y then
      local a = c.a
      if a.type2_96 == 0 then a.layer = M.layerByTile(f, a); c.stepped = true end
      if M.passes(f, a) then return false end
      return wall0(f, x, y, (a.layer == 2) and 2 or 1)
    end
    return wall0(f, x, y, layer)
  end
  IB.updateArrow = function(f, a)
    if a.action ~= 1 or a.deleted then return upd0(f, a) end
    local c = { f = f, a = a }
    cur = c
    local ok, err = pcall(upd0, f, a)
    cur = nil
    if not ok then error(err, 0) end
    -- the layer step also runs on a frame whose wall test was skipped (a light arrow's tile hit)
    if not c.stepped and a.action == 1 and not a.deleted and a.type2_96 == 0 then a.layer = M.layerByTile(f, a) end
  end
end
M.install()

return M
