-- WHICH ABILITY A POKEMON SHOWS on the summary / PC screens: the one its
-- ability slot picks, as battle reads it (src/battle/Abilities.lua: list[
-- mon.abilitySlot] with an absent / 0 second slot meaning slot one --
-- pokeplatinum pokemon.c "if (ability2 != ABILITY_NONE) ..."). The screens
-- read list[1] and so showed the first ability for every Pokemon whose
-- personality picked the second (and never a Black / White Hidden Ability,
-- slot 3, Pokemon.abilitySlotFor).
local M = {}

local function empty(v) return v == nil or v == 0 or v == "" or v == "NONE" or v == "ABILITY_NONE" end

-- `list`: the species' abilities (names) or abilityIds (numbers).
function M.pick(mon, list)
  if type(mon) == "table" and mon.ability ~= nil then return mon.ability end
  if type(list) ~= "table" then return nil end
  local slot = type(mon) == "table" and tonumber(mon.abilitySlot) or 1
  local v = list[slot]
  if empty(v) then v = list[1] end
  if empty(v) then return nil end
  return v
end

return M
