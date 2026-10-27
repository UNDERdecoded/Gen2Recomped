-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- The Gen2 host can request a stored mon's entry directly, or the whole dex.
local M={}
function M.new(game,opts)
  opts=opts or {}
  if opts.entrySpecies then return require("src.ui.DexEntryMenu").new(game,{species=opts.entrySpecies,forceOwned=true}) end
  return require("src.ui.PokedexMenu").new(game,{onCancel=opts.onClose or opts.onCancel})
end
return M
