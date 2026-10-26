-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Shared native GSC form identity and catch-order state. Words and pictures
-- remain in the imported dataset, never in a second cartridge catalogue.
local M = {NUM_UNOWN = 26, ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"}
function M.supported()
  local version = require("src.core.GameVersion").get()
  return version == "gold" or version == "silver" or version == "crystal"
end
function M.index(letter)
  if type(letter) == "string" and #letter == 1 then
    return M.ALPHABET:find(letter:upper(), 1, true)
  end
  if type(letter) == "number" and letter % 1 == 0 and letter >= 1 and letter <= 26 then
    return letter
  end
end
function M.name(letter)
  local index = M.index(letter)
  return index and M.ALPHABET:sub(index, index) or nil
end
local function middle(dv)
  dv = dv or 0
  if type(dv) ~= "number" or dv ~= dv or dv < 0 or dv > 15 then return nil end
  return math.floor(dv / 2) % 4
end
function M.letterFromDVs(dvs)
  if type(dvs) ~= "table" then return nil end
  local a,b,c,d = middle(dvs.attack), middle(dvs.defense), middle(dvs.speed), middle(dvs.special)
  if not (a and b and c and d) then return nil end
  return math.floor((a*64+b*16+c*4+d) / 10) + 1
end
function M.dvsForLetter(letter)
  local index = M.index(letter)
  if not index then return nil end
  local packed = (index - 1) * 10
  return {attack = math.floor(packed / 64) % 4 * 2,
    defense = math.floor(packed / 16) % 4 * 2,
    speed = math.floor(packed / 4) % 4 * 2, special = packed % 4 * 2}
end
function M.liveData(data)
  if type(data) == "table" then return data end
  local game = package.loaded["src.core.Game"]
  return type(game) == "table" and type(game.data) == "table" and game.data or nil
end
function M.definition(data)
  data = M.liveData(data)
  if not (data and type(data.pokemon) == "table") then return nil end
  local known = data.pokemon.UNOWN
  if type(known) == "table" then return known end
  for _, def in pairs(data.pokemon) do
    if type(def) == "table" and (def.translationSourceName or def.name) == "UNOWN" then
      return def
    end
  end
end
function M.word(letter, data)
  local index = M.index(letter)
  data = M.liveData(data)
  local record = data and data.unown_dex
  local words = type(record) == "table" and record.words
  local word = index and type(words) == "table" and words[index]
  return type(word) == "string" and word or nil
end
function M.forms(pokemon)
  local def = M.definition({pokemon = pokemon})
  return def and def.forms or nil
end
function M.formSprite(pokemon, letter, back)
  local index, def = M.index(letter), M.definition({pokemon = pokemon})
  if not (index and def) then return nil end
  local form = def.forms and def.forms[index]
  if back then return form and form.spriteBack or def.spriteBack end
  return form and form.spriteFront or def.spriteFront
end
function M.monLetter(mon, data)
  if type(mon) ~= "table" or require("src.pokemon.Party").isEgg(mon) then return nil end
  data = M.liveData(data)
  local def = data and data.pokemon and data.pokemon[mon.species]
  if def then
    if def ~= M.definition(data) then return nil end
  elseif mon.species ~= "UNOWN" then return nil end
  return M.index(mon.unownLetter) or M.letterFromDVs(mon.dvs)
end
function M.letters(save)
  local dex = type(save) == "table" and save.pokedex
  if type(dex) ~= "table" then return {} end
  local out, seen = {}, {}
  local function add(letter)
    local index = M.index(letter)
    if index and not seen[index] then seen[index] = true; out[#out + 1] = index end
  end
  for _, letter in ipairs(type(dex.unownDex) == "table" and dex.unownDex or {}) do add(letter) end
  local forms = type(dex.unownForms) == "table" and dex.unownForms or {}
  for i = 1, 26 do if forms[i] then add(i) end end
  return out
end
function M.count(save) return #M.letters(save) end
function M.caught(save, letter)
  local index = M.index(letter)
  if not index then return false end
  for _, present in ipairs(M.letters(save)) do if present == index then return true end end
  return false
end
function M.updateDex(save, letter, data)
  local index = M.index(letter)
  if not (M.supported() and type(save) == "table" and index) or M.caught(save, index) then return false end
  if save.pokedex ~= nil and type(save.pokedex) ~= "table" then return false end
  if save.pokedex and save.pokedex.unownForms ~= nil and type(save.pokedex.unownForms) ~= "table" then return false end
  local list = M.letters(save)
  list[#list + 1] = index
  save.pokedex = save.pokedex or {}
  local dex = save.pokedex
  dex.unownDex, dex.unownForms = list, dex.unownForms or {}
  for _, value in ipairs(list) do dex.unownForms[value] = true end
  local Runtime = require("src.mods.Runtime")
  if Runtime.wants("unown.unlocked") then
    Runtime.emit("unown.unlocked", {letter=index, name=M.name(index), word=M.word(index, data), count=#list})
  end
  return true
end
function M.registerCatch(save, mon, data)
  local letter = M.monLetter(mon, data)
  return letter and M.updateDex(save, letter, data) or false
end
return M
