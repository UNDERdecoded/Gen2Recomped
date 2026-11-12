-- Round 6: native NPC fusers (the cartridge's GetFuserId / GetFusionToOffer /
-- InitializeNPCFusion / UpdateFuseInteraction / NotifyFusersOnFusionDone).
--
-- CARTRIDGE RULES (code_08001A7C.s, common.c, npcUtils.c, playerUtils.c):
--   * GetFuserId(entity) walks a 6-byte list {id, type, type2, fuserId,
--     nameText u16} -- enemies at 0x0800232E + 6, NPCs at 0x08002342 + 6,
--     ending at id 0; a type / type2 of $FF matches anything.
--   * gUnk_08001DCC[fuserId] points to the fuser's data: [0] the lowest
--     gSave.global_progress it fuses at, [1] its stability (percent chance
--     to offer on each load), [5..] its list of kinstone ids (0 ends the
--     list, $FF = a random shared fusion).
--   * gSave.kinstones.fuserOffers / fuserProgress remember, per fuser, the
--     id on offer and how far down its list it is ($F1 needs replacement,
--     $F2 just fused, $F3 done).
--   * gUnk_08001A7C[fuserId] -> NPCData {text, cancelled, fusing}: the three
--     messages InitializeNPCFusion passes to InitializeFuseInfo.
--   * Each fuser NPC calls GetFusionToOffer when it loads; L in front of it
--     with the offer in 1..100 starts the fusion (no pieces at all: Ezlo's
--     hint TEXT_EZLO $65 instead).
-- All tables are read from the player's ROM (menudata.bin, Layout.MENU_DATA
-- `fusers`); nothing here is ROM data.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local Fusers = {}

Fusers.NONE, Fusers.NEEDS, Fusers.JUST, Fusers.DONE, Fusers.RANDOM = 0, 0xF1, 0xF2, 0xF3, 0xFF
local NONE, NEEDS, JUST, DONE, RANDOM = 0, 0xF1, 0xF2, 0xF3, 0xFF
Fusers.ITEM_KINSTONE_BAG = 0x67
local ENEMY_LIST, NPC_LIST = 0x0800232E, 0x08002342
local FUSER_DATA, NPC_DATA = 0x08001DCC, 0x08001A7C
Fusers.TEXT_NO_PIECES = 0x0B65 -- TEXT_INDEX(TEXT_EZLO, 0x65)

-- a reader over the `fusers` range of menudata.bin
function Fusers.reader(A)
  if A.fuserReader ~= nil then return A.fuserReader or nil end
  local e = A.manifest and A.manifest.menuData and A.manifest.menuData.fusers
  local blob = e and A.store and (A.menuBlob or A.store:read("menudata.bin"))
  if not blob then A.fuserReader = false return nil end
  A.menuBlob = blob
  local base, off, size = e[1], e[2], e[3] or 0
  local t = {}
  function t.u8(a)
    local o = a - base
    if o < 0 or (size > 0 and o >= size) then return 0 end
    return blob:byte(off + o + 1) or 0
  end
  function t.u16(a) return t.u8(a) + 256 * t.u8(a + 1) end
  function t.u32(a) return t.u16(a) + 65536 * t.u16(a + 2) end
  A.fuserReader = t
  return t
end

-- GetFuserId: fuserId, name text (0, 0 when not a fuser)
function Fusers.fuserId(A, kind, id, type, type2)
  local t = Fusers.reader(A)
  if not t or (kind ~= 3 and kind ~= 7) then return 0, 0 end
  local a = (kind == 3 and ENEMY_LIST or NPC_LIST) + 6
  for _ = 1, 256 do
    local eid = t.u8(a)
    if eid == 0 then break end
    local et, et2 = t.u8(a + 1), t.u8(a + 2)
    if eid == id and (et == 0xFF or et == type) and (et2 == 0xFF or et2 == type2) then
      return t.u8(a + 3), t.u16(a + 4)
    end
    a = a + 6
  end
  return 0, 0
end

-- the entity's type2 (EntityData.type2 is a u32 at +4: paramB; the
-- entity keeps its low byte)
function Fusers.type2(d)
  if d.type2 then return d.type2 end
  return band(d.paramB or 0, 0xFF)
end

local function store(save)
  local ks = save.kinstones
  ks.fuserOffers = ks.fuserOffers or {}
  ks.fuserProgress = ks.fuserProgress or {}
  return ks
end

-- GetRandomSharedFusion
function Fusers.randomShared(kin, r)
  local list = kin.data.shared or {}
  r = (r or math.random(0, 17)) % 18
  for _ = 1, 18 do
    local id = list[r + 1] or 0
    if not kin:isFused(id) then return id end
    r = (r + 1) % 18
  end
  return JUST
end

-- GetFusionToOffer(entity); `roll` (0..99) and `rnd` (0..17) for tests
function Fusers.offer(field, fid, roll, rnd)
  if not fid or fid == 0 then return NONE end
  local A = field.assets
  local t = Fusers.reader(A)
  if not t then return NONE end
  local data = t.u32(FUSER_DATA + 4 * fid)
  if data < 0x08000000 then return NONE end
  local save = field.save
  if field:inventory(Fusers.ITEM_KINSTONE_BAG) == 0 or t.u8(data) > (save.progress or 1) then return NONE end
  local kin = field.kinstone
  local ks = store(save)
  local offered, prog = ks.fuserOffers[fid] or NONE, ks.fuserProgress[fid] or 0
  local function at(p) return t.u8(data + 5 + p) end
  for _ = 1, 300 do
    local step = false
    if offered == NEEDS or offered == NONE then
      offered = at(prog)
      if not (offered == NONE or offered == RANDOM or not kin:isFused(offered)) then step = true end
    elseif offered == JUST then
      step = true
    end
    if step then prog = prog + 1; offered = at(prog) end
    if offered == RANDOM then offered = Fusers.randomShared(kin, rnd) end
    if offered == NONE then offered = DONE break end
    if offered ~= JUST then
      if not kin:isFused(offered) then break end
      offered = NEEDS
    end
  end
  ks.fuserOffers[fid], ks.fuserProgress[fid] = offered, prog
  if t.u8(data + 1) <= (roll or math.random(0, 99)) then return NONE end -- fickleness
  if offered < 1 or offered > 100 then return NONE end
  return offered
end

-- NPCData {text, cancelled, fusing} (InitializeNPCFusion)
function Fusers.texts(A, fid)
  local t = Fusers.reader(A)
  if not t then return 0, 0, 0 end
  local p = t.u32(NPC_DATA + 4 * fid)
  if p < 0x08000000 then return 0, 0, 0 end
  return t.u16(p), t.u16(p + 2), t.u16(p + 4)
end

-- the fuser's name (the text GetFuserId returns in r1), as plain text
function Fusers.name(A, textId)
  if not textId or textId == 0 or not A.message then return "" end
  local bytes = A:message(textId)
  if not bytes then return "" end
  local ok, lines = pcall(require("src.zelda.tmc.TextBox").parse, bytes, "")
  if not ok or not lines[1] then return "" end
  local s = ""
  for _, run in ipairs(lines[1]) do s = s .. (run.text or "") end
  return s
end

-- an NPC / enemy loads (its native init): fuser id and the offer
function Fusers.onSpawn(field, e, d)
  local A = field.assets
  if not A then return end
  local fid, nameText = Fusers.fuserId(A, d.kind, d.id, d.paramA or 0, Fusers.type2(d))
  if fid == 0 then return end
  e.fuserId, e.fuserName = fid, nameText
  e.fuser = Fusers.offer(field, fid)
end

-- L in front of a fuser (playerUtils.c): true when handled
function Fusers.tryFuse(field, e)
  local k = e.fuser
  if not k or k < 1 or k > 100 then return false end
  local kin = field.kinstone
  if #kin:pieces() == 0 then
    field:message(Fusers.TEXT_NO_PIECES, nil, nil, "ezlo")
    return true
  end
  if not e.fuserId then
    e.interactType = 2 -- a scripted fuser: its script answers (ScriptCommand_0807EA4C)
    return true
  end
  -- InitializeNPCFusion
  local KM = require("src.zelda.tmc.KinstoneMenu")
  local a, b, c = Fusers.texts(field.assets, e.fuserId)
  KM.initFuse(field, e, a, b, c)
  field.fuseInfo.kinstoneId = k
  field.fuseInfo.name = Fusers.name(field.assets, e.fuserName)
  kin.npcFuse = e
  kin.active = true
  e.fusing = true
  -- the NPC turns to Link
  local dx, dy = field.player.x - e.x, field.player.y - e.y
  if math.abs(dx) > math.abs(dy) then e.animationState = dx > 0 and 2 or 6
  else e.animationState = dy > 0 and 4 or 0 end
  return true
end

-- UpdateFuseInteraction, once per frame while the NPC fuses (its action 3)
function Fusers.update(field, e)
  local KM = require("src.zelda.tmc.KinstoneMenu")
  local st = KM.performFuse(field)
  if st == 1 or st == 2 then
    e.fusing = nil
    local kin = field.kinstone
    if kin.npcFuse == e then kin.npcFuse = nil; kin.active = false; kin.window = nil end
    return st == 2 and 1 or -1
  end
  return 0
end

-- NotifyFusersOnFusionDone
function Fusers.notifyDone(field, id)
  if not id or id < 1 or id > 100 then return end
  local ks = store(field.save)
  for fid, v in pairs(ks.fuserOffers) do if v == id then ks.fuserOffers[fid] = NEEDS end end
  local fi = field.fuseInfo
  local fid = fi and fi.entity and fi.entity.fuserId
  if fid and ks.fuserOffers[fid] == NEEDS then ks.fuserOffers[fid] = JUST end
  for _, e in ipairs(field.entities or {}) do if e.fuser == id then e.fuser = NEEDS end end
end

-- MarkFuserDone
function Fusers.markDone(field, e)
  if e and e.fuserId and e.fuserId ~= 0 then store(field.save).fuserOffers[e.fuserId] = DONE end
end

return Fusers
