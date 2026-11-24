-- Bug round "stall94" (user report: "At the beginning the items Zelda is
-- looking at on the pillows don't appear ... also when used I don't see it").
--
-- 1. The festival stall (data/scripts/cutscene/introTown/script_Npc4EIntroTown,
--    TEXT_PROLOGUE $22 .. $2B): the items on the merchant's cushions are
--    CUTSCENE_MISC_OBJECT ($6A) entities the script makes and removes with
--    natives of src/object/cutsceneMiscObject.c that were not ported (the
--    script skipped them, so nothing was drawn):
--      sub_08094CDC: CreateObject($6A, 3, $62) at origin + (224, 600), SFX 324
--      sub_08094DD8: CreateObject($6A, 4, 0)   at origin + (240, 600), SFX 324
--      sub_08094D34: CreateObject($6A, $15, $0D) at origin + (256, 600), SFX 324
--      sub_08094D10 / sub_08094E0C / sub_08094D70: FindEntity of that
--        type / type2 -> action $FF (the type's next frame: DeleteThisEntity)
--    CutsceneMiscObject_Type3 (types 3 and $15): drawn, sub_08080CB4 with
--    type = type2 (InitAnimationForceUpdate(type2) once, then
--    UpdateAnimationSingleFrame).  Type4: drawn, animation 0.  Sprite /
--    palette / gfx are the object's definition (gObjectDefinitions $6A,
--    read from the ROM at import like every object).
-- 2. The shield in use (src/playerItem/playerItemShield.c): PLAYER_ITEM_SHIELD
--    is an entity of its own drawn with Link (gPlayerItemDefinitions
--    MULTI_FORM(2, 13) -> gPlayerItemDefinition_2: SPRITE_17, OBJ palette 1,
--    both shields).  PlayerItemShield_Action1: while Link's sprite is 1 or 4
--    and frameIndex - $25 < $3F, its frame is Link's frameIndex - $25 (+ $27
--    for the Mirror Shield, unk_68 == 14), with Link's flip / frame settings;
--    sub_08078E84 puts it in front of Link when Link's frame's unk_1 is set,
--    else behind.  The port drew Link's arm pose only, never the shield.
--    SIMPLIFIED: the Mirror Shield's shine (gUnk_081271DC / gUnk_08127220
--    gfx-frame cycle) is not played; its base frame is drawn.
local bit = require("bit")
local band = bit.band

local M = {}
local N = require("src.zelda.tmc.Native").N

M.AREA = 0x15            -- the festival town (Hyrule Town at global progress 1)
M.MISC = 0x6A            -- CUTSCENE_MISC_OBJECT
M.SFX = 324              -- SoundReq(324) of the three creators
M.Y = 600                -- Q_8_8(2.345)
M.ITEMS = {              -- [native] = { type, type2, x }  (creators)
  [0x08094CDC] = { 3, 0x62, 224 },
  [0x08094DD8] = { 4, 0x00, 240 },
  [0x08094D34] = { 0x15, 0x0D, 256 },
}
M.REMOVE = {             -- [native] = { type, type2 }  (action = $FF)
  [0x08094D10] = { 3, 0x62 },
  [0x08094E0C] = { 4, 0x00 },
  [0x08094D70] = { 0x15, 0x0D },
}
M.SHIELD_SPRITE = 17     -- gPlayerItemDefinition_2 spriteIndex
M.SHIELD_PALETTE = 1     -- its bitfield (palette)
M.MIRROR_OFFSET = 0x27   -- unk_70 for unk_68 == ITEM_MIRROR_SHIELD
M.FRAME_BASE = 0x25

local function isStall(e)
  return e and e.kind == 6 and e.id == M.MISC and (e.form == 3 or e.form == 4 or e.form == 0x15) and e.stall94
end

-- FindEntity(OBJECT, CUTSCENE_MISC_OBJECT, 6, type, type2)
function M.find(f, typ, type2)
  for _, o in ipairs(f.entities or {}) do
    if not o.deleted and o.kind == 6 and o.id == M.MISC and o.form == typ and (o.type2 or 0) == type2 then return o end
  end
end

function M.create(f, typ, type2, x, y)
  local rm = f.room
  if not rm then return nil end
  local e = f:spawn({ kind = 6, id = M.MISC, paramA = typ, paramB = type2, x = x, y = y, pool = 0x0F, paramC = 0, collision = 0 })
  if e and f.sound then f:sound(M.SFX) end
  return e
end

for fn, c in pairs(M.ITEMS) do
  N[fn] = N[fn] or function(f) M.create(f, c[1], c[2], c[3], M.Y) end
end
for fn, c in pairs(M.REMOVE) do
  N[fn] = N[fn] or function(f) local o = M.find(f, c[1], c[2]) if o then o.action = 0xFF end end
end

-- Type3 / Type4's frame
function M.update(D, e)
  if band(e.action or 0, 0x80) ~= 0 then e.deleted = true return end
  e.hidden = false
  if e.anim and e.sprite then e.anim:update(1) end
end

-- R27A: Dungeon:spawnObject for the stall's types (only made by the natives above)
function M.spawnObject(D, e)
  if e.id ~= M.MISC or not (e.form == 3 or e.form == 4 or e.form == 0x15) then return nil end
  local f = D.field
  if not (f and f.room and f.room.area == M.AREA) then return nil end
  local O = f:objects()
  local def = O and O:def(M.MISC, e.form)
  if not def then return nil end
  local a = e.form == 4 and 0 or (e.type2 or 0) -- sub_08080CB4: the animation is type2
  O:dress(e, def, a)
  e.objAnim, e.animIndex = a, nil
  e.action = 1
  e.stall94 = true
  e.extUpdate = function(DD, x) M.update(DD, x) end
  D:track(e)
  return e
end
M.isStall = isStall

-- ------------------------------------------------------------------ Zelda after the kidnap
-- 3. User report: "Zelda also returns following me ... after she's already been kidnapped".  On the cartridge
--    Hyrule Town stays the festival town until LV1_CLEAR (global_progress 1) and sub_unk3_HyruleTown_0 sets
--    ZELDA_CHASE on every entry, so CreateZeldaFollower would bring her back -- but the town cannot be reached:
--    sub_unk3_HyruleField_OutsideCastle (North Hyrule Field) with TABIDACHI and no Gust Jar puts gUnk_080F7CD0 in
--    place of the room's list 0 and runs sub_0804F5E8 as its room code: PERMA_ROCK tiles (TILE_TYPE_467 .. 470)
--    across the road south to the town at (30..34, 47..49) and SPECIAL_TILE_114 at (27, 46/47), (36, 42/43).  The port
--    had no room code for North Hyrule Field, the road stayed open, the festival town set ZELDA_CHASE again and Zelda
--    followed Link everywhere after that.
--    SIMPLIFIED: the room's other code (sub_0804F4E4's cloud overlay and SOUGEN_06_SLIDE list, the LV2_CLEAR /
--    SOUGEN_06_SAIKAI list, sub_StateChange_HyruleField_OutsideCastle's SOUGEN_06_AKINDO list) stays unported, as before.
--    A save made in the old state (the follower on after the kidnap, outside the festival town, before LV1_CLEAR) has
--    ZELDA_CHASE cleared once on the next room load: the cartridge never reaches that state.
M.AREA_FIELD, M.ROOM_NORTH_FIELD = 0x03, 0x06
M.LIST_ROCKS = 0x080F7CD0 -- gUnk_080F7CD0 (address only; the list is read from the player's ROM)
M.TABIDACHI, M.ZELDA_CHASE, M.ITEM_GUST_JAR = 0x15, 0x1C, 0x11
M.CASTLE_04_MEZAME, M.FLAG_BANK_1 = 0x9F, 0x100
M.ROCKS = { { 467, 30, 47 }, { 470, 34, 47 }, { 468, 31, 48 }, { 469, 32, 48 }, { 470, 30, 49 } }
M.SPECIAL_114 = 0x4072
M.ROCKS_TOP = 47 * 16 -- the rock band's top edge (tile row 47)
M.SPECIAL = { { 27, 46 }, { 27, 47 }, { 36, 42 }, { 36, 43 } }

function M.northFieldBlocked(f)
  return f:flag("global", M.TABIDACHI) and (f:inventory(M.ITEM_GUST_JAR) or 0) == 0
end

local function dropList(f, list)
  if not list then return end
  for _, dat in ipairs(list) do
    for _, e in ipairs(f.entities) do if e.data == dat then e.deleted = true end end
  end
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  -- (a Link arriving from the town below the rocks comes from an old-port save: the cartridge cannot get there;
  -- the road is left open that once so he is not shut inside the rock band)
  local fromTown = f.player and f.player.y and f.player.y >= M.ROCKS_TOP
  if r.area == M.AREA_FIELD and r.room == M.ROOM_NORTH_FIELD and M.northFieldBlocked(f) and not fromTown then
    dropList(f, r.entities and r.entities[0]) -- properties[0] replaced
    f:loadEntityList(M.LIST_ROCKS)
    local O = f:objects()
    for _, t in ipairs(M.ROCKS) do O:setTileType(1, t[2], t[3], t[1]) end
    for _, t in ipairs(M.SPECIAL) do r:setTile(1, t[1], t[2], M.SPECIAL_114) end
  end
  -- the old port's state: Zelda following after the kidnap (see 3.)
  if r.area ~= M.AREA and f:flag("global", M.ZELDA_CHASE) and f:flag("bank", M.CASTLE_04_MEZAME, M.FLAG_BANK_1)
     and (f.save.progress or 1) == 1 then
    f:setFlag("global", M.ZELDA_CHASE, false)
    if f.zeldaFollower then f.zeldaFollower.deleted = true; f.zeldaFollower = nil end
  end
end

-- ------------------------------------------------------------------ the shield
-- the shield part for Link's current frame: sprite, frame, front (or nil)
function M.shieldPart(p, frame)
  if p.state ~= "shield" or p.minish then return nil end
  local sp = p:sprite()
  if sp ~= 1 and sp ~= 4 then return nil end
  local d = (frame or 0) - M.FRAME_BASE
  if d < 0 or d >= 0x3F then return nil end
  local f = p.field
  local item = f and f.equipped and f:equipped(p.itemButton or "a") -- the button holding it
  local sf = d + (item == 0x0E and M.MIRROR_OFFSET or 0)
  local A = f and f.assets
  local link = A and A:sprite(sp)
  local lf = link and link.frames and link.frames[frame]
  local front = not (lf and (lf[2] or 0) == 0)
  return M.SHIELD_SPRITE, sf, front
end

-- drawn behind Link (front = false) or over him (front = true)
function M.drawShield(p, x, y, frame, front)
  local si, sf, fr = M.shieldPart(p, frame)
  if not si or fr ~= front then return end
  local A = p.field.assets
  local img, ox, oy = A:spriteFrame(si, sf, A:objPalette(M.SHIELD_PALETTE), "shield94")
  if not img then return end
  if p:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
end

return M
