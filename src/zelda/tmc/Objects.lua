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
  -- round 9: ItemOnGround (src/object/itemOnGround.c).  A drop (kind 0,
  -- CreateItemDrop) is Kindx: action 1 rises (zVelocity 1.875, gravity
  -- 40/256) to its apex, then action 2 bounces (BounceUpdate) with its
  -- collision on and counts 600 frames down, blinking under 90.  z is kept
  -- as the cartridge's Q16 (negative = up) in e.cz / e.czv.
  e.life = nil
  local k = opts.drop and 0 or opts.kind
  if k == 0 or k == 5 or k == 6 or k == 10 then
    e.act, e.cz, e.czv = 1, 0, math.floor((opts.zVelocity or 1.875) * 65536)
    e.t6c, e.bounced = (k == 10) and 120 or 600, false
    e.noDespawn = (k == 5)
    if opts.direction then e.dir, e.spd = band(opts.direction, 0x1F), opts.speed or 0x100 end
    e.drop = true
  else
    e.act = 2; e.static = true -- kinds 4 / 5 and the rest: they stay
  end
  e.key = opts.key
  self.field.entities[#self.field.entities + 1] = e
  return e
end

-- round 9: CreateItemDrop / CreateRandomItemDrop / the area table are the
-- cartridge's own (Drops.lua); these keep the old entry points
function Objects:createItemDrop(src, item, param)
  local id = require("src.zelda.tmc.Drops").createItemDrop(self.field, src, item, param, self)
  return id ~= 0 and id or nil
end

function Objects:randomDrop(src, tableIndex)
  local id = require("src.zelda.tmc.Drops").randomDrop(self.field, src, tableIndex, self)
  return id ~= 0 and id or nil
end

function Objects:areaDroptable()
  return self.field.areaDroptable
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
  if item == ITEM.FAIRY then f:modStat("health", 0x20); f:sound(SFX.HEART); return end -- round 20: gItemMetaData[ITEM_FAIRY] ModHealth($20) (was 6 hearts)
  if item == ITEM.KINSTONE then f.kinstone:addPiece(e.param); f:sound(SFX.RUPEE); return end
  if item == ITEM.SHELLS then f:modStat("shells", math.max(1, e.param or 1)); f:sound(SFX.RUPEE); return end
  if item == ITEM.BOMBS5 then require("src.zelda.tmc.Bombs").mod(f, 5); return end -- round 20: ModBombs caps at the bag (19 of 10 were seen)
  if item == ITEM.ARROWS5 then f:modStat("arrowCount", 5); return end
  f:giveItem(item, e.param)
end

function Objects:updateGround(e)
  local f = self.field
  -- round 9: ItemOnGround_Burried_Action2: shown (kind 0) once the tile
  -- under it changes (dug); a sunken item waits for a dive (not ported)
  if e.buried then
    if e.buried == 7 and f.room:tileType(1, math.floor(e.x / 16), math.floor(e.y / 16)) ~= e.originalTile then
      e.buried, e.hidden = nil, nil
    else
      e.hidden = true
      return
    end
  end
  local G40 = 40 * 256 -- Q_8_8(40.0) in Q16
  if e.act == 4 then
    -- the pickup hop over Link's head (ItemOnGround_Action4), 14 frames
    e.timer = e.timer - 1
    if e.timer <= 0 then e.deleted = true return end
    e.x, e.y = f.player.x, f.player.y
    local nz = e.cz - e.czv
    if nz >= 0 then e.cz, e.czv = 0, 0 else e.cz, e.czv = nz, e.czv - G40 end
    e.z = -e.cz / 65536
    return
  end
  if e.act == 1 then
    -- ItemOnGround_Action1: ProcessMovement2, GravityUpdate until the apex
    if e.dir then self:moveDrop(e) end
    local nz = e.cz - e.czv
    if nz >= 0 then e.cz, e.czv = 0, 0 else e.cz, e.czv = nz, e.czv - G40 end
    if e.czv <= 0 then e.act = 2; e.t6c = 600 end
  elseif e.act == 2 and not e.static then
    -- Kindx_Action2: sub_08081500 (BounceUpdate) then sub_080814C0
    if not e.bounced then
      local nz = e.cz - e.czv
      if nz < 0 then
        e.cz, e.czv = nz, e.czv - G40
        if e.dir then self:moveDrop(e) end
      else
        e.cz = 1
        local v = math.floor(-(e.czv - G40) / 2)
        v = v + math.floor(v / 4)
        if math.floor(v / 4096) >= 0xC then
          e.czv = v
          local sfx = self.m.drops and self.m.drops.itemSfx and self.m.drops.itemSfx[e.item]
          if sfx and sfx ~= 0 then f:sound(sfx) end
          if e.dir then self:moveDrop(e) end
        else
          e.czv, e.bounced = 0, true
        end
      end
    end
    if not e.noDespawn and not (f.textbox or f.playerScript or f:inputLocked()) then -- AnyPrioritySet
      e.t6c = e.t6c - 1
      if e.t6c <= 0 then e.deleted = true return end
      if e.t6c < 90 then e.hidden = not e.hidden end
    end
  end
  e.z = -(e.cz or 0) / 65536
  if e.act ~= 2 then return end
  -- contact: the item's hitbox (0, -3, 2x2) against Link's (0, -3, 6x6),
  -- depth 5 + 5 (IsColliding)
  local p = f.player
  -- round 18: whole pixels (x.HALF.HI), as the cartridge compares them
  if p.state ~= "dead" and math.abs(math.floor(p.x) - e.x) <= 8 and math.abs(math.floor(p.y) - e.y) <= 8
     and math.abs((p.z or 0) - e.z) <= 10 then
    self:collect(e)
    -- sub_08081598: the hop over Link's head (action 4); items with an
    -- item-get scene go straight to it
    local it = e.item
    if not (RUPEES[it] or it == ITEM.HEART or it == ITEM.KINSTONE or it == ITEM.SHELLS
            or it == ITEM.BOMBS5 or it == ITEM.ARROWS5) then return end
    e.deleted = nil
    e.act, e.timer, e.cz, e.czv, e.hidden = 4, 14, -math.floor(((p.z or 0) + 4) * 65536), 2 * 65536, false
    e.pickedUp = true
  end
end

-- ProcessMovement2 for a drop launched forward (direction | $80, speed):
-- a step that would land in a wall is dropped
function Objects:moveDrop(e)
  local a = e.dir * 8 / 256 * 2 * math.pi
  local s = (e.spd or 0x100) / 256
  local nx, ny = e.x + math.sin(a) * s, e.y - math.cos(a) * s
  if not self.field.room:isSolid(nx, ny, 1) then e.x, e.y = nx, ny end
end

-- the item icon (held up, in menus): its ground sprite's first frame
function Objects:drawItemIcon(item, x, y)
  -- round 19: LINK_HOLDING_ITEM ($0B) and FOUR_ELEMENTS ($AC) also show an
  -- item by sub_08080CB4 (animation = the item); the elements have no
  -- GROUND_ITEM frames, so Link held nothing up for them
  local d, frame
  for _, id in ipairs({ OBJ.GROUND_ITEM, 0x0B, 0xAC }) do
    local dd = self:def(id, item)
    local s = dd and dd.sprite and self.A:sprite(dd.sprite)
    local keys = s and s.anims and s.anims[item]
    local fr = keys and keys[1] and keys[1][1]
    if fr and fr ~= 0xFF then d, frame = dd, fr break end
  end
  if not d or not frame then return end
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

function Objects:tryAction(p, interactOnly)
  local f = self.field
  if not interactOnly and self:tryPortal(p) then return true end
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
  if interactOnly then return false end -- bug round: A interacts, R lifts
  -- lift: a liftable tile (filter 6) or a pot object in front
  for _, e in ipairs(f.entities) do
    if e.liftable and not e.deleted and math.abs(e.x - px) < 10 and math.abs(e.y - (py + 3)) < 10 then
      if e.carryHook then return e.carryHook(f, p, e) end -- round 21: an entity that stays itself while carried (Rollobite)
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
  if c.bomb then return end -- round 20: a carried bomb draws itself (Bombs.drawBomb, over Link's head)
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
  if c and c.bomb then return require("src.zelda.tmc.Bombs").throw(self.field, p) end -- round 20
  if c and c.hook then return c.hook.throw(self.field, p, c) end -- round 21 (EnemyBeetle: Rollobite)
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
  if p.carried and p.carried.bomb then return require("src.zelda.tmc.Bombs").drop(self.field, p) end -- round 20
  if p.carried and p.carried.hook then return p.carried.hook.drop(self.field, p, p.carried) end -- round 21
  if p.carried then
    local c = p.carried
    p.carried = nil
    self:breakThrown({ x = p.x, y = p.y, id = c.obj or OBJ.POT, form = c.form })
  end
end

-- round 9: BreakPot / sub_0808288C (src/object/pot.c): form 0 makes
-- FX_POT_SHATTER with type2 $80 (its drop table, 19 = object table 3 +
-- the area table); another form leaves that item (param e.potParam);
-- $FF nothing
function Objects:shatter(e, form, param)
  self.field:sound(0x11C) -- the pot / bush break
  form = form or 0
  if form == 0 then
    require("src.zelda.tmc.Drops").fxDrop(self.field, e, 0x05, self) -- FX_POT_SHATTER
  elseif form ~= 0xFF then
    self:groundItem(form, param or 0, e.x, e.y, { drop = true })
  end
end

function Objects:updateThrown(e)
  local f = self.field
  e.x = e.x + e.vx
  e.y = e.y + e.vy
  e.z = e.z + e.zv
  e.zv = e.zv - (e.grav or 0.25)
  if e.potFlip and e.zv < 0 then e.flipY = true end -- round 10: Pot_Action5
  local hit = not e.potFlip and f.room:isSolid(e.x, e.y, 1)
  if not hit then hit = f:enemies():hitByObject(e) end
  if e.z <= 0 or hit then
    e.deleted = true
    self:breakThrown(e)
  end
end

-- round 9: what breaks where a thrown object lands: a pot (BreakPot, by
-- its form), a bush (Bush_Action2SubAction5: CreateFx(FX_BUSH-type, $80),
-- the bush variant and its drop roll)
function Objects:breakThrown(e)
  if e.id == 0x7D then -- round 21: OBJECT_ON_BEETLE thrown: sub_080989C0, CreateFx(FX_BUSH + type)
    self.field:sound(0x11C)
    self.field:addFx(e.x, e.y, OBJ.SPECIAL_FX, 3 + (e.form or 0))
    return
  end
  if e.id == OBJ.BUSH then
    local Drops = require("src.zelda.tmc.Drops")
    local t = Drops.fxVariant(self.field, 0x03)
    self.field:sound(0x11C)
    self.field:addFx(e.x, e.y, OBJ.SPECIAL_FX, t)
    Drops.fxDrop(self.field, e, t, self)
  else
    self:shatter(e, e.form or 0, e.potParam)
  end
end

-- ---------------------------------------------------------------------------
-- cutting: the sword's DoTileInteraction(filter 0)
-- ---------------------------------------------------------------------------
function Objects:cut(x, y, layer)
  local entry, cx, cy = self:tileInteraction(0, x, y, layer)
  if entry then
    -- round 9: DoTileInteraction (asm/src/player.s): the entry's object
    -- at the tile's centre; a SPECIAL_FX gets type2 $80, so its init picks
    -- the FX variant (FX_BUSH / FX_GRASS_CUT: Random() & 3) and rolls
    -- CreateRandomItemDrop(gUnk_0811F960[type].droptable): grass 16, bush
    -- 17 (object table + area table).  Object $FF makes nothing.
    local Drops = require("src.zelda.tmc.Drops")
    if entry.obj == OBJ.SPECIAL_FX then
      local t = Drops.fxVariant(self.field, entry.objType)
      self.field:addFx(cx, cy, entry.obj, t)
      Drops.fxDrop(self.field, { x = cx, y = cy }, t, self)
    elseif entry.obj == OBJ.GROUND_ITEM then
      self:groundItem(entry.objType, 0, x, y, { drop = true })
    elseif entry.obj ~= 0xFF then
      self.field:addFx(cx, cy, entry.obj, entry.objType)
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
  -- round 10: Minish Link uses a portal from anywhere in the manager's
  -- 64x64 box (minishPortalManager.c CheckPlayerProximity(x - $20, y - $20,
  -- $40, $40) + PortalReadyForMinish: portal_mode 3); full-size Link has to
  -- stand on it (PortalJump.lua: portal_mode 2)
  local r = pl.minish and 0x20 or 10
  for _, p in ipairs(self.field.portals or {}) do
    if math.abs(pl.x - p.x) <= r and math.abs(pl.y - p.y) <= r then return p end
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
  require("src.zelda.tmc.PortalJump").clear(pl) -- round 10
  pl.state = "normal"
  pl.animId = -1
  if pl.minish then
    pl.minish = false
    pl.x, pl.y = p.x, p.y + 8
    pl.animationState = 4
    -- round 10: a portal on a stump (ACT_TILE_61 under it): Link stays on
    -- top of it, as on the cartridge, and hops off with the d-pad
    local r = self.field.room
    local tt = r:tileType(pl.layer or 1, math.floor(p.x / 16), math.floor(p.y / 16))
    if tt and tt < 0x4000 and self.field.assets.actTile[tt] == 0x3D then
      require("src.zelda.tmc.PortalJump").standOn(pl, p)
    end
  else
    pl.minish = true
    local o = EXIT_OFF[p.exit] or EXIT_OFF[2]
    pl.x, pl.y = p.x + o[1], p.y + o[2]
    pl.animationState = p.exit * 2
  end
  pl.invuln = 0
end

return Objects
