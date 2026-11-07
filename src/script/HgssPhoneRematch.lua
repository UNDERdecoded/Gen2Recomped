-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER PHONE REMATCHES IN THE FIELD.
--
-- A registered trainer who rings to ask for a rematch is marked "seeking"
-- (PhoneCall_ApplyGenericNPCcallSideEffect, kind 3 -> save.hgssPhoneState
-- .seeking, src/ui/HgssPhoneCall.lua). The field asks with
--
--   GetPhoneBookRematch <contact, dest>  (ScrCmd_GetPhoneBookRematch ->
--     PhoneBookTrainerGetRematchInfo, pokeheartgold src/unk_020932A4.c):
--     0 unless the contact is seeking; 0 for contact 0x10 (Kenji) outside
--     the day band of Field_GetTimeOfDayWildParam; else
--     TryGetRematchTrainerIdByBaseTrainerId (src/overlay_26_022598C0.c):
--     the set whose base is the contact's phonebook trainer, its first
--     unbeaten rung (TRAINER_NONE ends the set: the last rung repeats), and
--     back down to the nearest rung below while that rung's unlock flag
--     (FLAG_UNK_97B + rung) is clear.
--   ScrCmd_462 <contact>  clears "seeking" once the rematch is fought.
--
-- Both had been aliased at import to constants (Gen4HgssScriptAliases), so no
-- one who called for a rematch ever offered one. They now keep their HGSS
-- names and lower here; a cache imported before this keeps the constants.

local M = {}

M.UNLOCK_FLAG_BASE = 0x97B
M.KENJI = 0x10

-- sTrainerRematchSets, trainer ids from include/constants/trainers.h:
-- { base, rung 0 .. rung 4 }; 0 is TRAINER_NONE
M.SETS = {
  {414, 414, 303, 446, 602, 0},
  {151, 151, 335, 453, 603, 0},
  {27, 27, 276, 277, 518, 0},
  {397, 397, 434, 435, 507, 0},
  {211, 211, 440, 441, 509, 0},
  {4, 4, 461, 460, 512, 0},
  {8, 8, 279, 280, 510, 0},
  {178, 178, 430, 431, 503, 0},
  {102, 102, 456, 457, 604, 0},
  {17, 17, 250, 278, 605, 0},
  {145, 145, 451, 452, 606, 0},
  {402, 402, 466, 467, 522, 0},
  {61, 61, 100, 155, 523, 0},
  {114, 114, 444, 445, 607, 0},
  {124, 124, 325, 450, 608, 0},
  {113, 113, 458, 459, 609, 0},
  {7, 7, 454, 455, 527, 0},
  {131, 131, 172, 173, 530, 0},
  {24, 24, 432, 433, 505, 0},
  {44, 44, 438, 439, 610, 0},
  {65, 65, 142, 334, 520, 0},
  {123, 123, 323, 324, 517, 0},
  {182, 182, 436, 437, 611, 0},
  {137, 137, 447, 448, 612, 0},
  {57, 57, 462, 463, 515, 0},
  {66, 66, 274, 275, 525, 0},
  {78, 78, 360, 449, 513, 0},
  {400, 400, 464, 465, 528, 0},
  {184, 184, 613, 614, 615, 0},
  {64, 64, 616, 617, 618, 0},
  {388, 388, 619, 620, 621, 0},
  {140, 140, 622, 623, 624, 0},
  {48, 48, 625, 626, 627, 0},
  {313, 313, 628, 629, 630, 0},
  {574, 574, 631, 632, 633, 0},
  {579, 579, 634, 635, 636, 0},
  {382, 382, 637, 638, 639, 0},
  {331, 331, 640, 641, 642, 0},
  {569, 569, 643, 644, 645, 0},
  {565, 565, 646, 647, 648, 0},
  {567, 567, 649, 650, 651, 0},
  {559, 559, 652, 653, 654, 0},
  {358, 358, 655, 656, 657, 0},
  {561, 561, 658, 659, 660, 0},
  {59, 59, 661, 662, 663, 0},
  {558, 558, 664, 665, 666, 0},
  {401, 401, 672, 673, 674, 0},
  {20, 20, 712, 0, 0, 0},
  {21, 21, 713, 0, 0, 0},
  {30, 30, 714, 0, 0, 0},
  {31, 31, 715, 0, 0, 0},
  {33, 33, 717, 0, 0, 0},
  {34, 34, 718, 0, 0, 0},
  {32, 32, 716, 0, 0, 0},
  {35, 35, 719, 0, 0, 0},
  {253, 253, 720, 0, 0, 0},
  {254, 254, 721, 0, 0, 0},
  {255, 255, 722, 0, 0, 0},
  {256, 256, 723, 0, 0, 0},
  {257, 257, 724, 0, 0, 0},
  {258, 258, 725, 0, 0, 0},
  {259, 259, 726, 0, 0, 0},
  {261, 261, 727, 0, 0, 0}
}

local function base(id)
  for i, set in ipairs(M.SETS) do
    if set[1] == id then return i end
  end
  return nil
end

-- the rematch trainer for the base trainer `id`, given `beaten(trainer)` and
-- `unlocked(rung)` -- TryGetRematchTrainerIdByBaseTrainerId
function M.rematchFor(id, beaten, unlocked)
  local s = base(tonumber(id) or -1)
  if not s then return 0 end
  local set = M.SETS[s]
  -- GetIndexOfFirstUnbeatenRematch: rungs 1..5 of the C row (2..6 here)
  local rung = 5
  for i = 1, 5 do
    local t = set[i + 1]
    if t == 0 then rung = i - 1; break end
    if t ~= 0xFFFF and not beaten(t) then rung = i; break end
    -- (all five beaten: GetIndexOfFirstUnbeatenRematch returns 5, the default)
  end
  -- CheckUnlockedRematchGroup / GetPreviousRematchIndexForTrainer
  if rung ~= 0 and not unlocked(rung) then
    local back = 0
    for i = rung - 1, 1, -1 do
      if set[i + 1] ~= 0xFFFF then back = i; break end
    end
    rung = back
  end
  return set[rung + 1] or 0
end

-- Field_GetTimeOfDayWildParam: morning 0, day / evening 1, night 2
local function wildTime()
  local ok, E = pcall(require, "src.import.Gen4Encounters")
  local band = ok and E.timeOfDayForHour and E.timeOfDayForHour(tonumber(os.date("%H")) or 12) or 1
  return (band == 0 and 0) or ((band == 1 or band == 2) and 1) or 2
end

local function G4() return require("src.script.Gen4Commands") end

function M.answer(game, save, contact)
  contact = math.floor(tonumber(contact) or 0)
  local st = save and save.hgssPhoneState
  if not (st and st.seeking and st.seeking[contact]) then return 0 end
  if contact == M.KENJI and wildTime() ~= 1 then return 0 end
  local pc = game and game.data and game.data.gen4_hgss_phone_call
  local entry = pc and pc.book and pc.book[contact]
  if not entry then return 0 end
  local tflags = save.gen4TrainerFlags or {}
  local flags = save.flags or {}
  return M.rematchFor(entry.trainerId,
    function(t) return tflags[t] and true or false end,
    function(rung) return flags[("FLAG_G4_%04X"):format(M.UNLOCK_FLAG_BASE + rung)] and true or false end)
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

function Commands.g4_hgss_phonebook_rematch(ctx, contact, destVar)
  local value = M.answer(ctx.game, ctx.save, G4().valueOf(ctx, contact))
  G4().setVar(ctx.save, destVar, value)
end

function Commands.g4_hgss_clear_phone_rematch(ctx, contact)
  local st = ctx.save and ctx.save.hgssPhoneState
  local c = math.floor(tonumber(G4().valueOf(ctx, contact)) or 0)
  if st and st.seeking then st.seeking[c] = nil end
end

function M.install(L)
  L.getphonebookrematch = function(ins, s)
    s.out[#s.out + 1] = { "g4_hgss_phonebook_rematch", ins.args[1], ins.args[2] }
  end
  L.scrcmd_462 = function(ins, s)
    s.out[#s.out + 1] = { "g4_hgss_clear_phone_rematch", ins.args[1] }
  end
end

return M
