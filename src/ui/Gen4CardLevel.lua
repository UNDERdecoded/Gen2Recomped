-- THE TRAINER CARD'S LEVEL (its stars and colour) for Platinum and
-- HeartGold / SoulSilver, one point per condition met.
--
-- READ FROM CODE:
--   Platinum, pokeplatinum src/trainer_case.c TrainerCase_CalculateTrainerCardLevel:
--     1 SystemFlag_CheckGameCompleted (FLAG_GAME_COMPLETED 0x964)
--     2 Pokedex_NationalDexCompleted: caught 1..493 minus sExcludedMonsNational
--       (Mew, Lugia, Ho-Oh, Celebi, Jirachi, Deoxys, Phione, Manaphy, Darkrai,
--       Shaymin, Arceus) >= NATIONAL_DEX_GOAL (493 - 11 = 482)
--     3 any Battle Tower record streak (frontier stats 0, 2, 4, 6, 8: single,
--       double, multi, link multi, Wi-Fi) >= 100
--     4 SystemFlag_CheckContestMaster for any of the five types
--       (FLAG_CONTEST_MASTER_COOL..TOUGH = 0x968..0x96C, set by
--       Contest_EndContest on a Master Rank win; the port also keeps them as
--       save.gen4ContestMaster[type])
--     5 UndergroundRecord_HasPlatBaseFlag: flag rank BASE_FLAG_PLATINUM (4)
--   HeartGold / SoulSilver, pokeheartgold asm/unk_02068FC8.s sub_020691E8:
--     1 CheckGameClearFlag
--     2 Pokedex_NationalDexIsComplete: caught minus sNationalMythicals (Mew,
--       Celebi, Jirachi, Deoxys, Phione, Manaphy, Darkrai, Shaymin, Arceus)
--       >= 493 - 9 = 484
--     3 any Battle Tower record streak (FrontierSave_GetStat 0, 2, 4, 6, 8) >= 100
--     4 flag 0xF1 (FLAG_UNK_0F1, a Pokeathlon one: scr_seq_0167 / the
--       Pokeathlon record app's sub_0203EE54 checks 0xEF, 0xF0, 0xF1)
--     5 flag 0x184 (FLAG_UNK_184, set by scr_seq_0849_T20R0402 with the
--       Shiny Leaf crown)
-- The game-clear point also counts the port's own Hall of Fame record.

local L = {}

local PT_EXCLUDED = { [151] = true, [249] = true, [250] = true, [251] = true, [385] = true,
  [386] = true, [489] = true, [490] = true, [491] = true, [492] = true, [493] = true }
local HG_EXCLUDED = { [151] = true, [251] = true, [385] = true, [386] = true, [489] = true,
  [490] = true, [491] = true, [492] = true, [493] = true }

local function flag(save, id) return ((save.flags or {})[("FLAG_G4_%04X"):format(id)]) == true end

function L.nationalCaught(save, excluded)
  local n = 0
  local owned = (save.pokedex or {}).owned or {}
  for sp = 1, 493 do
    if owned[sp] and not excluded[sp] then n = n + 1 end
  end
  return n
end

function L.towerHundred(save)
  local stats = (save.gen4Frontier or {}).stats or {}
  for _, i in ipairs({ 0, 2, 4, 6, 8 }) do
    if (tonumber(stats[i]) or 0) >= 100 then return true end
  end
  return false
end

local function gameClear(save, flagId)
  if flagId and flag(save, flagId) then return true end
  local hof = save.hallOfFame
  return type(hof) == "table" and #hof > 0
end

-- returns level, { reason = bool, ... }
function L.platinum(save)
  save = save or {}
  local why = {}
  why.gameClear = gameClear(save, 0x964)
  why.nationalDex = L.nationalCaught(save, PT_EXCLUDED) >= 493 - 11
  why.tower100 = L.towerHundred(save)
  local master = false
  for id = 0x968, 0x96C do if flag(save, id) then master = true end end
  for _, v in pairs(save.gen4ContestMaster or {}) do if v then master = true end end
  why.contestMaster = master
  local okU, Ug = pcall(require, "src.world.Gen4UgBase")
  why.platinumFlag = okU and Ug.rank and Ug.rank(save) == 4 or false
  local n = 0
  for _, v in pairs(why) do if v then n = n + 1 end end
  return n, why
end

function L.hgss(save)
  save = save or {}
  local why = {}
  why.gameClear = gameClear(save, 0x964)   -- FLAG_GAME_CLEAR 0x964 (flags.h)
  why.nationalDex = L.nationalCaught(save, HG_EXCLUDED) >= 493 - 9
  why.tower100 = L.towerHundred(save)
  why.flag0F1 = flag(save, 0xF1)
  why.shinyLeafCrown = flag(save, 0x184)
  local n = 0
  for _, v in pairs(why) do if v then n = n + 1 end end
  return n, why
end

-- Black / White: ov10 0x0216F830 (the 0x0CE handler's count; the card
-- screen's colour is the same count -- INFERRED, the card overlay not read):
--   1 event flag 0x960 (0x020142E8; the flag the Super Single line also
--     wants -- the game-clear flag)
--   2 0x0200D298: caught (dex +8 bits, 0x0200CED4) over 1..649 minus the
--     table at 0x0209DE2C (Mew, Celebi, Jirachi, Deoxys, Phione, Manaphy,
--     Darkrai, Shaymin, Arceus, Landorus, Kyurem, Keldeo, Meloetta,
--     Genesect, Victini) >= 634
--   3 save block 0x3A bits 7 and 8 (0x0200DBA0): the Super Single and Super
--     Double lines cleared (Gen5BattleSubway CLEAR_FLAG 5 -> 7, 6 -> 8)
--   4 save block 0x2A (the Musical): 0x0200A714 counts props owned over
--     0..255 and must be exactly 100 (every prop)
--   5 save block 3 (0x1B0 bytes, made by 0x0200BDC4) halfwords +0xC and
--     +0xE both >= 30 (0x0200BDF8 / BDFC). READ: their only writers are
--     0x0200BE00 (+0xC) and 0x0200BE24 (+0xE), each "add n, capped", and
--     both are called from ONE place, ov18 0x021806A2 / 0x021806AC, which adds
--     two bytes of a result record (+0x135 to +0xE, +0x134 to +0xC) as the
--     overlay copies a 0x3C-byte record it was handed. INFERRED: ov18 is a
--     wireless / infrared exchange (no field or story code reaches it), so
--     offline the cartridge never earns this point either. The port keeps the
--     two counters as save.gen5Block3 = { c = +0xC, e = +0xE } for whatever
--     link feature raises them (Gen4CardLevel.addBlock3).
-- 0x0200BE00 / 0x0200BE24: add to block 3's two counters, each capped at
-- the literal 0x0200BE20 / 0x0200BE44 (0x3E7 = 999)
function L.addBlock3(save, addC, addE)
  save.gen5Block3 = save.gen5Block3 or { c = 0, e = 0 }
  local b = save.gen5Block3
  b.c = math.min(999, (tonumber(b.c) or 0) + (tonumber(addC) or 0))
  b.e = math.min(999, (tonumber(b.e) or 0) + (tonumber(addE) or 0))
  return b
end

local BW_EXCLUDED = { [151] = true, [251] = true, [385] = true, [386] = true, [489] = true,
  [490] = true, [491] = true, [492] = true, [493] = true, [645] = true, [646] = true,
  [647] = true, [648] = true, [649] = true, [494] = true }
function L.bw(save)
  save = save or {}
  local why = {}
  why.gameClear = gameClear(save, 0x960)
  local n = 0
  local owned = (save.pokedex or {}).owned or {}
  for sp = 1, 649 do if owned[sp] and not BW_EXCLUDED[sp] then n = n + 1 end end
  why.nationalDex = n >= 634
  local f = ((save.gen5Subway or {}).flags) or {}
  why.superLines = (f[8] and f[9]) and true or false
  local props, count = ((save.gen5Musical or {}).props) or {}, 0
  for p = 0, 255 do if props[p] then count = count + 1 end end
  why.allProps = count == 100
  local b3 = save.gen5Block3 or {}
  why.block3 = (tonumber(b3.c) or 0) >= 30 and (tonumber(b3.e) or 0) >= 30
  local total = 0
  for _, v in pairs(why) do if v then total = total + 1 end end
  return total, why
end

return L
