-- Round 10: the C side of CUTSCENE_MISC_OBJECT ($6A) types the story
-- scenes on the route need (src/object/cutsceneMiscObject.c).  The objects'
-- scripts run from the ROM (Script.lua); this adds what their type action
-- does besides ExecuteScriptForEntity.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Type19 ($13, the Octoroks bullying Ezlo): when the animation's frame
--     byte has bit 0 (super->frame & 1), sub_08095954 makes a $14 object at
--     the shooter's offset gUnk_08122AF8[animationState] (read from the ROM
--     at import, manifest.r10.rockOffsets), z -3, running script_08012C48
--     ($08012C48: speed $280, MoveTo $388,$168, SetSyncFlag $100, delete),
--     plays SFX_124 and clears the bit; with no free entity it sets sync
--     $100 itself.
--   * Type20 ($14, the rock): PRIO_PLAYER_EVENT, animation 0, its script.
--   * Type7 ($07): the Jabber Nut (see type7 below).
local bit = require("bit")
local band, bor = bit.band, bit.bor

local C = {}

local SCRIPT_ROCK = 0x08012C48

function C.rockOffsets(f)
  local r10 = f.assets.manifest.r10
  return r10 and r10.rockOffsets
end

local function type19(f, e)
  local a = e.anim
  if not a then return end
  -- the frame byte of the current keyframe; handled once per keyframe
  if band(a.flags or 0, 1) ~= 0 and e._r10key ~= a.key then
    e._r10key = a.key
    local offs = C.rockOffsets(f)
    local st = band(e.animationState or 0, 7) -- s8XY[animationState] (states 0..7 read 8 pairs)
    local ox, oy = 0, 0
    if offs and offs[st] then ox, oy = offs[st][1], offs[st][2] end
    local o = f:spawn({ kind = 6, id = 0x6A, paramA = 0x14, paramB = 0, x = e.x + ox, y = e.y + oy,
                        paramC = SCRIPT_ROCK, pool = 0x4F })
    if o then
      o.parent = e
      o.z = -3
      o.prioB1 = 3 -- PRIO_PLAYER_EVENT (update priority; not a draw key)
      f:sound(0x124)
    else
      local S = require("src.zelda.tmc.Script")
      S.active.syncFlags = bor(S.active.syncFlags, 0x100)
    end
  elseif band(a.flags or 0, 1) == 0 then
    e._r10key = nil
  end
end

-- Type7 ($07): the Jabber Nut on the floor of the barrel Minish's house.
-- Deleted once Link has ITEM_JABBERNUT ($5B); AddInteractableCheckableObject;
-- checked -> CreateEzloHint(TEXT_BELARI $1F), then once the message is
-- gone CreateItemEntity(ITEM_JABBERNUT) (the item get).  Drawn as item $5B
-- (sub_08080CB4 with type 91 = the ground item's frame).
local function type7(f, e)
  e.r10act = e.r10act or 0
  if e.r10act == 0 then
    if f:inventory(0x5B) ~= 0 then e.deleted = true return end
    e.r10act = 1
    e.talkable = true
    e.spritePriority = 7
    local O = f:objects()
    local d = O:def(0x00, 0x5B)
    if d then O:dress(e, d, 0x5B); e.objAnim = 0x5B; e.animIndex = nil end
  elseif e.r10act == 1 then
    if (e.interactType or 0) ~= 0 then
      e.interactType = 0
      e.talkable = false
      e.r10act = 2
      f:message(0x1F1F, nil, nil, "ezlo")
    end
  elseif e.r10act == 2 then
    if not f:messageActive() then
      e.deleted = true
      f:giveItem(0x5B)
    end
  end
end

function C.update(f, e)
  if e.form == 0x13 then type19(f, e)
  elseif e.form == 0x07 and not e.script then type7(f, e) end
end

return C
