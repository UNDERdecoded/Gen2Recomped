-- Round 11: collision layer changes (asm/src/script.s CheckOnLayerTransition).
--
-- CARTRIDGE BEHAVIOUR: the act tile under an entity is looked up in
-- gTransitionTiles ($08016AB4: {u16 act tile, u8 a, u8 b}, zero-ended);
-- when the entity's collision layer is not `a` it becomes `b`.  The USA
-- table: $0A / $09 -> 1 (unless on 2), $0C / $0B -> 2 (unless on 1), $52 /
-- $27 / $26 -> 3 (both layers): stairs between the floors of a room go
-- bottom tile -> middle (layer 3) -> top tile.  The layer then picks the
-- collision map (layer 2: the top one) and whether the sprite draws over
-- the top BG layer (UpdateSpriteForCollisionLayer).
-- The table is read from the player's ROM (ExtractR11.lua).
local L = {}

function L.update(f, ent)
  local r11 = f.assets.manifest.r11
  local tab = r11 and r11.layerTiles
  if not tab then return end
  local layer = ent.layer or 1
  local r = f.room
  local tt = r:tileType(layer == 2 and 2 or 1, math.floor(ent.x / 16), math.floor(ent.y / 16))
  if not tt or tt >= 0x4000 then return end
  local act = f.assets.actTile[tt]
  if not act then return end
  for _, t in ipairs(tab) do
    if t[1] == act then
      if layer ~= t[2] then ent.layer = t[3] end
      return
    end
  end
end

-- round 12: ResolveCollisionLayer (asm/src/script.s), for a room entity
-- whose kind byte names no layer (room.c LoadRoomEntity: $10 -> 1, $20 ->
-- 2, else this): the top layer's tile type at its position; none -> layer
-- 1; a gTransitionTiles act tile -> that entry's layer; else layer 2
function L.resolve(f, ent)
  local r = f.room
  local tt = r:tileType(2, math.floor(ent.x / 16), math.floor(ent.y / 16))
  if not tt or tt == 0 then return 1 end
  local r11 = f.assets.manifest.r11
  local tab = r11 and r11.layerTiles
  local act = tt < 0x4000 and f.assets.actTile[tt] or nil
  if tab and act then
    for _, t in ipairs(tab) do if t[1] == act then return t[3] end end
  end
  return 2
end


-- round 23: sub_0807A8D8 (playerUtils.c, from the frame interrupt, every
-- frame): the flags of the tile type under Link on his own layer
-- (sub_080B1B84, manifest.r23): bit 1 -> layer 1 (sub_0807AABC), else bit 2
-- -> layer 2 (sub_0807AA80); hidden Link (PL_HIDDEN) is left alone.  The
-- Cave of Flames' rooms lay everything on the top map over a bottom of one
-- flagged tile type ($310): this is what puts Link on the top layer there
-- (walls, enemies on layer 2, drawn over BG1).  SIMPLIFIED: the path memory
-- (bit 5, sub_0807AAF8) is not kept.
function L.surface(f, p)
  local band = require("bit").band
  if p.hidden or not f.room then return end
  local tt = f.room:tileType(p.layer == 2 and 2 or 1, math.floor(p.x / 16), math.floor(p.y / 16))
  local fl = require("src.zelda.tmc.ExtractR23").flags(f.assets.manifest, tt)
  if band(fl, 2) ~= 0 then p.layer = 1
  elseif band(fl, 4) ~= 0 then p.layer = 2 end
end

return L
