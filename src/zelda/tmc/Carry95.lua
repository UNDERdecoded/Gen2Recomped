-- Bug round bugs95 (user report: "When picking up pots it's not showing them in my hand when picked up, it's showing
-- a gray tile for most"): a bush, rock or sign lifted from the map is drawn over Link's head and thrown as the
-- cartridge's own PLAYER_ITEM_HELD_OBJECT, not as the tile's SPECIAL_FX.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * asm/src/player.s DoItemTileInteraction(filter 6): the tile's gUnk_080047F6 entry gives byte 2 (object id) ->
--     the item's field_0x2[1], byte 3 (object type) -> timer, byte 5 -> subtimer; DoTileInteraction makes no
--     object for filter 6 and swaps the tile (entry word 6: the tile left behind; Objects:tileInteraction).
--   * src/item/itemTryPickupObject.c sub_08076088(this, NULL): CreatePlayerItemWithParent(PLAYER_ITEM_HELD_OBJECT),
--     type2 = the object id, timer = the object type, subtimer = byte 5, child = NULL.
--   * src/playerItem.c ItemInit: gPlayerItemDefinitions[PLAYER_ITEM_HELD_OBJECT] -> spriteIndex (SPRITE_POT).
--   * src/playerItem/playerItemHeldObject.c SubAction0, child == NULL: the item is its own child; palette slot =
--     gUnk_081320B8[subtimer].unk1 (an OBJ slot 0-5 as is: 2 = the field's fixed palette, 5 = BG palette 3),
--     spriteVramOffset = .unk2 (the common OBJ VRAM: the bush / rock / sign art), InitializeAnimation(.unk0).
--     The port drew the entry's SPECIAL_FX definition (FX_BUSH / FX_ROCK / FX_SIGN: the break pieces, not the
--     object) over Link's head and in the air.
--   * SubAction2 landing, child == this: an act tile of 13 / 16 / 17 / 19 / 90 makes its splash (PotCarry.ACT_FX,
--     unchanged); else type2 $0F -> CreateFx(this, timer, $80) (the FX's variant, sound gUnk_0811F960[type].sfx and
--     its drop roll), another type2 -> CreateObjectWithParent(type2, timer), $FF nothing.  The port broke it as a
--     pot (Objects:shatter: a GROUND_ITEM of "form" = the FX type).
--   * PlayerDropHeldObject (Link hurt, a whirlwind, ...) lands it where Link stands.
-- Every number above comes from the player's ROM through RomTables (Carry95.SLOTS / DEF / FX_SFX); nothing here is
-- a game value.
--
-- Hooked by Objects:tryAction (Carry95.fromTile, one line) and by wrapping Objects.drawCarried / dropCarried /
-- breakThrown and PotCarry.release (guard Objects.carry95Installed); listed in R27A.MODULES.
local RT = require("src.zelda.tmc.RomTables")

local M = {}

M.SLOTS = RT.t("Carry95.SLOTS")   -- gUnk_081320B8: {anim, pal, vram} by subtimer
M.DEF = RT.t("Carry95.DEF")       -- gPlayerItemDefinitions[PLAYER_ITEM_HELD_OBJECT]: {sprite}
M.FX_SFX = RT.t("Carry95.FX_SFX") -- gUnk_0811F960[type].sfx
M.SPECIAL_FX = 0x0F
M.NONE = 0xFF

-- the PLAYER_ITEM_HELD_OBJECT made from a filter-6 tile entry ({obj, objType, unk} = bytes 2, 3, 4-5)
function M.fromTile(O, entry)
  local sub = math.floor((entry.unk or 0) / 256) % 256
  local s = M.SLOTS[sub] or M.SLOTS[0]
  local what = { obj = entry.obj, form = entry.objType }
  if s and M.DEF.sprite then
    what.held95 = { slot = sub, sprite = M.DEF.sprite, anim = s.anim, pal = s.pal, vram = s.vram,
                    type2 = entry.obj, timer = entry.objType }
  end
  return what
end

-- the art: sprite, first keyframe of the animation, palette slot, common OBJ VRAM offset
function M.art(f, h)
  local A = f.assets
  local s = A:sprite(h.sprite)
  local keys = s and s.anims and s.anims[h.anim or 0]
  local frame = keys and keys[1] and keys[1][1]
  if not frame then return nil end
  local pal = A:objPalette(h.pal, f.room and f.room.atlas and f.room.atlas.palettes)
  return frame, pal, { vram = h.vram }
end

function M.drawHeld(O, c, x, y)
  local f = O.field
  local h = c.held95
  local frame, pal, gfx = M.art(f, h)
  if not frame then return end
  local img, ox, oy = f.assets:spriteFrame(h.sprite, frame, pal, "held95:" .. tostring(h.pal), gfx)
  if img then love.graphics.draw(img, math.floor(x + ox), math.floor(y + oy)) end
end

-- the thrown entity keeps the held object's art (Field:drawSpriteList draws e.sprite / staticFrame)
function M.dressThrown(f, e, h)
  local frame, pal, gfx = M.art(f, h)
  e.def, e.forceAnim, e.literalAnim, e.objAnim = nil, nil, nil, nil
  e.held95 = h
  e.sprite, e.palette, e.gfx, e.staticFrame = h.sprite, pal, gfx, frame
  if not frame then e.hidden = true end
end

-- SubAction2's landing for a held object that is its own child
function M.land(O, e)
  local f = O.field
  local h = e.held95
  if h.type2 == M.NONE then return end
  if h.type2 == M.SPECIAL_FX then
    local Drops = require("src.zelda.tmc.Drops")
    local t = Drops.fxVariant(f, h.timer)
    local row = M.FX_SFX[t]
    local sfx = row and row.sfx
    if sfx and sfx ~= 0 then f:sound(sfx) end
    f:addFx(e.x, e.y, M.SPECIAL_FX, t)
    Drops.fxDrop(f, e, t, O)
  else
    f:addFx(e.x, e.y, h.type2, h.timer)
  end
end

function M.install()
  local Objects = require("src.zelda.tmc.Objects")
  if Objects.carry95Installed then return end
  Objects.carry95Installed = true
  local PotCarry = require("src.zelda.tmc.PotCarry")
  local draw0, drop0, break0 = Objects.drawCarried, Objects.dropCarried, Objects.breakThrown
  function Objects:drawCarried(c, x, y)
    if c and c.held95 then
      local px, py = PotCarry.drawPos(self.field.player, c, x, y + 14)
      return M.drawHeld(self, c, px, py)
    end
    return draw0(self, c, x, y)
  end
  function Objects:dropCarried(p)
    local c = p and p.carried
    if c and c.held95 then
      p.carried = nil
      return M.land(self, { x = p.x, y = p.y, held95 = c.held95 })
    end
    return drop0(self, p)
  end
  function Objects:breakThrown(e)
    if e and e.held95 then return M.land(self, e) end
    return break0(self, e)
  end
  local release0 = PotCarry.release
  function PotCarry.release(f, p)
    local c = p and p.carried
    local n = #f.entities
    local r = release0(f, p)
    if c and c.held95 and #f.entities > n then M.dressThrown(f, f.entities[#f.entities], c.held95) end
    return r
  end
end

M.install()

return M
