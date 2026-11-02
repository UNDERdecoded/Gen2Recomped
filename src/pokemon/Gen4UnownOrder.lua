-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ORDER THE UNOWN LETTERS WERE FIRST CAUGHT (Gen 4).
--
-- pokeheartgold src/pokedex.c keeps two 28-byte arrays, unownSeenOrder and
-- unownCaughtOrder (0xFF = empty). Pokedex_SetMonCaughtFlag appends the
-- caught Unown's letter (Pokedex_TryAppendUnownLetter, once per letter, never
-- reordered); Pokedex_GetSeenFormByIdx_Unown(dex, i, TRUE) reads it back. The
-- UNOWN Report (overlay 113) lists its pages in exactly that order.
--
-- Here: save.pokedex.gen4UnownCaught, the zero-based forms (0 A .. 25 Z,
-- 26 !, 27 ?), appended at the catch (BattleState) and at a gift (givemon).
-- A save from before the list existed has only the seen-form record
-- (Gen4Forms, dex.gen4FormsSeen[201], in seen order); while Unown is owned,
-- that order stands in for it and seeds the list the first time it grows.

local U = { SPECIES = 201, LETTERS = 28 }

local order
local function formIndexOfKey(key)
  if not order then
    order = {}
    for _, row in ipairs(require("src.import.Gen4Otherpoke").FORMS or {}) do
      if row.species == U.SPECIES then order[#order + 1] = row.form end
    end
  end
  if type(key) == "number" then return key end
  for i, k in ipairs(order) do if k == key then return i - 1 end end
  return nil
end

local function owned(dex)
  local o = dex and dex.owned
  return o and (o[U.SPECIES] or o["SPECIES_201"] or o["201"]) and true or false
end

-- the stand-in for a save without the list: the seen order, while owned
function U.fallback(dex)
  local out, have = {}, {}
  if not owned(dex) then return out end
  local seen = dex.gen4FormsSeen and dex.gen4FormsSeen[U.SPECIES] or {}
  for _, key in ipairs(seen) do
    local f = formIndexOfKey(key)
    if f and f >= 0 and f < U.LETTERS and not have[f] then have[f] = true; out[#out + 1] = f end
  end
  return out
end

-- Pokedex_GetSeenFormByIdx_Unown(dex, i, TRUE) for every i: the letters in
-- catch order
function U.caught(save)
  local dex = save and save.pokedex
  if not dex then return {} end
  local list = dex.gen4UnownCaught
  if type(list) ~= "table" then return U.fallback(dex) end
  local out, have = {}, {}
  for _, f in ipairs(list) do
    f = tonumber(f)
    if f and f >= 0 and f < U.LETTERS and not have[f] then have[f] = true; out[#out + 1] = f end
  end
  return out
end

-- Pokedex_TryAppendUnownLetter(dex, letter, TRUE)
function U.record(game, species, mon)
  if not (game and game.data and (game.data.constants or {}).gen == 4 and mon) then return end
  local Forms = require("src.pokemon.Gen4Forms")
  if Forms.species(species) ~= U.SPECIES then return end
  if require("src.pokemon.Party").isEgg(mon) then return end
  local dex = game.save and game.save.pokedex
  if not dex then return end
  if type(dex.gen4UnownCaught) ~= "table" then dex.gen4UnownCaught = U.fallback(dex) end
  local f = Forms.index(mon)
  if not (f and f >= 0 and f < U.LETTERS) then return end
  for _, have in ipairs(dex.gen4UnownCaught) do if have == f then return end end
  dex.gen4UnownCaught[#dex.gen4UnownCaught + 1] = f
end

return U
