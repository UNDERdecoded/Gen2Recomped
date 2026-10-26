-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Reference spellings over the native imported records and native save.
local Native = require("src.pokemon.Gen2Unown")
local M = {NUM_UNOWN=Native.NUM_UNOWN, SPECIES="UNOWN", ALPHABET=Native.ALPHABET,
  name=Native.name, index=Native.index, letterFromDVs=Native.letterFromDVs,
  dvsForLetter=Native.dvsForLetter, monLetter=Native.monLetter,
  word=Native.word, formSprite=Native.formSprite,
  dex=Native.letters, caught=Native.caught, count=Native.count,
  updateDex=Native.updateDex, registerCatch=Native.registerCatch}
-- Reference consumers index forms by A..Z; native storage indexes by number.
-- The public name map is derived on demand; picture records remain native.
function M.forms(pokemon)
  local source = Native.forms(pokemon)
  if not source then return nil end
  local out = {}
  for i = 1, 26 do if source[i] then out[Native.name(i)] = source[i] end end
  return out
end
return M
