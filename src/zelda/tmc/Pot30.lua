-- Round 30: the pot's tile, its room-data fields, its shatter and the shadow
-- of a thrown object.  Listed in R27B.MODULES (only for ROM_RANGES); the
-- other entry points are called from one-line hooks in Field.lua /
-- Objects.lua / PotCarry.lua.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc src/object/pot.c, src/room.c):
--   * RegisterRoomEntity copies the 16-byte EntityData to field $78: the
--     pot's unk_7d = paramB byte 1 (its item's param), flag ($86) = paramC
--     >> 16; LoadRoomEntity: type2 = paramB & $FF.
--   * Pot_Init: type2 1 with CheckFlags(flag) set -> deleted (a pot that
--     stays broken); unk_70 = the tile index under it; a tile that already
--     is SPECIAL_TILE_0 (another pot there) -> deleted; SetTile(SPECIAL_TILE_0)
--     -- the pot is a solid tile (COLLISION_DATA_29 in the special table),
--     so Link, enemies and thrown things meet the tile, not an entity box.
--   * The tile goes back (SetTile(unk_70)) when the pot is lifted
--     (sub_08082510), pushed (Pot_Action1 SPECIAL_TILE_1-4; Pot_Action4
--     puts SPECIAL_TILE_0 on the new tile, re-reading unk_70), pulled by
--     the Gust Jar (sub_08082778), hit by the Cane ($1D) or broken.
--   * Pot_Action1 default: the tile under a resting pot no longer
--     SPECIAL_TILE_0 -> SPECIAL_TILE_103 deletes it (tile back), any other
--     tile breaks it (FX_FALL_DOWN first on ACT_TILE_13; SPECIAL_TILE_5
--     puts the old tile back).
--   * BreakPot: CreateFx(FX_POT_SHATTER, sub_0808288C(...)) always (param
--     $80 = the drop roll only for form 0); form $FF nothing, another form
--     a GROUND_ITEM (type = form, type2 = unk_7d; type2 2: timer 5 and the
--     pot's flag, so the item stays taken); type2 1 sets the flag.
--   * The thrown object (playerItemHeldObject sub_08082588 -> b1 = 3) and
--     the Cane-hopped pot (Action1 $1D: shadow 1, b1 = 3): arm_DrawEntities
--     (asm/src/intr.s sub_080B255C) queues a shadow when spritePriority.b1
--     bit 0 is set and, b1 bit 1 set, only while z < 0 (in the air): frame
--     spriteSettings.shadow of ram_0x80b2bd8 (USA ROM $080B2B3F: four 1-piece
--     OAM frames, tiles 0 / 1 / 3 / 7 of OBJ VRAM, OBJ palette 5) at the
--     entity's ground y, drawn after (under) the sprites.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.SPECIAL_TILE_0, M.SPECIAL_TILE_5, M.SPECIAL_TILE_103 = 0x4000, 0x4005, 0x4067
M.FX_POT_SHATTER, M.FX_FALL_DOWN, M.SPECIAL_FX = 0x05, 0x00, 0x0F
-- ram_0x80b2bd8's four targets (IWRAM $030068B3.. = USA ROM $080B2B3F..)
M.ROM_RANGES = { shadowFrames30 = { 0x080B2B3F, 0x080B2B57 } }

local function cell(f, e)
  local r = f.room
  local L = (e.layer == 2) and 2 or 1
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return nil end
  return L, tx, ty, ty * r.tw + tx
end

local function mapAt(f, L, i) return f.room.maps[L == 2 and "top" or "bottom"][i] end

-- Field:spawn (a POT object, after its layer): the room-data fields and
-- Pot_Init's checks / tile; false = the pot does not exist
function M.spawn(f, e, d)
  local pb = d.paramB or 0
  e.potType2 = band(pb, 0xFF)
  e.potParam = band(rshift(pb, 8), 0xFF)
  e.potFlag = rshift(d.paramC or 0, 16)
  if e.potType2 == 1 and e.potFlag ~= 0 and f:dungeon():check(e.potFlag) then e.deleted = true return false end
  local L, tx, ty, i = cell(f, e)
  if not L then return true end
  if mapAt(f, L, i) == M.SPECIAL_TILE_0 then e.deleted = true return false end
  M.place(f, e)
  return true
end

function M.place(f, e)
  local L, tx, ty, i = cell(f, e)
  if not L then return end
  e.potUnk70 = mapAt(f, L, i)
  e.potTile = { L, tx, ty, i, room = f.room }
  f.room:setTile(L, tx, ty, M.SPECIAL_TILE_0)
end

function M.restore(f, e)
  local t = e.potTile
  e.potTile = nil
  if not t or t.room ~= f.room then return end
  if mapAt(f, t[1], t[4]) == M.SPECIAL_TILE_0 and e.potUnk70 then f.room:setTile(t[1], t[2], t[3], e.potUnk70) end
end

-- the pot rests on its tile (Pot_Action1)
local function resting(e)
  return not e.deleted and not e.thrown and e.liftable and e.solid ~= false and not e.pushT and not e.jarSub
     and not e.potGust and not e.hidden and (e.z or 0) == 0
end

-- every frame (Field:update, after the pushed pots slide)
function M.sync(f)
  if not f.room then return end
  for _, e in ipairs(f.entities) do
    if e.kind == 6 and e.id == 0x05 and (e.potTile or (e.potType2 and not e.thrown)) then
      local t = e.potTile
      if t and t.room ~= f.room then e.potTile, t = nil, nil end
      if resting(e) then
        if t then
          local L, tx, ty, i = cell(f, e)
          local now = mapAt(f, t[1], t[4])
          if i ~= t[4] or L ~= t[1] then
            M.restore(f, e); M.place(f, e) -- moved (Pot_Action4: unk_70 of the new tile)
          elseif now ~= M.SPECIAL_TILE_0 then
            -- Pot_Action1 default: something wrote the tile
            e.potTile = nil
            if now == M.SPECIAL_TILE_103 then
              f.room:setTile(t[1], t[2], t[3], e.potUnk70); e.deleted = true
            else
              if now == M.SPECIAL_TILE_5 then f.room:setTile(t[1], t[2], t[3], e.potUnk70) end
              M.breakPot(f, e, true)
            end
          end
        else
          M.place(f, e)
        end
      elseif t then
        M.restore(f, e)
      end
    end
  end
end

-- Pot_Action1's break where it stands
function M.breakPot(f, e, checkHole)
  if checkHole then
    local r = f.room
    local tt = r:tileType(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16))
    local act = tt and tt < 0x4000 and f.assets.actTile and f.assets.actTile[tt]
    if act == 13 then f:addFx(e.x, e.y, M.SPECIAL_FX, M.FX_FALL_DOWN) end
  end
  e.deleted = true
  f:objects():shatter(e, e.form or 0, e.potParam)
end

-- the room-data fields a lifted pot keeps (Objects:tryAction -> lift)
function M.carryFields(c, e)
  c.potParam, c.potType2, c.potFlag = e.potParam, e.potType2, e.potFlag
  return c
end

-- BreakPot (Objects:shatter): the FX, the flag; returns opts for the item
-- and whether it may appear (nil = no item)
function M.shatterFx(f, e, form)
  if e.id == nil or e.id == 0x05 then f:addFx(e.x, e.y, M.SPECIAL_FX, M.FX_POT_SHATTER) end -- the roll ($80, form 0) stays in Drops.fxDrop
  if e.potType2 == 1 and e.potFlag and e.potFlag ~= 0 then f:dungeon():set(e.potFlag) end
  local opts = { drop = true }
  if e.potType2 == 2 and e.potFlag and e.potFlag ~= 0 then
    if f:dungeon():check(e.potFlag) then return nil end -- ItemOnGround_Init: CheckFlags -> deleted
    opts = { kind = 5, flagSpec = e.potFlag }
  end
  return opts
end

-- ---------------------------------------------------------------------------
-- the shadow
-- ---------------------------------------------------------------------------
local frames
local function shadowFrames(f)
  if frames ~= nil then return frames or nil end
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "shadowFrames30")
  if not T then frames = false return nil end
  frames = {}
  local lo = M.ROM_RANGES.shadowFrames30[1]
  for k = 0, 3 do
    local a = lo + k * 6
    local n, objs = T.u8(a), {}
    for j = 0, n - 1 do
      local q = a + 1 + j * 5
      objs[#objs + 1] = { T.s8(q), T.s8(q + 1), T.u8(q + 2), T.u8(q + 3), T.u8(q + 4) }
    end
    frames[k] = objs
  end
  return frames
end
function M.resetShadow() frames = nil end -- tests

-- who gets a shadow: b1 = 3 objects in the air
function M.hasShadow(e)
  if e.shadow30 ~= nil then return e.shadow30 end
  return (e.thrown or e.potFlip) and (e.z or 0) > 0 and not e.deleted and not e.hidden
end

function M.shadowSize(e)
  return e.shadowSize30 or (e.def and e.def.shadow) or 1
end

-- Field:drawSpriteList, before the sprites (shadows are under them)
function M.drawShadows(f, list)
  local A = f.assets
  local any
  for _, e in ipairs(list) do if e ~= f.player and M.hasShadow(e) then any = true break end end
  if not any then return end
  local fr = shadowFrames(f)
  if not fr then return end
  local key = "r30shadow"
  if not A.sprites[key] then A.sprites[key] = { objs = fr, frames = {}, anims = {} } end
  for _, e in ipairs(list) do
    if e ~= f.player and M.hasShadow(e) then
      local sz = band(M.shadowSize(e), 3)
      local img, ox, oy = A:spriteFrame(key, sz, A:objPalette(5), "shadow30", { vram = 0 })
      if img then love.graphics.draw(img, math.floor(e.x - f.camX) + ox, math.floor(e.y - f.camY) + oy) end
    end
  end
end

return M
