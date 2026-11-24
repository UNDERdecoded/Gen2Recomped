-- Round 37: the Armos interiors ($2C:00..$2C:0A): ARMOS_INTERIOR_MANAGER
-- $27 (src/manager/armosInteriorManager.c) and FLAME $2A type 4
-- (src/object/flame.c).
--
-- CARTRIDGE BEHAVIOUR:
--   * The manager (type = the room): its flag is local flag $67 + type of
--     FLAG_BANK_3.  Init: flag set -> action 2, else 1 (timer 1, subtimer
--     0).  Action 1: the flag comes on -> action 2, timer 1,
--     SFX_EM_ARMOS_ON.  Action 2: every 20 frames subtimer = (subtimer + 1)
--     mod 6 and LoadPaletteGroup(gUnk_08108D20[subtimer]) (the room's
--     palettes pulse), SFX_EM_ARMOS_ON when it wraps to 0; the flag going
--     off -> action 3, which runs action 2 until subtimer is back at 0, then
--     action 1.  Every frame its bit in gRoomTransition.armos_data.field_0xac
--     follows the flag.
--   * FLAME type 4: drawn (animation 0, SFX_124) while its flag (+$86) is
--     set; hidden while it is not.
-- SIMPLIFIED: armos_data.field_0xac (read by the Armos statues outside)
--   is not kept; the palette groups' OBJ palettes (dest >= 16) are not
--   applied (the BG palettes are, through Room:applySwap).
local bit = require("bit")
local band = bit.band

local M = {}
M.MANAGER, M.FLAME = 0x27, 0x2A
M.BANK3, M.FLAG0 = 3, 0x67
M.SFX_ARMOS_ON, M.SFX_124 = 0x11A, 0x124
local PALS = require("src.zelda.tmc.RomTables").t("Armos37.PALS") -- gUnk_08108D20
M.PALS = PALS

local function bankFlag(f, idx)
  local ok, v = pcall(function()
    local BANK = f.BANK_OFFSET or require("src.zelda.tmc.Field").BANK_OFFSET
    -- round 49: gLocalFlagBanks is indexed by LOCAL_BANK_n (LOCAL_BANK_G = 0), so FLAG_BANK_3
    -- ($300) is entry M.BANK3 + 1; entry 3 was FLAG_BANK_2 and the switch's flag never lit the room
    return BANK and BANK[M.BANK3 + 1] and f:flag("bank", idx, BANK[M.BANK3 + 1])
  end)
  return ok and v or false
end
M.bankFlag = bankFlag

local function loadPal(f, g)
  local r = f.room
  if r and r.applySwap then r:applySwap({ key = "armos37:" .. g, paletteGroups = { g } }) end
end

function M.spawnManager(d, m)
  if m.id ~= M.MANAGER then return nil end
  local f = d.field
  local s = { room = f.room, type = m.type or 0, timer = 1, subtimer = 0 }
  s.action = bankFlag(f, M.FLAG0 + s.type) and 2 or 1
  f.armos37 = s
  return true
end

local function action2(f, s)
  s.timer = s.timer - 1
  if s.timer <= 0 then
    s.timer = 20
    s.subtimer = s.subtimer + 1
    if s.subtimer > 5 then s.subtimer = 0 end
    loadPal(f, PALS[s.subtimer])
    if s.subtimer == 0 then f:sound(M.SFX_ARMOS_ON) end
  end
  if not bankFlag(f, M.FLAG0 + s.type) then s.action = 3 end
end

function M.frame(f)
  local s = f.armos37
  if not s then return false end
  if s.room ~= f.room then f.armos37 = nil return false end
  if s.action == 1 then
    if bankFlag(f, M.FLAG0 + s.type) then s.action, s.timer = 2, 1; f:sound(M.SFX_ARMOS_ON) end
  elseif s.action == 2 then
    action2(f, s)
  elseif s.action == 3 then
    if s.subtimer == 0 then s.action = 1 else action2(f, s) end
  end
  return false
end

function M.spawnObject(d, e)
  if e.id ~= M.FLAME or (e.form or 0) ~= 4 then return nil end
  local f = d.field
  local O = f:objects()
  local def = O and O:def(e.id, 4)
  if def then O:dress(e, def, 0) end
  e.objAnim = 0
  if d:check(e.flag) then
    e.hidden, e.subAction = false, 0
    f:sound(M.SFX_124)
  else
    e.hidden, e.subAction = true, 1
  end
  e.extUpdate = function(dd, me)
    local on = dd:check(me.flag)
    if me.subAction == 0 then
      if not on then me.subAction, me.hidden = 1, true end
    elseif on then
      me.subAction, me.hidden = 0, false
      if me.anim and me.sprite then me.anim:set(f.assets:sprite(me.sprite), 0, true) end
      f:sound(M.SFX_124)
    end
    if not me.hidden and me.anim then me.anim:update(1) end
  end
  d:track(e)
  return e
end

return M
