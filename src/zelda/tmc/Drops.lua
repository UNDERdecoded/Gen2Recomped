-- Round 9: the cartridge's item drops, ported from src/itemUtils.c
-- (CreateRandomItemDrop, CreateItemDrop, sub_08054524), src/room.c
-- (LoadRoomTileEntities: GRASS_DROP_CHANGER / LOCATION_CHANGER),
-- src/object/specialFx.c (the cut / break FX that roll a drop) and
-- asm/src/code_08000E44.s (Random).  Every table comes from the user's ROM
-- (Extract: manifest.drops).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Random(): gRand = ror32(gRand * 3, 13); returns gRand >> 1.  gRand
--     starts at $1234567 (src/main.c); one generator per game session.
--   * CreateRandomItemDrop(src, n): nothing while random drops are off;
--     n 1..12 the enemy table, 15 the room's area table, 16..23 an object
--     table plus the area table, 24/25 the health tables (by
--     needHealthDrop), anything else nothing.  Sum = base + modifier +
--     picolyte (s16, no clamp); +5 hearts at health <= 8, +3 bombs with no
--     bombs, +3 arrows with no arrows, +1 rupee5 at <= 10 Rupees; then the
--     no-shells (all figurines) / no-kinstones (all fusions) modifiers,
--     each slot clamped at 0, summed.  r = Random(): the walk starts at
--     slot (r >> 24) & 15 and stops where the running sum passes r % sum;
--     gUnk_080FE1B4 maps the slot to an item.
--   * CreateItemDrop: beetles only once Link has the Smith's Sword (an
--     enemy, not an item), bombs need the bomb bag, arrows the bow, shells
--     the Earth Element (param 0 -> 1), Kinstones the bag and at most 3
--     Kinstone drops the frame before; a red/blue/green piece becomes
--     gUnk_080FE1DD[color][Random() & $3F] (0 = nothing).
--   * The area table: gAreaDroptables[gUnk_080FE1C6[location]] with the
--     area's location (0 -> the previous one, > $16 -> 0); a room's
--     LOCATION_CHANGER ($0C) tile entity sets the location, its
--     GRASS_DROP_CHANGER ($0B) picks gAreaDroptables[n] directly.
--   * SpecialFx with type2 $80 rolls gUnk_0811F960[type].droptable; FX_BUSH
--     (3) and FX_GRASS_CUT ($17) first pick a variant with Random() & 3
--     (gUnk_0811FAC8 / gUnk_0811FACC).
-- NOT PORTED: picolytes (no modifier), figurine completion (never all).
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local Drops = {}

local ITEM = { SMITH_SWORD = 0x01, BOW = 0x09, EARTH_ELEMENT = 0x40, KINSTONE = 0x5C, BOMBS5 = 0x5D,
               ARROWS5 = 0x5E, SHELLS = 0x3F, BOMBBAG = 0x65, KINSTONE_BAG = 0x67,
               KINSTONE_RED = 0xFC, KINSTONE_GREEN = 0xFE, ENEMY_BEETLE = 0xFF }
Drops.ITEM = ITEM
local ENEMY_BEETLE_ID = 0x07
local FX_BUSH, FX_GRASS_CUT = 0x03, 0x17

-- ---------------------------------------------------------------------------
-- Random (asm/src/code_08000E44.s)
-- ---------------------------------------------------------------------------
local function u32(x) return x % 4294967296 end

function Drops.newRng(seed) return { s = seed or 0x1234567 } end

function Drops.random(rng)
  -- plain arithmetic (exact in doubles): s * 3 mod 2^32, then ror 13
  local s = u32(rng.s * 3)
  s = math.floor(s / 8192) + (s % 8192) * 524288
  rng.s = s
  return math.floor(s / 2)
end

local function rng(f)
  local g = f.game or f
  g.dropRng = g.dropRng or Drops.newRng()
  return g.dropRng
end
Drops.rngOf = rng

-- ---------------------------------------------------------------------------
-- the room's area table (sub_08052EA0 -> sub_08054524, LoadRoomTileEntities)
-- ---------------------------------------------------------------------------
function Drops.roomLoaded(f)
  local D = f.assets.manifest.drops
  f.randomDropsDisabled = false -- MemClear(&gRoomVars)
  if not D then f.areaDroptable = nil return end
  local info = f.room.areaInfo
  local loc = info and info.location or 0
  local function fromLoc(l)
    if l == 0 then l = f.lastLocation or 0 end
    if l > 0x16 then l = 0 end
    return D.area[D.areaSelect[l] or 0]
  end
  local tbl = fromLoc(loc)
  for _, t in ipairs(f.room.tileEntities or {}) do
    if t.type == 0x0C then loc = t.flag; tbl = fromLoc(loc)     -- LOCATION_CHANGER
    elseif t.type == 0x0B then tbl = D.area[t.flag] or tbl end  -- GRASS_DROP_CHANGER
  end
  f.areaDroptable = tbl
  if loc ~= 0 then f.lastLocation = loc end
end

-- ---------------------------------------------------------------------------
-- CreateRandomItemDrop
-- ---------------------------------------------------------------------------
local ZERO = {}
for k = 0, 15 do ZERO[k] = 0 end

-- the summed table for table index n (nil = no drop source); exposed for tests
function Drops.table(f, n)
  local D = f.assets.manifest.drops
  if not D then return nil end
  local mod, base = D.modifiers and D.modifiers[0] or ZERO, nil
  if n >= 1 and n <= 12 then base = D.enemy[n]
  elseif n == 24 or n == 25 then base = D.health and D.health[f.needHealthDrop and 1 or 0]
  elseif n >= 16 and n <= 23 then
    mod = D.object and D.object[n - 16] or ZERO
    base = f.areaDroptable
  elseif n == 15 then base = f.areaDroptable end
  if not base then return nil end
  local pic = D.modifiers and D.modifiers[0] or ZERO -- picolytes are not ported
  local t = {}
  for k = 0, 15 do t[k] = (base[k] or 0) + (mod[k] or 0) + (pic[k] or 0) end
  local s = f.save.stats
  if (s.health or 0) <= 8 then t[4] = t[4] + 5 end
  if (s.bombCount or 0) == 0 then t[6] = t[6] + 3 end
  if (s.arrowCount or 0) == 0 then t[7] = t[7] + 3 end
  if (s.rupees or 0) <= 10 then t[2] = t[2] + 1 end
  local m2 = (f.save.hasAllFigurines and D.modifiers and D.modifiers[1]) or ZERO
  local m3 = (Drops.allFusions(f) and D.modifiers and D.modifiers[2]) or ZERO
  local sum = 0
  for k = 0, 15 do
    local v = t[k] + (m2[k] or 0) + (m3[k] or 0)
    if v < 0 then v = 0 end
    t[k] = v
    sum = sum + v
  end
  return t, sum
end

function Drops.allFusions(f)
  return f.save.kinstones and f.save.kinstones.didAllFusions or false
end

-- the slot a roll picks from a summed table (pure; tests use it)
function Drops.pick(t, sum, r)
  local item = band(rshift(r, 24), 0xF)
  local m = r % sum
  local acc = 0
  for _ = 0, 15 do
    acc = acc + t[item]
    if acc > m then break end
    item = band(item + 1, 0xF)
  end
  return item
end

-- returns the item id created (0 = none)
function Drops.randomDrop(f, src, n, O)
  if f.randomDropsDisabled then return 0 end
  local D = f.assets.manifest.drops
  local t, sum = Drops.table(f, n)
  if not t or sum <= 0 then return 0 end
  local r = Drops.random(rng(f))
  local slot = Drops.pick(t, sum, r)
  local id = D.slotItems[slot] or 0
  if id ~= 0 then return Drops.createItemDrop(f, src, id, 0, O) end
  return 0
end

-- ---------------------------------------------------------------------------
-- CreateItemDrop
-- ---------------------------------------------------------------------------
function Drops.kinstoneDropsPrevFrame(f)
  local k = f.kinstoneDrops
  if not k or not f.frame then return 0 end
  if k.frame == f.frame then return k.prev end
  if k.frame == f.frame - 1 then return k.n end
  return 0
end

local function countKinstoneDrop(f)
  if not f.frame then return end
  local k = f.kinstoneDrops or { frame = f.frame, n = 0, prev = 0 }
  if k.frame ~= f.frame then
    k.prev = (k.frame == f.frame - 1) and k.n or 0
    k.frame, k.n = f.frame, 0
  end
  k.n = k.n + 1
  f.kinstoneDrops = k
end

function Drops.createItemDrop(f, src, item, param, O)
  local D = f.assets.manifest.drops
  param = param or 0
  if item == ITEM.ENEMY_BEETLE then
    if f:inventory(ITEM.SMITH_SWORD) == 0 then return 0 end
  elseif item == ITEM.BOMBS5 then
    if f:inventory(ITEM.BOMBBAG) == 0 then return 0 end
  elseif item == ITEM.ARROWS5 then
    if f:inventory(ITEM.BOW) == 0 then return 0 end
  elseif item == ITEM.SHELLS then
    if f:inventory(ITEM.EARTH_ELEMENT) == 0 then return 0 end
    if param == 0 then param = 1 end
  elseif item == ITEM.KINSTONE or (item >= ITEM.KINSTONE_RED and item <= ITEM.KINSTONE_GREEN) then
    if f:inventory(ITEM.KINSTONE_BAG) == 0 then return 0 end
    if Drops.kinstoneDropsPrevFrame(f) > 3 then return 0 end
    if item ~= ITEM.KINSTONE then
      local row = D and D.kinstonePieces and D.kinstonePieces[item - ITEM.KINSTONE_RED]
      param = row and row[band(Drops.random(rng(f)), 0x3F)] or 0
      if param == 0 then item = 0 else item = ITEM.KINSTONE end
    end
  end
  if item == 0 then return 0 end
  if item == ITEM.ENEMY_BEETLE then
    local en = f.enemies and f:enemies()
    if en then
      local e = en:spawn({ id = ENEMY_BEETLE_ID, paramA = 0, paramB = 0, paramC = 0,
                           x = math.floor(src.x), y = math.floor(src.y) })
      if e then f.entities[#f.entities + 1] = e end
    end
    return item
  end
  if item == ITEM.KINSTONE then countKinstoneDrop(f) end
  O = O or f._objects or f:objects()
  local opts = { drop = true, fromPlayer = (src == f.player) }
  -- object $1E (a thrown / kicked source) launches the item forward
  if src.kind == 6 and src.id == 0x1E then
    opts.direction = bor(lshift(src.animationState or 0, 3), 0x80)
    opts.speed, opts.zVelocity = 0xC0, 1.5
  end
  O:groundItem(item, param, src.x, src.y, opts)
  return item
end

-- ---------------------------------------------------------------------------
-- SpecialFx: the variant and the drop roll of a cut / broken tile
-- ---------------------------------------------------------------------------
function Drops.fxVariant(f, fxType)
  local D = f.assets.manifest.drops
  local v = D and D.fxVariants
  if not v then return fxType end
  if fxType == FX_BUSH then return v[band(Drops.random(rng(f)), 3)] end
  if fxType == FX_GRASS_CUT then return v[4 + band(Drops.random(rng(f)), 3)] end
  return fxType
end

function Drops.fxDrop(f, src, fxType, O)
  local D = f.assets.manifest.drops
  local n = D and D.fxTable and D.fxTable[fxType] or 0
  return Drops.randomDrop(f, src, n, O)
end

-- DisableRandomDrops / EnableRandomDrops (src/itemUtils.c), called by the
-- Ezlo and Vaati scenes' scripts
do
  local N = require("src.zelda.tmc.Native").N
  N[0x08054564] = function(f) f.randomDropsDisabled = true end
  N[0x08054570] = function(f) f.randomDropsDisabled = false end
end

return Drops
