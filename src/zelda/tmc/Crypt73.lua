-- Round 73: the Royal Crypt (area $68): its room init (src/roomInit.c) and ENEMY_ITEM ($C0, src/object/enemyItem.c).
-- Neither was ported: the entrance's two Gibdos carried nothing (the small key that opens the way to the mushroom
-- room never appeared), the entrance's TILE_TYPE_786 was never laid, the random drops stayed off, and the King
-- Gustaf room's list (the king and his scene object) never loaded.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * sub_StateChange_RoyalCrypt_Entrance ($68:08): SetTileType(TILE_TYPE_786, TILE_POS(8, 4), LAYER_BOTTOM);
--     EnableRandomDrops(); local flag $C4 clear -> LoadRoomEntityList(gUnk_080E718C); $C5 clear -> gUnk_080E71AC.
--   * sub_StateChange_RoyalCrypt_MushroomPit ($68:07): EnableRandomDrops().
--   * sub_StateChange_RoyalCrypt_KingGustaf ($68:00): local flag $32 clear -> LoadRoomEntityList(gUnk_080E693C).
--   * script_KingGustav's last NPC4E_DoScreenTransition (intVariable 1): gNpc4ETransitions[1], read from the ROM
--     (RomTables "Crypt73.TR_1"), added to the port's NPC4E transition list.
--   * EnemyItem: flag set -> gone.  Action 0: action 1, type = timer (the item), the first kind-3 entity with id ==
--     type2 whose x and y are within [-16, 16) of the object's becomes its child; none -> sub_080A2534 (a GROUND_ITEM
--     of that item, timer 4 (it lies there), the flag) and gone; DisableRandomDrops().  With a child: PositionRelative
--     (child, +4, +1), z = child z - 4; the child gone (entity->next == NULL) -> sub_080A2508 (GROUND_ITEM, timer 5
--     (it springs up and stays), the flag) and gone.  Drawn as the item (sub_08080CB4).
-- The lists are read by address from the importer's entity region (the player's ROM); no values are kept here.
-- SIMPLIFIED: the item is drawn with its ground-item animation; a child replaced by another entity (a Gibdo burnt
-- into a Stalfos) counts as gone, as on the cartridge (the Gibdo entity is deleted).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.AREA = 0x68
M.ROOM_KING, M.ROOM_MUSHROOM, M.ROOM_ENTRANCE = 0x00, 0x07, 0x08
M.ID = 0xC0 -- ENEMY_ITEM
M.LIST_ENTRANCE_A, M.LIST_ENTRANCE_B, M.LIST_KING = 0x080E718C, 0x080E71AC, 0x080E693C
M.FLAG_A, M.FLAG_B, M.FLAG_KING = 0xC4, 0xC5, 0x32
M.TILE_TYPE_786 = 786
M.TILE_X, M.TILE_Y = 8, 4

local function dropsOn(f, on) f.randomDropsDisabled = not on end

-- script_KingGustav ends with SetIntVariable 1 + NPC4E_DoScreenTransition: gNpc4ETransitions[1] (the graveyard before
-- the King's tomb); the port's NPC4E list (BossVaati3.NPC4E_TRANSITIONS) had no index 1, so Link stayed in the crypt
function M.registerTransition()
  local ok, V3 = pcall(require, "src.zelda.tmc.BossVaati3")
  if ok and type(V3) == "table" and V3.NPC4E_TRANSITIONS and not V3.NPC4E_TRANSITIONS[1] then
    local ok2, t = pcall(require("src.zelda.tmc.RomTables").fresh, "Crypt73.TR_1")
    if ok2 and t then V3.NPC4E_TRANSITIONS[1] = t end
  end
  return ok and V3 and V3.NPC4E_TRANSITIONS and V3.NPC4E_TRANSITIONS[1]
end

-- one entry of R27B.MODULES: R26.roomInit runs it after the room's lists
function M.roomInit(f)
  local r = f.room
  if not r or r.area ~= M.AREA then return end
  if r.room == M.ROOM_ENTRANCE then
    local O = f:objects()
    if O and O.setTileType then O:setTileType(1, M.TILE_X, M.TILE_Y, M.TILE_TYPE_786) end
    dropsOn(f, true)
    if not f:flag("local", M.FLAG_A) then f:loadEntityList(M.LIST_ENTRANCE_A) end
    if not f:flag("local", M.FLAG_B) then f:loadEntityList(M.LIST_ENTRANCE_B) end
  elseif r.room == M.ROOM_MUSHROOM then
    dropsOn(f, true)
  elseif r.room == M.ROOM_KING then
    if not f:flag("local", M.FLAG_KING) then f:loadEntityList(M.LIST_KING) end
    if not f.stub then M.registerTransition() end
  end
end

-- the item it leaves: GROUND_ITEM type = the item, timer = kind (4 lies, 5 springs up), its flag
local function leave(f, e, kind)
  local O = f:objects()
  local g = O and O:groundItem(e.item, 0, e.x, e.y, { kind = kind, flagSpec = e.flag })
  if g then
    g.flagSpec = (e.flag ~= 0) and e.flag or nil
    g.layer = e.layer
  end
  e.deleted = true
  return g
end
M.leave = leave

local function live(f, x)
  if not x or x.deleted then return false end
  for _, o in ipairs(f.entities) do if o == x then return true end end
  return false
end

function M.update(D, e)
  local f = D.field
  if e.deleted then return end
  if e.flag ~= 0 and D:check(e.flag) then e.deleted = true return end
  if e.action == 0 then
    e.action = 1
    e.item = e.timer0 or 0
    e.child = nil
    for _, o in ipairs(f.entities) do
      if o.kind == 3 and o.id == e.type2 and not o.deleted
          and band(math.floor(o.x) - math.floor(e.x) + 16, 0xFFFF) < 32
          and band(math.floor(o.y) - math.floor(e.y) + 16, 0xFFFF) < 32 then
        e.child = o
        break
      end
    end
    if not e.child then leave(f, e, 4) return end
    dropsOn(f, false)
  end
  local c = e.child
  if c then
    if not live(f, c) or c.deleted then leave(f, e, 5) return end
    e.x, e.y = c.x + 4, c.y + 1
    e.z = (c.z or 0) + 4
    e.layer = c.layer
    e.hidden = c.hidden
  end
end

-- one entry of R27B.MODULES (Dungeon:spawnObject -> R26 -> R27B): ENEMY_ITEM
function M.spawnObject(D, e)
  if e.id ~= M.ID or not (D.field.room and D.field.room.area) then return nil end
  if e.flag ~= 0 and D:check(e.flag) then return nil end
  local f = D.field
  local O = f:objects()
  local item = e.timer0 or 0
  local def = O and O:def(0x00, item) -- sub_08080CB4: drawn as the item
  if def then O:dress(e, def, item) end
  e.objAnim = item
  e.action = 0
  e.enemyItem73 = true
  e.extUpdate = function(DD, x) M.update(DD, x) end
  D:track(e)
  return e
end

return M
