-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- A POKEMON'S LANGUAGE (MON_DATA_LANGUAGE) for Gen 4 / 5.
--
-- The cartridge stamps every Pokemon it makes -- wild, gift, hatched -- with
-- its own language (gGameLanguage), and an in-game trade with the trade
-- record's (pokeheartgold npc_trade.c `SetMonData(mon, MON_DATA_LANGUAGE,
-- &trade_dat->language)`; Platinum's Foppa Magikarp is LANGUAGE_GERMAN).
-- Two places read it: the Masuda method (parents' languages differ) and the
-- traded-EXP bonus (x1.7 instead of x1.5 when it is not the game's).
--
-- The game's language is read from the dump's game code (the fourth
-- letter: J 1, E/O/P 2, F 3, I 4, D 5, S 7, K 8 -- the cartridge's LANGUAGE_*
-- numbering); a save keeps its own in save.language.

local M = {}

M.BY_REGION = { J = 1, E = 2, O = 2, P = 2, U = 2, F = 3, I = 4, D = 5, S = 7, K = 8 }
M.ENGLISH = 2

function M.game()
  local ok, GV = pcall(require, "src.core.GameVersion")
  local info = ok and GV.info and GV.info() or nil
  local code = info and info.gameCode
  local region = type(code) == "string" and code:sub(4, 4) or nil
  return (region and M.BY_REGION[region]) or M.ENGLISH
end

-- the save's language (stamped the first time it is asked)
function M.save(save)
  if type(save) ~= "table" then return M.game() end
  if tonumber(save.language) == nil then save.language = M.game() end
  return tonumber(save.language)
end

function M.of(save, mon)
  return tonumber(mon and mon.language) or M.save(save)
end

-- Pokemon.new: a Gen 4 / 5 Pokemon is born in the game's language
function M.stamp(mon)
  if type(mon) ~= "table" or mon.language ~= nil then return mon end
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not (ok and (GV.isGen4() or GV.isGen5())) then return mon end
  local G = package.loaded["src.core.Game"]
  mon.language = M.save(G and G.save)
  return mon
end

return M
