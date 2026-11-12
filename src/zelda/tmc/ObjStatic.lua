-- Objects drawn with a fixed frame (round 7): furniture, archways, minish
-- entrances, masks, shelves, boards, windcrests...
--
-- These objects have no animation: their init code sets frameIndex straight
-- from the entity's type / type2 (furniture.c FurnitureInit, archway.c,
-- minishSizedEntrance.c, minishSizedArchway.c, mask.c, doubleBookshelf.c,
-- board.c, windcrest.c, minishLight.c, pushableFurniture.c). Furniture also
-- takes its sprite offset from its FurnitureCfg (gUnk_08121EF8, and the nine
-- per-type2 tables when flags bit 15 is set), read from the player's ROM
-- (menudata.bin range `furnitureCfg`).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local ObjStatic = {}

local CFG = 0x08121EF8
-- furniture.c sCfgTable: the tables cfg->y names when flags & $8000
local SUB = { 0x08122128, 0x08122198, 0x081221A8, 0x081221B8, 0x081221C8,
              0x081221D8, 0x081221E8, 0x081221F8, 0x08122208 }

local function cfgReader(A)
  if A._furnCfg == nil then
    local e = A.manifest and A.manifest.menuData and A.manifest.menuData.furnitureCfg
    if e then
      A.menuBlob = A.menuBlob or (A.store and A.store:read("menudata.bin")) or ""
      local blob, base, off, size = A.menuBlob, e[1], e[2], e[3]
      local t = {}
      function t.u8(a)
        local o = a - base
        if o < 0 or o >= size then return 0 end
        return blob:byte(off + o + 1) or 0
      end
      function t.s8(a) local v = t.u8(a) return v >= 128 and v - 256 or v end
      function t.u16(a) return t.u8(a) + 256 * t.u8(a + 1) end
      A._furnCfg = t
    else
      A._furnCfg = false
    end
  end
  return A._furnCfg or nil
end

local function isDungeon(field)
  local a = field.room and field.room.area or 0
  return a >= 0x48 and a < 0x80
end

-- FurnitureInit: frame / sprite offset / priority
local function furniture(field, e, typ, type2)
  local R = cfgReader(field.assets)
  local frame = 0
  if R then
    local c = CFG + typ * 8
    if band(R.u16(c + 6), 0x8000) ~= 0 then
      local sub = SUB[R.u8(c + 3) + 1]
      if sub then c = sub + type2 * 8 end
      frame = type2
    end
    e.spriteOX, e.spriteOY = R.s8(c + 2), R.s8(c + 3)
    e.furniture = { w = R.u8(c), h = R.u8(c + 1), rendering = R.u8(c + 4), priority = R.u8(c + 5), flags = R.u16(c + 6) }
  end
  return frame
end

-- round 15: ChangeObjPalette (a per-entity definition copy keeps the
-- sprite cache key apart) and CreateObject for an object's parts
local function changePal(field, e, id)
  e.def = setmetatable({ palette = id }, { __index = e.def })
  e.palette = field.assets:objPalette(id, field.room and field.room.atlas and field.room.atlas.palettes)
end
local function child(field, e, id, typ, type2, dx, dy)
  if not field.spawn then return end
  field:spawn({ kind = 6, id = id, paramA = typ, paramB = type2 or 0, paramC = 0, pool = 0x0F,
                x = e.x + (dx or 0), y = e.y + (dy or 0), collision = e.layer or 1 })
end
ObjStatic.changePal = changePal

-- macroDecoration.c sub_08097F60: how far a Minish-size backdrop object
-- moves with the camera (the parallax of the huge decorations)
local function macroShift(typ, frame)
  if typ == 1 and rshift(frame, 1) == 1 then return 3 end
  if typ == 1 or typ == 2 or typ == 3 then return 1 end
  return nil
end
ObjStatic.macroShift = macroShift

-- object id -> function(field, e, type, type2) returning frameIndex
ObjStatic.FRAME = {
  [0x4D] = furniture,                                          -- FURNITURE
  [0x4C] = function() return 0 end,                            -- PUSHABLE_FURNITURE
  [0x4E] = function(f, e, t, t2) e.oamPrio, e.spritePriority = 3, 7 return t2 + (isDungeon(f) and 4 or 0) end, -- MINISH_SIZED_ENTRANCE (b3 3, b0 7; round 14)
  [0x4F] = function(f, e, t, t2) e.overLink = true return t2 end, -- ARCHWAY (layer 2)
  [0x6F] = function(f, e, t) e.overLink = true return t end,    -- MINISH_SIZED_ARCHWAY (layer 2)
  [0x5C] = function(f, e, t, t2) return band(t2, 0x3F) end,     -- MASK
  [0x8B] = function(f, e, t) return t end,                      -- DOUBLE_BOOKSHELF
  [0x80] = function(f, e, t) return t end,                      -- BOARD
  [0xBB] = function() return 0 end,                             -- WINDCREST
  [0xA4] = function() return 0 end,                             -- MINISH_LIGHT
  -- round 14: objects whose Init sets frameIndex itself (they drew nothing
  -- here until something set an animation)
  [0x71] = function(f, e, t) return t end,                      -- PUSHABLE_GRAVE (frameIndex = type)
  [0x72] = function(f, e, t) return t == 3 and 0 or t end,      -- STONE_TABLET
  [0xAE] = function(f, e, t) return t end,                      -- FLOATING_BLOCK
  [0x9D] = function() return 0 end,                             -- LIGHTABLE_SWITCH (unlit)
  -- round 15 (the p_invis list): giantTwig.c, macroDecorations.c,
  -- macroShoe.c, macroAcorn.c, waterfallOpening.c, bakerOven.c,
  -- cabinFurniture.c, figurineDevice.c Init code
  [0x62] = function(f, e, t, t2)                                -- GIANT_TWIG
    if t == 0 then
      e.oamPrio, e.spritePriority = 2, 5
      child(f, e, 0x62, 0x40, 0)
      return 1
    elseif t == 0x40 then e.spritePriority = 7; child(f, e, 0x62, 0x41, 0); return 2
    elseif t == 0x41 then e.flipY = true; return 0
    elseif t == 1 then e.spritePriority = 7; return band(t2, 1) + 3
    elseif t == 2 then
      e.oamPrio, e.spritePriority = 3, 7
      if band(t2, 1) ~= 0 then e.spriteOX = 8 end
      changePal(f, e, 0x7B)
      return band(t2, 1) + 5
    elseif t == 3 then e.spritePriority = 7; changePal(f, e, 0x7A); return band(t2, 3) + 7 end
    return 0
  end,
  [0x78] = function(f, e, t, t2)                                -- HUGE_DECORATION
    local frame = 0
    if t == 0 then
      if t2 ~= 0 then changePal(f, e, t2 + 0x0B) end
    elseif t == 1 then
      frame = t2
      local k = rshift(band(t2, 0xFF), 1)
      if k == 2 then changePal(f, e, 0x0D); e.flipY = true
      elseif k == 0 then e.flipY = true
      elseif k == 1 then e.spritePriority = 3; changePal(f, e, 0x0B) end
    elseif t == 2 or t == 3 then frame = t2 end
    e.macroShift = macroShift(t, frame)
    return frame
  end,
  [0x7C] = function() return 0 end,                              -- HUGE_SHOES (no frame set: 0)
  [0x9A] = function(f, e, t, t2)                                -- HUGE_ACORN
    local frame
    if t == 0xFF then frame = t2
    else
      local b = band(t, 1) ~= 0 and 4 or 0
      frame = b
      if band(t, 2) ~= 0 then
        child(f, e, 0x9A, 0xFF, b + 1); child(f, e, 0x9A, 0xFF, b + 2, 0, 1); child(f, e, 0x9A, 0xFF, b + 3)
      else
        child(f, e, 0x9A, 0xFF, b + 1)
      end
    end
    if band(frame, 1) ~= 0 then e.oamPrio, e.spritePriority = 3, 7 end
    return frame
  end,
  [0xAA] = function(f, e, t) e.oamPrio, e.spritePriority = 3, 7; return ({ [0] = 0, 4, 8, 0 })[t] or 0 end, -- WATERFALL_OPENING
  [0x92] = function(f, e, t) if t == 0 then e.spritePriority = 5 end return 0 end, -- BAKER_OVEN (type 0: no frame set)
  [0x8A] = function() return 0 end,                              -- CABIN_FURNITURE (no frame set: 0)
  [0x22] = function(f, e, t)                                    -- FIGURINE_DEVICE types 0 / 1: frame 0
    if t == 0 or t == 1 then e.oamPrio, e.spritePriority = 3, 7 end
    return 0
  end,
  -- round 16 (p_invis): minishVillageObject.c types 0 / 7 / 8,
  -- carlovObject.c type 1, paper.c types 0..2 set frameIndex in Init
  [0x3E] = function(f, e, t, t2)                                -- MINISH_VILLAGE_OBJECT
    e.spritePriority = 7
    if t == 7 or t == 8 then return t2 end
    return 0
  end,
  [0x35] = function() return 0 end,                             -- CARLOV_OBJECT type 1 (frameIndex 0)
  [0x5A] = function(f, e, t, t2)                                -- PAPER
    if t == 1 then
      if t2 == 0 then e.spriteOY = 2 elseif t2 == 2 then e.spriteOY = -2 end
      return t2
    end
    if t == 0 and t2 == 2 then e.hidden = true end              -- Paper_Type0: type2 2 is not drawn
    return 0
  end,
  [0x9E] = function(f, e, t)                                    -- TREE_THORNS: type 0 frame 1 (layer 1),
    if t ~= 0 then e.layer = 2 return 0 end                     -- its type-1 top frame 0 on layer 2
    e.layer = 1 return 1
  end,
}
-- round 14: these set frameIndex directly even when their sprite has
-- animations (the animation is not started by their Init)
local FORCE = { [0x71] = true, [0x72] = true, [0xAE] = true, [0x9D] = true, [0x9E] = true,
  [0x62] = true, [0x78] = true, [0x7C] = true, [0x9A] = true, [0xAA] = true, [0x8A] = true, -- round 15
  [0x92] = function(t) return t == 0 end, [0x22] = function(t) return t == 0 or t == 1 end,
  [0x3E] = function(t) return t == 0 or t == 7 or t == 8 end, [0x35] = function(t) return t == 1 end, -- round 16
  [0x5A] = function(t) return t <= 2 end }

-- after Objects:dress: a fixed frame for objects that never animate
function ObjStatic.apply(field, e, d)
  local fn = ObjStatic.FRAME[d.id]
  if not fn then return false end
  local spr = field.assets:sprite(e.sprite)
  -- an object whose sprite does animate keeps its animation
  local force = FORCE[d.id]
  if type(force) == "function" then force = force(d.paramA or 0) end
  if spr and spr.anims and spr.anims[0] and d.id ~= 0x4D and d.id ~= 0x4C and not force then return false end
  e.staticFrame = fn(field, e, d.paramA or 0, band(d.paramB or 0, 0xFF)) or 0
  return true
end

return ObjStatic
