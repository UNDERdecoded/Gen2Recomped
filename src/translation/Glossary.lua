-- THE OFFICIAL NAMES, BUILT ON THE PLAYER'S DEVICE.
--
-- A translation keeps Pokémon, move, item and place names as the official
-- localized ones ("CHARIZARD" -> "Glurak") instead of machine-translating
-- them: Plan.build takes them as protected terms. Those names belong to
-- Nintendo / The Pokémon Company, so the project does not ship them. The
-- first translation into a language downloads PokeAPI's name tables
-- (github.com/PokeAPI/pokeapi, data/v2/csv) and builds that language's list
-- here, into the save directory; later translations read it back.
--
--   translations/glossary/<target>.json   { format = 1, terms = { [source] = localized } }

local Json = require("src.link.Json")

local Glossary = {}

Glossary.BASE = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/"
Glossary.FILES = {
  { file = "pokemon_species_names.csv", id = "pokemon_species_id" },
  { file = "move_names.csv", id = "move_id" },
  { file = "item_names.csv", id = "item_id" },
  { file = "location_names.csv", id = "location_id" },
}
-- PokeAPI's local_language_id for the languages it has official names in
Glossary.LANGUAGE_ID = { ja = 11, zh = 12, fr = 5, de = 6, es = 7, it = 8, en = 9 }
local ENGLISH = 9
-- "Pokémon" and "Pokémon Center" as each language writes them
Glossary.GENERIC = {
  en = { "Pokémon", "Pokémon Center" }, fr = { "Pokémon", "Centre Pokémon" },
  de = { "Pokémon", "Pokémon-Center" }, es = { "Pokémon", "Centro Pokémon" },
  it = { "Pokémon", "Centro Pokémon" }, ja = { "ポケモン", "ポケモンセンター" },
  zh = { "宝可梦", "宝可梦中心" },
}
Glossary.FORMAT = 1

function Glossary.path(target) return "translations/glossary/" .. target .. ".json" end

-- RFC 4180 rows: quoted fields may hold commas, doubled quotes and newlines.
function Glossary.parseCsv(text)
  local rows, row, field, i, n = {}, {}, {}, 1, #text
  local quoted = false
  while i <= n do
    local c = text:sub(i, i)
    if quoted then
      if c == '"' then
        if text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1
        else quoted = false end
      else field[#field + 1] = c end
    elseif c == '"' then quoted = true
    elseif c == "," then row[#row + 1] = table.concat(field); field = {}
    elseif c == "\n" or c == "\r" then
      if c == "\r" and text:sub(i + 1, i + 1) == "\n" then i = i + 1 end
      row[#row + 1] = table.concat(field); field = {}
      if #row > 1 or row[1] ~= "" then rows[#rows + 1] = row end
      row = {}
    else field[#field + 1] = c end
    i = i + 1
  end
  if #field > 0 or #row > 0 then row[#row + 1] = table.concat(field); rows[#rows + 1] = row end
  return rows
end

-- One language's terms from the four CSV texts (keyed by file name).
-- Languages PokeAPI has no names for keep the English ones, which still
-- stops the model from translating a name as if it were a word.
function Glossary.build(csvs, target)
  local want = Glossary.LANGUAGE_ID[target] or ENGLISH
  local terms = {}
  for _, spec in ipairs(Glossary.FILES) do
    local rows = Glossary.parseCsv(csvs[spec.file] or "")
    local header, col = rows[1] or {}, {}
    for k, name in ipairs(header) do col[name] = k end
    local idCol, langCol, nameCol = col[spec.id], col.local_language_id, col.name
    if idCol and langCol and nameCol then
      -- in file order, so an English name two records share ends up with
      -- the later record's translation every time
      local byId, order = {}, {}
      for r = 2, #rows do
        local row = rows[r]
        local id, lang = row[idCol], tonumber(row[langCol])
        if id and lang then
          if not byId[id] then byId[id] = {}; order[#order + 1] = id end
          byId[id][lang] = row[nameCol]
        end
      end
      for _, id in ipairs(order) do
        local names = byId[id]
        local english = names[ENGLISH]
        if english and english ~= "" then
          local localized = names[want] or english
          if localized == "" then localized = english end
          for _, source in ipairs({ english, english:upper(), english:gsub(" ", ""):upper(),
                                    (english:gsub("%-", "")):upper() }) do
            terms[source] = localized
          end
        end
      end
    end
  end
  local generic = Glossary.GENERIC[target] or Glossary.GENERIC.en
  for _, source in ipairs({ "Pokemon", "Pokémon", "POKEMON", "POKéMON" }) do terms[source] = generic[1] end
  for _, source in ipairs({ "Pokemon Center", "Pokémon Center", "POKEMON CENTER", "POKéMON CENTER" }) do
    terms[source] = generic[2]
  end
  return terms
end

-- The saved terms for `target`, or nil.
function Glossary.read(target)
  local bytes = love.filesystem.read(Glossary.path(target))
  if not bytes then return nil end
  local ok, doc = pcall(Json.decode, bytes)
  if ok and type(doc) == "table" and doc.format == Glossary.FORMAT and type(doc.terms) == "table" then
    return doc.terms
  end
  return nil
end

-- The terms for `target`, downloading and building them on first use.
-- `emit` reports progress the worker's way. Errors when the download fails:
-- translating without the official names would bake machine-made names into
-- the cache.
function Glossary.ensure(target, emit)
  local have = Glossary.read(target)
  if have then return have end
  emit = emit or function() end
  local HostShell = require("src.core.HostShell")
  love.filesystem.createDirectory("translations/glossary")
  local save = love.filesystem.getSaveDirectory()
  local csvs = {}
  for k, spec in ipairs(Glossary.FILES) do
    emit({ kind = "progress", phase = "glossary", message = "Downloading official Pokémon names",
           done = k - 1, total = #Glossary.FILES, unit = "files" })
    local rel = "translations/glossary/" .. spec.file
    local ok, why = HostShell.httpDownload(Glossary.BASE .. spec.file, save .. "/" .. rel, "Gen2Recomp/translation")
    local text = love.filesystem.read(rel)
    love.filesystem.remove(rel)
    assert(ok and text and #text > 0, "Could not download the official Pokémon names ("
      .. spec.file .. "): " .. tostring(why or "empty file") .. ". Check the connection and translate again.")
    csvs[spec.file] = text
  end
  local terms = Glossary.build(csvs, target)
  assert(love.filesystem.write(Glossary.path(target),
    Json.encode({ format = Glossary.FORMAT, target = target, terms = terms,
                  source = "PokeAPI (github.com/PokeAPI/pokeapi), BSD-3-Clause; names are trademarks of Nintendo" })))
  return terms
end

return Glossary
