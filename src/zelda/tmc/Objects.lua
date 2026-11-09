-- World objects and tile actions for The Minish Cap.
--
--   * GROUND_ITEM (object 0): rupees, hearts, Kinstone pieces and the
--     items lying in rooms; their sprite is gObjectDefinitions[0][item] and
--     the animation index is the item id (sub_08080CB4).  Drops hop out
--     (zVelocity 1.875, gravity 40/256, ItemOnGround_Action1) and vanish
--     after 600 frames (sub_080814A4), blinking at the end.
--   * random drops (CreateRandomItemDrop): the droptable for the source
--     (enemy table by DeathFx_EnemyDroptables, area table for grass/pots)
--     plus the cartridge's low-health / low-rupee bonuses, a weighted pick
--     starting at a random slot, then CreateItemDrop's gates (bomb bag,
--     bow, Earth Element for shells, Kinstone bag for pieces).
--   * tile actions in front of Link (beanstalkSubtask.c): ACT_TILE_26
--     chests (OpenSmallChest: the tile entity's item, its local flag, tile
--     $74), ACT_TILE_58 / 91 signs (the SIGN tile entity's message), both
--     only facing north and not Minish; liftable tiles (DoTileInteraction
--     filter 6) and cuttable tiles (filter 0, the sword).
--   * the item-get sequence: Link holds the item up while the item's
--     message (gItemMetaData textId/textCategory) shows.
--   * Minish portals (MINISH_PORTAL_MANAGER): R on the portal shrinks or
--     grows Link (PlayerUsePortal), who lands at portal + sOffsets[exit].

local bit = require("bit")
local band, rshift, bor = bit.band, bit.rshift, bit.bor
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local Objects = {}
Objects.__index = Objects

local OBJ = { GROUND_ITEM = 0x00, POT = 0x05, EZLO_CAP = 0x06, SPECIAL_FX = 0x0F, BUSH = 0x11, HOUSE_SIGN = 0x1C }
Objects.OBJ = OBJ
local ITEM = {
  SHELLS = 0x3F, RUPEE1 = 0x54, RUPEE5 = 0x55, RUPEE20 = 0x56, RUPEE50 = 0x57, RUPEE100 = 0x58, RUPEE200 = 0x59,
  JABBERNUT = 0x5B, KINSTONE = 0x5C, BOMBS5 = 0x5D, ARROWS5 = 0x5E, HEART = 0x5F, FAIRY = 0x60,
  SHELLS30 = 0x61, HEART_CONTAINER = 0x62, HEART_PIECE = 0x63, WALLET = 0x64, BOMBBAG = 0x65, KINSTONE_BAG = 0x67,
  BOW = 0x09, EARTH_ELEMENT = 0x40, KINSTONE_RED = 0xFC, KINSTONE_GREEN = 0xFE, ENEMY_BEETLE = 0xFF,
}
Objects.ITEM = ITEM
local RUPEES = { [0x54] = 1, [0x55] = 5, [0x56] = 20, [0x57] = 50, [0x58] = 100, [0x59] = 200 }
local ACT_CHEST, ACT_SIGN, ACT_SIGN2 = 0x1A, 0x3A, 0x5B
local TILE_CHEST_OPEN = 0x74
local SFX = { CHEST = 0x11B, ITEM_GET = 0x109, RUPEE = 0x6F, HEART = 0x71, LIFT = 0x7F, SHRINK = 0x16F, GROW = 0x170,
              SECRET = 0x72 }
Objects.SFX = SFX

function Objects.new(field)
  return setmetatable({ field = field, A = field.assets, m = field.assets.manifest }, Objects)
end

-- the object definition (multi-form resolved)
function Objects:def(id, form)
  local d = self.m.objectDefs and self.m.objectDefs[id]
  if d and d.type == 2 then d = d.forms and d.forms[form or 0] end
  if d and d.type ~= 0 then return d end
  return nil
end

-- set up an entity's sprite from a definition
function Objects:dress(e, d, anim)
  e.def = d
  e.sprite = d.sprite
  e.palette = self.A:objPalette(d.palette, self.field.room.atlas and self.field.room.atlas.palettes)
  e.gfx = Assets.gfxSource(d.gfxType, d.gfx)
  e.anim = e.anim or Anim.new()
  e.forceAnim = anim or 0
  e.field80 = anim or 0
  e.literalAnim = true
end

-- ---------------------------------------------------------------------------
-- ground items
-- ---------------------------------------------------------------------------
function Objects:groundItem(item, param, x, y, opts)
  opts = opts or {}
  local e = { kind = 6, id = OBJ.GROUND_ITEM, form = item, item = item, param = param or 0,
              x = x, y = y, z = 0, zv = 0, animationState = 0, field82 = 0, interactType = 0,
              anim = Anim.new(), ground = true, life = 600 }
  local d = self:def(OBJ.GROUND_ITEM, item)
  if not d then return nil end
  self:dress(e, d, item)
  if item == ITEM.KINSTONE then
    local ev = self.m.kinstones and self.m.kinstones.events[param or 0]
    if ev then e.palette = self.A:objPalette(ev.objPalette) end
  end
  if opts.drop then
    e.zv = 1.875 -- Q_16_16(1.875)
    e.z = 0.01
  else
    e.life = nil -- placed items stay
  end
  e.key = opts.key
  self.field.entities[#self.field.entities + 1] = e
  return e
end

-- CreateItemDrop: the gates, then a ground item
function Objects:createItemDrop(src, item, param)
  local f = self.field
  if item == ITEM.ENEMY_BEETLE then return nil end -- spawns a Beetle on the cartridge
  if item == ITEM.BOMBS5 and f:inventory(ITEM.BOMBBAG) == 0 then return nil end
  if item == ITEM.ARROWS5 and f:inventory(ITEM.BOW) == 0 then return nil end
  if item == ITEM.SHELLS then
    if f:inventory(ITEM.EARTH_ELEMENT) == 0 then return nil end
    if (param or 0) == 0 then param = 1 end
  end
  if item == ITEM.KINSTONE or (item >= ITEM.KINSTONE_RED and item <= ITEM.KINSTONE_GREEN) then
    if f:inventory(ITEM.KINSTONE_BAG) == 0 then return nil end
    if item ~= ITEM.KINSTONE then
      local row = self.m.drops and self.m.drops.kinstonePieces and self.m.drops.kinstonePieces[item - ITEM.KINSTONE_RED]
      param = row and row[math.random(0, 0x3F)] or 0
      if param == 0 then return nil end
      item = ITEM.KINSTONE
    end
  end
  return self:groundItem(item, param, src.x, src.y, { drop = true })
end

-- CreateRandomItemDrop(src, table): 1-12 enemy tables, 15 the area's
function Objects:randomDrop(src, tableIndex)
  local D = self.m.drops
  if not D or self.field.dropsDisabled then return nil end
  local base
  if tableIndex >= 1 and tableIndex <= 12 then base = D.enemy[tableIndex]
  elseif tableIndex == 15 then base = self:areaDroptable() end
  if not base then return nil end
  local s = self.field.save.stats
  local t = {}
  for k = 0, 15 do t[k] = base[k] or 0 end
  if (s.health or 0) <= 8 then t[4] = t[4] + 5 end
  if (s.bombCount or 0) == 0 then t[6] = t[6] + 3 end
  if (s.arrowCount or 0) == 0 then t[7] = t[7] + 3 end
  if (s.rupees or 0) <= 10 then t[2] = t[2] + 1 end
  local sum = 0
  for k = 0, 15 do
    if t[k] < 0 then t[k] = 0 end
    sum = sum + t[k]
  end
  if sum <= 0 then return nil end
  local item = math.random(0, 15)
  local r = math.random(0, sum - 1)
  local acc = 0
  for _ = 0, 15 do
    acc = acc + t[item]
    if acc > r then break end
    item = (item + 1) % 16
  end
  local id = D.slotItems[item]
  if id and id ~= 0 then return self:createItemDrop(src, id, 0) end
  return nil
end

-- gRoomVars.currentAreaDroptable: gAreaDroptables[gUnk_080FE1C6[location]]
function Objects:areaDroptable()
  local D = self.m.drops
  local loc = self.field.room.areaInfo and self.field.room.areaInfo.location or 0
  if loc > 0x16 then loc = 0 end
  local idx = D.areaSelect and D.areaSelect[loc] or 0
  return D.area and D.area[idx]
end

-- collect: rupees, hearts and pieces at once; everything else through the
-- item-get sequence
function Objects:collect(e)
  local f = self.field
  local item = e.item
  e.deleted = true
  if e.key then f:markCollected(e.key) end
  if e.flagSpec then f:dungeon():set(e.flagSpec) end
  if RUPEES[item] then f:modStat("rupees", RUPEES[item]); f:sound(SFX.RUPEE); return end
  if item == ITEM.HEART then f:modStat("health", 8); f:sound(SFX.HEART); return end
  if item == ITEM.FAIRY then f:modStat("health", 8 * 6); f:sound(SFX.HEART); return end
  if item == ITEM.KINSTONE then f.kinstone:addPiece(e.param); f:sound(SFX.RUPEE); return end
  if item == ITEM.SHELLS then f:modStat("shells", math.max(1, e.param or 1)); f:sound(SFX.RUPEE); return end
  if item == ITEM.BOMBS5 then f:modStat("bombCount", 5); return end
  if item == ITEM.ARROWS5 then f:modStat("arrowCount", 5); return end
  f:giveItem(item, e.param)
end

function Objects:updateGround(e)
  local f = self.field
  if e.zv ~= 0 or (e.z or 0) > 0 then
    e.z = (e.z or 0) + e.zv
    e.zv = e.zv - 40 / 256
    if e.z <= 0 then e.z = 0; e.zv = 0 end
  end
  if e.life then
    e.life = e.life - 1
    e.hidden = e.life < 90 and e.life % 4 < 2
    if e.life <= 0 then e.deleted = true return end
  end
  local p = f.player
  if (e.z or 0) <= 2 and p.state ~= "dead" and math.abs(p.x - e.x) < 9 and math.abs(p.y - e.y) < 9 then
    self:collect(e)
  end
end

-- the item icon (held up, in menus): its ground sprite's first frame
function Objects:drawItemIcon(item, x, y)
  local d = self:def(OBJ.GROUND_ITEM, item)
  if not d then return end
  local s = self.A:sprite(d.sprite)
  local keys = s and s.anims and s.anims[item]
  local frame = keys and keys[1] and keys[1][1]
  if not frame then return end
  local img, ox, oy = self.A:spriteFrame(d.sprite, frame, self.A:objPalette(d.palette), "icon", Assets.gfxSource(d.gfxType, d.gfx))
  if img then love.graphics.draw(img, math.floor(x + ox), math.floor(y + oy)) end
end

-- ---------------------------------------------------------------------------
-- tiles: SetTileType needs the metatile that has a given tile type
-- ---------------------------------------------------------------------------
function Objects:setTileType(layer, tx, ty, ttype)
  local r = self.field.room
  local name = layer == 2 and "top" or "bottom"
  local atlas = r.atlas
  if not atlas then return end
  atlas.reverse = atlas.reverse or {}
  local rev = atlas.reverse[name]
  if not rev then
    rev = {}
    local types = atlas.types[name] or {}
    for i = 0x7FF, 0, -1 do rev[types[i] or 0] = i end
    atlas.reverse[name] = rev
  end
  local mt = rev[ttype]
  if mt then r:setTile(layer, tx, ty, mt) end
end

-- DoTileInteraction(filter) at room pixel (x, y): the entry for the tile
-- there when its mask has bit `filter`; replaces the tile, returns entry
function Objects:tileInteraction(filter, x, y, layer)
  local r = self.field.room
  layer = layer or 1
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return nil end
  local ttype = r:tileType(layer, tx, ty)
  local acts = self.m.tileActs
  if not (ttype and acts) then return nil end
  local idx = acts.map[ttype]
  local e = idx and acts.entries[idx]
  if not e or band(rshift(e.mask, filter), 1) == 0 then return nil end
  if e.tile == 0xFFFF then
    -- RestorePrevTileEntity: not tracked; leave the tile
  elseif band(e.tile, 0x4000) ~= 0 then
    r:setTile(layer, tx, ty, e.tile)
  else
    self:setTileType(layer, tx, ty, e.tile)
  end
  return e, tx * 16 + 8, ty * 16 + 8
end

-- ---------------------------------------------------------------------------
-- R in front of something: chest, sign, liftable tile or object, portal
-- ---------------------------------------------------------------------------
function Objects:tileEntityAt(tx, ty, ttype)
  for _, t in ipairs(self.field.room.tileEntities or {}) do
    if t.pos == tx + ty * 64 and (not ttype or t.type == ttype) then return t end
  end
  return nil
end

function Objects:tryAction(p)
  local f = self.field
  if self:tryPortal(p) then return true end
  if p.minish then return false end
  local px, py = p:probe()
  local r = f.room
  local tx, ty = math.floor(px / 16), math.floor(py / 16)
  -- chests and signs can sit on either BG layer (a chest's tile entity
  -- says which: _6 & 1 = top)
  local act, layer
  for _, l in ipairs({ p.layer, p.layer == 1 and 2 or 1 }) do
    local ttype = r:tileType(l, tx, ty)
    local a = ttype and ttype < 0x4000 and self.A.actTile[ttype] or nil
    if a == ACT_CHEST or a == ACT_SIGN or a == ACT_SIGN2 then act, layer = a, l break end
  end
  if p.animationState == 0 and act == ACT_CHEST then
    return self:openChest(tx, ty, layer)
  end
  if p.animationState == 0 and (act == ACT_SIGN or act == ACT_SIGN2) then
    local t = self:tileEntityAt(tx, ty, 5) -- SIGN
    local msg = t and (t.c + t.d * 256) or 0x0600 -- TEXT_INDEX(TEXT_LOCATIONS, 0)
    f:message(msg)
    return true
  end
  -- lift: a liftable tile (filter 6) or a pot object in front
  for _, e in ipairs(f.entities) do
    if e.liftable and not e.deleted and math.abs(e.x - px) < 10 and math.abs(e.y - (py + 3)) < 10 then
      e.deleted = true
      return self:lift(p, { obj = e.id, form = e.form, def = e.def })
    end
  end
  local entry = self:tileInteraction(6, px, py, p.layer)
  if entry then
    return self:lift(p, { obj = entry.obj, form = entry.objType })
  end
  return false
end

function Objects:openChest(tx, ty, layer)
  local f = self.field
  local t = self:tileEntityAt(tx, ty, 2) -- SMALL_CHEST
  self:setTileType(layer, tx, ty, TILE_CHEST_OPEN)
  f:sound(SFX.CHEST)
  if t then
    f:setFlag("local", t.flag, true)
    f:giveItem(t.a, t.b)
  else
    f:giveItem(ITEM.FAIRY, 0)
  end
  return true
end

-- chests already opened show open when the room loads (sub_0804B16C)
function Objects:roomLoaded()
  local f = self.field
  for _, t in ipairs(f.room.tileEntities or {}) do
    if t.type == 2 and f:flag("local", t.flag) then
      self:setTileType(band(t.c, 1) == 1 and 2 or 1, t.pos % 64, math.floor(t.pos / 64), TILE_CHEST_OPEN)
    end
  end
end

-- ---------------------------------------------------------------------------
-- lifting and throwing
-- ---------------------------------------------------------------------------
function Objects:lift(p, what)
  local f = self.field
  if what.obj and what.obj ~= 0xFF and not what.def then what.def = self:def(what.obj, what.form) end
  p.carried = what
  p.state = "carry"
  p:setAnim(p.hasCap and 0x338 or 0x928, true) -- ANIM_PICKUP / _NOCAP
  f:sound(SFX.LIFT)
  return true
end

function Objects:drawCarried(c, x, y)
  local d = c.def
  if not d then
    love.graphics.setColor(0.35, 0.55, 0.85, 1)
    love.graphics.rectangle("fill", x - 6, y - 6, 12, 10, 3, 3)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local s = self.A:sprite(d.sprite)
  local keys = s and s.anims and (s.anims[c.form or 0] or s.anims[0])
  local frame = keys and keys[1] and keys[1][1]
  if not frame then return end
  local img, ox, oy = self.A:spriteFrame(d.sprite, frame, self.A:objPalette(d.palette), "carry",
    Assets.gfxSource(d.gfxType, d.gfx))
  if img then love.graphics.draw(img, math.floor(x + ox), math.floor(y + oy)) end
end

function Objects:throwCarried(p)
  local c = p.carried
  p.carried = nil
  if not c then return end
  local s = p.animationState
  local vx = (s == 2 and 1 or s == 6 and -1 or 0) * 2.5
  local vy = (s == 4 and 1 or s == 0 and -1 or 0) * 2.5
  local e = { kind = 6, id = c.obj or OBJ.POT, form = c.form, x = p.x, y = p.y, z = 14, zv = 0.5,
              vx = vx, vy = vy, thrown = true, animationState = 0, field82 = 0, interactType = 0, anim = Anim.new() }
  if c.def then self:dress(e, c.def, c.form or 0) end
  self.field.entities[#self.field.entities + 1] = e
  self.field:sound(0x7C) -- SFX_PLY_JUMP-like whoosh
end

function Objects:dropCarried(p)
  if p.carried then
    local c = p.carried
    p.carried = nil
    self:shatter({ x = p.x, y = p.y })
    local _ = c
  end
end

function Objects:shatter(e)
  self.field:sound(0x11C) -- the pot / bush break
  self:randomDrop(e, 15)
end

function Objects:updateThrown(e)
  local f = self.field
  e.x = e.x + e.vx
  e.y = e.y + e.vy
  e.z = e.z + e.zv
  e.zv = e.zv - 0.25
  local hit = f.room:isSolid(e.x, e.y, 1)
  if not hit then hit = f:enemies():hitByObject(e) end
  if e.z <= 0 or hit then
    e.deleted = true
    self:shatter(e)
  end
end

-- ---------------------------------------------------------------------------
-- cutting: the sword's DoTileInteraction(filter 0)
-- ---------------------------------------------------------------------------
function Objects:cut(x, y, layer)
  local entry, cx, cy = self:tileInteraction(0, x, y, layer)
  if entry then
    -- grass / bush cut: FX, sometimes a drop from the area table
    self.field:addFx(cx, cy, entry.obj, entry.objType)
    if entry.obj == OBJ.SPECIAL_FX or entry.obj == OBJ.BUSH then
      self:randomDrop({ x = cx, y = cy }, 15)
    end
    self.field:sound(0x14C) -- SFX_14C: the cut
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Minish portals
-- ---------------------------------------------------------------------------
local PORTAL_Y = { [0] = -3, -3, -3, 0 }        -- gUnk_08107C6C by portal type
local EXIT_OFF = { [0] = { 0, -22 }, { 22, 0 }, { 0, 22 }, { -22, 0 } } -- sub_080717F8 sOffsets

function Objects:addPortal(d)
  -- MINISH_PORTAL_MANAGER: x/y the portal, type2 low = exit direction,
  -- type2 high = layer (RegisterRoomEntity copies EntityData over the
  -- manager's fields)
  local p = { x = d.x, y = d.y + (PORTAL_Y[d.paramA] or 0), exit = band(d.paramB, 0xFF) % 4,
              type = d.paramA, layer = band(rshift(d.paramB, 8), 0xFF) }
  self.field.portals[#self.field.portals + 1] = p
end

function Objects:portalNear(pl)
  for _, p in ipairs(self.field.portals or {}) do
    if math.abs(pl.x - p.x) <= 10 and math.abs(pl.y - p.y) <= 10 then return p end
  end
  return nil
end

function Objects:tryPortal(pl)
  local f = self.field
  if not f:flag("global", 0x14) then return false end -- EZERO_1ST: Ezlo knows the way
  local p = self:portalNear(pl)
  if not p then return false end
  pl.state = "portal"
  pl.portal = p
  pl.x, pl.y = p.x, p.y
  pl.animationState = 4
  if pl.minish then
    pl:setAnim(0x73C, true) -- ANIM_GROW
    f:sound(SFX.GROW)
    pl.timer = 60
  else
    pl:setAnim(0x2C3, true) -- ANIM_PORTAL_SHRINK
    f:sound(SFX.SHRINK)
    pl.timer = 90
  end
  return true
end

function Objects:portalDone(pl)
  local p = pl.portal
  pl.portal = nil
  pl.state = "normal"
  pl.animId = -1
  if pl.minish then
    pl.minish = false
    pl.x, pl.y = p.x, p.y + 8
    pl.animationState = 4
  else
    pl.minish = true
    local o = EXIT_OFF[p.exit] or EXIT_OFF[2]
    pl.x, pl.y = p.x + o[1], p.y + o[2]
    pl.animationState = p.exit * 2
  end
  pl.invuln = 0
end

return Objects
