-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Public Gen2 colour reads over the native palette pack. No duplicate
-- species catalogue, ROM colours or private renderer implementation.
local Context = require("src.render.Gen2PaletteContext")
local M = {}

-- Return the native source table without allocation for the built-in renderer.
-- Public consumers receive detached RGB values through colors() below.
function M.native(data, species, shiny)
  local owner = Context.owner(data)
  local pokemon = owner and owner.pokemon
  local def = type(pokemon) == "table" and pokemon[species]
  local pack = owner and owner.palettes
  local palettes = type(pack) == "table" and pack.palettes
  if type(def) ~= "table" or type(palettes) ~= "table" then return nil end
  if shiny and def.shinyPalette and palettes[def.shinyPalette] then
    return palettes[def.shinyPalette]
  end
  if def.palette and palettes[def.palette] then return palettes[def.palette] end
  local names = pack.pokemon
  local name = type(names) == "table" and (names[def.id or species] or names[species])
  return name and palettes[name] or nil
end

local function color(value)
  if type(value) ~= "table" then return nil end
  local rgb = {}
  for i = 1, 3 do
    local n = value[i]
    if type(n) ~= "number" or n ~= n or n < 0 or n > 255 then return nil end
    rgb[i] = n
  end
  return rgb
end
local function detached(palette)
  if type(palette) ~= "table" then return nil end
  local out = {}
  for i = 1, 4 do
    out[i] = color(palette[i])
    if not out[i] then return nil end
  end
  return out
end

function M.colors(data, species, shiny)
  if type(data) ~= "table" or type(species) ~= "string" then return nil end
  local owner, bound = Context.owner(data)
  if owner then return detached(M.native(data, species, shiny)) end
  if bound then return nil end -- Never revive a retired dataset view.
  -- Reference palette-only records carry the two ROM middle colours, rather
  -- than native names into a four-colour pack. Preserve that public input.
  local rows = data.pokemon
  local entry = type(rows) == "table" and rows[species]
  if type(entry) ~= "table" then return nil end
  local pair = shiny and entry.shiny or entry.normal
  if type(pair) ~= "table" then return nil end
  local first, second = color(pair[1]), color(pair[2])
  if not first or not second then return nil end
  return { {255,255,255}, first, second, {0,0,0} }
end
return M
