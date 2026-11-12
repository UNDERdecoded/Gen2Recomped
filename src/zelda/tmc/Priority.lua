-- Round 14: the GBA's BG / OBJ priority, as the cartridge sets it up.
--
-- CARTRIDGE BEHAVIOUR (src/common.c, asm/src/script.s):
-- * Rooms run BG1 (gMapTop) at priority 1 and BG2 (gMapBottom) at priority
--   2 (gScreen.bg1.control = $1C01, bg2 = $1D02); a few managers change it
--   (the Gleerok room's lava BG1 under the sprites, the barrel).
-- * An entity's OAM priority (spriteRendering.b3) comes from its collision
--   layer through UpdateSpriteForCollisionLayer ($08016A04): layer 0 / 1 ->
--   2, layer 2 / 3 -> 1.  Some objects set b3 themselves (an ARCHWAY is
--   layer 2, so 1; MINISH_SIZED_ENTRANCE writes 3).
-- * The PPU draws, back to front, priority 3 .. 0; within one priority the
--   OBJs are over the BGs and BG1 is over BG2; among OBJs the OAM order
--   (ResolveOamDrawPriority, Field:drawEntities' sort) decides.
-- So Link (layer 1, priority 2) walks under the BG1 door frames, tree tops
-- and arches, and under an ARCHWAY object, while on a raised floor or on
-- stairs (layer 2 / 3) he is over BG1.
local P = {}

local LAYER_PRIO = { [0] = 2, 2, 1, 1 }
P.LAYER_PRIO = LAYER_PRIO

function P.oam(e)
  if e.oamPrio then return e.oamPrio end
  if e.overLink then return 1 end -- ARCHWAY / MINISH_SIZED_ARCHWAY: collision layer 2
  return LAYER_PRIO[e.layer or 1] or 2
end

-- AREA_HOUSE_INTERIORS_1..3, TREE_INTERIORS, DOJOS, MINISH_CRACKS,
-- HOUSE_INTERIORS_4, WIND_TRIBE_TOWER, EZLO_CUTSCENE (LoadRoomGfx's switch)
P.BG1_PRIO2_AREAS = { [0x21] = true, [0x22] = true, [0x23] = true, [0x24] = true, [0x25] = true,
  [0x27] = true, [0x28] = true, [0x30] = true, [0x38] = true }

-- BG priorities of the room: bottom = BG2, top = BG1 (nil: not drawn)
function P.bg(f, r)
  local top = 1
  -- round 15: LoadRoomGfx gives the house-type areas BG1 control
  -- gUnk_080B77C0[2] = $1D46: priority 2 (sprites over the top layer)
  if P.BG1_PRIO2_AREAS[r.area or -1] then top = 2 end
  if r.topUnder then top = 2 end -- BG1 under the sprites (Gleerok's lava)
  if f.debugNoTop or (r.hideTop and not r.topUnder) then top = nil end
  return (r.bgPrio and r.bgPrio.bottom) or 2, (r.bgPrio and r.bgPrio.top) or top
end

-- draw the room picture (both BG layers, the barrel's BG, the sprites)
-- with the field's camera; `opts.noSprites` draws the BGs only
function P.compose(f, r, opts)
  local g = love.graphics
  local list = (not (opts and opts.noSprites)) and f:drawEntities("sort") or {}
  local buckets = { [0] = {}, {}, {}, {} }
  for _, e in ipairs(list) do local b = buckets[P.oam(e)] or buckets[2]; b[#b + 1] = e end
  local bp, tp = P.bg(f, r)
  local pp = P.oam(f.player)
  local camX, camY = f.camX, f.camY
  local function layer(name)
    if f.layerFn then f.layerFn(r, name, camX, camY) else r:drawLayer(name, camX, camY) end
  end
  for p = 3, 0, -1 do
    if p == 3 and r.bg3 then require("src.zelda.tmc.Bg3").draw(f, r, camX, camY) end -- round 15
    if bp == p then
      layer("bottom")
      if f._dungeon and f._dungeon.barrel then f._dungeon.barrel:draw() end -- round 6: the barrel's BG2
    end
    if tp == p then
      g.setColor(1, 1, 1, r.topAlpha or 1)
      layer("top")
      g.setColor(1, 1, 1, 1)
    end
    if #buckets[p] > 0 then f:drawSpriteList(buckets[p]) end
    if p == pp and not (opts and opts.noSprites) then
      require("src.zelda.tmc.GustJar").draw(f, camX, camY) -- round 13: the jar's puff
      g.setColor(1, 1, 1, 1)
    end
  end
  return list
end

return P
