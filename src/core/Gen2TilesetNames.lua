-- Public constant spelling for the importer's named Gen2 ROM families.
-- Keep the actual tileset record (and its asset paths/id) under both names.
local Names = {}

function Names.constant(id)
  if type(id) ~= "string" then return nil end
  local family = id:match("^Tileset(%u[%w_]*)$")
  if not family then return nil end
  -- The ROM symbol spells the device PokeCom; its constant is POKECOM.
  family = family:gsub("PokeCom", "Pokecom")
  family = family:gsub("(%u)(%u%l)", "%1_%2")
                 :gsub("(%l)(%u)", "%1_%2")
  return "TILESET_" .. family:upper()
end

function Names.publish(data)
  if type(data.tilesets) ~= "table" or type(data.maps) ~= "table" then return false end
  local previous = data._gen2TilesetNameAliases or {}
  local pending, available, generated = {}, {}, {}
  for native, tileset in pairs(data.tilesets) do
    local constant = Names.constant(native)
    if constant and type(tileset) == "table" then
      local row = pending[constant]
      if not row then row = { value=tileset, names={} }; pending[constant] = row end
      if row.value ~= tileset then row.conflict = true end
      row.names[#row.names + 1] = native
    end
  end
  for constant, row in pairs(pending) do
    local current = data.tilesets[constant]
    -- Refresh only aliases we published ourselves. An authored constant
    -- already pointing elsewhere is an explicit choice, never overwritten.
    -- Two distinct native families sharing a spelling are never guessed.
    if not row.conflict and (current == nil or current == row.value
        or current == previous[constant]) then
      data.tilesets[constant] = row.value
      generated[constant] = row.value
      for _, native in ipairs(row.names) do available[native] = constant end
    end
  end
  data._gen2TilesetNameAliases = generated
  for _, def in pairs(data.maps) do
    if type(def) == "table" and available[def.tileset] then
      if def.sourceTileset == nil then def.sourceTileset = def.tileset end
      def.tileset = available[def.tileset]
    end
  end
  return true
end

return Names
