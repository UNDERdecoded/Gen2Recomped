-- WHICH EXTRACTED STRINGS ARE PLAYER-FACING, in one place.
--
-- The translator collects strings (Service.stringsIn, run by the worker) and
-- the game swaps them in at boot (Service.install).  The two used to keep
-- their own lists, and they drifted: Fly-menu town names, Gen 2 town-map
-- landmarks and the Battle Tower's menus were collected (or not) under one
-- name and installed under another, so they stayed English in every game.
-- Both now walk the same rules here.
--
-- `field` is the cartridge-specific grab bag: text sits next to map ids, asset
-- paths and facing directions, and translating one of those breaks the game.
-- So a string in `field` is text only when its own key (or the key of the list
-- holding it) is a text key, and never under a subtree of proper names.

local Sources = {}

-- name/label/description anywhere in `field`, plus these text-bearing keys
local FIELD_TEXT = {
  name = true, label = true, description = true,
  hatchText = true, menu = true, ruleTexts = true, notReadyText = true,
  cancelLabel = true, texts = true, customOption = true,
}
-- subtrees that hold people's names or logic labels, never translated
local FIELD_SKIP = {
  trainers = true, playerForms = true, gen2Trades = true, intro = true,
  player = true, rival = true, timeOfDay = true, title = true, boot = true,
}
Sources.FIELD_TEXT, Sources.FIELD_SKIP = FIELD_TEXT, FIELD_SKIP

-- Data tables whose records carry a display `name` / `description`.
Sources.RECORDS = { "pokemon", "moves", "items", "trainers" }
-- Tables whose name/label/description leaves are all display text.
Sources.LABEL_TABLES = { "landmarks", "mapSections" }

local function isId(text)
  return text:match("^[A-Z%d_]+_[A-Z%d_]+$") ~= nil
end
Sources.isId = isId

-- Visit every display string of `field`: fn(text) for collecting.
local function walkField(t, inText, fn, seen)
  seen = seen or {}
  if type(t) ~= "table" or seen[t] then return end
  seen[t] = true
  for key, v in pairs(t) do
    if not (type(key) == "string" and FIELD_SKIP[key]) then
      local text = inText or (type(key) == "string" and FIELD_TEXT[key])
      if type(v) == "string" then
        if text then fn(v) end
      elseif type(v) == "table" then
        walkField(v, text, fn, seen)
      end
    end
  end
end

-- A copy of `field` with its display strings looked up in `catalog`.
local function mapField(t, inText, catalog)
  local out = {}
  for key, v in pairs(t) do
    if type(key) == "string" and FIELD_SKIP[key] then
      out[key] = v
    else
      local text = inText or (type(key) == "string" and FIELD_TEXT[key])
      if type(v) == "string" then
        out[key] = text and catalog[v] or v
      elseif type(v) == "table" then
        out[key] = mapField(v, text, catalog)
      else
        out[key] = v
      end
    end
  end
  return out
end

local function walkLabels(t, fn)
  for key, v in pairs(t or {}) do
    if key == "name" or key == "label" or key == "description" then
      if type(v) == "string" then fn(v) end
    elseif type(v) == "table" then walkLabels(v, fn) end
  end
end

local function mapLabels(t, catalog)
  local out = {}
  for key, v in pairs(t or {}) do
    if type(v) == "table" then out[key] = mapLabels(v, catalog)
    elseif (key == "name" or key == "label" or key == "description") and type(v) == "string" then
      out[key] = catalog[v] or v
    else out[key] = v end
  end
  return out
end

-- Names shown through a display-time lookup rather than swapped into data,
-- because code also uses them as keys: type names (TypeChart.displayName) and
-- the Pokétch's app names (its DRAW / UNDER tables are keyed by them).
local function eachDisplayName(data, fn)
  local chart = data.type_chart
  for _, rec in pairs(chart and chart.types or {}) do
    if type(rec) == "table" and type(rec.name) == "string" then fn(rec.name) end
  end
  local menus = data.gen4_menus
  for _, app in pairs(menus and menus.poketch and menus.poketch.apps or {}) do
    if type(app) == "table" and type(app.name) == "string" then fn(app.name) end
  end
end

-- Modules the worker reads from the cache to collect.
Sources.MODULES = { "text", "pokemon", "moves", "items", "trainers", "field",
                    "landmarks", "mapSections", "type_chart", "gen4_menus" }

-- Every player-facing string in `data`, each once, sorted.
function Sources.collect(data)
  local strings, seen = {}, {}
  local function add(text)
    if type(text) == "string" and text ~= "" and not seen[text] and not isId(text) then
      seen[text] = true; strings[#strings + 1] = text
    end
  end
  local function walk(t)
    for key, v in pairs(t or {}) do
      if tostring(key):sub(1, 1) ~= "_" then
        if type(v) == "string" then add(v) elseif type(v) == "table" then walk(v) end
      end
    end
  end
  walk(data.text)
  for _, name in ipairs(Sources.RECORDS) do
    for _, def in pairs(data[name] or {}) do
      if type(def) == "table" then add(def.name); add(def.description) end
    end
  end
  for _, name in ipairs(Sources.LABEL_TABLES) do walkLabels(data[name], add) end
  walkField(data.field, false, add)
  eachDisplayName(data, add)
  table.sort(strings)
  return strings
end

-- Swap translated copies into `data` (new tables: the cache's own stay intact).
function Sources.apply(data, catalog)
  local function clone(t)
    local out = {}
    for key, v in pairs(t or {}) do
      out[key] = type(v) == "string" and (catalog[v] or v) or type(v) == "table" and clone(v) or v
    end
    return out
  end
  data.text = clone(data.text)
  for _, name in ipairs(Sources.RECORDS) do
    local out = {}
    for key, def in pairs(data[name] or {}) do
      if type(def) == "table" then
        local copy = {}; for k, v in pairs(def) do copy[k] = v end
        copy.translationSourceName = def.translationSourceName or def.name
        copy.name = catalog[def.name] or def.name
        copy.description = catalog[def.description] or def.description
        out[key] = copy
      else out[key] = def end
    end
    data[name] = out
  end
  for _, name in ipairs(Sources.LABEL_TABLES) do
    if data[name] then data[name] = mapLabels(data[name], catalog) end
  end
  if type(data.field) == "table" then data.field = mapField(data.field, false, catalog) end
end

return Sources
