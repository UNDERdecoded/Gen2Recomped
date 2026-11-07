-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- PLATINUM'S VS. SEEKER (pokeplatinum src/overlay005/vs_seeker.c).
--
-- The bag already ran `scripts_vs_seeker` entry 0, but its `StartVsSeeker`
-- had no handler: the script's `SetVar VAR_RESULT, 0` made every use fall
-- into VsSeeker_OK and release, and the battery never charged (the step
-- counter was FireRed's). The cartridge's pieces, here:
--
--   * BATTERY (VsSeeker_UpdateStepCount): +1 a step while the item is in the
--     bag, to 100, in VAR_VS_SEEKER_BATTERY_LEVEL (0x4033). Once used with a
--     trainer picked (FLAG_VS_SEEKER_USED 0x96D), VAR_VS_SEEKER_STEP_COUNT
--     (0x4034) counts to 100 and then every armed trainer stands down.
--   * USE (VsSeeker_ExecuteTask): battery below 100 -> result 1 with the
--     missing steps in STRVAR 0; no trainer in the box (7 left / right, 7 up,
--     6 down; disguised trainers excluded) -> 2; otherwise the beep, battery
--     to 0, and each trainer in the box: unbeaten -> "!"; beaten -> 50% to
--     arm ("!!", and their double partner too), result 3 if nobody reacted.
--   * REMATCH (VsSeeker_GetRematchTrainerID): an armed trainer's party is the
--     first unbeaten rung of gVsSeekerRematchData, held back to the last rung
--     the FLAG_UNLOCKED_VS_SEEKER_LVL_n (0x97F + n - 1) flags allow.
--
-- The rematch table is gVsSeekerRematchData, trainer ids resolved through
-- generated/trainers.txt: { base, rung1 .. rung5 }, 0xFFFF a skipped rung,
-- 0 the end. Armed state is per map object (save.vsSeeker.rematches, the key
-- src/world/VsSeeker.lua uses), holding the BASE id; the rung is worked out
-- when the trainer is talked to, as the cartridge does.
--
-- Armed trainers spin on the spot (V.spin, MOVEMENT_TYPE_VS_SEEKER_SPIN)
-- until talked to. Not drawn: the player's Vs. Seeker pose.

local V = {}

V.BATTERY_VAR, V.STEP_VAR = 0x4033, 0x4034
V.USED_FLAG, V.LEVEL_FLAG_BASE = 0x96D, 0x97F
V.MAX_BATTERY, V.MAX_ACTIVE_STEPS, V.CHANCE = 100, 100, 50
V.LEFT, V.RIGHT, V.UP, V.DOWN = 7, 7, 7, 6
V.ITEM = 443
V.NONE, V.END = 0xFFFF, 0
V.RESULT = { OK = 0, NO_BATTERY = 1, NO_TRAINERS = 2, NONE_PICKED = 3 }

V.REMATCH = {
  { 14, 14, 0, 0, 0, 0 },
  { 21, 627, 628, 65535, 629, 0 },
  { 44, 44, 0, 0, 0, 0 },
  { 45, 65535, 630, 631, 65535, 632 },
  { 20, 20, 0, 0, 0, 0 },
  { 38, 65535, 633, 634, 65535, 635 },
  { 74, 65535, 65535, 636, 65535, 637 },
  { 76, 76, 0, 0, 0, 0 },
  { 81, 81, 0, 0, 0, 0 },
  { 554, 65535, 65535, 65535, 65535, 638 },
  { 555, 555, 0, 0, 0, 0 },
  { 46, 65535, 639, 640, 641, 0 },
  { 56, 56, 0, 0, 0, 0 },
  { 47, 65535, 642, 643, 644, 0 },
  { 57, 57, 0, 0, 0, 0 },
  { 16, 16, 0, 0, 0, 0 },
  { 34, 34, 0, 0, 0, 0 },
  { 377, 645, 646, 65535, 647, 0 },
  { 132, 132, 0, 0, 0, 0 },
  { 133, 133, 0, 0, 0, 0 },
  { 140, 65535, 65535, 65535, 648, 0 },
  { 134, 134, 0, 0, 0, 0 },
  { 135, 135, 0, 0, 0, 0 },
  { 141, 65535, 65535, 65535, 649, 0 },
  { 87, 87, 0, 0, 0, 0 },
  { 272, 272, 0, 0, 0, 0 },
  { 273, 273, 0, 0, 0, 0 },
  { 274, 65535, 65535, 65535, 650, 0 },
  { 381, 381, 0, 0, 0, 0 },
  { 382, 382, 0, 0, 0, 0 },
  { 48, 48, 0, 0, 0, 0 },
  { 58, 65535, 65535, 651, 65535, 652 },
  { 25, 25, 0, 0, 0, 0 },
  { 26, 26, 0, 0, 0, 0 },
  { 27, 65535, 653, 654, 65535, 655 },
  { 28, 28, 0, 0, 0, 0 },
  { 29, 29, 0, 0, 0, 0 },
  { 30, 30, 0, 0, 0, 0 },
  { 31, 65535, 656, 657, 65535, 658 },
  { 32, 32, 0, 0, 0, 0 },
  { 75, 75, 0, 0, 0, 0 },
  { 73, 65535, 65535, 659, 65535, 660 },
  { 277, 65535, 65535, 65535, 65535, 661 },
  { 557, 65535, 65535, 65535, 65535, 662 },
  { 558, 558, 0, 0, 0, 0 },
  { 559, 559, 0, 0, 0, 0 },
  { 560, 560, 0, 0, 0, 0 },
  { 66, 66, 0, 0, 0, 0 },
  { 170, 65535, 65535, 65535, 663, 0 },
  { 278, 65535, 65535, 664, 65535, 665 },
  { 282, 282, 0, 0, 0, 0 },
  { 563, 65535, 65535, 65535, 65535, 666 },
  { 564, 65535, 65535, 65535, 65535, 667 },
  { 565, 565, 0, 0, 0, 0 },
  { 566, 566, 0, 0, 0, 0 },
  { 567, 567, 0, 0, 0, 0 },
  { 568, 568, 0, 0, 0, 0 },
  { 67, 67, 0, 0, 0, 0 },
  { 171, 65535, 65535, 65535, 668, 0 },
  { 286, 286, 0, 0, 0, 0 },
  { 287, 65535, 65535, 669, 65535, 670 },
  { 573, 65535, 65535, 65535, 65535, 671 },
  { 574, 65535, 65535, 65535, 65535, 672 },
  { 575, 575, 0, 0, 0, 0 },
  { 576, 576, 0, 0, 0, 0 },
  { 577, 577, 0, 0, 0, 0 },
  { 578, 578, 0, 0, 0, 0 },
  { 119, 65535, 65535, 673, 65535, 674 },
  { 288, 65535, 65535, 65535, 65535, 675 },
  { 583, 65535, 65535, 65535, 65535, 676 },
  { 120, 65535, 65535, 677, 65535, 678 },
  { 289, 65535, 65535, 65535, 65535, 679 },
  { 585, 65535, 65535, 65535, 65535, 680 },
  { 290, 290, 0, 0, 0, 0 },
  { 291, 291, 0, 0, 0, 0 },
  { 292, 65535, 65535, 681, 65535, 682 },
  { 22, 22, 0, 0, 0, 0 },
  { 23, 65535, 683, 65535, 684, 0 },
  { 24, 24, 0, 0, 0, 0 },
  { 43, 43, 0, 0, 0, 0 },
  { 91, 91, 0, 0, 0, 0 },
  { 92, 92, 0, 0, 0, 0 },
  { 93, 93, 0, 0, 0, 0 },
  { 111, 111, 0, 0, 0, 0 },
  { 153, 65535, 65535, 65535, 685, 0 },
  { 154, 154, 0, 0, 0, 0 },
  { 168, 168, 0, 0, 0, 0 },
  { 172, 172, 0, 0, 0, 0 },
  { 173, 65535, 65535, 65535, 686, 0 },
  { 174, 174, 0, 0, 0, 0 },
  { 175, 175, 0, 0, 0, 0 },
  { 15, 15, 0, 0, 0, 0 },
  { 65, 65535, 65535, 687, 65535, 688 },
  { 294, 294, 0, 0, 0, 0 },
  { 121, 65535, 65535, 689, 65535, 690 },
  { 84, 65535, 691, 692, 65535, 693 },
  { 300, 65535, 65535, 65535, 694, 0 },
  { 113, 113, 0, 0, 0, 0 },
  { 114, 114, 0, 0, 0, 0 },
  { 304, 304, 0, 0, 0, 0 },
  { 305, 305, 0, 0, 0, 0 },
  { 441, 441, 0, 0, 0, 0 },
  { 442, 65535, 65535, 695, 696, 0 },
  { 49, 49, 0, 0, 0, 0 },
  { 130, 130, 0, 0, 0, 0 },
  { 306, 306, 0, 0, 0, 0 },
  { 307, 65535, 65535, 697, 65535, 698 },
  { 308, 308, 0, 0, 0, 0 },
  { 42, 42, 0, 0, 0, 0 },
  { 69, 69, 0, 0, 0, 0 },
  { 79, 79, 0, 0, 0, 0 },
  { 126, 126, 0, 0, 0, 0 },
  { 127, 127, 0, 0, 0, 0 },
  { 128, 128, 0, 0, 0, 0 },
  { 129, 129, 0, 0, 0, 0 },
  { 148, 148, 0, 0, 0, 0 },
  { 258, 65535, 65535, 65535, 699, 0 },
  { 313, 313, 0, 0, 0, 0 },
  { 587, 65535, 65535, 65535, 65535, 700 },
  { 588, 588, 0, 0, 0, 0 },
  { 55, 55, 0, 0, 0, 0 },
  { 85, 65535, 65535, 701, 65535, 702 },
  { 3, 3, 0, 0, 0, 0 },
  { 11, 703, 704, 65535, 705, 0 },
  { 12, 12, 0, 0, 0, 0 },
  { 322, 706, 707, 708, 0, 0 },
  { 323, 323, 0, 0, 0, 0 },
  { 18, 18, 0, 0, 0, 0 },
  { 19, 19, 0, 0, 0, 0 },
  { 36, 36, 0, 0, 0, 0 },
  { 37, 37, 0, 0, 0, 0 },
  { 39, 39, 0, 0, 0, 0 },
  { 40, 40, 0, 0, 0, 0 },
  { 41, 41, 0, 0, 0, 0 },
  { 326, 326, 0, 0, 0, 0 },
  { 451, 65535, 709, 710, 65535, 711 },
  { 13, 712, 713, 65535, 714, 0 },
  { 327, 65535, 715, 716, 717, 0 },
  { 328, 328, 0, 0, 0, 0 },
  { 17, 17, 0, 0, 0, 0 },
  { 35, 35, 0, 0, 0, 0 },
  { 456, 718, 719, 65535, 720, 0 },
  { 53, 65535, 721, 722, 723, 0 },
  { 88, 88, 0, 0, 0, 0 },
  { 89, 89, 0, 0, 0, 0 },
  { 90, 90, 0, 0, 0, 0 },
  { 102, 102, 0, 0, 0, 0 },
  { 332, 65535, 724, 725, 726, 0 },
  { 333, 333, 0, 0, 0, 0 },
  { 82, 82, 0, 0, 0, 0 },
  { 335, 65535, 65535, 65535, 727, 728 },
  { 83, 65535, 729, 730, 65535, 731 },
  { 94, 65535, 732, 733, 65535, 734 },
  { 95, 95, 0, 0, 0, 0 },
  { 591, 65535, 65535, 65535, 65535, 735 },
  { 592, 592, 0, 0, 0, 0 },
  { 593, 593, 0, 0, 0, 0 },
  { 96, 65535, 736, 737, 65535, 738 },
  { 97, 97, 0, 0, 0, 0 },
  { 594, 65535, 65535, 65535, 65535, 739 },
  { 595, 595, 0, 0, 0, 0 },
  { 596, 596, 0, 0, 0, 0 },
  { 110, 110, 0, 0, 0, 0 },
  { 180, 180, 0, 0, 0, 0 },
  { 337, 65535, 65535, 65535, 740, 741 },
  { 338, 338, 0, 0, 0, 0 },
  { 482, 65535, 65535, 65535, 65535, 742 },
  { 98, 98, 0, 0, 0, 0 },
  { 99, 99, 0, 0, 0, 0 },
  { 486, 65535, 743, 744, 745, 0 },
  { 70, 70, 0, 0, 0, 0 },
  { 71, 71, 0, 0, 0, 0 },
  { 72, 72, 0, 0, 0, 0 },
  { 78, 65535, 746, 747, 748, 0 },
  { 80, 80, 0, 0, 0, 0 },
  { 146, 146, 0, 0, 0, 0 },
  { 147, 147, 0, 0, 0, 0 },
  { 488, 488, 0, 0, 0, 0 },
  { 489, 489, 0, 0, 0, 0 },
  { 490, 490, 0, 0, 0, 0 },
  { 346, 65535, 65535, 749, 65535, 750 },
  { 491, 491, 0, 0, 0, 0 },
  { 492, 492, 0, 0, 0, 0 },
  { 136, 136, 0, 0, 0, 0 },
  { 137, 65535, 65535, 751, 752, 0 },
  { 142, 142, 0, 0, 0, 0 },
  { 143, 65535, 65535, 753, 65535, 754 },
  { 138, 138, 0, 0, 0, 0 },
  { 139, 65535, 65535, 755, 756, 0 },
  { 144, 144, 0, 0, 0, 0 },
  { 145, 65535, 65535, 757, 758, 0 },
  { 103, 103, 0, 0, 0, 0 },
  { 104, 104, 0, 0, 0, 0 },
  { 159, 159, 0, 0, 0, 0 },
  { 160, 160, 0, 0, 0, 0 },
  { 161, 161, 0, 0, 0, 0 },
  { 166, 166, 0, 0, 0, 0 },
  { 183, 65535, 65535, 65535, 65535, 759 },
  { 184, 184, 0, 0, 0, 0 },
  { 185, 65535, 65535, 65535, 65535, 760 },
  { 186, 186, 0, 0, 0, 0 },
  { 187, 187, 0, 0, 0, 0 },
  { 188, 188, 0, 0, 0, 0 },
  { 597, 65535, 65535, 65535, 65535, 761 },
  { 598, 598, 0, 0, 0, 0 },
  { 599, 599, 0, 0, 0, 0 },
  { 600, 600, 0, 0, 0, 0 },
  { 105, 105, 0, 0, 0, 0 },
  { 106, 106, 0, 0, 0, 0 },
  { 162, 162, 0, 0, 0, 0 },
  { 163, 163, 0, 0, 0, 0 },
  { 164, 164, 0, 0, 0, 0 },
  { 167, 167, 0, 0, 0, 0 },
  { 189, 65535, 65535, 65535, 65535, 762 },
  { 190, 190, 0, 0, 0, 0 },
  { 191, 191, 0, 0, 0, 0 },
  { 192, 65535, 65535, 65535, 65535, 763 },
  { 193, 193, 0, 0, 0, 0 },
  { 194, 194, 0, 0, 0, 0 },
  { 494, 494, 0, 0, 0, 0 },
  { 601, 65535, 65535, 65535, 65535, 764 },
  { 602, 602, 0, 0, 0, 0 },
  { 603, 603, 0, 0, 0, 0 },
  { 604, 604, 0, 0, 0, 0 },
  { 1, 765, 766, 767, 0, 0 },
  { 2, 2, 0, 0, 0, 0 },
  { 4, 4, 0, 0, 0, 0 },
  { 10, 10, 0, 0, 0, 0 },
  { 33, 33, 0, 0, 0, 0 },
  { 355, 768, 769, 65535, 770, 0 },
  { 356, 356, 0, 0, 0, 0 },
  { 107, 65535, 771, 65535, 772, 0 },
  { 358, 358, 0, 0, 0, 0 },
  { 359, 359, 0, 0, 0, 0 },
  { 108, 65535, 65535, 773, 775, 0 },
  { 360, 360, 0, 0, 0, 0 },
  { 361, 361, 0, 0, 0, 0 },
  { 68, 65535, 65535, 774, 65535, 776 },
  { 362, 65535, 65535, 65535, 65535, 777 },
  { 605, 65535, 65535, 65535, 65535, 778 },
}

local byBase
local function rematchRow(base)
  if not byBase then
    byBase = {}
    for _, row in ipairs(V.REMATCH) do byBase[row[1]] = byBase[row[1]] or row end
  end
  return byBase[tonumber(base) or -1]
end
V.rematchRow = rematchRow

local function C() return require("src.script.Gen4Commands") end
local function flagKey(f) return ("FLAG_G4_%04X"):format(f) end
local function flag(save, f) return save and save.flags and save.flags[flagKey(f)] == true end

local function beaten(save, id)
  local t = save and save.gen4TrainerFlags
  return t and t[tonumber(id)] and true or false
end

local function owns(save)
  local inv = save and save.inventory or {}
  return (inv[V.ITEM] or inv["ITEM_443"] or 0) > 0
end

local function store(save)
  save.vsSeeker = save.vsSeeker or { steps = 0, rematches = {} }
  save.vsSeeker.rematches = save.vsSeeker.rematches or {}
  return save.vsSeeker.rematches
end

local function key(ow, npc)
  return tostring(ow.map.id) .. ":" .. tostring(npc.def.localId or npc.def.index)
end

function V.battery(save) return tonumber(C().getVar(save, V.BATTERY_VAR)) or 0 end

-- VsSeeker_UpdateStepCount, once per step on a Platinum map
function V.step(game, ow)
  local save = game and game.save
  if not save then return end
  -- "armed" is the object's movement type on the cartridge, and a warp
  -- rebuilds every object from the header (field_map_change.c): leaving the
  -- map disarms everyone (the used flag and step count stay)
  local here = ow and ow.map and ow.map.id
  if here ~= nil and save.vsSeeker and save.vsSeeker.map ~= here then
    if save.vsSeeker.map ~= nil then save.vsSeeker.rematches = {} end
    save.vsSeeker.map = here
  end
  local battery = V.battery(save)
  if owns(save) and battery < V.MAX_BATTERY then C().setVar(save, V.BATTERY_VAR, battery + 1) end
  if flag(save, V.USED_FLAG) then
    local steps = tonumber(C().getVar(save, V.STEP_VAR)) or 0
    if steps < V.MAX_ACTIVE_STEPS then
      steps = steps + 1
      C().setVar(save, V.STEP_VAR, steps)
    end
    if steps >= V.MAX_ACTIVE_STEPS then
      -- SystemVars_ResetVsSeeker + VsSeeker_ClearRematchMoveCode
      C().setVar(save, V.STEP_VAR, 0)
      save.flags[flagKey(V.USED_FLAG)] = nil
      save.vsSeeker.rematches = {}
      for _, npc in ipairs((ow and ow.npcs) or {}) do npc.vsSeekerReady = nil end
    end
  end
end

local function trainerId(npc)
  local t = npc and npc.def and npc.def.trainer
  return type(t) == "table" and tonumber(t.id) or nil
end

local DISGUISE = { DISGUISE_SNOW = true, DISGUISE_SAND = true, DISGUISE_ROCK = true, DISGUISE_GRASS = true,
                   MOVEMENT_TYPE_DISGUISE_SNOW = true, MOVEMENT_TYPE_DISGUISE_SAND = true,
                   MOVEMENT_TYPE_DISGUISE_ROCK = true, MOVEMENT_TYPE_DISGUISE_GRASS = true }

-- VsSeekerSystem_CollectViableNPCs
function V.visible(ow)
  local p = ow and ow.player
  local out = {}
  if not p then return out end
  local xMin, xMax = math.max(0, p.cellX - V.LEFT), p.cellX + V.RIGHT
  local zMin, zMax = math.max(0, p.cellY - V.UP), p.cellY + V.DOWN
  for _, npc in ipairs(ow.npcs or {}) do
    local id = trainerId(npc)
    local mt = npc.def and (npc.def.movementType or npc.def.movement)
    if id and not npc.hidden and not DISGUISE[tostring(mt)]
       and npc.cellX >= xMin and npc.cellX <= xMax and npc.cellY >= zMin and npc.cellY <= zMax then
      out[#out + 1] = npc
    end
  end
  return out
end

-- the double-battle partner: another trainer object with the same trainer id
local function partnerOf(ow, npc)
  local id = trainerId(npc)
  for _, other in ipairs(ow.npcs or {}) do
    if other ~= npc and trainerId(other) == id and not other.hidden then return other end
  end
  return nil
end

local function bubble(ow, npc, double)
  local Gen4Emotes = require("src.import.Gen4Emotes")
  local b = { npc = npc, frames = Gen4Emotes.FRAMES, totalFrames = Gen4Emotes.FRAMES,
              bubble = double and "double" or 1 }
  if ow.emote then
    ow.extraEmotes = ow.extraEmotes or {}
    ow.extraEmotes[#ow.extraEmotes + 1] = b
  else
    ow.emote = b
  end
end

-- StartVsSeeker: returns the result code (and, for NO_BATTERY, the missing
-- steps, which the caller puts in STRVAR 0)
function V.use(game, ow, rng)
  local save = game.save
  rng = rng or love.math.random
  local trainers = V.visible(ow)
  local battery = V.battery(save)
  if battery < V.MAX_BATTERY then
    return V.RESULT.NO_BATTERY, V.MAX_BATTERY - battery
  end
  if #trainers == 0 then return V.RESULT.NO_TRAINERS end
  -- SE_DP_VS_SEEKER_BEEP, the SDAT's SEQ_SE_DP_UG_005 (seqInfo 1568)
  pcall(function() require("src.core.Sound").play(game.data, "SEQ_SE_DP_UG_005") end)
  C().setVar(save, V.BATTERY_VAR, 0)
  local any = false
  local armed = store(save)
  for _, npc in ipairs(trainers) do
    local id = trainerId(npc)
    if not beaten(save, id) then
      bubble(ow, npc, false)
      any = true
    elseif rng(0, 99) < V.CHANCE and not armed[key(ow, npc)] then
      armed[key(ow, npc)] = id
      npc.vsSeekerReady = true
      bubble(ow, npc, true)
      local second = partnerOf(ow, npc)
      if second then
        armed[key(ow, second)] = trainerId(second)
        second.vsSeekerReady = true
        bubble(ow, second, true)
      end
      any = true
      save.flags = save.flags or {}
      save.flags[flagKey(V.USED_FLAG)] = true
    end
  end
  return any and V.RESULT.OK or V.RESULT.NONE_PICKED
end

-- VsSeeker_GetRematchTrainerID: 0 unless this object is armed
function V.rematchTrainerId(save, ow, npc)
  if not (ow and npc and npc.def and ow.map) then return 0 end
  local base = store(save)[key(ow, npc)]
  if not base then return 0 end
  local row = rematchRow(base)
  if not row then return 0 end
  -- VsSeeker_GetCurrentLevelForRematchData
  local level = 1
  while level < 6 do
    local id = row[level + 1]
    if id == V.END then level = level - 1 break end
    if id ~= V.NONE and not beaten(save, id) then break end
    level = level + 1
  end
  if level >= 6 then level = 5 end
  -- VsSeeker_AdjustRematchLevel
  if level ~= 0 and not flag(save, V.LEVEL_FLAG_BASE + level - 1) then
    local lower = 0
    for i = level - 1, 1, -1 do
      if row[i + 1] ~= V.NONE then lower = i break end
    end
    level = lower
  end
  return row[level + 1] or 0
end

-- VsSeeker_SetMoveCodeForFacingDirection: the trainer (and partner) stand down
function V.clear(save, ow, npc)
  if not (ow and npc and npc.def and ow.map) then return end
  local armed = store(save)
  armed[key(ow, npc)] = nil
  npc.vsSeekerReady, npc.vsSeekerSpin = nil, nil
  local second = partnerOf(ow, npc)
  if second then armed[key(ow, second)] = nil; second.vsSeekerReady, second.vsSeekerSpin = nil, nil end
end

-- MOVEMENT_TYPE_VS_SEEKER_SPIN (pokeplatinum unk_0206450C.c sub_02064AF0 /
-- sub_02064AFC, Unk_020EE870): an armed trainer turns on the spot -- face the
-- way it is looking (a turn action), wait for it, hold 24 frames, then the
-- next way round the compass, clockwise N E S W to begin with (mode 3, the
-- second table); each time it comes back to its initial facing the turn
-- reverses (Direction_GetOpposite: N W S E). Two engine ticks a field frame.
V.SPIN_HOLD = 24
V.SPIN_TICKS = (V.SPIN_HOLD + 1) * 2
V.SPIN_CW = { up = "right", right = "down", down = "left", left = "up" }
V.SPIN_CCW = { up = "left", left = "down", down = "right", right = "up" }
local INITIAL = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }

-- the next facing and direction flag after a hold (sub_02064B74)
function V.spinNext(facing, ccw, initial)
  local ring = ccw and V.SPIN_CCW or V.SPIN_CW
  local nextFacing = ring[facing] or "down"
  if nextFacing == initial then ccw = not ccw end
  return nextFacing, ccw
end

-- NPC:update's hook for an armed trainer: true while the spin owns it
function V.spin(npc)
  if not npc.vsSeekerReady then return false end
  local s = npc.vsSeekerSpin
  if not s then
    local d = npc.def and tonumber(npc.def.direction)
    s = { ccw = false, timer = V.SPIN_TICKS, initial = INITIAL[d] or npc.facing }
    npc.vsSeekerSpin = s
  end
  s.timer = s.timer - 1
  if s.timer > 0 then return true end
  npc.facing, s.ccw = V.spinNext(npc.facing, s.ccw, s.initial)
  s.timer = V.SPIN_TICKS
  return true
end

return V
