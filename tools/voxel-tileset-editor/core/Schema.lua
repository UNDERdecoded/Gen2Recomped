-- WHAT IS EDITABLE, ASKED OF THE PROFILE RATHER THAN HARDCODED.
--
-- The panels used to be one hand-written editor per feature: a class list, a
-- conditionals tab, an objects tab, a buildings tab, side tables nobody had
-- got round to.  Two problems with that, and they are the same problem.
--
-- It SPRAWLED.  Eight tabs, each laid out differently, most of them empty
-- most of the time, and the setting you wanted was in whichever one you were
-- not looking at.
--
-- And it was INCOMPLETE, permanently.  `Shape.mergeEntry` round-trips every
-- key it does not model -- `figures`, `mounted`, `rail_face`,
-- `bookcase_relief`, the `can_*` family, `column_foot` -- precisely so an
-- exporter never silently deletes them.  Round-tripping is not editing.  A
-- fork that adds a key gets it carried through and no way to touch it, and
-- the only fix under the old shape was to write another panel by hand for
-- every key anyone ever adds.
--
-- So this module asks the LIVE PROFILE what is in it and says what kind of
-- thing each key holds.  The panel renders whatever comes back.  A fork that
-- invents `awning_face` gets an editor for it with nothing to update here,
-- which is the only version of "every possible setting is editable" that
-- stays true after this conversation ends.
--
-- Nothing here writes.  It reports fields; `core/Doc.lua` stores the reader's
-- answers and `Shape.mergeEntry` merges them back.

local Schema = {}

-- ------------------------------------------------------------- typing

-- The kinds, and how each is recognised.  Order matters: the first rule that
-- fits wins, and the specific ones come before the general.
--
--   classList  an array of tile ids under a key that is a CLASS NAME.  This
--              is the profile's main shape -- `wall = { 0x03, 0x04 }` -- and
--              it is edited as a pin, not as a list, because "this tile is a
--              wall" is the sentence the reader is actually saying.
--   ruleMap    tile id -> array of rule tables.  `when_above` and friends.
--   tileMap    tile id -> tile id or number.  `prop_ground`.
--   numberMap  a name -> number table.  `heights`.
--   tileList   a bare array of tile ids.  `prop_bg`.
--   templates  `buildings`: a per-tileset ordered list with its own editor.
--   number, flag, text
--   opaque     a table this cannot read.  Shown, counted, and left alone --
--              saying "12 entries, not editable here" is honest, and
--              pretending it is a tile list would corrupt it.
local function allNumbers(t)
  local n = 0
  for _, v in pairs(t) do
    if type(v) ~= "number" then return false end
    n = n + 1
  end
  return n > 0
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then return false end
    n = n + 1
  end
  if n == 0 then return false end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

local function arrayOfTables(t)
  if not isArray(t) then return false end
  for _, v in ipairs(t) do if type(v) ~= "table" then return false end end
  return true
end

-- Keys the editor models with a purpose-built control, because a generic one
-- would be worse rather than merely different.  They are still listed -- the
-- panel just routes them somewhere else.
Schema.SPECIAL = {
  heights = "numberMap",
  buildings = "templates",
  when_above = "ruleMap",
  when_below = "ruleMap",
  when_cell = "ruleMap",
  prop_ground = "tileMap",
  prop_bg = "tileList",
}

function Schema.kindOf(key, value, vocab)
  local special = Schema.SPECIAL[key]
  if special then return special end
  local tv = type(value)
  if tv == "number" then return "number" end
  if tv == "boolean" then return "flag" end
  if tv == "string" then return "text" end
  if tv ~= "table" then return "opaque" end
  if vocab and vocab[key] and isArray(value) and allNumbers(value) then
    return "classList"
  end
  if isArray(value) and allNumbers(value) then return "tileList" end
  if arrayOfTables(value) then return "ruleMap" end
  if allNumbers(value) then return "tileMap" end
  return "opaque"
end

-- How many things a key holds, for the line that says so.
function Schema.countOf(value)
  if type(value) ~= "table" then return nil end
  local n = 0
  for _, v in pairs(value) do
    if type(v) == "table" then
      local m = 0
      for _ in pairs(v) do m = m + 1 end
      n = n + math.max(1, m)
    else
      n = n + 1
    end
  end
  return n
end

-- ------------------------------------------------------------- discovery

-- Every key in the merged profile entry for one tileset, plus every key this
-- document has invented on top of it, typed and sorted.
--
-- `vocab` is the class vocabulary, which is what separates "this key is a
-- class" from "this key is a side table that happens to hold tile ids".
function Schema.fields(entry, docEntry, vocab)
  entry = entry or {}
  vocab = vocab or {}
  local seen, out = {}, {}

  local function put(key, value)
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = {
      key = key,
      value = value,
      kind = Schema.kindOf(key, value, vocab),
      isClass = vocab[key] ~= nil,
      count = Schema.countOf(value),
    }
  end

  for k, v in pairs(entry) do put(k, v) end
  -- keys the reader has authored that the profile does not have yet
  for k, v in pairs((docEntry and docEntry.extra) or {}) do put(k, v) end
  -- and every class the vocabulary knows, even where this tileset uses none
  -- of it: a class with no tiles yet is exactly the one you want to assign
  for k in pairs(vocab) do
    if not seen[k] then put(k, entry[k] or {}) end
  end

  table.sort(out, function(a, b)
    if a.isClass ~= b.isClass then return b.isClass end
    return a.key < b.key
  end)
  return out
end

-- The non-class keys only, which is "everything the tabs never covered".
function Schema.sideFields(entry, docEntry, vocab)
  local out = {}
  for _, f in ipairs(Schema.fields(entry, docEntry, vocab)) do
    if not f.isClass then out[#out + 1] = f end
  end
  return out
end

-- Is this tile named by this field?  For a class list and a tile list that
-- is membership; for the maps it is a key.  Used to show, per selected tile,
-- which of the profile's keys currently mention it.
function Schema.mentions(field, tile)
  local v = field.value
  if type(v) ~= "table" or tile == nil then return false end
  if field.kind == "classList" or field.kind == "tileList" then
    for _, t in ipairs(v) do if t == tile then return true end end
    return false
  end
  return v[tile] ~= nil
end

return Schema
