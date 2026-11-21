-- THE CARTRIDGE'S OWN DEFAULT NAMES for the hero.
--
-- Platinum's name-entry bank (text bank 427) holds the preset names:
-- entry 42 is the boy's default and 43 the girl's ("Lucas" / "Dawn" on the
-- US cartridge, "Lucius" / "Lucia" on the German one).  Before this the engine
-- spelled the English pair itself, so a German game greeted its hero as
-- "Lucas".  A cache without the bank (HeartGold / SoulSilver, which number
-- their banks differently, or an old cache) keeps the English pair.

local M = {}

M.BANK = 427
M.BOY, M.GIRL = 42, 43

function M.hero(data, girl)
  local text = data and data.text
  local isPlatinum = data and data.gen4_version == nil
  local s = isPlatinum and text and text[("TEXT_B%04d_%05d"):format(M.BANK, girl and M.GIRL or M.BOY)]
  if type(s) == "string" and s ~= "" and #s <= 8 then return s end
  return girl and "Dawn" or "Lucas"
end

return M
