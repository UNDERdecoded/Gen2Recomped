-- ENGLISH NAME -> GEN IV ID, FOR A CACHE IN ANOTHER LANGUAGE.
--
-- Several systems are handed an English item or move name: a Monster Walker
-- prize or catch (src/pokewalker), a Gen III cartridge's held item (Pal Park,
-- src/pokemon/CrossGen.lua), a Platinum Pokemon moving on to Black / White.
-- They used to find the destination's entry by comparing that name with the
-- destination's own, which only works while the destination is English: on a
-- German Platinum the held item was dropped and the Walker's prizes became
-- Potions.
--
-- Move ids are the National move index of every generation, and a Gen IV
-- item id is the same on every language, so the id is the language-free
-- answer.  Gen4EnglishNames.lua is the table (tools/gen4_english_ref_gen.lua
-- writes it from an English import); this is its reader.

local Ref = {}

local function names() return require("src.pokemon.Gen4EnglishNames") end

local function norm(s)
  return (tostring(s or ""):gsub("é", "e"):gsub("É", "E"):upper():gsub("[^%w]", ""))
end
Ref.norm = norm

-- the data table's entry for a Gen IV id (numeric key, or the `ITEM_nnn` alias)
local function entry(tbl, id)
  if type(tbl) ~= "table" then return nil, nil end
  if tbl[id] ~= nil then return id, tbl[id] end
  local alias = ("ITEM_%03d"):format(id)
  if tbl[alias] ~= nil then return alias, tbl[alias] end
  return nil, nil
end

-- Is `data` a Gen IV dataset (ids are the cartridge's)?
function Ref.isGen4(data)
  return type(data) == "table" and type(data.constants) == "table" and data.constants.gen == 4
end

-- move / item key in `data` for an English name; nil when `data` is not Gen IV
-- or the name is not one of Gen IV's.  Returns the key the data table uses.
function Ref.moveKey(data, name)
  if not Ref.isGen4(data) then return nil end
  local id = names().moves[norm(name)]
  if not id then return nil end
  return (entry(data.moves, id))
end

function Ref.itemKey(data, name)
  if not Ref.isGen4(data) then return nil end
  local id = names().items[norm(name)]
  if not id then return nil end
  return (entry(data.items, id))
end

-- the other way: a Gen IV id (or ITEM_nnn alias) -> its English name
local reverse
function Ref.englishName(kind, key)
  local id = tonumber(key) or tonumber(tostring(key):match("^ITEM_(%d+)$"))
  if not id then return nil end
  reverse = reverse or {}
  if not reverse[kind] then
    local out = {}
    for n, i in pairs(names()[kind]) do if out[i] == nil then out[i] = n end end
    reverse[kind] = out
  end
  return reverse[kind][id]
end

return Ref
